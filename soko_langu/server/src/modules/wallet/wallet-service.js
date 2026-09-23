// Seller wallet service — Firestore implementation (Phase 5).
//
// Previously the money moved through Postgres rows (`wallet`,
// `walletLedgerEntry`, `withdrawal`, `payoutTransaction`). Now the wallet is
// `wallets/{sellerUid}` with an append-only `walletTransactions/{id}` ledger,
// and withdrawals live in `withdrawals/{id}`. The public function names and
// return shapes are unchanged so routes, admin routes, and finance-jobs keep
// their contracts.
const { getFirebaseFirestore } = require('../../config/firebase');
const { acquireLock, releaseLock } = require('../../config/redis');
const { getProvider } = require('../payments/provider-factory');
const commerceStore = require('../../services/commerce-store');

function withLockTimeout(promise, ms = 5000) {
  return Promise.race([
    promise,
    new Promise((resolve) => setTimeout(() => resolve({ acquired: true, skipped: true }), ms)),
  ]);
}

async function locked(key, ttl) {
  return withLockTimeout(acquireLock(key, ttl));
}

/**
 * Get the seller's wallet (auto-created on first access).
 */
async function getWallet(sellerId) {
  return commerceStore.getWallet(sellerId);
}

/**
 * Alias kept for callers that used the transactional variant; the Firestore
 * wallet is idempotent so there is nothing to coordinate.
 */
async function ensureWallet(sellerId) {
  return commerceStore.getWallet(sellerId);
}

/**
 * Get wallet balances plus a paginated ledger history. Shape matches what the
 * Flutter `WalletDetail.fromApi` parses: `balances.available/pending/frozen/
 * totalEarned/totalWithdrawn` and a `ledger[]`.
 */
async function getWalletDetail(sellerId, { page = 1, limit = 20 } = {}) {
  const wallet = await commerceStore.getWallet(sellerId);
  const { ledger, pagination } = await commerceStore.listLedger(sellerId, { page, limit });
  return {
    wallet,
    balances: {
      available: String(wallet.availableBalance),
      pending: String(wallet.pendingBalance),
      frozen: String(wallet.frozenBalance),
      totalEarned: String(wallet.totalEarned),
      totalWithdrawn: String(wallet.totalWithdrawn),
    },
    ledger,
    pagination,
  };
}

/**
 * Seller requests a withdrawal. Debits the ledger atomically (idempotent on
 * `ledger_withdrawal_{id}`), then returns the withdrawal + freshly serialized
 * wallet.
 */
async function requestWithdrawal({ sellerId, amount, phoneNumber }) {
  const lock = await locked(`withdraw:${sellerId}`, 60);
  const db = getFirebaseFirestore();

  try {
    const wallet = await commerceStore.getWallet(sellerId);
    if (wallet.status !== 'active') throw httpError(409, 'WALLET_FROZEN');

    if (Number(amount) <= 0) throw httpError(400, 'INVALID_AMOUNT');
    if (wallet.availableBalance < Number(amount)) {
      throw httpError(400, 'INSUFFICIENT_BALANCE');
    }

    const min = Number(process.env.WITHDRAWAL_MIN) || 0;
    const max = Number(process.env.WITHDRAWAL_MAX) || 5000000;
    if (amount < min) throw httpError(400, `BELOW_MINIMUM:${min}`);
    if (amount > max) throw httpError(400, `ABOVE_MAXIMUM:${max}`);

    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const dailyLimit = Number(process.env.DAILY_WITHDRAWAL_LIMIT) || 5000000;
    const todayTotal = await commerceStore.sumWithdrawalsToday(sellerId, today, { db });
    if (todayTotal + Number(amount) > dailyLimit) {
      throw httpError(429, 'DAILY_WITHDRAWAL_LIMIT_EXCEEDED');
    }

    const idempotencyKey = `withdrawal_${sellerId}_${Date.now()}`;
    const ref = db.collection(commerceStore.COLLECTIONS.withdrawals).doc();
    await ref.set({
      sellerId: String(sellerId),
      amount: Number(amount),
      provider: 'clickpesa',
      status: 'pending',
      phoneNumber: phoneNumber || null,
      idempotencyKey,
      createdAt: require('firebase-admin/firestore').FieldValue.serverTimestamp(),
    });

    await commerceStore.postLedger({
      sellerUid: sellerId,
      amount: -Number(amount),
      type: commerceStore.LEDGER_TYPES.WITHDRAWAL_DEBITED,
      referenceType: 'withdrawal',
      referenceId: ref.id,
      idempotencyKey: `ledger_withdrawal_${ref.id}`,
      description: 'Seller withdrawal',
    });

    const updatedWallet = await commerceStore.getWallet(sellerId);
    const withdrawal = commerceStore.serializeWithdrawal({
      id: ref.id,
      data: () => ({
        sellerId: String(sellerId),
        amount: Number(amount),
        provider: 'clickpesa',
        status: 'pending',
        phoneNumber: phoneNumber || null,
        idempotencyKey,
        createdAt: null,
      }),
    });
    // Re-read committed doc so createdAt carries a real server Timestamp.
    const committed = await ref.get();
    return { withdrawal: commerceStore.serializeWithdrawal(committed), wallet: updatedWallet };
  } finally {
    if (!lock.skipped) await releaseLock(`withdraw:${sellerId}`);
  }
}

async function processWithdrawal({ withdrawalId, executedBy = 'system' }) {
  const lock = await locked(`withdraw:${withdrawalId}`, 60);
  const db = getFirebaseFirestore();

  try {
    const ref = db.collection(commerceStore.COLLECTIONS.withdrawals).doc(String(withdrawalId));
    const snap = await ref.get();
    if (!snap.exists) throw httpError(404, 'WITHDRAWAL_NOT_FOUND');
    const withdrawal = commerceStore.serializeWithdrawal(snap);
    if (withdrawal.status !== 'pending') throw httpError(409, 'WITHDRAWAL_NOT_PENDING');

    const provider = getProvider(withdrawal.provider || 'clickpesa');
    const payout = await provider.initiatePayout({
      amount: withdrawal.amount,
      orderReference: `W${withdrawal.id}`,
      phoneNumber: await withdrawalPayoutPhone(withdrawal, { db }),
    });

    await ref.update({
      status: 'processing',
      providerPayoutId: payout.id || payout.providerPayoutId || null,
      processedAt: require('firebase-admin/firestore').FieldValue.serverTimestamp(),
    });

    await db.collection(commerceStore.COLLECTIONS.payoutTransactions).doc(String(withdrawalId)).set({
      withdrawalId: String(withdrawalId),
      amount: withdrawal.amount,
      providerResponse: payout,
      status: 'processing',
      updatedAt: require('firebase-admin/firestore').FieldValue.serverTimestamp(),
    }, { merge: true });

    return commerceStore.serializeWithdrawal(await ref.get());
  } finally {
    if (!lock.skipped) await releaseLock(`withdraw:${withdrawalId}`);
  }
}

async function confirmPayout({ withdrawalId, providerPayoutId }) {
  const lock = await locked(`withdraw:${withdrawalId}`, 60);
  const db = getFirebaseFirestore();

  try {
    const ref = db.collection(commerceStore.COLLECTIONS.withdrawals).doc(String(withdrawalId));
    const snap = await ref.get();
    if (!snap.exists) throw httpError(404, 'WITHDRAWAL_NOT_FOUND');
    const current = commerceStore.serializeWithdrawal(snap);
    if (current.status === 'completed') return current;

    await ref.update({
      status: 'completed',
      providerPayoutId: providerPayoutId || current.providerPayoutId,
    });

    await db.collection(commerceStore.COLLECTIONS.payoutTransactions).doc(String(withdrawalId)).set({
      withdrawalId: String(withdrawalId),
      amount: current.amount,
      providerResponse: { providerPayoutId },
      status: 'completed',
      updatedAt: require('firebase-admin/firestore').FieldValue.serverTimestamp(),
    }, { merge: true });

    // totalWithdrawn is bookkeeping, not a balance move, so it can be a plain
    // increment — the ledger already recorded the debit at request time.
    const wallet = await commerceStore.getWallet(current.sellerId);
    await db.collection(commerceStore.COLLECTIONS.wallets).doc(String(current.sellerId)).set({
      totalWithdrawn: require('firebase-admin/firestore').FieldValue.increment(current.amount),
      updatedAt: require('firebase-admin/firestore').FieldValue.serverTimestamp(),
    }, { merge: true });

    return { ...current, status: 'completed', providerPayoutId: providerPayoutId || current.providerPayoutId };
  } finally {
    if (!lock.skipped) await releaseLock(`withdraw:${withdrawalId}`);
  }
}

/**
 * Ports a legacy Firestore `users/{uid}` sellerBalance into the wallet with an
 * idempotent `legacy_balance_{uid}` ledger entry so the cutover never credits
 * twice even if the script re-runs.
 */
async function creditLegacyBalance({ sellerId, amount, priorWithdrawn = 0 }) {
  const amt = Math.round(Number(amount));
  const withdrawn = Math.round(Number(priorWithdrawn));
  if (!Number.isFinite(amt) || amt <= 0) throw httpError(400, 'INVALID_AMOUNT');
  const lock = await locked(`legacy:${sellerId}`, 60);

  try {
    const prior = await commerceStore.getWallet(sellerId);
    // A wallet whose ledger already has the legacy entry is considered migrated.
    const { ledger } = await commerceStore.listLedger(sellerId, { page: 1, limit: 100 });
    const hasLegacyEntry = ledger.some(
      (e) => e.referenceType === 'legacy_balance' && e.referenceId === String(sellerId),
    );
    if (hasLegacyEntry) return { alreadyMigrated: true, sellerId };

    await commerceStore.postLedger({
      sellerUid: sellerId,
      amount: amt,
      type: commerceStore.LEDGER_TYPES.LEGACY_BALANCE,
      referenceType: 'legacy_balance',
      referenceId: String(sellerId),
      idempotencyKey: `legacy_balance_${sellerId}`,
      description: 'Firestore sellerBalance migrated at wallet cutover',
    });

    if (withdrawn > 0) {
      await getFirebaseFirestore()
        .collection(commerceStore.COLLECTIONS.wallets)
        .doc(String(sellerId))
        .set({
          totalWithdrawn: require('firebase-admin/firestore').FieldValue.increment(withdrawn),
          updatedAt: require('firebase-admin/firestore').FieldValue.serverTimestamp(),
        }, { merge: true });
    }

    void prior;
    return { alreadyMigrated: false, sellerId, amount: amt };
  } finally {
    if (!lock.skipped) await releaseLock(`legacy:${sellerId}`);
  }
}

/**
 * Resolves the phone number a withdrawal pays out to: the phone captured at
 * request time wins; legacy rows fall back to the seller's user profile phone.
 */
async function withdrawalPayoutPhone(withdrawal, { db, userPhone } = {}) {
  if (withdrawal.phoneNumber) return withdrawal.phoneNumber;
  if (userPhone) return userPhone;
  if (withdrawal.seller?.user?.phone) return withdrawal.seller.user.phone;
  if (!db || !withdrawal.sellerId) return null;
  const snap = await db.collection('users').doc(String(withdrawal.sellerId)).get();
  if (!snap.exists) return null;
  const u = snap.data();
  return u.phone || u.phoneNumber || null;
}

async function listWithdrawals(sellerId) {
  return commerceStore.listWithdrawals(sellerId);
}

function httpError(status, message) {
  const err = new Error(message);
  err.status = status;
  return err;
}

module.exports = {
  getWallet,
  getWalletDetail,
  ensureWallet,
  requestWithdrawal,
  processWithdrawal,
  confirmPayout,
  creditLegacyBalance,
  withdrawalPayoutPhone,
  listWithdrawals,
};