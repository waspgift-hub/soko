// Canonical payment-method normalization for Soko Vibe.
//
// The two client surfaces historically used different spellings:
//   legacy app  -> 'escrow' | 'cod'
//   v2 app      -> 'mobile_money' | 'cash'
// The backend stores only the canonical values ('escrow' | 'cod') and rejects
// everything else. Never trust a raw client string anywhere else.
const ALIASES = {
  escrow: 'escrow',
  mobile_money: 'escrow',
  cod: 'cod',
  cash: 'cod',
};

function normalizePaymentMethod(method) {
  if (typeof method !== 'string') return null;
  const key = method.trim().toLowerCase();
  return Object.prototype.hasOwnProperty.call(ALIASES, key) ? ALIASES[key] : null;
}

function isCanonicalPaymentMethod(method) {
  return method === 'escrow' || method === 'cod';
}

function assertCanonicalPaymentMethod(method) {
  const canonical = normalizePaymentMethod(method);
  if (!canonical) {
    const err = new Error('INVALID_PAYMENT_METHOD');
    err.code = 'INVALID_PAYMENT_METHOD';
    err.status = 400;
    throw err;
  }
  return canonical;
}

// Method-aware eligibility helpers. Centralised so controllers, jobs and
// webhooks never re-implement these checks inline.
function isEscrow(method) {
  return normalizePaymentMethod(method) === 'escrow';
}

function isCod(method) {
  return normalizePaymentMethod(method) === 'cod';
}

module.exports = {
  normalizePaymentMethod,
  isCanonicalPaymentMethod,
  assertCanonicalPaymentMethod,
  isEscrow,
  isCod,
  CANONICAL_PAYMENT_METHODS: ['escrow', 'cod'],
};