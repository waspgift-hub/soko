const test = require('node:test');
const assert = require('node:assert/strict');

const { toBigIntSafe, sameAmount } = require('../src/utils/money');
const { buildDedupKey } = require('../src/modules/payments/webhook-outbox');

// ---------------------------------------------------------------------------
// Money-safe BigInt coercion
// ---------------------------------------------------------------------------

test('toBigIntSafe passes through BigInt unchanged', () => {
  assert.equal(toBigIntSafe(10000n), 10000n);
});

test('toBigIntSafe converts integer numbers and numeric strings', () => {
  assert.equal(toBigIntSafe(10000), 10000n);
  assert.equal(toBigIntSafe('9500'), 9500n);
});

test('toBigIntSafe rounds fractional amounts to integer TZS', () => {
  assert.equal(toBigIntSafe(47500.6), 47501n);
  assert.equal(toBigIntSafe('1299.99'), 1300n);
});

test('toBigIntSafe treats null/undefined/empty as zero', () => {
  assert.equal(toBigIntSafe(null), 0n);
  assert.equal(toBigIntSafe(undefined), 0n);
  assert.equal(toBigIntSafe(''), 0n);
});

test('sameAmount treats Number and BigInt representations as equal', () => {
  assert.equal(sameAmount(50000, 50000n), true);
  assert.equal(sameAmount('50000', 50000n), true);
  assert.equal(sameAmount(50000, 50001n), false);
});

test('sameAmount tolerates client-vs-server rounding drift on integers', () => {
  assert.equal(sameAmount(1234.4, 1234n), true);
  assert.equal(sameAmount(1234.6, 1235n), true);
});

// ---------------------------------------------------------------------------
// Webhook dedup key
// ---------------------------------------------------------------------------

test('buildDedupKey uses provider event id when present', () => {
  assert.equal(buildDedupKey('clickpesa', 'evt_123', {}), 'clickpesa:evt_123');
});

test('buildDedupKey is deterministic for the same payload without an id', () => {
  const payload = { orderReference: 'SV202609090001', status: 'SUCCESS', amount: 500 };
  const a = buildDedupKey('clickpesa', null, payload);
  const b = buildDedupKey('clickpesa', undefined, payload);
  assert.equal(a, b);
});

test('buildDedupKey differs when payload differs', () => {
  const a = buildDedupKey('clickpesa', null, { id: 'x', status: 'SUCCESS' });
  const b = buildDedupKey('clickpesa', null, { id: 'x', status: 'FAILED' });
  assert.notEqual(a, b);
});

test('buildDedupKey prefixes with provider to avoid cross-provider collisions', () => {
  assert.notEqual(
    buildDedupKey('clickpesa', 'evt_1', {}),
    buildDedupKey('another', 'evt_1', {})
  );
});