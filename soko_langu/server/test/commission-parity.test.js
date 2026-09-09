const { test } = require('node:test');
const assert = require('node:assert');
const { computeSellerParity } = require('../src/utils/commission-parity');

test('parity keeps seller entitlement equal to price + shipping', () => {
  const { totalAmount, commission, sellerEntitlement } = computeSellerParity(50000n, 2000n);
  assert.strictEqual(sellerEntitlement, 52000n);
  assert.strictEqual(totalAmount - commission, sellerEntitlement);
});

test('commission is 3.5% of price plus USSD pass-through tier', () => {
  // 50000: 3.5% = 1750; USSD tier 50000-95999 = 2136 (ClickPesa July 2026)
  const { commission } = computeSellerParity(50000n, 0n);
  assert.strictEqual(commission, 3886n);
  // 1000: 3.5% = 35; USSD tier 900-1999 = 92
  const small = computeSellerParity(1000n, 0n);
  assert.strictEqual(small.commission, 127n);
  assert.strictEqual(small.sellerEntitlement, 1000n);
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