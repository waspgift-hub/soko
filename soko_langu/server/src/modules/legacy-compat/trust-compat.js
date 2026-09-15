// Firestore-native Trust Passport: computes the same indicator model as the
// Postgres trust-passport module but from the Firestore orders the legacy
// compat engine actually uses, so seller UIDs resolve correctly.
const { Router } = require('express');

const COMPLETED_FAMILY = ['completed', 'wallet_credited', 'payout_pending', 'payout_complete'];
const TRANSIT_FAMILY = ['dispatched', 'in_transit', 'out_for_delivery', 'delivery_attempted'];

function levelFor(value, green, amber) {
  if (value >= green) return 'green';
  if (value >= amber) return 'amber';
  return 'red';
}

function rateOf(count, total) {
  return total > 0 ? count / total : 0;
}

async function collectSellerDocs(db, sellerId) {
  const seen = new Map();
  const consume = (snap) => {
    snap.forEach((docSnap) => {
      const docs = docSnap.data();
      if (!docs) return;
      const id = docSnap.id;
      const existing = seen.get(id);
      if (!existing) seen.set(id, docs);
    });
  };
  const [tx, orders] = await Promise.all([
    db.collection('transactions').where('sellerId', '==', sellerId).limit(300).get(),
    db.collection('orders').where('sellerId', '==', sellerId).limit(300).get(),
  ]);
  consume(tx);
  consume(orders);
  return Array.from(seen.values());
}

const router = Router();

// Public seller trust passport (Firestore-backed).
router.get('/trust/passport/:sellerId', async function (req, res) {
  try {
    const locals = req.app.locals;
    const admin = locals.admin;
    const db = locals.db;
    if (!db || !admin) return res.status(503).json({ error: 'Database not configured' });
    const sellerId = req.params.sellerId;
    if (!sellerId) return res.status(400).json({ error: 'sellerId required' });

    // Two-tier cache: passport reads up to 600 Firestore docs per request and
    // is viewed on every seller profile — serve 5-min stale copies instead.
    const cacheKey = `trust-passport:${sellerId}`;
    const cache = req.app.locals.cache;
    if (cache) {
      try {
        const cached = await cache.get(cacheKey);
        if (cached) {
          return res.json({ success: true, data: cached });
        }
      } catch (_) {}
    }

    let userSnap = null;
    try {
      userSnap = await db.collection('users').doc(sellerId).get();
    } catch (_) {}
    const profile = userSnap && userSnap.exists ? userSnap.data() : {};

    const docs = await collectSellerDocs(db, sellerId);

    const totalOrders = docs.length;
    const completedOrders = docs.filter(
      (o) => o.escrowReleased === true || COMPLETED_FAMILY.includes(o.status)
    ).length;
    const onTimeDispatches = docs.filter(
      (o) => o.dispatchedAt != null || TRANSIT_FAMILY.includes(o.status)
    ).length;
    const activeDisputes = docs.filter((o) => o.status === 'disputed').length;

    const fulfillmentRate = rateOf(completedOrders, totalOrders);
    const dispatchRate = rateOf(onTimeDispatches, totalOrders);
    const disputeRate = rateOf(activeDisputes, totalOrders);

    const reliabilityScore = Math.round(
      Math.min(
        100,
        Math.max(0, fulfillmentRate * 60 + (1 - disputeRate) * 40)
      )
    );

    const storeName = String(
      profile.storeName || profile.name || profile.displayName || 'Muuzaji'
    );
    const verificationStatus = String(profile.verificationStatus || 'grey');
    const identityLevel =
      verificationStatus === 'verified'
        ? 'green'
        : verificationStatus === 'pending'
          ? 'amber'
          : 'grey';

    const indicators = [
      { key: 'identity_verified', level: identityLevel },
      {
        key: 'fulfillment',
        value: Math.round(fulfillmentRate * 100),
        level: levelFor(fulfillmentRate, 0.9, 0.7),
      },
      {
        key: 'dispatch_punctuality',
        value: Math.round(dispatchRate * 100),
        level: levelFor(dispatchRate, 0.85, 0.6),
      },
      {
        key: 'dispute_behavior',
        value: Math.round(disputeRate * 100),
        level: levelFor(1 - disputeRate, 0.95, 0.85),
      },
    ];

    const body = {
      seller: {
        id: sellerId,
        storeName,
        reliabilityScore,
        verificationStatus,
      },
      metrics: {
        totalOrders,
        completedOrders,
        onTimeDispatches,
        activeDisputes,
        fulfillmentRate,
        dispatchRate,
        disputeRate,
      },
      indicators,
    };
    if (cache) {
      try {
        await cache.set(cacheKey, body, 300_000);
      } catch (_) {}
    }
    res.json({ success: true, data: body });
  } catch (e) {
    console.error('[TRUST-PASSPORT]', e.message);
    res.status(500).json({ error: 'Internal server error' });
  }
});

module.exports = router;