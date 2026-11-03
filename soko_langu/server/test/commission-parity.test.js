const { test } = require('node:test');
const assert = require('node:assert');
const { computeSellerParity } = require('../src/utils/commission-parity');

test('parity keeps seller entitlement equal to price + shipping', () => {
  const { totalAmount, commission, sellerEntitlement } = computeSellerParity(50000n, 2000n);
  assert.strictEqual(sellerEntitlement, 52000n);
  assert.strictEqual(totalAmount - commission, sellerEntitlement);
});

test('no platform fee and no USSD pass-through on orders', () => {
  // Business rule: Soko Vibe charges 0 fee; ClickPesa's own charges are theirs.
  const { commission, totalAmount } = computeSellerParity(50000n, 0n);
  assert.strictEqual(commission, 0n);
  assert.strictEqual(totalAmount, 50000n);
  const small = computeSellerParity(100n, 0n);
  assert.strictEqual(small.commission, 0n);
  assert.strictEqual(small.totalAmount, 100n);
  assert.strictEqual(small.sellerEntitlement, 100n);
});

test('money conservation: escrow total always covers seller + commission', () => {
  for (const price of [100, 500, 1000, 9800, 39000, 250000, 1200000]) {
    const { totalAmount, commission, sellerEntitlement } = computeSellerParity(BigInt(price), BigInt(price % 2000));
    assert.strictEqual(totalAmount, commission + sellerEntitlement, `price ${price}`);
    assert.strictEqual(sellerEntitlement, BigInt(price) + BigInt(price % 2000));
  }
});

test('zero shipping edge case', () => {
  const r = computeSellerParity(15000n, 0n);
  assert.strictEqual(r.sellerEntitlement, 15000n);
  assert.strictEqual(r.totalAmount - r.commission, 15000n);
});