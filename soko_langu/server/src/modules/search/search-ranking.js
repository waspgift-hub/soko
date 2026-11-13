const rankingConfig = require('../ads/ads-config');

/**
 * Marketplace ranking.
 *
 * The Blue Tick is one weighted signal among several, never a hard-coded
 * "always #1" rule:
 *
 *     FinalScore = Relevance + Quality + Trust + Engagement + VerifiedSellerBoost
 *
 * Relevance remains dominant by construction. `MAX_RELEVANCE` is the largest
 * value `relevance()` can return for the live scorer, and the verified boost is
 * capped at `MAX_RELEVANCE * maxSearchVerifiedBoost` (default 0.25). An exact
 * title match therefore always outranks a token-only match, no matter how well
 * verified the latter's seller is.
 *
 * `allowBoostToOutrankRelevance` is the only way to relax that, and it is off by
 * default. When an admin turns it on the boost is still bounded by
 * `maxSearchVerifiedBoost`, so it can reorder within a narrow band but cannot
 * promote an irrelevant product to the top of an unrelated query.
 *
 * Engagement and quality are read from the product doc; neither rating, review
 * count nor sold count is ever modified by this system. Verified status changes
 * *ordering only*.
 */

/** Maximum score `relevance()` can return for a matching product. */
const MAX_RELEVANCE = 100;

const WEIGHTS = Object.freeze({
  quality: 18,
  trust: 12,
  engagement: 10,
});

function num(v, fallback = 0) {
  const n = Number(v);
  return Number.isFinite(n) ? n : fallback;
}

function clamp01(v) {
  const n = num(v, 0);
  return n < 0 ? 0 : n > 1 ? 1 : n;
}

/**
 * Quality: average rating, saturated at 5 stars. A seller cannot inflate this by
 * editing their own doc because `rating` and `reviewCount` are server-owned
 * (`firestore.rules` + `review-store.recomputeProductRating`).
 */
function quality(doc) {
  const rating = clamp01(num(doc.rating, 0) / 5);
  return rating * WEIGHTS.quality;
}

/**
 * Trust: fulfillment / dispute history when the catalog mirror carries it, else
 * the verification signal. Deliberately *not* the Blue Tick — that is the
 * separate `verifiedSellerBoost` term, so a verified seller with poor fulfilment
 * still ranks below an unverified seller with excellent fulfilment.
 */
function trust(doc) {
  const fulfilment = clamp01(num(doc.fulfilmentRate, num(doc.onTimeDispatchRate, 0)));
  const disputes = clamp01(num(doc.disputeRate, 0));
  return (fulfilment * 0.7 + (1 - disputes) * 0.3) * WEIGHTS.trust;
}

/** Engagement: sales velocity and review volume, log-damped so a runaway
 *  best-seller cannot dominate. */
function engagement(doc) {
  const sold = Math.log1p(Math.max(0, num(doc.soldCount, 0)));
  const reviews = Math.log1p(Math.max(0, num(doc.reviewCount, 0)));
  // log1p(1000) ~= 6.9; normalised so a very large catalogue saturates at 1.
  return Math.min(1, (sold / 7 + reviews / 5) / 2) * WEIGHTS.engagement;
}

/** True when the doc is genuinely verified, per the server-owned denormalised
 *  flag written by `kyc-service.mirrorToFirestore`. */
function isVerifiedSeller(doc) {
  return doc.sellerKycApproved === true;
}

/**
 * The configured verified-seller boost, in relevance points.
 * Held per config version so a ranking sweep does not re-read the config doc
 * for every candidate.
 */
let boostCache = { version: null, points: 0, allowOutrank: false };

/** Seeds the boost cache from the compiled defaults so ranking works even if the
 *  config document is unreachable. Callers normally overwrite this with the
 *  loaded config via [setRankingConfig]. */
function setRankingConfig(cfg) {
  const maxBoost = Number(cfg.maxSearchVerifiedBoost);
  const boost = Number(cfg.searchVerifiedBoost);
  const allowOutrank = cfg.allowBoostToOutrankRelevance === true;
  boostCache = {
    version: cfg.version,
    points:
      Math.max(0, Math.min(boost, Number.isFinite(maxBoost) ? maxBoost : 0.25)) * MAX_RELEVANCE,
    allowOutrank,
  };
  return boostCache;
}

/**
 * Raw verified-seller boost before the relevance clamp in [finalScore].
 *
 * With `allowBoostToOutrankRelevance` off the value is halved, so a verified
 * seller still gains a visible but bounded advantage: they break ties and win
 * within near-equal relevance, they do not leapfrog a clearly better match.
 */
function verifiedSellerBoost(doc) {
  if (!isVerifiedSeller(doc)) return 0;
  return boostCache.allowOutrank ? boostCache.points : boostCache.points * 0.5;
}

/**
 * Combines all signals. `relevance` must be the live scorer's output.
 */
function finalScore({ relevance, doc, config }) {
  if (config) setRankingConfig(config);
  const rel = num(relevance, 0);
  if (rel <= 0) return 0; // non-matching docs never enter the result set

  const boost = verifiedSellerBoost(doc);
  // With allowBoostToOutrankRelevance off, the boost can only reorder inside the
  // relevance band it belongs to: a doc can gain at most half its own relevance
  // score, so a strictly-better-relevance doc can still win on a tie-break but
  // never be displaced by more than that margin.
  const bounded = boostCache.allowOutrank ? boost : Math.min(boost, rel * 0.5);
  return rel + quality(doc) + trust(doc) + engagement(doc) + bounded;
}

/**
 * Sorts scored rows. Price sorts intentionally bypass relevance entirely, so the
 * verified boost is not applied there — a buyer who asked for cheapest-first
 * should get cheapest-first.
 */
function sortRows(rows, { sort, config } = {}) {
  if (sort === 'price_asc') return rows.slice().sort((a, b) => a.d.price - b.d.price);
  if (sort === 'price_desc') return rows.slice().sort((a, b) => b.d.price - a.d.price);
  if (config) setRankingConfig(config);

  return rows.slice().sort((a, b) => {
    const fa = finalScore({ relevance: a.score, doc: a.d, config });
    const fb = finalScore({ relevance: b.score, doc: b.d, config });
    if (fb !== fa) return fb - fa;
    // Deterministic tie-break: newest first, then id so pagination is stable.
    const created = String(b.d.createdAt || '').localeCompare(String(a.d.createdAt || ''));
    if (created !== 0) return created;
    return String(a.id).localeCompare(String(b.id));
  });
}

module.exports = {
  MAX_RELEVANCE,
  WEIGHTS,
  quality,
  trust,
  engagement,
  isVerifiedSeller,
  setRankingConfig,
  rankingConfig,
  verifiedSellerBoost,
  finalScore,
  sortRows,
};