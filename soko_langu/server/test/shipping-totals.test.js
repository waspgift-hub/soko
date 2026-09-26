// Must be set before any config-loading require below: config/index.js caches
// the commission percent at first load.
process.env.PLATFORM_COMMISSION_PERCENT = '10';

const { test } = require('node:test');
const assert = require('node:assert/strict');

const state = { prisma: null };
const DB = require('../src/config/database');
DB.getPrisma = () => state.prisma;

// redis acquireLock returns { acquired:true, skipped:true } when no client —
// services run without Redis in the hermetic tests.
const { submitQuote } = require('../src/modules/shipping/shipping-quote-service');
const { ORDER_STATES } = require('../src/modules/orders/order-state-machine');

function createFakePrisma(orderSeed) {
  const store = {
    order: [orderSeed],
    shippingQuote: [],
  };

  const api = {
    $transaction: async (fn) => fn(api),
    order: {
      findUnique: async ({ where } = {}) =>
        store.order.find((r) => r.id === where.id) ?? null,
      update: async ({ where, data } = {}) => {
        const row = store.order.find((r) => r.id === where.id);
        Object.assign(row, data);
        return row;
      },
    },
    shippingQuote: {
      create: async ({ data } = {}) => {
        const row = { id: `sq-${store.shippingQuote.length + 1}`, ...data };
        store.shippingQuote.push(row);
        return row;
      },
    },
  };

  Object.defineProperty(api, '_store', { value: store });
  return api;
}

const SELLER = { id: 'sp-1', region: 'Dar Es Salaam', reliabilityScore: 0.5 };

test('submitQuote recalculates the payable: seller sets shipping, platform fee + total go live', async () => {
  const api = createFakePrisma({
    id: 'or-1',
    orderNumber: 'SV202609260101',
    sellerId: 'sp-1',
    buyerId: 'buyer-1',
    status: ORDER_STATES.AWAITING_SELLER_SHIPPING,
    productPrice: BigInt(60000),
    shippingFee: BigInt(0),
    platformCommission: BigInt(0),
    totalAmount: BigInt(60000),
    shippingAddressSnapshot: { region: 'Dar Es Salaam', city: 'Kinondoni' },
    seller: { ...SELLER },
  });
  state.prisma = api;

  const result = await submitQuote({
    orderId: 'or-1',
    sellerId: 'sp-1',
    amount: 5000,
    estimatedDays: 2,
    notes: 'Na day delivery',
  });

  assert.equal(result.validation.verdict, 'NORMAL');

  const order = api._store.order[0];
  assert.equal(order.status, ORDER_STATES.AWAITING_PAYMENT);
  // 10% commission on the 60000 product price; total = product + shipping.
  assert.equal(order.shippingFee, BigInt(5000));
  assert.equal(order.platformCommission, 6000);
  assert.equal(order.totalAmount, BigInt(65000));
  assert.equal(order.statusChangedBy, 'sp-1');

  const quote = api._store.shippingQuote[0];
  assert.equal(quote.amount, BigInt(5000));
  assert.equal(quote.status, 'submitted');

  // Snapshot serializes the quote as a string amount.
  assert.equal(order.shippingQuoteSnapshot.amount, '5000');
});

test('submitQuote accepts mixed NumericBigInt/BigInt money without throwing', async () => {
  const api = createFakePrisma({
    id: 'or-1',
    orderNumber: 'SV202609260102',
    sellerId: 'sp-1',
    buyerId: 'buyer-1',
    status: ORDER_STATES.AWAITING_SELLER_SHIPPING,
    // Number money (legacy Firestore-shaped reads) must coerce safely.
    productPrice: 60000,
    shippingFee: 0,
    platformCommission: 0,
    totalAmount: 60000,
    shippingAddressSnapshot: { region: 'Dar Es Salaam', city: 'Kinondoni' },
    seller: { ...SELLER },
  });
  state.prisma = api;

  const result = await submitQuote({
    orderId: 'or-1',
    sellerId: 'sp-1',
    amount: '8000',
    estimatedDays: 3,
  });

  assert.equal(result.validation.verdict, 'NORMAL');
  const order = api._store.order[0];
  assert.equal(order.shippingFee, BigInt(8000));
  assert.equal(order.platformCommission, 6000);
  assert.equal(order.totalAmount, BigInt(68000));
});

test('submitQuote blocks the wrong seller from setting shipping', async () => {
  const api = createFakePrisma({
    id: 'or-1',
    orderNumber: 'SV202609260103',
    sellerId: 'sp-1',
    buyerId: 'buyer-1',
    status: ORDER_STATES.AWAITING_SELLER_SHIPPING,
    productPrice: BigInt(60000),
    shippingFee: BigInt(0),
    totalAmount: BigInt(60000),
    seller: { ...SELLER },
  });
  state.prisma = api;

  await assert.rejects(
    submitQuote({ orderId: 'or-1', sellerId: 'sp-2', amount: 5000 }),
    (err) => err.status === 403
  );

  assert.equal(api._store.shippingQuote.length, 0);
  assert.equal(api._store.order[0].status, ORDER_STATES.AWAITING_SELLER_SHIPPING);
});