const { test } = require('node:test');
const assert = require('node:assert');
const { computeSellerParity, calcCommission } = require('../src/utils/commission-parity');

test('buyer pays the 3.5% commission on top of the item price', () => {
  const { totalAmount, commission, sellerEntitlement } = computeSellerParity(50000n, 2000n);
  assert.strictEqual(commission, 1750n);
  assert.strictEqual(totalAmount, 53750n);
  assert.strictEqual(sellerEntitlement, 52000n);
  assert.strictEqual(totalAmount - commission, sellerEntitlement);
});

test('an explicit zero rate is honoured (zero-fee promotion)', () => {
  const { commission, totalAmount, sellerEntitlement } = computeSellerParity(50000n, 0n, 0);
  assert.strictEqual(commission, 0n);
  assert.strictEqual(totalAmount, 50000n);
  assert.strictEqual(sellerEntitlement, 50000n);
});

test('shipping is excluded from the commission base', () => {
  const withShipping = computeSellerParity(50000n, 9000n);
  const withoutShipping = computeSellerParity(50000n, 0n);
  assert.strictEqual(withShipping.commission, withoutShipping.commission);
  assert.strictEqual(withShipping.totalAmount, 59000n + withoutShipping.commission);
});

test('money conservation: escrow total always covers seller + commission', () => {
  for (const price of [100, 500, 1000, 9800, 39000, 250000, 1200000]) {
    const shipping = BigInt(price % 2000);
    const { totalAmount, commission, sellerEntitlement } = computeSellerParity(BigInt(price), shipping);
    assert.strictEqual(totalAmount, commission + sellerEntitlement, `price ${price}`);
    assert.strictEqual(sellerEntitlement, BigInt(price) + shipping);
    assert.strictEqual(commission, BigInt(Math.round(price * 0.035)));
  }
});

test('rounding matches the app: whole TZS, half up', () => {
  assert.strictEqual(calcCommission(100), 4); // 3.5 -> 4
  assert.strictEqual(calcCommission(15000), 525);
  assert.strictEqual(calcCommission(100000), 3500);
  assert.strictEqual(calcCommission(1), 0);
});

test('a percentage-unit rate is accepted alongside a fraction', () => {
  assert.strictEqual(calcCommission(50000, 0.035), 1750);
  assert.strictEqual(calcCommission(50000, 3.5), 1750);
  assert.strictEqual(calcCommission(50000, 0), 0);
});

test('zero shipping edge case', () => {
  const r = computeSellerParity(15000n, 0n);
  assert.strictEqual(r.commission, 525n);
  assert.strictEqual(r.sellerEntitlement, 15000n);
  assert.strictEqual(r.totalAmount - r.commission, 15000n);
});
