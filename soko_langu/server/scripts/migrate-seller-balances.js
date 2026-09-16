// Phase B cutover: fold the legacy Firestore sellerBalance (money already
// released to sellers) plus the totalWithdrawn stat into each seller's Postgres
// wallet, so flipping the wallet UI (§5.13) shows real balances instead of
// zeros. Idempotent via a stable per-seller ledger key; re-running only picks
// up sellers the previous run skipped (e.g. no SellerProfile yet) or balances
// that kept moving during the cutover window.
//
// pendingEscrow is intentionally NOT migrated: after the release/wallet flip it
// settles through the regular v1 escrow release, so migrating it here would
// double-credit the same order.
//
// Run before flipping ApiConfig.kUseOrdersApi + kUseWalletApi (dry-run first):
//   node scripts/migrate-seller-balances.js            # dry-run
//   node scripts/migrate-seller-balances.js --commit   # write to Postgres
//   node scripts/migrate-seller-balances.js --limit 50 # cap batch size

require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });

const admin = require('firebase-admin');
const { getPrisma } = require('../src/config/database');
const walletService = require('../src/modules/wallet/wallet-service');

if (!process.env.DATABASE_URL) {
  console.error('FATAL: DATABASE_URL not set');
  process.exit(1);
}
if (!process.env.FIREBASE_SERVICE_ACCOUNT_JSON) {
  console.error('FATAL: FIREBASE_SERVICE_ACCOUNT_JSON not set');
  process.exit(1);
}

const COMMIT = process.argv.includes('--commit');
const LIMIT = (() => {
  const idx = process.argv.indexOf('--limit');
  if (idx !== -1) {
    const v = parseInt(process.argv[idx + 1], 10);
    if (Number.isFinite(v) && v > 0) return v;
  }
  return Infinity;
})();

// The script reads Firestore via admin and writes Postgres via the shared
// config client (getPrisma is lazy, so no extra connection pool is opened).
admin.initializeApp({
  credential: admin.credential.cert(JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON)),
});
const firestore = admin.firestore();
const prisma = getPrisma();

// UID → SellerProfile resolution cache. A missing profile means the seller has
// never hit the v1 API (the auth middleware provisions it on login); the run
// lists them and a re-run after they log in picks them up.
const profileCache = new Map();
async function resolveSellerProfile(firebaseUid) {
  if (profileCache.has(firebaseUid)) return profileCache.get(firebaseUid);
  const user = await prisma.user.findUnique({
    where: { firebaseUid },
    select: { sellerProfile: { select: { id: true } } },
  });
  const result = user?.sellerProfile?.id || null;
  profileCache.set(firebaseUid, result);
  return result;
}

async function main() {
  console.log(`[migrate-seller-balances] mode=${COMMIT ? 'COMMIT' : 'DRY-RUN'} limit=${LIMIT === Infinity ? 'none' : LIMIT}`);

  const snapshot = await firestore.collection('users').limit(10000).get();
  console.log(`[migrate-seller-balances] Firestore users fetched: ${snapshot.size}`);

  let migrated = 0;
  let already = 0;
  let noMoney = 0;
  let noProfile = 0;
  let errored = 0;
  let totalTZS = 0;

  for (const doc of snapshot.docs) {
    if (migrated + noMoney + noProfile + already + errored >= LIMIT) break;

    const uid = doc.id;
    const data = doc.data() || {};
    const amount = Math.round(Number(data.sellerBalance || 0));
    const withdrawn = Math.round(Number(data.totalWithdrawn || 0));

    if (!Number.isFinite(amount) || amount <= 0) {
      noMoney += 1;
      continue;
    }

    const sellerId = await resolveSellerProfile(uid);
    if (!sellerId) {
      noProfile += 1;
      console.warn(`[migrate-seller-balances] SKIP ${uid}: no SellerProfile — re-run after they log in via v1`);
      continue;
    }

    totalTZS += amount;

    if (!COMMIT) {
      migrated += 1;
      continue;
    }

    try {
      const res = await walletService.creditLegacyBalance({
        sellerId,
        amount,
        priorWithdrawn: withdrawn,
      });
      if (res.alreadyMigrated) {
        already += 1;
      } else {
        migrated += 1;
      }
    } catch (e) {
      errored += 1;
      console.error(`[migrate-seller-balances] ERROR ${uid} (${sellerId}): ${e.message}`);
    }
  }

  console.log(
    `[migrate-seller-balances] done. eligible_TZS=${totalTZS} migrated=${migrated} already=${already} no_money=${noMoney} no_profile=${noProfile} errors=${errored}`
  );
  await prisma.$disconnect();
}

main().catch(async (e) => {
  console.error('[migrate-seller-balances] fatal:', e);
  await prisma.$disconnect();
  process.exit(1);
});