// Creation-time order risk.
//
// The auto-release gate already refuses to pay a self-dealt order, but that is
// the last line of defence: by then the fake GMV, review eligibility and
// support cost have already happened. This module looks at the buyer/seller
// relationship and the buyer's recent order rate *before* the order exists, so
// the fraud is stopped at the door and the signals are visible to admins.
//
// Signals are persisted on the order (`riskSignals`) instead of only returned,
// so later reviews, disputes and payouts can see what creation already knew.
// Only self-dealing blocks; velocity is recorded and alerted because a loyal
// customer or a reseller can legitimately place several orders quickly.
const RISK_THRESHOLDS = {
  burstWindowMinutes: 10,
  burstOrderLimit: 5,        // buyer orders inside the window that trigger a burst
  pairWindowHours: 24,
  pairOrderLimit: 5,         // same buyer -> same seller inside the window
  newAccountHours: 24,
  newAccountOrderLimit: 3,   // orders inside the burst window for a new account
};

const RISK_SIGNALS = {
  SELF_DEALING: 'SELF_DEALING',
  RAPID_ORDER_BURST: 'RAPID_ORDER_BURST',
  REPEAT_BUYER_SELLER_PAIR: 'REPEAT_BUYER_SELLER_PAIR',
  BUYER_NEW_ACCOUNT_BURST: 'BUYER_NEW_ACCOUNT_BURST',
};

const SIGNAL_DETAILS = {
  [RISK_SIGNALS.SELF_DEALING]: {
    severity: 'high',
    score: 3,
    detail: 'Buyer and seller resolve to the same account',
  },
  [RISK_SIGNALS.RAPID_ORDER_BURST]: {
    severity: 'medium',
    score: 2,
    detail: 'Unusually many orders from one buyer in a short window',
  },
  [RISK_SIGNALS.REPEAT_BUYER_SELLER_PAIR]: {
    severity: 'medium',
    score: 2,
    detail: 'Same buyer and seller trading repeatedly in a short window',
  },
  [RISK_SIGNALS.BUYER_NEW_ACCOUNT_BURST]: {
    severity: 'medium',
    score: 2,
    detail: 'Brand-new buyer account placing several orders immediately',
  },
};

const MINUTE = 60 * 1000;
const HOUR = 60 * MINUTE;

function toMillis(value) {
  if (value == null) return null;
  if (typeof value.toDate === 'function') return value.toDate().getTime();
  if (value instanceof Date) return value.getTime();
  if (typeof value === 'number') return value;
  const parsed = new Date(value).getTime();
  return Number.isFinite(parsed) ? parsed : null;
}

function orderTime(order) {
  return toMillis(order && (order.placedAt || order.createdAt));
}

function inWindow(order, sinceMs, nowMs) {
  const at = orderTime(order);
  return at != null && at >= sinceMs && at <= nowMs;
}

/**
 * Evaluate the risk of one new order for a buyer/seller pair.
 *
 * `store` is the store root or an interactive transaction; both expose the same
 * model facades. Missing model methods are tolerated so the rule never turns a
 * data-layer change into a checkout outage.
 */
async function evaluateOrderRisk(store, { buyerId, sellerId, now = new Date() } = {}) {
  const nowMs = now instanceof Date ? now.getTime() : toMillis(now);
  const signals = [];
  const details = [];

  const add = (code, extra = {}) => {
    if (signals.includes(code)) return;
    const meta = SIGNAL_DETAILS[code];
    signals.push(code);
    details.push({ code, severity: meta.severity, score: meta.score, detail: meta.detail, ...extra });
  };

  if (!buyerId) return { signals, details, blocked: false, score: 0 };

  let sellerUserId = null;
  if (sellerId && store.sellerProfile && typeof store.sellerProfile.findUnique === 'function') {
    const profile = await store.sellerProfile.findUnique({ where: { id: sellerId } });
    sellerUserId = profile ? (profile.userId || profile.id) : null;
  }

  if (sellerUserId && String(sellerUserId) === String(buyerId)) {
    add(RISK_SIGNALS.SELF_DEALING);
    return { signals, details, blocked: true, score: 3 };
  }

  let buyerOrders = [];
  if (typeof store.order?.findMany === 'function') {
    buyerOrders = await store.order.findMany({ where: { buyerId } });
  }

  const burst = buyerOrders.filter((o) => inWindow(o, nowMs - RISK_THRESHOLDS.burstWindowMinutes * MINUTE, nowMs));
  if (burst.length >= RISK_THRESHOLDS.burstOrderLimit) {
    add(RISK_SIGNALS.RAPID_ORDER_BURST, { count: burst.length });
  }

  const pair = buyerOrders.filter(
    (o) => String(o.sellerId || '') === String(sellerId || '')
      && inWindow(o, nowMs - RISK_THRESHOLDS.pairWindowHours * HOUR, nowMs),
  );
  if (pair.length >= RISK_THRESHOLDS.pairOrderLimit) {
    add(RISK_SIGNALS.REPEAT_BUYER_SELLER_PAIR, { count: pair.length });
  }

  let buyerCreatedAt = null;
  if (store.user && typeof store.user.findUnique === 'function') {
    const buyer = await store.user.findUnique({ where: { id: buyerId } });
    buyerCreatedAt = buyer ? toMillis(buyer.createdAt) : null;
  }
  if (
    buyerCreatedAt != null
    && nowMs - buyerCreatedAt < RISK_THRESHOLDS.newAccountHours * HOUR
    && burst.length >= RISK_THRESHOLDS.newAccountOrderLimit
  ) {
    add(RISK_SIGNALS.BUYER_NEW_ACCOUNT_BURST, { count: burst.length });
  }

  return { signals, details, blocked: false, score: details.reduce((sum, d) => sum + d.score, 0) };
}

/**
 * Write one admin-visible `fraud_alerts` row per signal. Best-effort: a failed
 * alert must never roll back a legitimate order, and `store` may be a test
 * double without the model.
 */
async function raiseFraudAlerts(store, { signals = [], details = [], buyerId, sellerId, productId, orderId, orderNumber, now = new Date() } = {}) {
  if (!signals.length) return 0;
  if (!store.fraudAlert || typeof store.fraudAlert.create !== 'function') return 0;

  let sellerName = sellerId || 'Unknown';
  if (sellerId && store.sellerProfile && typeof store.sellerProfile.findUnique === 'function') {
    const profile = await store.sellerProfile.findUnique({ where: { id: sellerId } });
    sellerName = (profile && (profile.storeName || profile.businessName || profile.displayName)) || sellerName;
  }

  let written = 0;
  for (const detail of details) {
    try {
      await store.fraudAlert.create({
        data: {
          type: detail.code,
          severity: detail.severity,
          description: detail.detail,
          sellerId: sellerId || null,
          sellerName,
          buyerId: buyerId || null,
          productId: productId || null,
          orderId: orderId || null,
          orderNumber: orderNumber || null,
          detectedAt: now,
          resolved: false,
        },
      });
      written += 1;
    } catch (e) {
      console.error('[FRAUD][ALERT]', e.message);
    }
  }
  return written;
}

module.exports = {
  RISK_THRESHOLDS,
  RISK_SIGNALS,
  evaluateOrderRisk,
  raiseFraudAlerts,
  // Exposed for tests of the time normalization.
  toMillis,
};
