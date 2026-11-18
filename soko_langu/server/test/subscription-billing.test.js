const test = require('node:test');
const assert = require('node:assert');

const billing = require('../src/modules/subscriptions/billing');
const store = require('../src/modules/subscriptions/subscription-store');
const plans = require('../src/modules/subscriptions/plans');

test('billing reuses the subscription store collection names', () => {
  assert.strictEqual(billing.COLLECTIONS.subscriptions, store.COLLECTIONS.subscriptions);
  assert.strictEqual(billing.COLLECTIONS.entitlements, store.COLLECTIONS.entitlements);
});

test('isValidPhone accepts international and local forms', () => {
  assert.strictEqual(billing.isValidPhone('+255712345678'), true);
  assert.strictEqual(billing.isValidPhone('0712345678'), true);
  assert.strictEqual(billing.isValidPhone('255712345678'), true);
});

test('isValidPhone rejects malformed numbers', () => {
  assert.strictEqual(billing.isValidPhone(''), false);
  assert.strictEqual(billing.isValidPhone('123'), false);
  assert.strictEqual(billing.isValidPhone('abcdefghij'), false);
  assert.strictEqual(billing.isValidPhone(null), false);
});

test('all paid plans have a positive price and a positive AI quota', () => {
  for (const plan of Object.values(plans.PLANS)) {
    if (plan.priceTzs > 0) {
      assert.ok(plan.aiActionsPerDay > 0, plan.id + ' must grant AI actions');
    }
  }
});

test('planById returns null for unknown plans', () => {
  assert.strictEqual(plans.planById('nope'), null);
  assert.ok(plans.planById('seller_plus'));
});
