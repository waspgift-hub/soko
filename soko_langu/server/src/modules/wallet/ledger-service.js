const { getPrisma } = require('../../config/database');

/**
 * Append-only financial ledger.
 *
 * Invariant: Buyer payment = Seller entitlement + Platform commission + authorized adjustments.
 *
 * NEVER settle by directly incrementing a balance without a ledger entry.
 * Every ledger entry carries a unique idempotency key to prevent double-posting.
 */

const LEDGER_TYPES = {
  PAYMENT_RECEIVED: 'PAYMENT_RECEIVED',        // buyer -> escrow
  SHIPPING_FEE_RECEIVED: 'SHIPPING_FEE_RECEIVED', // buyer -> escrow
  COMMISSION_DEBITED: 'COMMISSION_DEBITED',    // escrow -> platform
  SETTLEMENT_CREDITED: 'SETTLEMENT_CREDITED',  // escrow -> seller wallet
  WITHDRAWAL_DEBITED: 'WITHDRAWAL_DEBITED',    // seller wallet -> payout
  REFUND_PROCESSED: 'REFUND_PROCESSED',        // escrow -> buyer
  CHARGEBACK: 'CHARGEBACK',                    // escrow -> platform
  ADJUSTMENT: 'ADJUSTMENT',                    // manual correction with audit
};

/**
 * Append a wallet ledger entry. Idempotent on the unique idempotencyKey;
 * if a duplicate is posted, it is silently skipped and returns the existing entry.
 */
async function postWalletEntry({
  walletId,
  type,
  amount,
  balanceAfter,
  referenceType,
  referenceId,
  idempotencyKey,
  description,
}) {
  const prisma = getPrisma();

  const existing = await prisma.walletLedgerEntry.findUnique({
    where: { idempotencyKey },
  });
  if (existing) return existing;

  return prisma.walletLedgerEntry.create({
    data: {
      walletId,
      type,
      amount,
      balanceAfter,
      referenceType,
      referenceId,
      idempotencyKey,
      description,
    },
  });
}

/**
 * Post an escrow transaction (escrow-level ledger for FUNDS_HELD, release, commission).
 */
async function postEscrowTransaction({ escrowHoldId, type, amount, referenceId }) {
  const prisma = getPrisma();
  return prisma.escrowTransaction.create({
    data: { escrowHoldId, type, amount, referenceId },
  });
}

/**
 * Reconcile a wallet: balanceAfter on the latest ledger entry should equal
 * the wallet's available balance. Returns discrepancy if any.
 */
async function reconcileWallet(walletId) {
  const prisma = getPrisma();
  const wallet = await prisma.wallet.findUnique({ where: { id: walletId } });
  const latest = await prisma.walletLedgerEntry.findFirst({
    where: { walletId },
    orderBy: { createdAt: 'desc' },
  });

  const ledgerBalance = latest ? latest.balanceAfter : 0n;
  return {
    walletId,
    walletBalance: wallet.availableBalance,
    ledgerBalance,
    inSync: wallet.availableBalance === ledgerBalance,
  };
}

module.exports = {
  LEDGER_TYPES,
  postWalletEntry,
  postEscrowTransaction,
  reconcileWallet,
};
