const { getPrisma } = require('../../config/database');

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
  userId,
  amount, // Positive for credit, negative for debit
  type,
  referenceType,
  referenceId,
  idempotencyKey,
  description,
}) {
  const prisma = getPrisma();

  return prisma.$transaction(async (tx) => {
    // 1. Idempotency Check
    const existingEntry = await tx.ledgerEntry.findUnique({
      where: { id: idempotencyKey }, // Using the idempotency key as the entry ID for simplicity
    });
    if (existingEntry) return existingEntry;

    // 2. Fetch/Create Wallet
    let wallet = await tx.wallet.findUnique({
      where: { ownerId: userId },
    });

    if (!wallet) {
      wallet = await tx.wallet.create({
        data: { ownerId: userId, availableBalance: 0 },
      });
    }

    // 3. Calculate new balance
    const newBalance = Number(wallet.availableBalance) + Number(amount);
    if (newBalance < 0) {
      throw new Error(`Insufficient funds in wallet for user ${userId}`);
    }

    // 4. Update Wallet
    const updatedWallet = await tx.wallet.update({
      where: { id: wallet.id },
      data: { availableBalance: newBalance, updatedAt: new Date() },
    });

    // 5. Create Ledger Entry
    // We need a LedgerAccount for the user
    let account = await tx.ledgerAccount.findFirst({
      where: { userId, accountName: 'USER_WALLET' },
    });

    if (!account) {
      account = await tx.ledgerAccount.create({
        data: { userId, accountName: 'USER_WALLET', type: 'ASSET' },
      });
    }

    const entry = await tx.ledgerEntry.create({
      data: {
        id: idempotencyKey,
        accountId: account.id,
        transactionId: referenceId,
        direction: amount > 0 ? 'CREDIT' : 'DEBIT',
        amount: Math.abs(amount),
        referenceType,
        referenceId,
        createdAt: new Date(),
      },
    });

    return { wallet: updatedWallet, entry };
  });
}

/**
 * Escrow Settlement
 * Moves funds from Escrow account to Seller Wallet.
 */
async function settleEscrowToSeller({
  orderId,
  sellerId,
  amount,
  idempotencyKey,
}) {
  const prisma = getPrisma();

  return prisma.$transaction(async (tx) => {
    // 1. Debit from Escrow Pool (Internal Account)
    const escrowAccount = await tx.ledgerAccount.findFirst({
      where: { accountName: 'ESCROW_POOL' },
    });

    if (!escrowAccount) throw new Error('Escrow pool account not found');

    await tx.ledgerEntry.create({
      data: {
        accountId: escrowAccount.id,
        transactionId: orderId,
        direction: 'DEBIT',
        amount,
        referenceType: 'SETTLEMENT',
        referenceId: orderId,
      },
    });

    // 2. Credit to Seller Wallet
    return updateWalletBalance({
      userId: sellerId,
      amount,
      type: LEDGER_TYPES.SETTLEMENT_CREDITED,
      referenceType: 'SETTLEMENT',
      referenceId: orderId,
      idempotencyKey,
    });
  });
}

module.exports = {
  LEDGER_TYPES,
  updateWalletBalance,
  settleEscrowToSeller,
};
