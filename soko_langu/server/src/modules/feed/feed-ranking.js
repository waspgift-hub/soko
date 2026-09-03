// Feed ranking weights (tunable)
const WEIGHTS = {
  watchTime: 0.30,
  completionRate: 0.20,
  productClickRate: 0.15,
  purchaseSignal: 0.15,
  shareRate: 0.10,
  engagementRate: 0.05,
  freshness: 0.05,
};

// Max age in ms for a post to get full freshness credit.
const FRESHNESS_FULL_MS = 24 * 60 * 60 * 1000; // 24 hours

function clamp01(x) {
  return Math.max(0, Math.min(1, x));
}

/**
 * Rank a single feed item. All inputs are 0..1 normalized signals.
 * Returns a score. Freshness decays over time.
 */
function rankItem({ watchTime = 0, completionRate = 0, productClickRate = 0, purchaseSignal = 0, shareRate = 0, engagementRate = 0, createdAt }) {
  const ageMs = createdAt ? Date.now() - new Date(createdAt).getTime() : 0;
  const freshness = ageMs <= 0 ? 1 : Math.max(0, 1 - ageMs / FRESHNESS_FULL_MS);

  return (
    WEIGHTS.watchTime * clamp01(watchTime) +
    WEIGHTS.completionRate * clamp01(completionRate) +
    WEIGHTS.productClickRate * clamp01(productClickRate) +
    WEIGHTS.purchaseSignal * clamp01(purchaseSignal) +
    WEIGHTS.shareRate * clamp01(shareRate) +
    WEIGHTS.engagementRate * clamp01(engagementRate) +
    WEIGHTS.freshness * freshness
  );
}

module.exports = { WEIGHTS, rankItem };
