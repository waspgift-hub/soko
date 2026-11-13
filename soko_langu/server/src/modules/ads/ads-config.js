const { getFirebaseFirestore } = require('../../config/firebase');

/**
 * Admin-controlled runtime configuration for advertising and marketplace
 * visibility.
 *
 * Stored in Firestore `app_settings/ad_config`, which `firestore.rules` restricts
 * to `isAdmin()` writes, and also exposed through
 * `PUT /api/v1/admin/config/ads` behind `authenticateAdmin`. Two independent
 * gates mean an admin change never requires a mobile release.
 *
 * Caching mirrors `search:products:*`: a short in-process TTL plus the Cloudflare
 * Worker's edge cache. A config change is therefore visible within roughly a
 * minute, which is the right trade for an emergency "switch ads off" lever.
 */

const DOC_ID = 'ad_config';
const TTL_MS = 60_000;

const DEFAULTS = Object.freeze({
  // ─── Advertising ──────────────────────────────────────────────────────────
  adsEnabled: true,
  bannerEnabled: true,
  nativeEnabled: true,
  interstitialEnabled: true,
  rewardedEnabled: true,
  disabledPlacements: [],
  disabledScreens: [],

  // ─── Blue Tick ────────────────────────────────────────────────────────────
  adsExemptBlueTickEnabled: true,

  // ─── Ranking ──────────────────────────────────────────────────────────────
  // searchVerifiedBoost is expressed as a fraction of the maximum achievable
  // relevance score. Because it is clamped to maxSearchVerifiedBoost (default
  // 0.25) and applied inside the relevance band, a verified seller can never
  // overtake a strictly more relevant result unless an admin explicitly flips
  // allowBoostToOutrankRelevance.
  searchVerifiedBoost: 0.12,
  maxSearchVerifiedBoost: 0.25,
  allowBoostToOutrankRelevance: false,

  // ─── Frequency ────────────────────────────────────────────────────────────
  frequency: Object.freeze({
    maxInterstitialsPerSession: 4,
    maxAdsPerSession: 12,
    minIntervalBetweenInterstitialsMs: 5 * 60_000,
    minTimeAfterLaunchMs: 2 * 60_000,
    minTimeAfterAnyAdMs: 2 * 60_000,
    minGapBetweenInlineAdsMs: 45_000,
    maxLoadAttemptsPerHour: 12,
    retryBackoffBaseMs: 45_000,
    maxRetryBackoffMs: 15 * 60_000,
    dailyInterstitialCeiling: 20,
    gateTtlMs: 30 * 24 * 60 * 60_000,
  }),

  version: 0,
});

let cached = null;
let cachedAt = 0;
let inFlight = null;

function coerce(raw) {
  if (!raw || typeof raw !== 'object') return { ...DEFAULTS, frequency: { ...DEFAULTS.frequency } };
  const bool = (v, d) => (typeof v === 'boolean' ? v : d);
  const int = (v, d, lo, hi) => {
    const n = Number(v);
    if (!Number.isFinite(n)) return d;
    return Math.min(hi, Math.max(lo, Math.trunc(n)));
  };
  const num = (v, d, lo, hi) => {
    const n = Number(v);
    if (!Number.isFinite(n)) return d;
    return Math.min(hi, Math.max(lo, n));
  };
  const list = (v) => (Array.isArray(v) ? v.map(String).filter(Boolean) : []);

  const maxBoost = num(raw.maxSearchVerifiedBoost, DEFAULTS.maxSearchVerifiedBoost, 0, 1);
  const freq = raw.frequency && typeof raw.frequency === 'object' ? raw.frequency : {};

  return {
    adsEnabled: bool(raw.adsEnabled, DEFAULTS.adsEnabled),
    bannerEnabled: bool(raw.bannerEnabled, DEFAULTS.bannerEnabled),
    nativeEnabled: bool(raw.nativeEnabled, DEFAULTS.nativeEnabled),
    interstitialEnabled: bool(raw.interstitialEnabled, DEFAULTS.interstitialEnabled),
    rewardedEnabled: bool(raw.rewardedEnabled, DEFAULTS.rewardedEnabled),
    disabledPlacements: list(raw.disabledPlacements),
    disabledScreens: list(raw.disabledScreens),
    adsExemptBlueTickEnabled: bool(raw.adsExemptBlueTickEnabled, DEFAULTS.adsExemptBlueTickEnabled),
    searchVerifiedBoost: num(raw.searchVerifiedBoost, DEFAULTS.searchVerifiedBoost, 0, maxBoost),
    maxSearchVerifiedBoost: maxBoost,
    allowBoostToOutrankRelevance: bool(
      raw.allowBoostToOutrankRelevance,
      DEFAULTS.allowBoostToOutrankRelevance,
    ),
    frequency: {
      maxInterstitialsPerSession: int(
        freq.maxInterstitialsPerSession,
        DEFAULTS.frequency.maxInterstitialsPerSession,
        0,
        50,
      ),
      maxAdsPerSession: int(freq.maxAdsPerSession, DEFAULTS.frequency.maxAdsPerSession, 0, 200),
      minIntervalBetweenInterstitialsMs: int(
        freq.minIntervalBetweenInterstitialsMs,
        DEFAULTS.frequency.minIntervalBetweenInterstitialsMs,
        0,
        24 * 60 * 60_000,
      ),
      minTimeAfterLaunchMs: int(
        freq.minTimeAfterLaunchMs,
        DEFAULTS.frequency.minTimeAfterLaunchMs,
        0,
        60 * 60_000,
      ),
      minTimeAfterAnyAdMs: int(freq.minTimeAfterAnyAdMs, DEFAULTS.frequency.minTimeAfterAnyAdMs, 0, 60 * 60_000),
      minGapBetweenInlineAdsMs: int(
        freq.minGapBetweenInlineAdsMs,
        DEFAULTS.frequency.minGapBetweenInlineAdsMs,
        0,
        60 * 60_000,
      ),
      maxLoadAttemptsPerHour: int(
        freq.maxLoadAttemptsPerHour,
        DEFAULTS.frequency.maxLoadAttemptsPerHour,
        0,
        500,
      ),
      retryBackoffBaseMs: int(freq.retryBackoffBaseMs, DEFAULTS.frequency.retryBackoffBaseMs, 1_000, 60 * 60_000),
      maxRetryBackoffMs: int(freq.maxRetryBackoffMs, DEFAULTS.frequency.maxRetryBackoffMs, 1_000, 24 * 60 * 60_000),
      dailyInterstitialCeiling: int(
        freq.dailyInterstitialCeiling,
        DEFAULTS.frequency.dailyInterstitialCeiling,
        0,
        500,
      ),
      gateTtlMs: int(freq.gateTtlMs, DEFAULTS.frequency.gateTtlMs, 0, 365 * 24 * 60 * 60_000),
    },
    version: int(raw.version, 0, 0, Number.MAX_SAFE_INTEGER),
  };
}

async function load({ force = false } = {}) {
  const now = Date.now();
  if (!force && cached && now - cachedAt < TTL_MS) return cached;
  if (inFlight && !force) return inFlight;

  inFlight = (async () => {
    try {
      const db = getFirebaseFirestore();
      const snap = await db.collection('app_settings').doc(DOC_ID).get();
      cached = snap.exists ? coerce(snap.data()) : coerce(null);
    } catch (e) {
      // Offline or denied: keep the last known value, or the compiled defaults.
      if (!cached) cached = coerce(null);
    } finally {
      cachedAt = Date.now();
      inFlight = null;
    }
    return cached;
  })();

  return inFlight;
}

/**
 * Persists an admin change and bumps the version so connected clients can tell
 * a real update from a cached read.
 */
async function save(patch, { actor } = {}) {
  const db = getFirebaseFirestore();
  const next = coerce({ ...(await load()), ...(patch || {}) });
  next.version = (cached ? cached.version : 0) + 1;
  next.updatedAt = new Date().toISOString();
  if (actor) next.updatedBy = String(actor);
  await db.collection('app_settings').doc(DOC_ID).set(next, { merge: true });
  cached = next;
  cachedAt = Date.now();
  return next;
}

/** Clears the process cache. Used by tests. */
function invalidate() {
  cached = null;
  cachedAt = 0;
}

module.exports = { DOC_ID, DEFAULTS, load, save, coerce, invalidate };