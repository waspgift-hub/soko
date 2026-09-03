const { getPrisma } = require('../../config/database');

/**
 * Compute a buyer reliability score (0-100) for abuse prevention.
 * Internal only — never exposed to the buyer. Signals: OTP release rate,
 * dispute-filing abuse, chargeback rate.
 */
async function computeBuyerReliability({ buyerId }) {
  const prisma = getPrisma();

  const [orders, buyerDisputes, refunds] = await Promise.all([
    prisma.order.findMany({
      where: { buyerId },
      orderBy: { createdAt: 'desc' },
      take: 50,
    }),
    prisma.dispute.count({ where: { filedBy: buyerId, status: 'resolved', resolution: 'FULL_REFUND' } }),
    prisma.refund.findMany({ where: { order: { buyerId } } }),
  ]);

  const total = orders.length;
  if (total === 0) return 0;

  const completed = orders.filter((o) =>
    ['completed', 'wallet_credited', 'payout_pending', 'payout_complete'].includes(o.status)
  ).length;
  const refundRate = refunds.length / total;
  const disputeLossRate = buyerDisputes / total;

  const score =
    0.60 * (completed / total) +
    0.20 * (1 - refundRate) +
    0.20 * (1 - disputeLossRate);

  return Math.round(100 * clamp(score, 0, 1));
}

function clamp(n, min, max) {
  return Math.max(min, Math.min(max, n));
}

module.exports = { computeBuyerReliability };
