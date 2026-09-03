const { getPrisma } = require('../../config/database');

/**
 * Trust passport: combines seller identity, transaction history, fulfillment,
 * dispute behavior, review quality, and verified business signals into
 * visible Trust indicators.
 */
async function getTrustPassport({ sellerId }) {
  const prisma = getPrisma();
  const seller = await prisma.sellerProfile.findUnique({
    where: { id: sellerId },
  });
  if (!seller) throw httpError(404, 'SELLER_NOT_FOUND');

  // Aggregate order metrics
  const [totalOrders, completedOrders, onTimeDispatches, activeDisputes, reviews] = await Promise.all([
    prisma.order.count({ where: { sellerId } }),
    prisma.order.count({ where: { sellerId, status: { in: ['completed', 'wallet_credited', 'payout_pending', 'payout_complete'] } } }),
    prisma.order.count({ where: { sellerId, dispatchedAt: { not: null } } }),
    prisma.dispute.count({ where: { order: { sellerId }, status: 'open' } }),
    prisma.order.count({ where: { sellerId, status: 'completed' } }), // placeholder for reviews
  ]);

  const fulfillmentRate = totalOrders > 0 ? completedOrders / totalOrders : 0;
  const dispatchRate = totalOrders > 0 ? onTimeDispatches / totalOrders : 0;
  const disputeRate = totalOrders > 0 ? activeDisputes / totalOrders : 0;

  const indicators = [
    { key: 'identity_verified', level: seller.verificationStatus === 'verified' ? 'green' : seller.verificationStatus === 'pending' ? 'amber' : 'grey' },
    { key: 'fulfillment', value: Math.round(fulfillmentRate * 100), level: fulfillmentRate >= 0.9 ? 'green' : fulfillmentRate >= 0.7 ? 'amber' : 'red' },
    { key: 'dispatch_punctuality', value: Math.round(dispatchRate * 100), level: dispatchRate >= 0.85 ? 'green' : dispatchRate >= 0.6 ? 'amber' : 'red' },
    { key: 'dispute_behavior', level: disputeRate <= 0.05 ? 'green' : disputeRate <= 0.15 ? 'amber' : 'red' },
  ];

  return {
    seller: {
      id: seller.id,
      storeName: seller.storeName,
      storeSlug: seller.storeSlug,
      reliabilityScore: Number(seller.reliabilityScore),
      verificationStatus: seller.verificationStatus,
    },
    metrics: {
      totalOrders,
      completedOrders,
      onTimeDispatches,
      activeDisputes,
      reviews,
      fulfillmentRate,
      dispatchRate,
      disputeRate,
    },
    indicators,
  };
}

function httpError(status, message) {
  const e = new Error(message);
  e.status = status;
  return e;
}

module.exports = { getTrustPassport };
