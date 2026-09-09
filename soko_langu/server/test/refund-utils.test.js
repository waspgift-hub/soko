const test = require('node:test');
const assert = require('node:assert/strict');

const {
  computeRefundMode,
  isRefundableEscrowState,
  buildCorrelationId,
} = require('../src/modules/refunds/refund-service');

// ---------------------------------------------------------------------------
// computeRefundMode: full vs partial refund determination
// ---------------------------------------------------------------------------

test('null/undefined amount means a full refund of the total', () => {
  assert.deepEqual(computeRefundMode(50000n, null), { mode: 'full', amount: 50000n });
  assert.deepEqual(computeRefundMode(50000n, undefined), { mode: 'full', amount: 50000n });
});

test('amount equal to total is a full refund', () => {
  assert.deepEqual(computeRefundMode(50000n, 50000), { mode: 'full', amount: 50000n });
  assert.deepEqual(computeRefundMode(50000n, 50000n), { mode: 'full', amount: 50000n });
});

test('amount larger than total is clamped to a full refund', () => {
  assert.deepEqual(computeRefundMode(50000n, 60000), { mode: 'full', amount: 50000n });
});

test('amount strictly below total is a partial refund', () => {
  assert.deepEqual(computeRefundMode(50000n, 20000), { mode: 'partial', amount: 20000n });
  assert.deepEqual(computeRefundMode(50000n, '23450'), { mode: 'partial', amount: 23450n });
});

test('zero or negative partial amounts are rejected', () => {
  assert.throws(() => computeRefundMode(50000n, 0));
  assert.throws(() => computeRefundMode(50000n, -100));
});

// ---------------------------------------------------------------------------
// isRefundableEscrowState
// ---------------------------------------------------------------------------

test('escrow-funded states are refundable', () => {
  for (const s of ['in_escrow', 'dispatched', 'delivered', 'inspection_period', 'otp_pending', 'refund_pending']) {
    assert.equal(isRefundableEscrowState(s), true);
  }
});

test('transit/resolution states are not directly refundable', () => {
  for (const s of ['ready_to_dispatch', 'in_transit', 'out_for_delivery', 'delivery_attempted', 'disputed', 'completed', 'wallet_credited']) {
    assert.equal(isRefundableEscrowState(s), false);
  }
});

// ---------------------------------------------------------------------------
// buildCorrelationId
// ---------------------------------------------------------------------------

test('correlation id embeds the order number and is unique per call', () => {
  const a = buildCorrelationId('SV-12345');
  const b = buildCorrelationId('SV-12345');
  assert.ok(a.startsWith('refund_SV-12345_'));
  assert.notEqual(a, b);
});