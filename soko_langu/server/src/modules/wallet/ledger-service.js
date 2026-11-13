// Financial Ledger Service — Firestore implementation (Phase 5).
//
// Invariant preserved from the Postgres version: every wallet balance change
// MUST be accompanied by a ledger entry. The mechanics moved from Prisma
// $transaction to commerce-store, where a `walletTransactions/{id}` document
// id IS the idempotency key, so a retried operation is a no-op instead of a
// double credit. The two public functions keep their exact call signatures so
// downstream callers (wallet-service, handover-service, order-service) keep
// working while the storage backend swaps underneath.
const commerceStore = require('../../services/commerce-store');

const LEDGER_TYPES = commerceStore.LEDGER_TYPES;

/**
 * Atomic wallet update: positive amount credits, negative debits (guarded
 * against going below zero). Returns { wallet, entry } like the Prisma
 * version did.
 */
async function updateWalletBalance({
  userId,
  amount,
  type,
  referenceType,
  referenceId,
  idempotencyKey,
  description,
}) {
  const entry = await commerceStore.postLedger({
    sellerUid: userId,
    amount,
    type,
    referenceType,
    referenceId,
    idempotencyKey,
    description,
  });
  const wallet = await commerceStore.getWallet(userId);
  return { wallet, entry };
}

/**
 * Moves escrow money to the seller's Firestore wallet exactly once. Re-delegates
 * to commerce-store which additionally closes out the app-facing order and
 * transaction docs in the same transaction.
 */
async function settleEscrowToSeller({ orderId, sellerId, amount, commission = 0, idempotencyKey }) {
  return commerceStore.settleEscrowToSeller({
    orderId,
    sellerId,
    amount,
    commission,
    idempotencyKey,
  });
}

module.exports = {
  LEDGER_TYPES,
  updateWalletBalance,
  settleEscrowToSeller,
};