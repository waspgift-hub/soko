const { getStore } = require('../../config/database');
const { getFirebaseFirestore } = require('../../config/firebase');
const { deriveBlueTick } = require('../ads/blue-tick');

/**
 * Trust passport: combines seller identity, transaction history, fulfillment,
 * dispute behavior, review quality, and verified business signals into
 * visible Trust indicators.
 */
async function getTrustPassport({ sellerId }) {
  const store = getStore();

  // Accept both the Postgres SellerProfile UUID and the Firebase UID (User.id /
  // SellerProfile.userId).  Client order docs carry the Firebase UID; admin or
  // internal callers may pass the Postgres UUID directly.
  let seller = await store.sellerProfile.findUnique({ where: { id: sellerId } });
  if (!seller) {
    seller = await store.sellerProfile.findUnique({ where: { userId: sellerId } });
  }
  if (!seller) throw httpError(404, 'SELLER_NOT_FOUND');

  // The Blue Tick is derived from authoritative KYC state plus the admin grant,
  // never read straight off a client-writable field.
  const firebaseUid = seller.userId || (typeof sellerId === 'string' && /^[a-zA-Z0-9]{20,}$/.test(sellerId) ? sellerId : null);
  const userDoc = firebaseUid ? await readUserDoc(firebaseUid) : null;
  const blueTick = deriveBlueTick(userDoc, seller);

  // Aggregate order metrics
  const [totalOrders, completedOrders, onTimeDispatches, activeDisputes, reviews] = await Promise.all([
    store.order.count({ where: { sellerId } }),
    store.order.count({ where: { sellerId, status: { in: ['completed', 'wallet_credited', 'payout_pending', 'payout_complete'] } } }),
    store.order.count({ where: { sellerId, dispatchedAt: { not: null } } }),
    store.dispute.count({ where: { order: { sellerId }, status: 'open' } }),
    store.order.count({ where: { sellerId, status: 'completed' } }), // placeholder for reviews
  ]);

  const fulfillmentRate = totalOrders > 0 ? completedOrders / totalOrders : 0;
  const dispatchRate = totalOrders > 0 ? onTimeDispatches / totalOrders : 0;
  const disputeRate = totalOrders > 0 ? activeDisputes / totalOrders : 0;

  const indicators = [
    {
      key: 'identity_verified',
      level: blueTick.blueTick === 'active' ? 'green' : blueTick.kyc.status === 'approved' ? 'amber' : 'grey',
    },
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
      firebaseUid: firebaseUid || null,
    },
    // The single source of truth for the Blue Tick badge and the ad exemption.
    // Clients must render from this, never from a client-supplied boolean.
    trust: {
      blueTick: blueTick.blueTick,
      adsExempt: blueTick.adsExempt,
      reason: blueTick.reason,
      kyc: {
        status: blueTick.kyc.status,
        approved: blueTick.kyc.approved,
      },
      blueTickGrantedAt: blueTick.grantedAt,
      blueTickRevokedAt: blueTick.revokedAt,
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

/** Best-effort Firestore read. A missing doc or an unreachable Firestore yields
 *  null, which `deriveBlueTick` treats as "no verification", so a transient
 *  outage downgrades a badge rather than inventing one. */
async function readUserDoc(uid) {
  try {
    const db = getFirebaseFirestore();
    const snap = await db.collection('users').doc(uid).get();
    return snap.exists ? snap.data() : null;
  } catch (_) {
    return null;
  }
}

function httpError(status, message) {
  const e = new Error(message);
  e.status = status;
  return e;
}

module.exports = { getTrustPassport };
