// Phase 6 step 1: Firestore <-> Postgres money reconciliation. Read-only by
// default; pass --fix to realign accounting fields (no money moves) and to
// backfill missing CommissionTransaction rows for migrated orders.
require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
require('dotenv').config({ path: require('path').join(__dirname, '..', '..', '..', '.env.production') });

const admin = require('firebase-admin');
const { PrismaClient } = require('@prisma/client');

if (!process.env.DATABASE_URL) { console.error('FATAL: DATABASE_URL not set'); process.exit(1); }
if (!process.env.FIREBASE_SERVICE_ACCOUNT_JSON) { console.error('FATAL: FIREBASE_SERVICE_ACCOUNT_JSON not set'); process.exit(1); }

const FIX = process.argv.includes('--fix');
const prisma = new PrismaClient({ datasources: { db: { url: process.env.DATABASE_URL } } });
admin.initializeApp({ credential: admin.credential.cert(JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON)) });
const db = admin.firestore();

const MONEY_STATUSES = new Set([
  'pending', 'awaiting_shipping_quote', 'quoted', 'paid', 'escrow_hold',
  'dispatched', 'delivered', 'confirmed', 'completed', 'cancelled', 'disputed', 'refunded', 'failed',
]);

const toBigInt = (v) => {
  const n = Number(v);
  return Number.isFinite(n) && n >= 0 ? BigInt(Math.round(n)) : null;
};

async function run() {
  const snap = await db.collection('transactions').get();

  const byStatus = {};
  let firestoreMoneyDocs = 0;
  let firestoreMoneyTotal = 0n;
  let firestoreEscrowDocs = 0;
  let firestoreEscrowTotal = 0n;

  for (const doc of snap.docs) {
    const t = doc.data() || {};
    const st = t.status || 'none';
    if (t.type === 'boost') continue; // product-promotion payments, not orders
    if (t.sourceV2 === true) continue; // mirrored new orders; their truth is Postgres
    if (!MONEY_STATUSES.has(st)) continue;
    firestoreMoneyDocs += 1;
    const legTotal = toBigInt(t.totalAmount);
    if (legTotal !== null) firestoreMoneyTotal += legTotal;
    if (['escrow_hold', 'dispatched', 'delivered', 'confirmed', 'disputed', 'refunded'].includes(st)
      || (st === 'completed' && t.escrowReleased)) {
      firestoreEscrowDocs += 1;
      if (legTotal !== null) firestoreEscrowTotal += legTotal;
    }
    byStatus[st] = (byStatus[st] || 0) + 1;
  }

  const migrated = await prisma.order.findMany({
    where: { NOT: [{ legacyFirestoreId: null }] },
    select: { id: true, sellerId: true, legacyFirestoreId: true, status: true, productPrice: true, shippingFee: true, platformCommission: true, totalAmount: true },
  });

  const migratedIds = new Map(migrated.map((o) => [o.legacyFirestoreId, o]));

  // A) Postgres-side commission drift: expected commission = total - price - ship.
  const drift = [];
  for (const o of migrated) {
    const expected = o.totalAmount - o.productPrice - o.shippingFee;
    if (o.platformCommission !== expected) drift.push({ id: o.id, legacy: o.legacyFirestoreId, status: o.status, before: o.platformCommission, expected });
  }

  // B) Firestore coverage: every money-bearing doc should map to a v2 order.
  const missing = [];
  for (const doc of snap.docs) {
    const t = doc.data() || {};
    if (t.type === 'boost') continue;
    if (t.sourceV2 === true) continue;
    if (!MONEY_STATUSES.has(t.status || 'none')) continue;
    if (!migratedIds.has(doc.id)) missing.push({ id: doc.id, status: t.status });
  }

  const escrowHolds = await prisma.escrowHold.count({ where: { payment: { idempotencyKey: { startsWith: 'migrate_pay_' } } } });
  const sumTotal = migrated.reduce((a, o) => a + o.totalAmount, 0n);
  const sumCommission = migrated.reduce((a, o) => a + o.platformCommission, 0n);

  console.log(`\n=== RECONCILE (fix=${FIX ? 'YES' : 'NO'}) ===`);
  console.log(`Firestore money-bearing docs: ${firestoreMoneyDocs} (sum totalAmount: ${firestoreMoneyTotal})`);
  console.log(`Firestore escrow-held docs:   ${firestoreEscrowDocs} (sum totalAmount: ${firestoreEscrowTotal})`);
  console.log(`v2 migrated orders: ${migrated.length} | migrated escrowHolds: ${escrowHolds}`);
  console.log(`v2 sums — total: ${sumTotal} | commission: ${sumCommission} | sellerNet: ${sumTotal - sumCommission}`);
  console.log(`\nDrift (commission != total - price - ship): ${drift.length}`);
  for (const d of drift) console.log(`   ${d.legacy} [${d.status}] commission ${d.before} -> ${d.expected}`);
  console.log(`\nFirestore money docs WITHOUT a v2 order: ${missing.length}`);
  for (const m of missing.slice(0, 25)) console.log(`   ${m.id} [${m.status}]`);

  let commissionRows = 0;
  if (FIX) {
    for (const d of drift) {
      await prisma.order.update({ where: { id: d.id }, data: { platformCommission: d.expected } });
    }
    const migratedIdsList = migrated.map((o) => o.id);
    const existing = await prisma.commissionTransaction.findMany({ select: { orderId: true }, where: { orderId: { in: migratedIdsList } } });
    const haveRows = new Set(existing.map((c) => c.orderId));
    for (const o of migrated) {
      if (o.platformCommission <= 0n || haveRows.has(o.id)) continue;
      await prisma.commissionTransaction.create({
        data: { orderId: o.id, sellerId: o.sellerId, amount: o.platformCommission, rate: 0.035 },
      });
      commissionRows += 1;
    }
    console.log(`\n[FIX] commission realigned on ${drift.length} orders; CommissionTransaction rows backfilled: ${commissionRows}`);
  }

  await prisma.$disconnect();
  process.exit(FIX || drift.length === 0 ? 0 : 1);
}

run().catch((e) => { console.error('FATAL:', e); process.exit(1); });