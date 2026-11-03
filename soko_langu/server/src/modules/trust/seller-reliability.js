const { getPrisma } = require('../../config/database');

const SCORE_WINDOW_ORDERS = 50;
const BASE_WEIGHTS = {
  dispatchPunctuality: 0.35,
  cancellationRate: 0.15,
  deliveryCompletion: 0.25,
  disputeRate: 0.15,
  buyerFeedback: 0.10,
};

/**
 * Compute a seller reliability score (0-100) from transaction history.
 * Lower cancellation/dispute rates and higher dispatch/delivery completion
 * produce a higher score.
 */
async function computeSellerReliability({ sellerId }) {
  const prisma = getPrisma();

  const recentOrders = await prisma.order.findMany({
    where: { sellerId },
    orderBy: { createdAt: 'desc' },
    take: SCORE_WINDOW_ORDERS,
  });

  const total = recentOrders.length;
  if (total === 0) return 0;

  const completed = recentOrders.filter((o) =>
    ['completed', 'wallet_credited', 'payout_pending', 'payout_complete'].includes(o.status)
  ).length;
  const cancelled = recentOrders.filter((o) => o.status === 'cancelled').length;
  const dispatched = recentOrders.filter((o) => o.dispatchedAt).length;
  const disputed = recentOrders.filter((o) => o.status === 'disputed').length;

  const dispatchPunctuality = dispatched / total;
  const cancellationRate = cancelled / total;
  const deliveryCompletion = completed / total;
  const disputeRate = disputed / total;

  const score =
    BASE_WEIGHTS.dispatchPunctuality * dispatchPunctuality * 100 +
    BASE_WEIGHTS.cancellationRate * (1 - cancellationRate) * 100 +
    BASE_WEIGHTS.deliveryCompletion * deliveryCompletion * 100 +
    BASE_WEIGHTS.disputeRate * (1 - disputeRate) * 100 +
    BASE_WEIGHTS.buyerFeedback * defaultFeedbackScore(recentOrders);

  const rounded = Math.round(clamp(score, 0, 100));

  // Persist back onto seller profile
  await prisma.sellerProfile.update({
    where: { id: sellerId },
    data: { reliabilityScore: rounded / 100 } // stored as 0..1 decimal
  });

  return rounded;
}

function defaultFeedbackScore(orders) {
  // Placeholder: buyer feedback integration point; neutral 0.5 until wired.
  return 0.5;
}

function clamp(n, min, max) {
  return Math.max(min, Math.min(max, n));
}

module.exports = { computeSellerReliability, BASE_WEIGHTS, SCORE_WINDOW_ORDERS };
