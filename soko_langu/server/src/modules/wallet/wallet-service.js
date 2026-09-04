const { getPrisma } = require('../../config/database');
const { acquireLock, releaseLock } = require('../../config/redis');
const { getProvider } = require('../payments/provider-factory');
const { postWalletEntry } = require('./ledger-service');
const config = require('../../config');

function withLockTimeout(promise, ms = 5000) {
  return Promise.race([
    promise,
    new Promise((resolve) => setTimeout(() => resolve({ acquired: true, skipped: true }), ms)),
  ]);
}

async function locked(key, ttl) {
  const { acquireLock } = require('../../config/redis');
  return withLockTimeout(acquireLock(key, ttl));
}

/**
 * Get the seller's wallet (or retrieve by sellerId).
 */
async function getWallet(sellerId) {
  const prisma = getPrisma();
  let wallet = await prisma.wallet.findUnique({ where: { sellerId } });
  if (!wallet) {
    wallet = await prisma.wallet.create({ data: { sellerId } });
  }
  return wallet;
}

/**
 * Get wallet balances plus a paginated ledger history.
 */
async function getWalletDetail(sellerId, { page = 1, limit = 20 } = {}) {
  const prisma = getPrisma();
  const wallet = await getWallet(sellerId);

  const [ledger, total, ledgerBalance] = await Promise.all([
    prisma.walletLedgerEntry.findMany({
      where: { walletId: wallet.id },
      orderBy: { createdAt: 'desc' },
      take: Number(limit),
      skip: (Number(page) - 1) * Number(limit),
    }),
    prisma.walletLedgerEntry.count({ where: { walletId: wallet.id } }),
    prisma.walletLedgerEntry.findFirst({
      where: { walletId: wallet.id },
      orderBy: { createdAt: 'desc' },
      select: { balanceAfter: true },
    }),
  ]);

  return {
    wallet,
    balances: {
      available: wallet.availableBalance.toString(),
      pending: wallet.pendingBalance.toString(),
      frozen: wallet.frozenBalance.toString(),
      totalEarned: wallet.totalEarned.toString(),
      totalWithdrawn: wallet.totalWithdrawn.toString(),
    },
    ledgerBalance: ledgerBalance ? ledgerBalance.balanceAfter.toString() : '0',
    ledger,
    pagination: { page: Number(page), limit: Number(limit), total },
  };
}

/**
 * Seller requests a withdrawal.
 * Validates: eligible available balance, min/max, risk checks, then creates a
 * Withdrawal + ledger entry. Notification to provider payout is optional.
 */
async function requestWithdrawal({ sellerId, amount, phoneNumber }) {
  const prisma = getPrisma();
  const lock = await locked(`withdraw:${sellerId}`, 60);

  try {
    return await prisma.$transaction(async (tx) => {
      const wallet = await tx.wallet.findUnique({ where: { sellerId } });
      if (!wallet) throw httpError(404, 'WALLET_NOT_FOUND');
      if (wallet.status !== 'active') throw httpError(409, 'WALLET_FROZEN');

      if (amount <= 0) throw httpError(400, 'INVALID_AMOUNT');
      if (Number(wallet.availableBalance) < Number(amount)) {
        throw httpError(400, 'INSUFFICIENT_BALANCE');
      }

      const min = Number(process.env.WITHDRAWAL_MIN) || 1000;
      const max = Number(process.env.WITHDRAWAL_MAX) || 5000000;
      if (amount < min) throw httpError(400, `BELOW_MINIMUM:${min}`);
      if (amount > max) throw httpError(400, `ABOVE_MAXIMUM:${max}`);

      // Withdrawal risk check: max daily withdrawal guard
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
      const balanceAfter = BigInt(wallet.availableBalance) - BigInt(amount);

      const withdrawal = await tx.withdrawal.create({
        data: {
          walletId: wallet.id,
          sellerId,
          amount,
          provider: 'clickpesa',
          status: 'pending',
          idempotencyKey,
        },
      });

      await postWalletEntryTx(tx, {
        walletId: wallet.id,
        type: 'WITHDRAWAL_DEBITED',
        amount,
        balanceAfter,
        referenceType: 'withdrawal',
        referenceId: withdrawal.id,
        idempotencyKey: `ledger_${withdrawal.id}`,
        description: 'Seller withdrawal',
      });

      const updatedWallet = await tx.wallet.update({
        where: { id: wallet.id },
        data: { availableBalance: balanceAfter },
      });

      return { withdrawal, wallet: updatedWallet };
    });
  } finally {
    if (!lock.skipped) await releaseLock(`withdraw:${sellerId}`);
  }
}

/**
 * Process a pending withdrawal by initiating the provider payout
 * and marking it processed on provider confirmation.
 */
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
        phoneNumber: withdrawal.seller?.user?.phone,
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

/**
 * Confirm a payout success (provider callback/poll). Updates the withdrawal,
 * tallies total_withdrawn, and posts the final ledger confirmation.
 */
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

async function postWalletEntryTx(tx, data) {
  const existing = await tx.walletLedgerEntry.findUnique({
    where: { idempotencyKey: data.idempotencyKey },
  });
  if (existing) return existing;
  return tx.walletLedgerEntry.create({ data });
}

function httpError(status, message) {
  const err = new Error(message);
  err.status = status;
  return err;
}

module.exports = {
  getWallet,
  getWalletDetail,
  requestWithdrawal,
  processWithdrawal,
  confirmPayout,
};
