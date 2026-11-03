const config = require('../../config');

// Baseline shipping cost buckets (TZS) by distance tier.
// Configurable; these are sane defaults for Tanzania intercity/regional delivery.
const DISTANCE_BASELINE = {
  intra_city: { min: 2000, max: 8000 },
  nearby: { min: 3000, max: 15000 },
  regional: { min: 5000, max: 30000 },
  cross_regional: { min: 10000, max: 60000 },
};

// A quote deviating beyond this multiple of the midpoint triggers review.
// E.g. midpoint 5000 -> review if below 2500 or above 12000.
const DEVIATION_THRESHOLD = 2.4;

/**
 * Determine a rough distance tier from city/region strings.
 * This is intentionally conservative and overridable by admin baselines.
 */
function estimateDistanceTier(shippingAddress, sellerRegion) {
  if (!shippingAddress || !sellerRegion) return 'cross_regional';
  const sameRegion =
    String(shippingAddress.region || '').toLowerCase() ===
    String(sellerRegion || '').toLowerCase();
  if (sameRegion) {
    const sameCity =
      String(shippingAddress.city || '').toLowerCase() ===
      String(shippingAddress.city || '').toLowerCase();
    return sameCity ? 'intra_city' : 'nearby';
  }
  return 'cross_regional';
}

/**
 * Validate a seller's shipping quote against regional baselines and risk signals.
 * Returns { verdict: 'NORMAL'|'REVIEW_REQUIRED'|'BLOCKED', reason, distanceTier }.
 */
function validateShippingQuote({ amount, shippingAddress, sellerRegion, sellerRiskScore = 0 }) {
  const tier = estimateDistanceTier(shippingAddress, sellerRegion);
  const baseline = DISTANCE_BASELINE[tier] || DISTANCE_BASELINE.cross_regional;
  const midpoint = (baseline.min + baseline.max) / 2;

  let verdict = 'NORMAL';
  let reason = null;

  // Hard upper bound: never allow egregiously inflated quotes without review.
  if (amount > baseline.max * DEVIATION_THRESHOLD) {
    verdict = 'REVIEW_REQUIRED';
    reason = `Quote TZS ${amount} exceeds baseline max TZS ${baseline.max} for ${tier}`;
  }

  // Unusually low quotes (possible fee-shifting / scam signal).
  if (amount < baseline.min / 2) {
    verdict = verdict === 'REVIEW_REQUIRED' ? 'REVIEW_REQUIRED' : 'REVIEW_REQUIRED';
    reason = (reason ? reason + '; ' : '') + `Quote TZS ${amount} unusually low for ${tier}`;
  }

  // High-risk seller quotes get flagged regardless of amount.
  if (sellerRiskScore >= 70) {
    verdict = 'REVIEW_REQUIRED';
    reason = (reason ? reason + '; ' : '') + `Seller risk score ${sellerRiskScore}`;
  }

  // Block hard-failing risk signals only when combined with an inflated quote.
  if (verdict === 'REVIEW_REQUIRED' && sellerRiskScore >= 90 && amount > baseline.max * DEVIATION_THRESHOLD) {
    verdict = 'BLOCKED';
    reason = `High-risk seller ${sellerRiskScore} with inflated quote`;
  }

  return { verdict, reason, distanceTier: tier, baseline };
}

module.exports = {
  DISTANCE_BASELINE,
  DEVIATION_THRESHOLD,
  estimateDistanceTier,
  validateShippingQuote,
};
