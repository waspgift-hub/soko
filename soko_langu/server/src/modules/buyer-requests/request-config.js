// Buyer Request ("Natafuta Bidhaa") policy + pure validation helpers.
//
// Every limit that changes user behaviour lives here and is persisted in
// `app_settings/admin_settings.buyerRequests`, so an operator can retune the
// marketplace without a Flutter release. The Flutter app only ever receives
// the public projection (`publicPolicy`) and re-validates nothing on its own:
// the server re-checks the same rules on every write.
//
// Pure by design (no Firestore, no clock) so the state machine is unit-tested
// without infrastructure. Callers pass `nowMs` explicitly — the device clock is
// never authoritative.

const DEFAULT_POLICY = {
  enabled: true,
  defaultExpiryHours: 168, // 7 days
  expiryOptionsHours: [24, 72, 168, 336],
  maxExpiryHours: 720, // 30 days
  maxActivePerBuyer: 5,
  defaultOfferLimit: 10,
  maxOfferLimit: 50,
  offerLimitOptions: [5, 10, 20],
  maxEdits: 5,
  allowExtension: true,
  maxExtensions: 1,
  extensionHours: 72,
  minBudgetTzs: 1000,
  maxBudgetTzs: 500000000,
  // 'any' | 'verified' — verified means users/{uid}.kyc.approved === true.
  sellerEligibility: 'any',
  // 'signed_in' | 'verified_sellers'. Controls who may read request details.
  requestVisibility: 'signed_in',
  autoExpire: true,
  sellerViewNotifications: true,
  expiringSoonHours: 24,
  moderationHideThreshold: 3,
};

const CONDITIONS = ['new', 'used_like_new', 'used_good', 'used_fair', 'any'];
const DELIVERY_MODES = ['pickup', 'delivery', 'either', 'negotiable'];
const STATUSES = ['active', 'limit_reached', 'expired', 'completed', 'closed', 'suspended'];
const TERMINAL_STATUSES = ['completed', 'closed', 'suspended'];

// A buyer tab is not the same thing as the stored status: "Receiving Offers" is
// an active request that already has live offers, and "Expiring Soon" is a
// window over active/limit-reached requests. Keeping the two concepts separate
// is what lets the list stay a single Firestore query.
const CATEGORIES = [
  'all', 'active', 'receiving_offers', 'limit_reached', 'expiring_soon',
  'expired', 'completed', 'closed',
];

const LIMITS = {
  title: { min: 3, max: 120 },
  description: { min: 10, max: 2000 },
  requirements: { max: 2000 },
  deliveryDetails: { max: 500 },
  location: { max: 120 },
  brand: { max: 80 },
  model: { max: 80 },
  images: 5,
  offerMessage: { max: 1000 },
  offerPriceMin: 1,
  offerPriceMax: 100000000000,
  offerDeliveryDays: { min: 1, max: 90 },
};

function httpError(status, code, message) {
  const e = new Error(message || code);
  e.status = status;
  e.code = code;
  return e;
}

function badRequest(code, message) {
  return httpError(400, code, message);
}

function toInt(value, fallback, min, max) {
  const n = Number(value);
  if (!Number.isFinite(n)) return fallback;
  const i = Math.floor(n);
  if (i < min) return min;
  if (i > max) return max;
  return i;
}

function hoursList(value, fallback) {
  const source = Array.isArray(value) ? value : fallback;
  const seen = new Set();
  const out = [];
  source.forEach((raw) => {
    const n = Number(raw);
    if (!Number.isFinite(n)) return;
    const i = Math.floor(n);
    if (i < 1 || i > 24 * 90) return;
    if (seen.has(i)) return;
    seen.add(i);
    out.push(i);
  });
  out.sort((a, b) => a - b);
  return out.length ? out : [...fallback];
}

function offerLimitList(value, fallback, maxOfferLimit) {
  const list = hoursList(value, fallback).filter((n) => n <= maxOfferLimit);
  return list.length ? list : [Math.min(5, maxOfferLimit)];
}

/**
 * Merges a persisted (possibly partial or hostile) policy object over the
 * defaults and clamps every value to a sane range. Admin writes go through this
 * on the way in *and* on the way out, so a hand-edited Firestore document can
 * never disable server-side validation or set a zero offer limit.
 */
function normalizePolicy(raw) {
  const src = raw && typeof raw === 'object' ? raw : {};
  const maxExpiryHours = toInt(src.maxExpiryHours, DEFAULT_POLICY.maxExpiryHours, 1, 24 * 90);
  const maxOfferLimit = toInt(src.maxOfferLimit, DEFAULT_POLICY.maxOfferLimit, 1, 500);
  const expiryOptionsHours = hoursList(src.expiryOptionsHours, DEFAULT_POLICY.expiryOptionsHours)
    .filter((h) => h <= maxExpiryHours);
  const offerLimitOptions = offerLimitList(
    src.offerLimitOptions,
    DEFAULT_POLICY.offerLimitOptions,
    maxOfferLimit,
  );
  const defaultExpiryHours = pickAllowed(
    src.defaultExpiryHours,
    expiryOptionsHours,
    DEFAULT_POLICY.defaultExpiryHours,
    maxExpiryHours,
  );
  const defaultOfferLimit = pickAllowed(
    src.defaultOfferLimit,
    offerLimitOptions,
    DEFAULT_POLICY.defaultOfferLimit,
    maxOfferLimit,
  );

  return {
    enabled: src.enabled !== false,
    defaultExpiryHours,
    expiryOptionsHours: expiryOptionsHours.length ? expiryOptionsHours : [defaultExpiryHours],
    maxExpiryHours,
    maxActivePerBuyer: toInt(src.maxActivePerBuyer, DEFAULT_POLICY.maxActivePerBuyer, 1, 50),
    defaultOfferLimit,
    maxOfferLimit,
    offerLimitOptions: offerLimitOptions.length ? offerLimitOptions : [defaultOfferLimit],
    maxEdits: toInt(src.maxEdits, DEFAULT_POLICY.maxEdits, 0, 50),
    allowExtension: src.allowExtension !== false,
    maxExtensions: toInt(src.maxExtensions, DEFAULT_POLICY.maxExtensions, 0, 10),
    extensionHours: toInt(src.extensionHours, DEFAULT_POLICY.extensionHours, 1, 24 * 30),
    minBudgetTzs: toInt(src.minBudgetTzs, DEFAULT_POLICY.minBudgetTzs, 0, 100000000),
    maxBudgetTzs: toInt(src.maxBudgetTzs, DEFAULT_POLICY.maxBudgetTzs, 1000, 10000000000),
    sellerEligibility: src.sellerEligibility === 'verified' ? 'verified' : 'any',
    requestVisibility: src.requestVisibility === 'verified_sellers' ? 'verified_sellers' : 'signed_in',
    autoExpire: src.autoExpire !== false,
    sellerViewNotifications: src.sellerViewNotifications !== false,
    expiringSoonHours: toInt(
      src.expiringSoonHours,
      DEFAULT_POLICY.expiringSoonHours,
      1,
      maxExpiryHours,
    ),
    moderationHideThreshold: toInt(
      src.moderationHideThreshold,
      DEFAULT_POLICY.moderationHideThreshold,
      1,
      100,
    ),
  };
}

function pickAllowed(raw, allowed, fallback, max) {
  const n = Number(raw);
  if (Number.isFinite(n) && allowed.includes(Math.floor(n))) return Math.floor(n);
  if (Number.isFinite(n) && n > 0) return Math.min(Math.floor(n), max);
  return allowed.includes(fallback) ? fallback : allowed[0];
}

/** The subset of policy the Flutter client is allowed to see. */
function publicPolicy(raw) {
  const p = normalizePolicy(raw);
  return {
    enabled: p.enabled,
    defaultExpiryHours: p.defaultExpiryHours,
    expiryOptionsHours: p.expiryOptionsHours,
    maxExpiryHours: p.maxExpiryHours,
    maxActivePerBuyer: p.maxActivePerBuyer,
    defaultOfferLimit: p.defaultOfferLimit,
    maxOfferLimit: p.maxOfferLimit,
    offerLimitOptions: p.offerLimitOptions,
    maxEdits: p.maxEdits,
    allowExtension: p.allowExtension,
    maxExtensions: p.maxExtensions,
    extensionHours: p.extensionHours,
    minBudgetTzs: p.minBudgetTzs,
    maxBudgetTzs: p.maxBudgetTzs,
    sellerEligibility: p.sellerEligibility,
    requestVisibility: p.requestVisibility,
    expiringSoonHours: p.expiringSoonHours,
    // The client must not derive expiry from the device clock; this is the
    // value it compares against the server-supplied `serverTime`.
    autoExpire: p.autoExpire,
  };
}

function text(value, { max, min = 0, code = 'INVALID_TEXT' } = {}) {
  const out = String(value == null ? '' : value).replace(/\r\n/g, '\n').trim();
  if (out.length < min) throw badRequest(code, `${code}: too short`);
  if (max && out.length > max) throw badRequest(code, `${code}: too long`);
  return out;
}

function optionalText(value, opts) {
  if (value == null || value === '') return '';
  return text(value, opts);
}

function nonNegativeNumber(value, { code, min = 0, max = Number.MAX_SAFE_INTEGER } = {}) {
  const n = Number(value);
  if (!Number.isFinite(n) || n < min || n > max) throw badRequest(code, `${code}: invalid amount`);
  return Math.round(n);
}

function sanitizeImages(value) {
  if (!Array.isArray(value)) return [];
  const out = [];
  value.forEach((raw) => {
    const url = String(raw == null ? '' : raw).trim();
    if (!url || url.length > 2048) return;
    if (!/^https?:\/\//i.test(url)) return;
    if (out.includes(url)) return;
    if (out.length >= LIMITS.images) return;
    out.push(url);
  });
  return out;
}

/** Normalizes a create payload and rejects anything the policy disallows. */
function validateCreateInput(input, rawPolicy, nowMs = Date.now()) {
  const policy = normalizePolicy(rawPolicy);
  if (!policy.enabled) throw httpError(403, 'BUYER_REQUESTS_DISABLED');

  const src = input && typeof input === 'object' ? input : {};
  const title = text(src.title, { min: LIMITS.title.min, max: LIMITS.title.max, code: 'INVALID_TITLE' });
  const description = text(src.description, {
    min: LIMITS.description.min,
    max: LIMITS.description.max,
    code: 'INVALID_DESCRIPTION',
  });

  const minBudget = nonNegativeNumber(src.minBudget, {
    code: 'INVALID_MIN_BUDGET',
    min: policy.minBudgetTzs,
    max: policy.maxBudgetTzs,
  });
  const maxBudget = nonNegativeNumber(src.maxBudget, {
    code: 'INVALID_MAX_BUDGET',
    min: policy.minBudgetTzs,
    max: policy.maxBudgetTzs,
  });
  if (maxBudget < minBudget) throw badRequest('INVALID_BUDGET_RANGE');

  const condition = String(src.condition || 'any').trim();
  if (!CONDITIONS.includes(condition)) throw badRequest('INVALID_CONDITION');

  const delivery = String(src.delivery || 'negotiable').trim();
  if (!DELIVERY_MODES.includes(delivery)) throw badRequest('INVALID_DELIVERY_MODE');

  const expiresInHours = resolveExpiry(src.expiresInHours, policy);
  const offerLimit = resolveOfferLimit(src.offerLimit, policy);

  return {
    title,
    description,
    categoryId: optionalText(src.categoryId, { max: 120, code: 'INVALID_CATEGORY' }),
    categoryName: optionalText(src.categoryName, { max: 120, code: 'INVALID_CATEGORY' }),
    images: sanitizeImages(src.images),
    brand: optionalText(src.brand, { max: LIMITS.brand.max, code: 'INVALID_BRAND' }),
    model: optionalText(src.model, { max: LIMITS.model.max, code: 'INVALID_MODEL' }),
    condition,
    minBudget,
    maxBudget,
    location: optionalText(src.location, { max: LIMITS.location.max, code: 'INVALID_LOCATION' }),
    delivery,
    deliveryDetails: optionalText(src.deliveryDetails, {
      max: LIMITS.deliveryDetails.max,
      code: 'INVALID_DELIVERY_DETAILS',
    }),
    requirements: optionalText(src.requirements, {
      max: LIMITS.requirements.max,
      code: 'INVALID_REQUIREMENTS',
    }),
    expiresInHours,
    offerLimit,
    // The buyer is never asked for a phone number: sellers contact them
    // through the platform, or through a seller-owned WhatsApp number.
    preferredContact: src.preferredContact === 'whatsapp' ? 'whatsapp' : 'in_app',
    language: src.language === 'en' ? 'en' : 'sw',
    expiresAtMs: nowMs + expiresInHours * 3600 * 1000,
  };
}

function resolveExpiry(value, policy) {
  const n = Number(value);
  if (!Number.isFinite(n) || n <= 0) return policy.defaultExpiryHours;
  const hours = Math.floor(n);
  if (hours > policy.maxExpiryHours) throw badRequest('EXPIRY_TOO_LONG');
  if (!policy.expiryOptionsHours.includes(hours) && hours < 1) throw badRequest('INVALID_EXPIRY');
  return hours;
}

function resolveOfferLimit(value, policy) {
  const n = Number(value);
  if (!Number.isFinite(n) || n <= 0) return policy.defaultOfferLimit;
  const limit = Math.floor(n);
  if (limit > policy.maxOfferLimit) throw badRequest('OFFER_LIMIT_TOO_HIGH');
  if (limit < 1) throw badRequest('INVALID_OFFER_LIMIT');
  return limit;
}

const IMPORTANT_FIELDS = [
  'title', 'description', 'categoryId', 'categoryName', 'brand', 'model',
  'condition', 'minBudget', 'maxBudget', 'location', 'delivery',
  'deliveryDetails', 'requirements', 'images', 'expiresAt', 'offerLimit',
];

function sameValue(a, b) {
  if (Array.isArray(a) || Array.isArray(b)) {
    return JSON.stringify(a || []) === JSON.stringify(b || []);
  }
  return a === b;
}

function changedFields(previous, next) {
  return IMPORTANT_FIELDS.filter((field) => !sameValue(previous?.[field], next?.[field]));
}

/**
 * Validates a partial edit. Returns only the fields the buyer actually sent so
 * an omitted field is never silently cleared.
 */
function validateEditInput(input, { request, policy, nowMs = Date.now() }) {
  const src = input && typeof input === 'object' ? input : {};
  const out = {};
  const has = (key) => Object.prototype.hasOwnProperty.call(src, key);

  if (has('title')) out.title = text(src.title, { min: LIMITS.title.min, max: LIMITS.title.max, code: 'INVALID_TITLE' });
  if (has('description')) {
    out.description = text(src.description, {
      min: LIMITS.description.min,
      max: LIMITS.description.max,
      code: 'INVALID_DESCRIPTION',
    });
  }
  if (has('categoryId')) out.categoryId = optionalText(src.categoryId, { max: 120, code: 'INVALID_CATEGORY' });
  if (has('categoryName')) out.categoryName = optionalText(src.categoryName, { max: 120, code: 'INVALID_CATEGORY' });
  if (has('brand')) out.brand = optionalText(src.brand, { max: LIMITS.brand.max, code: 'INVALID_BRAND' });
  if (has('model')) out.model = optionalText(src.model, { max: LIMITS.model.max, code: 'INVALID_MODEL' });
  if (has('location')) out.location = optionalText(src.location, { max: LIMITS.location.max, code: 'INVALID_LOCATION' });
  if (has('deliveryDetails')) {
    out.deliveryDetails = optionalText(src.deliveryDetails, {
      max: LIMITS.deliveryDetails.max,
      code: 'INVALID_DELIVERY_DETAILS',
    });
  }
  if (has('requirements')) {
    out.requirements = optionalText(src.requirements, {
      max: LIMITS.requirements.max,
      code: 'INVALID_REQUIREMENTS',
    });
  }
  if (has('images')) out.images = sanitizeImages(src.images);
  if (has('condition')) {
    const condition = String(src.condition || '').trim();
    if (!CONDITIONS.includes(condition)) throw badRequest('INVALID_CONDITION');
    out.condition = condition;
  }
  if (has('delivery')) {
    const delivery = String(src.delivery || '').trim();
    if (!DELIVERY_MODES.includes(delivery)) throw badRequest('INVALID_DELIVERY_MODE');
    out.delivery = delivery;
  }

  const nextMin = has('minBudget') ? nonNegativeNumber(src.minBudget, {
    code: 'INVALID_MIN_BUDGET',
    min: policy.minBudgetTzs,
    max: policy.maxBudgetTzs,
  }) : request.minBudget;
  const nextMax = has('maxBudget') ? nonNegativeNumber(src.maxBudget, {
    code: 'INVALID_MAX_BUDGET',
    min: policy.minBudgetTzs,
    max: policy.maxBudgetTzs,
  }) : request.maxBudget;
  if (nextMax < nextMin) throw badRequest('INVALID_BUDGET_RANGE');
  if (has('minBudget')) out.minBudget = nextMin;
  if (has('maxBudget')) out.maxBudget = nextMax;

  if (has('offerLimit')) {
    const offerLimit = resolveOfferLimit(src.offerLimit, policy);
    // Lowering the limit below offers already received would make the counter
    // lie and could strand live offers; reject instead of silently clamping.
    if (offerLimit < Number(request.offersCount || 0)) throw badRequest('OFFER_LIMIT_BELOW_OFFERS');
    out.offerLimit = offerLimit;
  }

  if (has('expiresInHours')) {
    const expiresInHours = resolveExpiry(src.expiresInHours, policy);
    const expiresAtMs = nowMs + expiresInHours * 3600 * 1000;
    if (expiresAtMs <= nowMs + 60 * 1000) throw badRequest('EXPIRY_IN_PAST');
    out.expiresAtMs = expiresAtMs;
  }

  if (!Object.keys(out).length) throw badRequest('NO_CHANGES');
  return out;
}

function millis(value) {
  if (value == null) return 0;
  if (typeof value === 'number') return value;
  if (typeof value.toMillis === 'function') return value.toMillis();
  if (typeof value.toDate === 'function') return value.toDate().getTime();
  if (value instanceof Date) return value.getTime();
  const t = Date.parse(String(value));
  return Number.isFinite(t) ? t : 0;
}

/**
 * Authoritative status for a stored request at `nowMs`.
 *
 * `status` is persisted lazily (on write or by the sweeper); reads always pass
 * through here so an expired request can never accept an offer just because a
 * background job has not run yet.
 */
function statusFor(doc, policy, nowMs = Date.now()) {
  const stored = String(doc?.status || 'active');
  if (TERMINAL_STATUSES.includes(stored)) return stored;
  if (stored === 'expired') return 'expired';
  const expiresAtMs = millis(doc?.expiresAtMs || doc?.expiresAt);
  if (policy && policy.autoExpire !== false && expiresAtMs && expiresAtMs <= nowMs) return 'expired';
  if (Number(doc?.offersCount || 0) >= Number(doc?.offerLimit || 0)) return 'limit_reached';
  return 'active';
}

function isExpiringSoon(doc, policy, nowMs = Date.now()) {
  const status = statusFor(doc, policy, nowMs);
  if (status !== 'active' && status !== 'limit_reached') return false;
  const expiresAtMs = millis(doc?.expiresAtMs || doc?.expiresAt);
  if (!expiresAtMs) return false;
  return expiresAtMs - nowMs <= policy.expiringSoonHours * 3600 * 1000;
}

function canEdit(doc, policy, nowMs = Date.now()) {
  const status = statusFor(doc, policy, nowMs);
  if (status !== 'active' && status !== 'limit_reached') return false;
  return Number(doc?.editsUsed || 0) < Number(policy.maxEdits || 0);
}

function canExtend(doc, policy, nowMs = Date.now()) {
  if (!policy.allowExtension) return false;
  const status = statusFor(doc, policy, nowMs);
  // An expired request may be revived inside the extension budget, but a
  // closed/completed one is finished business.
  if (status !== 'active' && status !== 'limit_reached' && status !== 'expired') return false;
  return Number(doc?.extensionsUsed || 0) < Number(policy.maxExtensions || 0);
}

function canReopen(doc, policy, nowMs = Date.now()) {
  if (String(doc?.status || '') !== 'closed') return false;
  const expiresAtMs = millis(doc?.expiresAtMs || doc?.expiresAt);
  return !policy.autoExpire || !expiresAtMs || expiresAtMs > nowMs;
}

function categoryMatches(doc, category, policy, nowMs = Date.now()) {
  if (!category || category === 'all') return true;
  const status = statusFor(doc, policy, nowMs);
  switch (category) {
    case 'active': return status === 'active' && Number(doc.offersCount || 0) === 0;
    case 'receiving_offers': return status === 'active' && Number(doc.offersCount || 0) > 0;
    case 'limit_reached': return status === 'limit_reached';
    case 'expiring_soon': return isExpiringSoon(doc, policy, nowMs);
    case 'expired': return status === 'expired';
    case 'completed': return status === 'completed';
    case 'closed': return status === 'closed';
    default: return false;
  }
}

function validateOfferInput(input) {
  const src = input && typeof input === 'object' ? input : {};
  const price = nonNegativeNumber(src.price, {
    code: 'INVALID_OFFER_PRICE',
    min: LIMITS.offerPriceMin,
    max: LIMITS.offerPriceMax,
  });
  const message = optionalText(src.message, {
    max: LIMITS.offerMessage.max,
    code: 'INVALID_OFFER_MESSAGE',
  });
  let deliveryDays = null;
  if (src.deliveryDays != null && src.deliveryDays !== '') {
    deliveryDays = toInt(
      src.deliveryDays,
      LIMITS.offerDeliveryDays.min,
      LIMITS.offerDeliveryDays.min,
      LIMITS.offerDeliveryDays.max,
    );
  }
  return {
    price,
    message,
    deliveryDays,
    condition: CONDITIONS.includes(String(src.condition)) ? String(src.condition) : null,
    brand: optionalText(src.brand, { max: LIMITS.brand.max, code: 'INVALID_BRAND' }),
    model: optionalText(src.model, { max: LIMITS.model.max, code: 'INVALID_MODEL' }),
    warranty: optionalText(src.warranty, { max: 200, code: 'INVALID_WARRANTY' }),
  };
}

module.exports = {
  DEFAULT_POLICY,
  CONDITIONS,
  DELIVERY_MODES,
  STATUSES,
  CATEGORIES,
  LIMITS,
  IMPORTANT_FIELDS,
  httpError,
  badRequest,
  normalizePolicy,
  publicPolicy,
  validateCreateInput,
  validateEditInput,
  validateOfferInput,
  resolveExpiry,
  resolveOfferLimit,
  statusFor,
  isExpiringSoon,
  canEdit,
  canExtend,
  canReopen,
  categoryMatches,
  changedFields,
  millis,
};
