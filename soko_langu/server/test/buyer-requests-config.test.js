const test = require('node:test');
const assert = require('node:assert');

const cfg = require('../src/modules/buyer-requests/request-config');

test('default policy has 7-day expiry and 5/10/20 offer options', () => {
  const p = cfg.normalizePolicy({});
  assert.strictEqual(p.defaultExpiryHours, 168);
  assert.deepStrictEqual(p.expiryOptionsHours, [24, 72, 168, 336]);
  assert.deepStrictEqual(p.offerLimitOptions, [5, 10, 20]);
  assert.strictEqual(p.maxEdits, 5);
});

test('statusFor marks overdue active request as expired', () => {
  const policy = cfg.normalizePolicy({});
  const now = Date.now();
  const doc = { status: 'active', expiresAtMs: now - 1000, offersCount: 0, offerLimit: 10 };
  assert.strictEqual(cfg.statusFor(doc, policy, now), 'expired');
});

test('statusFor marks limit reached when offersCount >= offerLimit', () => {
  const policy = cfg.normalizePolicy({});
  const now = Date.now();
  const doc = { status: 'active', expiresAtMs: now + 100000, offersCount: 10, offerLimit: 10 };
  assert.strictEqual(cfg.statusFor(doc, policy, now), 'limit_reached');
});

test('validateCreateInput rejects maxBudget < minBudget', () => {
  const policy = cfg.normalizePolicy({});
  assert.throws(() => cfg.validateCreateInput({
    title: 'iPhone 13 Pro', description: 'Looking for a clean unit', minBudget: 100000, maxBudget: 50000,
  }, policy, Date.now()), /INVALID_BUDGET_RANGE/);
});

test('validateCreateInput uses server nowMs for expiresAt', () => {
  const policy = cfg.normalizePolicy({});
  const now = 1_700_000_000_000;
  const out = cfg.validateCreateInput({
    title: 'iPhone 13 Pro', description: 'Looking for a clean unit',
    minBudget: 100000, maxBudget: 500000, expiresInHours: 24,
  }, policy, now);
  assert.strictEqual(out.expiresAtMs, now + 24 * 3600 * 1000);
});

test('validateEditInput rejects lowering offerLimit below offers received', () => {
  const policy = cfg.normalizePolicy({});
  const request = { offersCount: 5, offerLimit: 10, minBudget: 1, maxBudget: 10 };
  assert.throws(() => cfg.validateEditInput({ offerLimit: 3 }, { request, policy, nowMs: Date.now() }), /OFFER_LIMIT_BELOW_OFFERS/);
});

test('categoryMatches expiring_soon window', () => {
  const policy = cfg.normalizePolicy({ expiringSoonHours: 24 });
  const now = Date.now();
  const doc = { status: 'active', expiresAtMs: now + 10 * 3600 * 1000, offersCount: 0, offerLimit: 10 };
  assert.strictEqual(cfg.categoryMatches(doc, 'expiring_soon', policy, now), true);
});

test('publicPolicy omits maxActivePerBuyer? includes it', () => {
  const p = cfg.publicPolicy(cfg.normalizePolicy({}));
  assert.ok(Object.prototype.hasOwnProperty.call(p, 'maxActivePerBuyer'));
  assert.ok(!Object.prototype.hasOwnProperty.call(p, 'autoExpire') === false);
});