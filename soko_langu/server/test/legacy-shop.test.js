const { test } = require('node:test');
const assert = require('node:assert');
const { buildLegacyMirror, LEGACY_STATUS } = require('../src/modules/legacy-shop/routes');

test('buildLegacyMirror produces the legacy Flutter document shape', () => {
  const order = {
    id: 'or-123',
    status: 'awaiting_escrow_payment',
    productPrice: 50000n,
    totalAmount: 50000n, // seller nets price + shipping in full; 0 platform/ClickPesa fees
    shippingFee: 0n,
  };
  const body = {
    productName: 'Vitamin C',
    productImage: 'http://img/vit.jpg',
    quantity: 2,
    productPrice: 50000,
    sellerId: 's1',
    sellerName: 'Duka Bora',
    buyerId: 'guest:255700000000',
    buyerName: 'Juma',
    buyerPhone: '+255700000000',
    region: 'Dar es Salaam',
    district: 'Kinondoni',
    ward: 'Mikocheni',
    street: 'Bagamoyo Rd',
    deliveryType: 'delivery',
  };
  const m = buildLegacyMirror(order, body);

  assert.strictEqual(m.orderId, 'or-123');
  assert.strictEqual(m.status, 'pending');
  assert.strictEqual(m.escrowStatus, 'none');
  assert.strictEqual(m.productName, 'Vitamin C');
  assert.strictEqual(m.productPrice, 50000);
  assert.strictEqual(m.quantity, 2);
  assert.strictEqual(m.shippingCost, 0);
  // Soko Vibe has no fee; the mirror shows zero platform/ClickPesa lines
  assert.strictEqual(m.platformFee, 0);
  assert.strictEqual(m.clickpesaFee, 0);
  assert.strictEqual(m.totalAmount, 50000);
  assert.strictEqual(m.buyerId, 'guest:255700000000');
  assert.strictEqual(m.sourceV2, true);
  assert.strictEqual(m.deliveryType, 'delivery');
});

test('mirror fee math matches the parity commission invariant', () => {
  for (const price of [1500, 10000, 50000, 250000]) {
    const order = { id: `o-${price}`, status: 'in_escrow', productPrice: BigInt(price), totalAmount: 0n, shippingFee: 0n };
    const body = { productPrice: price };
    const m = buildLegacyMirror(order, body);
    // totalAmount Number(BigInt) is parsed from order; mirror embeds legacized
    // presentation fields only, so conservation is checked via fee composition:
    assert.strictEqual(m.platformFee + m.clickpesaFee, 0);
  }
});

test('LEGACY_STATUS covers every money-relevant v2 state', () => {
  const states = [
    'payment_pending', 'pending_shipping_fee', 'awaiting_escrow_payment', 'in_escrow',
    'ready_to_dispatch', 'dispatched', 'delivered', 'inspection_period', 'otp_pending',
    'completed', 'wallet_credited', 'disputed', 'refunded', 'cancelled', 'failed', 'expired',
  ];
  for (const s of states) {
    assert.ok(LEGACY_STATUS[s], `missing legacy mapping for ${s}`);
  }
  assert.strictEqual(LEGACY_STATUS.awaiting_escrow_payment, 'pending');
  assert.strictEqual(LEGACY_STATUS.in_escrow, 'escrow_hold');
  assert.strictEqual(LEGACY_STATUS.completed, 'completed');
});