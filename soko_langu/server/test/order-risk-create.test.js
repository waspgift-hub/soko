// The creation-time risk gate must be wired into the real order service, not
// just exist as a standalone helper. These tests exercise createOrder with an
// in-memory store: a self-dealt purchase never becomes an order, and velocity
// is persisted on the order plus written to the admin fraud panel.
const { test } = require('node:test');
const assert = require('node:assert/strict');
require('./helpers/locks').stubLocksAlwaysAvailable();

const DATABASE = require.resolve('../src/config/database');

const txState = {};

function loadServices() {
  const fakeStore = { $transaction: async (fn) => fn(txState.tx) };
  require.cache[DATABASE] = {
    id: DATABASE,
    filename: DATABASE,
    loaded: true,
    exports: { getStore: () => fakeStore },
  };
  delete require.cache[require.resolve('../src/modules/orders/order-service')];
  return require('../src/modules/orders/order-service');
}

function fakeTx(seed = {}) {
  const state = {
    orders: seed.orders ? [...seed.orders] : [],
    createdOrders: [],
    items: [],
    audits: [],
    alerts: [],
    sellerProfiles: seed.sellerProfiles || [],
    users: seed.users || [],
  };
  state.tx = {
    product: { findUnique: async () => seed.product ?? null },
    address: { findUnique: async () => seed.address ?? null },
    order: {
      findMany: async ({ where }) => state.orders.filter((o) => o.buyerId === where.buyerId),
      create: async ({ data }) => {
        const row = { id: 'ord-new', ...data };
        state.createdOrders.push(row);
        state.orders.push(row);
        return row;
      },
      findUnique: async ({ where }) => state.orders.find((o) => o.id === where.id) ?? null,
      update: async ({ where, data }) => {
        const row = state.orders.find((o) => o.id === where.id);
        if (!row) throw new Error('order not found');
        Object.assign(row, data);
        return row;
      },
    },
    orderItem: { create: async ({ data }) => { state.items.push(data); return data; } },
    auditLog: { create: async ({ data }) => { state.audits.push(data); return data; } },
    sellerProfile: {
      findUnique: async ({ where }) => state.sellerProfiles.find((p) => p.id === where.id) ?? null,
    },
    user: {
      findUnique: async ({ where }) => state.users.find((u) => u.id === where.id) ?? null,
    },
    fraudAlert: {
      create: async ({ data }) => { state.alerts.push(data); return data; },
    },
    shippingQuote: { updateMany: async () => ({ count: 0 }) },
  };
  txState.tx = state.tx;
  return state;
}

const orders = loadServices();

function product(overrides = {}) {
  return {
    id: 'prod-1',
    status: 'published',
    deletedAt: null,
    stock: 10,
    price: 50000n,
    sellerId: 'sp-1',
    currency: 'TZS',
    title: 'Soksi',
    slug: 'soksi',
    snapshot: null,
    condition: 'new',
    ...overrides,
  };
}

function address(overrides = {}) {
  return { id: 'addr-1', userId: 'buyer-1', fullName: 'Juma', phone: '+255700000000', ...overrides };
}

test('a seller buying their own listing is rejected before an order exists', async () => {
  const state = fakeTx({
    product: product(),
    address: address(),
    sellerProfiles: [{ id: 'sp-1', userId: 'buyer-1' }],
  });

  await assert.rejects(
    orders.createOrder({ buyerId: 'buyer-1', productId: 'prod-1', quantity: 1, addressId: 'addr-1' }),
    { status: 403, message: 'SELF_DEALING_BLOCKED' },
  );
  assert.equal(state.createdOrders.length, 0);
  assert.equal(state.alerts.length, 0);
});

test('a normal order is created with an empty risk record', async () => {
  const state = fakeTx({
    product: product(),
    address: address(),
    sellerProfiles: [{ id: 'sp-1', userId: 'seller-1' }],
    users: [{ id: 'buyer-1', createdAt: new Date(Date.now() - 30 * 24 * 3600 * 1000) }],
  });

  const order = await orders.createOrder({
    buyerId: 'buyer-1',
    productId: 'prod-1',
    quantity: 2,
    addressId: 'addr-1',
  });

  assert.deepEqual(order.riskSignals, []);
  assert.equal(order.riskScore, 0);
  assert.equal(state.alerts.length, 0);
});

test('a rapid buyer order burst is stored on the order and alerted', async () => {
  const now = Date.now();
  const recent = Array.from({ length: 5 }, (_, i) => ({
    id: `old-${i}`,
    buyerId: 'buyer-1',
    sellerId: 'sp-1',
    status: 'PENDING_SHIPPING_FEE',
    placedAt: new Date(now - 60 * 1000),
  }));
  const state = fakeTx({
    product: product(),
    address: address(),
    sellerProfiles: [{ id: 'sp-1', userId: 'seller-1', storeName: 'Amina Shop' }],
    users: [{ id: 'buyer-1', createdAt: new Date(now - 30 * 24 * 3600 * 1000) }],
    orders: recent,
  });

  const order = await orders.createOrder({
    buyerId: 'buyer-1',
    productId: 'prod-1',
    quantity: 1,
    addressId: 'addr-1',
  });

  assert.ok(order.riskSignals.includes('RAPID_ORDER_BURST'));
  assert.ok(order.riskSignals.includes('REPEAT_BUYER_SELLER_PAIR'));
  assert.equal(order.riskScore > 0, true);
  assert.equal(state.alerts.length, order.riskSignals.length);
  assert.ok(state.alerts.every((a) => a.orderId === 'ord-new'));
  assert.ok(state.alerts.every((a) => a.sellerName === 'Amina Shop'));
  assert.ok(state.alerts.every((a) => a.resolved === false));
});

test('a new buyer account burst is flagged without blocking the order', async () => {
  const now = Date.now();
  const recent = Array.from({ length: 3 }, (_, i) => ({
    id: `old-${i}`,
    buyerId: 'buyer-1',
    sellerId: `sp-${i}`,
    status: 'PENDING_SHIPPING_FEE',
    placedAt: new Date(now - 60 * 1000),
  }));
  const state = fakeTx({
    product: product(),
    address: address(),
    sellerProfiles: [{ id: 'sp-1', userId: 'seller-1' }],
    users: [{ id: 'buyer-1', createdAt: new Date(now - 60 * 60 * 1000) }],
    orders: recent,
  });

  const order = await orders.createOrder({
    buyerId: 'buyer-1',
    productId: 'prod-1',
    quantity: 1,
    addressId: 'addr-1',
  });

  assert.ok(order.riskSignals.includes('BUYER_NEW_ACCOUNT_BURST'));
  assert.equal(state.createdOrders.length, 1);
});
