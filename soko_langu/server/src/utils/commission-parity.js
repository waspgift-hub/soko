const config = require('../config');

// Buyer-pays-top commission (Terms 8.2): the platform fee is charged on the
// item subtotal only — never on shipping — and is added to what the buyer pays.
// The seller still nets the item price plus shipping in full, which is the
// invariant escrow-release relies on when it computes
// `sellerReceives = totalAmount - platformCommission`.
function normalizeRate(rate) {
  const n = Number(rate);
  if (!Number.isFinite(n) || n < 0) return 0;
  // The admin field is labelled "(%)", so accept both 3.5 and 0.035.
  if (n > 1) return n <= 100 ? n / 100 : 0;
  return n;
}

// Configured fraction (0.035 = 3.5%). Read at call time so an env override is
// honoured without reloading the module.
function platformRate() {
  return normalizeRate(config.business.platformCommissionPercent);
}

// The admin panel field is the owner's live control. Cache the resolved value
// briefly so a checkout does not pay a Firestore read every time, while a panel
// change still applies within a minute instead of needing a deploy.
const RATE_CACHE_TTL_MS = 60 * 1000;
let rateCache = { at: 0, rate: null };

/**
 * Effective commission rate, in precedence order:
 *   1. `paymentsAndCurrency.platformCommissionPct` from the admin settings
 *      document, when the owner has actually saved one.
 *   2. `PLATFORM_COMMISSION_PERCENT` env var (default 3.5%).
 *   3. 0, only when neither source yields a usable value.
 *
 * A stored 0 is honoured (a real zero-fee promotion); a missing document or a
 * failed Firestore read falls through to the env default so an outage cannot
 * silently change what buyers are charged.
 */
async function resolvePlatformRate() {
  if (rateCache.rate != null && Date.now() - rateCache.at < RATE_CACHE_TTL_MS) {
    return rateCache.rate;
  }
  let rate = null;
  try {
    // Required lazily: settings-service reaches commerce-store, and loading that
    // graph at module-init would make every pure money helper depend on Firebase.
    const { getStoredSettings, commissionPercent } = require('../modules/admin/settings-service');
    const stored = await getStoredSettings();
    const pct = stored?.paymentsAndCurrency?.platformCommissionPct;
    if (pct !== undefined) rate = commissionPercent(stored);
  } catch (_) {
    // Firestore unavailable: fall through to the env/default chain.
  }
  if (rate == null) rate = platformRate();
  rateCache = { at: Date.now(), rate };
  return rate;
}

function calcCommission(productPrice, rate = platformRate()) {
  return Math.round(Number(productPrice) * normalizeRate(rate));
}

function computeSellerParity(productPrice, shippingFee = 0n, rate = platformRate()) {
  const p = BigInt(productPrice);
  const s = BigInt(shippingFee);
  const commission = BigInt(calcCommission(p, rate));
  const totalAmount = p + s + commission;
  return {
    commission,
    totalAmount,
    sellerEntitlement: totalAmount - commission,
  };
}

module.exports = { calcCommission, computeSellerParity, platformRate, resolvePlatformRate };
