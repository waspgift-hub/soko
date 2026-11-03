// Phase 4: one-time idempotent backfill of legacy Firestore `transactions`
// into the v2 Postgres schema. Dry-run by default; pass --commit to write.
// Money fields travel as BigInt (no floats). Source of truth stays Firestore
// until all applications have moved to v2 routes.

require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
require('dotenv').config({ path: require('path').join(__dirname, '..', '..', '..', '.env.production') });

const admin = require('firebase-admin');
const { PrismaClient } = require('@prisma/client');

if (!process.env.DATABASE_URL) {
  console.error('FATAL: DATABASE_URL not set (expected in ../../.env.production)');
  process.exit(1);
}
if (!process.env.FIREBASE_SERVICE_ACCOUNT_JSON) {
  console.error('FATAL: FIREBASE_SERVICE_ACCOUNT_JSON not set (expected in server/.env)');
  process.exit(1);
}

const COMMIT = process.argv.includes('--commit');

const prisma = new PrismaClient({ datasources: { db: { url: process.env.DATABASE_URL } } });
admin.initializeApp({
  credential: admin.credential.cert(JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON)),
  databaseURL: `https://${JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON).project_id}.firebaseio.com`,
});

const db = admin.firestore();

// Legacy statuses we carry over. `pending` is included: payment may have landed.
const LEGACY_STATUSES = new Set([
  'pending', 'awaiting_shipping_quote', 'quoted', 'paid', 'escrow_hold',
  'dispatched', 'delivered', 'confirmed', 'completed', 'cancelled', 'disputed', 'refunded', 'failed',
]);

const v2 = {
  pending_shipping_fee: 'pending_shipping_fee',
  quoted: 'shipping_fee_submitted',
  paid: 'awaiting_escrow_payment',
  escrow_hold: 'in_escrow',
  dispatched: 'dispatched',
  delivered: 'delivered',
  confirmed: 'delivered',
  completed: 'completed',
  cancelled: 'cancelled',
  disputed: 'disputed',
  refunded: 'refunded',
  failed: 'failed',
  pending: 'payment_pending',
};

const toBigInt = (v) => {
  const n = Number(v);
  if (!Number.isFinite(n) || n < 0) return null;
  return BigInt(Math.round(n));
};

const toDate = (v) => {
  if (!v) return null;
  const d = v.toDate ? v.toDate() : v instanceof Date ? v : new Date(v);
  return Number.isNaN(d.getTime()) ? null : d;
};

const slugify = (name, suffix) => {
  const base = (name || 'duka').toString().toLowerCase().replace(/[^a-z0-9]+/g, '').slice(0, 40) || 'duka';
  return `${base}-${suffix}`.slice(0, 100);
};

function buildOrderNumber(docId) {
  // Legacy doc ids are Firestore ids; orderNumber is VarChar(20).
  const sanitized = docId.replace(/[^a-zA-Z0-9]/g, '');
  return `L${sanitized.length <= 19 ? sanitized : sanitized.slice(-19)}`;
}

async function resolveUser(firestoreUid) {
  if (!firestoreUid) return null;
  const uid = String(firestoreUid);
  const existing = await prisma.user.findUnique({ where: { firebaseUid: uid }, select: { id: true } });
  if (existing) return existing.id;

  // Backfill identity from legacy Firestore users/{uid} so FKs resolve.
  const snap = await db.collection('users').doc(uid).get();
  const ud = snap.exists ? snap.data() || {} : {};
  const displayName = ud.name || ud.displayName || null;
  const isSeller = ud.sellerStatus && ud.sellerStatus !== 'not_seller';
  const role = ud.isAdmin ? 'admin' : isSeller ? 'seller' : ud.role || 'buyer';
  const base = {
    firebaseUid: uid, displayName, role,
    accountStatus: ud.isSuspended ? 'suspended' : 'active',
    phoneVerified: Boolean(ud.phoneVerified), emailVerified: Boolean(ud.emailVerified),
  };
  try {
    const user = await prisma.user.create({ data: { ...base, email: ud.email || null, phone: ud.phone || null } });
    return user.id;
  } catch (e) {
    // email/phone are unique: a legacy value may collide or already exist.
    const user = await prisma.user.create({ data: { ...base } });
    return user.id;
  }
}

async function resolveSellerProfile(sellerUid, sellerName) {
  const userId = await resolveUser(sellerUid);
  if (!userId) return null;
  let profile = await prisma.sellerProfile.findUnique({ where: { userId }, select: { id: true } });
  if (!profile) {
    const snap = await db.collection('users').doc(String(sellerUid || '')).get();
    const ud = snap.exists ? snap.data() || {} : {};
    const name = sellerName || ud.name || ud.displayName || 'Duka';
    profile = await prisma.sellerProfile.create({
      data: { userId, storeName: name, storeSlug: slugify(name, userId.slice(0, 8)) },
      select: { id: true },
    });
  }
  return profile.id;
}

// eslint-disable-next-line max-len
async function exportOrder(docId, tx) {
  const orderNumber = buildOrderNumber(docId);
  const existing = await prisma.order.findUnique({ where: { legacyFirestoreId: docId }, select: { id: true } });
  if (existing) return { outcome: 'skipped' };

  const buyerId = await resolveUser(tx.buyerId);
  if (!buyerId) return { outcome: 'missingBuyer' };
  const sellerId = await resolveSellerProfile(tx.sellerId, tx.sellerName);
  if (!sellerId) return { outcome: 'missingSeller' };

  const productPrice = toBigInt(tx.productPrice);
  const shippingFee = toBigInt(tx.shippingCost) || 0n;
  const commission = toBigInt(tx.sokoLanguCommission || tx.platformFee) || 0n;
  const totalAmount = toBigInt(tx.totalAmount) ?? (productPrice !== null ? productPrice + shippingFee : null);
  if (productPrice === null || totalAmount === null) return { outcome: 'badAmount' };

  const legacyStatus = String(tx.status || 'pending');
  const status = v2[legacyStatus] || 'failed';

  const escrowReleased = tx.escrowReleased === true;
  const legacyHeld = tx.escrowStatus === 'held' || ['escrow_hold', 'dispatched', 'delivered', 'confirmed', 'disputed', 'refunded'].includes(legacyStatus)
    || (legacyStatus === 'completed' && escrowReleased);
  let holdStatus = null;
  if (legacyStatus === 'refunded' && legacyHeld) holdStatus = 'released_to_buyer';
  else if (legacyStatus === 'disputed' && legacyHeld) holdStatus = 'disputed';
  else if (escrowReleased && legacyHeld) holdStatus = 'released';
  else if (legacyHeld) holdStatus = 'holding';

  const productSnap = {
    productId: tx.productId || null,
    name: tx.productName || 'Legacy order',
    image: tx.productImage || null,
    quantity: tx.quantity ? Number(tx.quantity) : 1,
    unitPrice: tx.unitPrice !== undefined ? Number(tx.unitPrice) : Number(tx.productPrice || 0),
  };
  const addressSnap = tx.region ? {
    region: tx.region, district: tx.district || null, ward: tx.ward || null,
    street: tx.street || null, landmarks: tx.landmarks || null, deliveryType: tx.deliveryType || 'local',
  } : null;
  const legacySnap = {
    status: legacyStatus, escrowStatus: tx.escrowStatus || null, escrowReleased: escrowReleased,
    confirmedBy: tx.confirmedBy || null, cancellationType: tx.cancellationType || null,
    refundFee: tx.refundFee !== undefined ? Number(tx.refundFee) : null,
    autoReleaseDays: tx.autoReleaseDays !== undefined ? Number(tx.autoReleaseDays) : null,
    clickpesaReference: tx.clickpesaReference || null, dispatchProof: tx.dispatchProof || null,
    buyerTransport: tx.buyerTransport || null,
  };

  const orderData = {
    legacyFirestoreId: docId,
    orderNumber,
    buyerId,
    sellerId,
    status,
    productSnapshot: productSnap,
    shippingAddressSnapshot: addressSnap,
    shippingQuoteSnapshot: { amount: Number(shippingFee), busName: tx.busName || null, plateNumber: tx.plateNumber || null },
    legacySnapshot: legacySnap,
    productPrice,
    shippingFee,
    platformCommission: commission,
    totalAmount,
    currency: 'TZS',
    shippingMethod: tx.deliveryType || null,
    placedAt: toDate(tx.createdAt),
    paidAt: toDate(tx.paidAt || tx.escrowHeldAt || tx.createdAt),
    dispatchedAt: toDate(tx.dispatchedAt || tx.escrowReleasedAt),
    deliveredAt: toDate(tx.deliveredAt || tx.escrowReleasedAt),
    completedAt: toDate(tx.completedAt || tx.escrowReleasedAt || tx.deliveryOtpVerifiedAt),
    cancelledAt: toDate(tx.cancelledAt),
  };

  const paymentStatus = legacyStatus === 'failed' ? 'failed'
    : legacyStatus === 'cancelled' ? 'cancelled'
    : ['pending', 'awaiting_shipping_quote', 'quoted'].includes(legacyStatus) ? 'pending' : 'completed';

  const escrowHeld = holdStatus !== null;
  const data = {
    orderData,
    payment: {
      provider: 'clickpesa', providerPaymentId: tx.clickpesaReference || null,
      providerReference: tx.transactionReference || orderIdRef(tx, docId),
      amount: totalAmount, status: paymentStatus, idempotencyKey: `migrate_pay_${docId}`,
      verifiedAt: escrowHeld ? toDate(tx.escrowHeldAt || tx.paidAt) : null,
    },
    escrowHold: escrowHeld ? {
      amount: totalAmount,
      releasedToBuyer: legacyStatus === 'refunded' ? totalAmount : 0n,
      status: holdStatus, releasedAt: toDate(tx.escrowReleasedAt || tx.completedAt || tx.cancelledAt),
    } : null,
    refund: legacyStatus === 'refunded' ? {
      amount: totalAmount, mode: 'full', reason: 'Legacy buyer_cancel refund (migrated)',
      status: 'completed', correlationId: `migrate_refund_${docId}`,
      requestedBy: buyerId, processedAt: toDate(tx.cancelledAt || tx.escrowReleasedAt),
    } : null,
  };
  return { outcome: 'new', data };
}

function orderIdRef(tx, docId) { return tx.transactionReference || docId; }

async function migrateOne(docId, tx) {
  // Firestore `transactions/{docId}` sometimes lacks buyer/seller ids; the
  // parallel `orders/{docId}` mirror carries them for escrow-originated rows.
  if (!tx.buyerId || !tx.sellerId) {
    const mirror = await db.collection('orders').doc(docId).get();
    if (mirror.exists) {
      const m = mirror.data() || {};
      if (!tx.buyerId && m.buyerId) tx.buyerId = m.buyerId;
      if (!tx.sellerId && m.sellerId) tx.sellerId = m.sellerId;
    }
  }
  const r = await exportOrder(docId, tx);
  if (r.outcome !== 'new') return { docId, status: tx.status, outcome: r.outcome };
  if (!COMMIT) return { docId, status: tx.status, outcome: 'wouldCreate' };

  try {
    const order = await prisma.order.create({ data: r.data.orderData });
    const payment = await prisma.payment.create({ data: { ...r.data.payment, orderId: order.id } });
    if (r.data.escrowHold) {
      await prisma.escrowHold.create({ data: { ...r.data.escrowHold, orderId: order.id, paymentId: payment.id } });
    }
    if (r.data.refund) {
      await prisma.refund.create({ data: { ...r.data.refund, orderId: order.id, paymentId: payment.id } });
    }
    return { docId, status: tx.status, outcome: 'created' };
  } catch (e) {
    try { await prisma.order.deleteMany({ where: { legacyFirestoreId: docId } }); } catch { /* best effort */ }
    return { docId, status: tx.status, outcome: `error:${e.message}` };
  }
}

async function ensureWallets() {
  // v2 settlement only credits an EXISTING wallet; migrate sellers must have
  // one or their future settlement silently disappears.
  const sellerProfiles = await prisma.sellerProfile.findMany({ select: { id: true } });
  let created = 0;
  for (const sp of sellerProfiles) {
    const wallet = await prisma.wallet.findUnique({ where: { sellerId: sp.id }, select: { id: true } });
    if (!wallet) {
      await prisma.wallet.create({ data: { sellerId: sp.id } });
      created += 1;
    }
  }
  return created;
}

async function run() {
  const counts = {};
  const snap = await db.collection('transactions').get();
  let total = 0;
  const results = [];
  for (const doc of snap.docs) {
    const tx = doc.data() || {};
    const st = String(tx.status || 'none');
    counts[st] = (counts[st] || 0) + 1;
    if (!LEGACY_STATUSES.has(st)) continue;
    total += 1;
    results.push(await migrateOne(doc.id, tx));
  }

  const byOutcome = {};
  for (const r of results) byOutcome[r.outcome] = (byOutcome[r.outcome] || 0) + 1;

  console.log(`\n=== FIRESTORE transactions scan (dry=${!COMMIT ? 'YES' : 'NO'}) ===`);
  console.log(`Total docs: ${snap.size}`);
  console.log('By legacy status:', JSON.stringify(counts, null, 2));
  console.log(`In-scope orders to migrate: ${total}`);
  console.log('Outcomes (preview):', JSON.stringify(byOutcome, null, 2));
  if (COMMIT) {
    console.log('Outcomes (written):', JSON.stringify(byOutcome, null, 2));
    const errors = results.filter((r) => r.outcome.startsWith('error'));
    if (errors.length) {
      console.log(`\nErrors (${errors.length}):`);
      for (const e of errors.slice(0, 25)) console.log(`  ${e.docId} [${e.status}] ${e.outcome}`);
    }
    const skipped = results.filter((r) => r.outcome === 'skipped');
    if (skipped.length) console.log(`Already migrated: ${skipped.length}`);
    const wallets = await ensureWallets();
    console.log(`Wallets ensured for migrated sellers: ${wallets}`);
  } else {
    console.log('Dry-run: nothing written. Re-run with --commit to migrate.');
  }
  await prisma.$disconnect();
}

run().catch((e) => { console.error('FATAL:', e); process.exit(1); });