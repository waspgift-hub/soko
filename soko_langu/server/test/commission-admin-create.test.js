// End-to-end proof that the admin panel rate reaches the order row, not just a
// helper: with a saved 5% setting, createOrder must store 5% — not the env
// default — on a package with no shipping quote yet.
const { test } = require('node:test');
const assert = require('node:assert/strict');
require('./helpers/locks').stubLocksAlwaysAvailable();

const DATABASE = require.resolve('../src/config/database');
const SETTINGS = require.resolve('../src/modules/admin/settings-service');
const PARITY = require.resolve('../src/utils/commission-parity');
const ORDER_SERVICE = require.resolve('../src/modules/orders/order-service');

const realSettings = require(SETTINGS);
const txState = {};

function loadOrders() {
  require.cache[DATABASE] = {
    id: DATABASE,
    filename: DATABASE,
    loaded: true,
    exports: { getStore: () => ({ $transaction: async (fn) => fn(txState.tx) }) },
  };
  require.cache[SETTINGS] = {
    id: SETTINGS,
    filename: SETTINGS,
    loaded: true,
    exports: {
      ...realSettings,
      getStoredSettings: async () => ({ paymentsAndCurrency: { platformCommissionPct: 5 } }),
    },
  };
  delete require.cache[PARITY];
  delete require.cache[ORDER_SERVICE];
  return require(ORDER_SERVICE);
}

function fakeTx(seed) {
  const state = { orders: [], created: [] };
  state.tx = {
    product: { findUnique: async () => seed.product },
    address: { findUnique: async () => seed.address },
    order: {
      findMany: async () => [],
      create: async ({ data }) => {
        const row = { id: 'ord-admin-rate', ...data };
        state.created.push(row);
        state.orders.push(row);
        return row;
      },
      findUnique: async ({ where }) => state.orders.find((o) => o.id === where.id) ?? null,
    },
    orderItem: { create: async () => ({}) },
    auditLog: { create: async () => ({}) },
    sellerProfile: { findUnique: async () => null },
    user: { findUnique: async () => null },
    fraudAlert: { create: async () => ({}) },
  };
  txState.tx = state.tx;
  return state;
}

test('createOrder charges the admin-configured rate', async () => {
  try {
    const orders = loadOrders();
    const state = fakeTx({
      product: {
        id: 'p1',
        status: 'published',
        deletedAt: null,
        stock: 5,
        price: 100000n,
        sellerId: 'sp-1',
        currency: 'TZS',
        title: 'Soksi',
        slug: 'soksi',
        condition: 'new',
      },
      address: { id: 'a1', userId: 'buyer-1' },
    });

    const order = await orders.createOrder({
      buyerId: 'buyer-1',
      productId: 'p1',
      quantity: 1,
      addressId: 'a1',
    });

    assert.equal(order.platformCommission, 5000n);
    assert.equal(order.totalAmount, 105000n);
    assert.equal(state.created.length, 1);
  } finally {
    delete require.cache[PARITY];
    delete require.cache[ORDER_SERVICE];
    delete require.cache[SETTINGS];
  }
});
