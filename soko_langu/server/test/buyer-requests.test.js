const test = require('node:test');
const assert = require('node:assert');

const {
  DEFAULT_POLICY,
  normalizePolicy,
  publicPolicy,
  validateCreateInput,
  validateEditInput,
  validateOfferInput,
  statusFor,
  isExpiringSoon,
  canEdit,
  canExtend,
  canReopen,
  categoryMatches,
  changedFields,
  millis,
  httpError,
} = require('../src/modules/buyer-requests/request-config');

test('normalizePolicy clamps hostile values back to safe ranges', () => {
  const p = normalizePolicy({
    enabled: false,
    maxExpiryHours: 1,
    expiryOptionsHours: [24, 72, 168],
    defaultExpiryHours: 72,
    maxOfferLimit: 3,
    offerLimitOptions: [5, 10, 20],
    defaultOfferLimit: 10,
    maxEdits: 100,
    allowExtension: false,
  });
  assert.strictEqual(p.enabled, false);
  assert.strictEqual(p.maxExpiryHours, 1);
  // Expiry options are filtered to <= maxExpiryHours, so none of 24/72/168 survive.
  assert.deepStrictEqual(p.expiryOptionsHours, [1]);
  assert.strictEqual(p.defaultExpiryHours, 1);
  assert.strictEqual(p.maxOfferLimit, 3);
  assert.deepStrictEqual(p.offerLimitOptions, [3]);
  assert.strictEqual(p.defaultOfferLimit, 3);
  assert.strictEqual(p.maxEdits, 50);
  assert.strictEqual(p.allowExtension, false);
});

test('normalizePolicy keeps defaults when input is empty', () => {
  const p = normalizePolicy();
  assert.deepStrictEqual(p, normalizePolicy(DEFAULT_POLICY));
  assert.strictEqual(p.defaultExpiryHours, 168);
  assert.deepStrictEqual(p.expiryOptionsHours, [24, 72, 168, 336]);
});

test('publicPolicy never leaks internal-only fields', () => {
  const pub = publicPolicy(DEFAULT_POLICY);
  assert.ok(pub.enabled);
  assert.ok(Array.isArray(pub.expiryOptionsHours));
  // Internal moderation threshold must not reach the client.
  assert.strictEqual(pub.moderationHideThreshold, undefined);
});

test('statusFor expires past-due active requests without a sweeper', () => {
  const policy = normalizePolicy(DEFAULT_POLICY);
  const now = Date.now();
  const doc = { status: 'active', offersCount: 2, offerLimit: 5, expiresAtMs: now - 1000 };
  assert.strictEqual(statusFor(doc, policy, now), 'expired');
  const future = { ...doc, expiresAtMs: now + 100000 };
  assert.strictEqual(statusFor(future, policy, now), 'active');
});

test('statusFor flips to limit_reached at the boundary', () => {
  const policy = normalizePolicy(DEFAULT_POLICY);
  const now = Date.now();
  const below = { status: 'active', offersCount: 4, offerLimit: 5, expiresAtMs: now + 100000 };
  const at = { ...below, offersCount: 5 };
  const over = { ...below, offersCount: 6 };
  assert.strictEqual(statusFor(below, policy, now), 'active');
  assert.strictEqual(statusFor(at, policy, now), 'limit_reached');
  assert.strictEqual(statusFor(over, policy, now), 'limit_reached');
});

test('terminal statuses are never overwritten by lazy expiry', () => {
  const policy = normalizePolicy(DEFAULT_POLICY);
  const now = Date.now();
  ['completed', 'closed', 'suspended'].forEach((status) => {
    const doc = { status, offersCount: 0, offerLimit: 5, expiresAtMs: now - 100000 };
    assert.strictEqual(statusFor(doc, policy, now), status);
  });
});

test('canEdit respects edit counter and terminal/expired states', () => {
  const policy = normalizePolicy({ ...DEFAULT_POLICY, maxEdits: 2 });
  const now = Date.now();
  const base = { status: 'active', editsUsed: 0, offersCount: 0, offerLimit: 5, expiresAtMs: now + 100000 };
  assert.strictEqual(canEdit(base, policy, now), true);
  assert.strictEqual(canEdit({ ...base, editsUsed: 2 }, policy, now), false);
  assert.strictEqual(canEdit({ ...base, status: 'expired' }, policy, now), false);
  assert.strictEqual(canEdit({ ...base, status: 'completed' }, policy, now), false);
});

test('canExtend and canReopen gate the right transitions', () => {
  const policy = normalizePolicy({ ...DEFAULT_POLICY, allowExtension: true, maxExtensions: 1 });
  const now = Date.now();
  const active = { status: 'active', extensionsUsed: 0, expiresAtMs: now + 100000 };
  assert.strictEqual(canExtend(active, policy, now), true);
  assert.strictEqual(canExtend({ ...active, extensionsUsed: 1 }, policy, now), false);
  const closed = { status: 'closed', expiresAtMs: now + 100000 };
  assert.strictEqual(canReopen(closed, policy, now), true);
  assert.strictEqual(canReopen({ ...closed, expiresAtMs: now - 1 }, policy, now), false);
});

test('categoryMatches partitions a request into the buyer tabs', () => {
  const policy = normalizePolicy(DEFAULT_POLICY);
  const now = Date.now();
  const receiving = { status: 'active', offersCount: 3, offerLimit: 5, expiresAtMs: now + 10 * 86400000 };
  assert.strictEqual(categoryMatches(receiving, 'receiving_offers', policy, now), true);
  assert.strictEqual(categoryMatches(receiving, 'active', policy, now), false);
  const expiring = { status: 'active', offersCount: 0, offerLimit: 5, expiresAtMs: now + 1000 };
  assert.strictEqual(categoryMatches(expiring, 'expiring_soon', policy, now), true);
  const limited = { status: 'limit_reached', offersCount: 5, offerLimit: 5, expiresAtMs: now + 86400000 };
  assert.strictEqual(categoryMatches(limited, 'limit_reached', policy, now), true);
});

test('changedFields detects edits that affect submitted offers', () => {
  const prev = { title: 'iPhone', minBudget: 100000, maxBudget: 200000, offerLimit: 5 };
  const next = { title: 'iPhone 13', minBudget: 100000, maxBudget: 200000, offerLimit: 10 };
  const changed = changedFields(prev, next);
  assert.ok(changed.includes('title'));
  assert.ok(changed.includes('offerLimit'));
  assert.ok(!changed.includes('minBudget'));
});

test('validateCreateInput rejects bad budgets and expiry', () => {
  const policy = normalizePolicy(DEFAULT_POLICY);
  assert.throws(() => validateCreateInput({
    title: 'ab',
    description: 'too short',
    minBudget: 0,
    maxBudget: 10,
  }, policy), (e) => e.code === 'INVALID_TITLE' || e.code === 'INVALID_MIN_BUDGET');

  const ok = validateCreateInput({
    title: 'Natafuta iPhone 13',
    description: 'Ninahitaji iPhone 13 Pro max 256GB, nzuri, Dar es Salaam.',
    minBudget: 500000,
    maxBudget: 800000,
    expiresInHours: 168,
    offerLimit: 10,
  }, policy);
  assert.strictEqual(ok.title, 'Natafuta iPhone 13');
  assert.strictEqual(ok.offerLimit, 10);
  assert.strictEqual(ok.expiresInHours, 168);
  assert.ok(ok.expiresAtMs > Date.now());
});

test('validateCreateInput rejects expiry beyond admin maximum', () => {
  const policy = normalizePolicy(DEFAULT_POLICY);
  assert.throws(() => validateCreateInput({
    title: 'Natafuta iPhone 13',
    description: 'Ninahitaji iPhone 13 Pro max 256GB, nzuri, Dar es Salaam.',
    minBudget: 500000,
    maxBudget: 800000,
    expiresInHours: 10000,
    offerLimit: 10,
  }, policy), (e) => e.code === 'EXPIRY_TOO_LONG');
});

test('validateEditInput rejects when nothing changes', () => {
  const policy = normalizePolicy(DEFAULT_POLICY);
  const request = { minBudget: 1000, maxBudget: 2000, offersCount: 0, offerLimit: 5, editsUsed: 0 };
  assert.throws(() => validateEditInput({}, { request, policy }), (e) => e.code === 'NO_CHANGES');
});

test('validateOfferInput clamps and validates price', () => {
  const v = validateOfferInput({ price: '150000', message: 'Bei nzuri', deliveryDays: 3 });
  assert.strictEqual(v.price, 150000);
  assert.strictEqual(v.deliveryDays, 3);
  assert.throws(() => validateOfferInput({ price: 0 }), (e) => e.code === 'INVALID_OFFER_PRICE');
});

test('isExpiringSoon uses the admin-configured window', () => {
  const policy = normalizePolicy({ ...DEFAULT_POLICY, expiringSoonHours: 48 });
  const now = Date.now();
  const soon = { status: 'active', offersCount: 0, offerLimit: 5, expiresAtMs: now + 24 * 3600 * 1000 };
  const later = { ...soon, expiresAtMs: now + 72 * 3600 * 1000 };
  assert.strictEqual(isExpiringSoon(soon, policy, now), true);
  assert.strictEqual(isExpiringSoon(later, policy, now), false);
});
