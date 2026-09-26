const { getPrisma } = require('../../config/database');
const { acquireLock, releaseLock } = require('../../config/redis');
const { getProvider } = require('../payments/provider-factory');
const ledgerService = require('./ledger-service');

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
 * Get the seller's wallet.
 */
async function getWallet(sellerId) {
  const prisma = getPrisma();
  let wallet = await prisma.wallet.findUnique({ where: { sellerId } });
  if (!wallet) {
    wallet = await prisma.wallet.create({ data: { sellerId } });
  }
  return wallet;
}

async function ensureWallet(tx, sellerId) {
  let wallet = await tx.wallet.findUnique({ where: { sellerId } });
  if (!wallet) {
    wallet = await tx.wallet.create({ data: { sellerId } });
  }
  return wallet;
}

/**
 * Get wallet balances plus a paginated ledger history from V3 Ledger.
 */
async function getWalletDetail(sellerId, { page = 1, limit = 20 } = {}) {
  const prisma = getPrisma();
  const wallet = await getWallet(sellerId);

  const [ledger, total] = await Promise.all([
    prisma.walletLedgerEntry.findMany({
      where: { walletId: wallet.id },
      orderBy: { createdAt: 'desc' },
      take: Number(limit),
      skip: (Number(page) - 1) * Number(limit),
    }),
    prisma.walletLedgerEntry.count({ where: { walletId: wallet.id } }),
  ]);

  return {
    wallet,
    balances: {
      available: wallet.availableBalance.toString(),
    },
    ledger,
    pagination: { page: Number(page), limit: Number(limit), total },
  };
}

/**
 * Seller requests a withdrawal.
 * Uses ledgerService.updateWalletBalance for atomic debit.
 */
async function requestWithdrawal({ sellerId, amount, phoneNumber }) {
  const prisma = getPrisma();
  const lock = await locked(`withdraw:${sellerId}`, 60);

  try {
    return await prisma.$transaction(async (tx) => {
      const wallet = await ensureWallet(tx, sellerId);
      if (wallet.status !== 'active') throw httpError(409, 'WALLET_FROZEN');

      if (amount <= 0) throw httpError(400, 'INVALID_AMOUNT');
      if (Number(wallet.availableBalance) < Number(amount)) {
        throw httpError(400, 'INSUFFICIENT_BALANCE');
      }

      const min = Number(process.env.WITHDRAWAL_MIN) || 0;
      const max = Number(process.env.WITHDRAWAL_MAX) || 5000000;
      if (amount < min) throw httpError(400, `BELOW_MINIMUM:${min}`);
      if (amount > max) throw httpError(400, `ABOVE_MAXIMUM:${max}`);

      const today = new Date();
      today.setHours(0, 0, 0, 0);
      const todayTotal = await tx.withdrawal.aggregate({
        where: { sellerId, createdAt: { gte: today }, status: { not: 'cancelled' } },
        _sum: { amount: true },
      });
      const dailyLimit = Number(process.env.DAILY_WITHDRAWAL_LIMIT) || 5000000;
      if (Number(todayTotal._sum.amount || 0) + Number(amount) > dailyLimit) {
        throw httpError(429, 'DAILY_WITHDRAWAL_LIMIT_EXCEEDED');
      }

      const idempotencyKey = `withdrawal_${sellerId}_${Date.now()}`;
      
      const withdrawal = await tx.withdrawal.create({
        data: {
          walletId: wallet.id,
          sellerId,
          amount,
          provider: 'clickpesa',
          status: 'pending',
          phoneNumber: phoneNumber || null,
          idempotencyKey,
        },
      });

      await ledgerService.updateWalletBalance({
        userId: sellerId,
        amount: -amount,
        type: ledgerService.LEDGER_TYPES.WITHDRAWAL_DEBITED,
        referenceType: 'withdrawal',
        referenceId: withdrawal.id,
        idempotencyKey: `ledger_withdrawal_${withdrawal.id}`,
        description: 'Seller withdrawal',
      });

      // We must fetch the updated wallet state to return it
      const updatedWallet = await tx.wallet.findUnique({
        where: { id: wallet.id },
      });

      return { withdrawal, wallet: updatedWallet };
    });
  } finally {
    if (!lock.skipped) await releaseLock(`withdraw:${sellerId}`);
  }
}

async function processWithdrawal({ withdrawalId, executedBy = 'system' }) {
  const prisma = getPrisma();
  const lock = await locked(`withdraw:${withdrawalId}`, 60);

  try {
    return await prisma.$transaction(async (tx) => {
      const withdrawal = await tx.withdrawal.findUnique({
        where: { id: withdrawalId },
        include: { seller: { include: { user: true } } },
      });
      if (!withdrawal) throw httpError(404, 'WITHDRAWAL_NOT_FOUND');
      if (withdrawal.status !== 'pending') throw httpError(409, 'WITHDRAWAL_NOT_PENDING');

      const provider = getProvider(withdrawal.provider || 'clickpesa');
      const payout = await provider.initiatePayout({
        amount: Number(withdrawal.amount),
        orderReference: `W${withdrawal.id}`,
        phoneNumber: withdrawalPayoutPhone(withdrawal),
      });

      const updated = await tx.withdrawal.update({
        where: { id: withdrawalId },
        data: {
          status: 'processing',
          providerPayoutId: payout.id || payout.providerPayoutId || null,
          processedAt: new Date(),
        },
      });

      await tx.payoutTransaction.create({
        data: {
          withdrawalId,
          amount: withdrawal.amount,
          providerResponse: payout,
          status: 'processing',
        },
      });

      return updated;
    });
  } finally {
    if (!lock.skipped) await releaseLock(`withdraw:${withdrawalId}`);
  }
}

async function confirmPayout({ withdrawalId, providerPayoutId }) {
  const prisma = getPrisma();
  const lock = await locked(`withdraw:${withdrawalId}`, 60);

  try {
    return await prisma.$transaction(async (tx) => {
      const withdrawal = await tx.withdrawal.findUnique({ where: { id: withdrawalId } });
      if (!withdrawal) throw httpError(404, 'WITHDRAWAL_NOT_FOUND');
      if (withdrawal.status === 'completed') return withdrawal;

      await tx.withdrawal.update({
        where: { id: withdrawalId },
        data: {
          status: 'completed',
          providerPayoutId: providerPayoutId || withdrawal.providerPayoutId,
        },
      });

      await tx.payoutTransaction.create({
        data: {
          withdrawalId,
          amount: withdrawal.amount,
          providerResponse: { providerPayoutId },
          status: 'completed',
        },
      });

      await tx.wallet.update({
        where: { id: withdrawal.walletId },
        data: { totalWithdrawn: { increment: withdrawal.amount } },
      });

      return withdrawal;
    });
  } finally {
    if (!lock.skipped) await releaseLock(`withdraw:${withdrawalId}`);
  }
}

async function creditLegacyBalance({ sellerId, amount, priorWithdrawn = 0, db = getPrisma() }) {
  const amt = Math.round(Number(amount));
  const withdrawn = Math.round(Number(priorWithdrawn));
  if (!Number.isFinite(amt) || amt <= 0) throw httpError(400, 'INVALID_AMOUNT');
  const lock = await locked(`legacy:${sellerId}`, 60);

  try {
    return await db.$transaction(async (tx) => {
      const prior = await tx.ledgerEntry.findFirst({
        where: { referenceType: 'legacy_balance', referenceId: sellerId },
      });
      if (prior) return { alreadyMigrated: true, sellerId };

      await ledgerService.updateWalletBalance({
        userId: sellerId,
        amount: amt,
        type: 'LEGACY_BALANCE',
        referenceType: 'legacy_balance',
        referenceId: sellerId,
        idempotencyKey: `legacy_balance_${sellerId}`,
        description: 'Firestore sellerBalance migrated at wallet cutover',
      });

      await tx.wallet.update({
        where: { sellerId },
        data: {
          totalWithdrawn: { increment: withdrawn },
          totalEarned: { increment: amt + withdrawn },
        },
      });

      return { alreadyMigrated: false, sellerId, amount: amt };
    });
  } finally {
    if (!lock.skipped) await releaseLock(`legacy:${sellerId}`);
  }
}

function withdrawalPayoutPhone(withdrawal) {
  return withdrawal.phoneNumber || withdrawal.seller?.user?.phone || null;
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
};