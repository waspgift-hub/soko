const { getPrisma } = require('../../config/database');

function httpError(status, message) {
  const error = new Error(message);
  error.status = status;
  return error;
}

/**
 * Financial Ledger Service (V3 Implementation)
 * 
 * Invariant: All wallet balance changes MUST be accompanied by a LedgerEntry.
 * All operations are wrapped in database transactions to ensure atomicity.
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
 * Atomic Wallet Update
 * Updates the wallet balance and creates a ledger entry in a single transaction.
 */
async function updateWalletBalance({
  sellerId,
  userId,
  amount,
  type,
  referenceType,
  referenceId,
  idempotencyKey,
  description,
  tx: providedTx,
}) {
  const prisma = getPrisma();
  const work = async (tx) => {
    // 1. Idempotency Check
    const existingEntry = await tx.walletLedgerEntry.findUnique({
      where: { idempotencyKey },
    });
    if (existingEntry) {
      const existingWallet = await tx.wallet.findUnique({ where: { id: existingEntry.walletId } });
      return { wallet: existingWallet, entry: existingEntry, alreadyApplied: true };
    }

    if (!idempotencyKey) throw httpError(400, 'IDEMPOTENCY_KEY_REQUIRED');

    // 2. Fetch/Create Wallet
    const sid = sellerId || userId;
    if (!sid) throw httpError(400, 'SELLER_ID_REQUIRED');

    let wallet = await tx.wallet.findUnique({ where: { sellerId: sid } });

    if (!wallet) {
      wallet = await tx.wallet.create({ data: { sellerId: sid } });
    }

    // 3. Calculate with exact BigInt arithmetic; TZS must never pass through JS Number.
    const delta = BigInt(amount);
    const newBalance = wallet.availableBalance + delta;
    if (newBalance < 0n) {
      throw new Error(`Insufficient funds in wallet for seller ${sellerId || userId}`);
    }

    // 4. Update Wallet
    const updatedWallet = await tx.wallet.update({
      where: { id: wallet.id },
      data: { availableBalance: newBalance },
    });

    const entry = await tx.walletLedgerEntry.create({
      data: {
        walletId: wallet.id,
        type,
        amount: delta,
        balanceAfter: updatedWallet.availableBalance,
        referenceType: referenceType || null,
        referenceId: referenceId || null,
        idempotencyKey,
        description: description || null,
      },
    });

    return { wallet: updatedWallet, entry };
  };
  return providedTx ? work(providedTx) : prisma.$transaction(work);
}

/**
 * Escrow Settlement
 * Moves funds from Escrow account to Seller Wallet.
 */
async function settleEscrowToSeller({ orderId, sellerId, amount, idempotencyKey = `settlement_${orderId}`, tx }) {
  return updateWalletBalance({
    sellerId,
    amount: BigInt(amount),
    type: LEDGER_TYPES.SETTLEMENT_CREDITED,
    referenceType: 'order',
    referenceId: orderId,
    idempotencyKey,
    description: 'Order settlement from escrow release',
    tx,
  });
}

module.exports = {
  LEDGER_TYPES,
  updateWalletBalance,
  settleEscrowToSeller,
};
