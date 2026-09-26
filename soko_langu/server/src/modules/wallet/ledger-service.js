const { getPrisma } = require('../../config/database');

/**
 * Wallet ledger service (authoritative schema).
 *
 * Invariant: every wallet balance change MUST be accompanied by a
 * WalletLedgerEntry row with a unique idempotencyKey. The wallet is keyed by
 * sellerId (SellerProfile), not a user id, and money math is BigInt end-to-end.
 *
 * `updateWalletBalance` runs inside the caller's interactive transaction when
 * `tx` is supplied (Prisma forbids nested $transaction calls), and opens its
 * own transaction otherwise.
 */

const LEDGER_TYPES = {
  PAYMENT_RECEIVED: 'PAYMENT_RECEIVED',        // Buyer -> Escrow
  SHIPPING_FEE_RECEIVED: 'SHIPPING_FEE_RECEIVED', // Buyer -> Escrow
  COMMISSION_DEBITED: 'COMMISSION_DEBITED',    // Escrow -> Platform
  SETTLEMENT_CREDITED: 'SETTLEMENT_CREDITED',  // Escrow -> Seller Wallet
  WITHDRAWAL_DEBITED: 'WITHDRAWAL_DEBITED',    // Seller Wallet -> Payout
  REFUND_PROCESSED: 'REFUND_PROCESSED',        // Escrow -> Buyer
  ADJUSTMENT: 'ADJUSTMENT',                    // Manual correction
};

/**
 * Atomic wallet update: debit or credit the seller wallet and post a matching
 * WalletLedgerEntry in one transaction. Idempotent per idempotencyKey — a
 * retry with the same key returns the existing entry without touching money.
 */
async function updateWalletBalance({
  sellerId,
  amount, // Positive for credit, negative for debit (BigInt or number)
  type,
  referenceType,
  referenceId,
  idempotencyKey,
  description,
  tx,
  wallet,
}) {
  const prisma = getPrisma();
  if (!tx) {
    return prisma.$transaction(async (inner) =>
      updateWalletBalance({
        sellerId,
        amount,
        type,
        referenceType,
        referenceId,
        idempotencyKey,
        description,
        tx: inner,
      })
    );
  }

  // 1. Idempotency check
  const existingEntry = await tx.walletLedgerEntry.findUnique({
    where: { idempotencyKey },
  });
  if (existingEntry) {
    return { wallet: existingEntryWallet(tx, existingEntry), entry: existingEntry };
  }

  // 2. Fetch/Create the seller wallet
  const existingWallet = wallet ?? (await tx.wallet.findUnique({ where: { sellerId } }));
  const w = existingWallet ??
    await tx.wallet.create({ data: { sellerId } });

  // 3. Calculate the new balance in BigInt
  const delta = BigInt(amount);
  const newBalance = BigInt(w.availableBalance) + delta;
  if (newBalance < 0n) {
    const err = new Error(`Insufficient funds in wallet for seller ${sellerId}`);
    err.status = 400;
    throw err;
  }

  // 4. Update wallet + post the ledger entry atomically
  const updatedWallet = await tx.wallet.update({
    where: { id: w.id },
    data: { availableBalance: newBalance, updatedAt: new Date() },
  });

  const entry = await tx.walletLedgerEntry.create({
    data: {
      walletId: w.id,
      type,
      amount: delta < 0n ? -delta : delta,
      balanceAfter: newBalance,
      referenceType,
      referenceId,
      idempotencyKey,
      description,
      createdAt: new Date(),
    },
  });

  return { wallet: updatedWallet, entry };
}

async function existingEntryWallet(tx, entry) {
  try {
    return await tx.wallet.findUnique({ where: { id: entry.walletId } });
  } catch {
    return null;
  }
}

module.exports = {
  LEDGER_TYPES,
  updateWalletBalance,
};