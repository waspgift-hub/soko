const { test } = require('node:test');
const assert = require('node:assert/strict');
// Money paths take a fail-closed Redis lock; hermetic tests install an
// in-process stub before the service modules bind requireLock at require time.
require('./helpers/locks').stubLocksAlwaysAvailable();

const DATABASE = require.resolve('../src/config/database');

// Replace the data seam before loading the services under test so createOrder
// and approveQuote run against an in-memory store instead of Firestore.
const txState = {};

function loadServices() {
  const fakeStore = {
    $transaction: async (fn) => fn(txState.tx),
  };
  require.cache[DATABASE] = {
    id: DATABASE,
    filename: DATABASE,
    loaded: true,
    exports: { getStore: () => fakeStore },
  };
  delete require.cache[require.resolve('../src/modules/orders/order-service')];
  delete require.cache[require.resolve('../src/modules/shipping/shipping-quote-service')];
  return {
    orders: require('../src/modules/orders/order-service'),
    shipping: require('../src/modules/shipping/shipping-quote-service'),
  };
}

function fakeTx(seed = {}) {
  const state = {
    orders: seed.orders ?? [],
    createdOrders: [],
    items: [],
    audits: [],
  };
  state.tx = {
    product: { findUnique: async () => seed.product ?? null },
    address: { findUnique: async () => seed.address ?? null },
    order: {
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
    orderItem: {
      create: async ({ data }) => {
        state.items.push(data);
        return data;
      },
    },
    auditLog: {
      create: async ({ data }) => {
        state.audits.push(data);
        return data;
      },
    },
    shippingQuote: {
      updateMany: async () => ({ count: 0 }),
    },
  };
  txState.tx = state.tx;
  return state;
}

const { orders, shipping } = loadServices();

test('createOrder charges 3.5% on the caller-supplied quantity', async () => {
  const state = fakeTx({
    product: {
      id: 'prod-1',
      status: 'published',
      deletedAt: null,
      stock: 10,
      price: 50000n,
      sellerId: 'seller-profile-1',
      currency: 'TZS',
      title: 'Soksi',
      slug: 'soksi',
      snapshot: null,
      condition: 'new',
    },
    address: { id: 'addr-1', userId: 'buyer-1', fullName: 'Juma', phone: '+255700000000' },
  });

  const order = await orders.createOrder({
    buyerId: 'buyer-1',
    productId: 'prod-1',
    quantity: 2,
    addressId: 'addr-1',
  });

  assert.equal(order.productPrice, 100000n, 'line total = unit price × quantity');
  assert.equal(order.platformCommission, 3500n, '3.5% of 100,000');
  assert.equal(order.totalAmount, 103500n, 'buyer pays item + commission');
  assert.equal(state.items[0].totalPrice, 100000n);
  assert.equal(order.status, 'PENDING_SHIPPING_FEE');
});

test('createOrder honours a zero commission rate', async () => {
  const previous = process.env.PLATFORM_COMMISSION_PERCENT;
  try {
    process.env.PLATFORM_COMMISSION_PERCENT = '0';
    // config caches the rate at require time, so reload config, the commission
    // utility and the services under test for this case.
    delete require.cache[require.resolve('../src/config')];
    delete require.cache[require.resolve('../src/utils/commission-parity')];
    const fresh = loadServices();
    fakeTx({
      product: {
        id: 'prod-2',
        status: 'published',
        deletedAt: null,
        stock: 10,
        price: 25000n,
        sellerId: 'seller-profile-1',
        currency: 'TZS',
        title: 'Kiatu',
        slug: 'kiatu',
        snapshot: null,
      },
      address: { id: 'addr-2', userId: 'buyer-2' },
    });

    const order = await fresh.orders.createOrder({
      buyerId: 'buyer-2',
      productId: 'prod-2',
      quantity: 1,
      addressId: 'addr-2',
    });

    assert.equal(order.platformCommission, 0n);
    assert.equal(order.totalAmount, 25000n);
  } finally {
    if (previous === undefined) delete process.env.PLATFORM_COMMISSION_PERCENT;
    else process.env.PLATFORM_COMMISSION_PERCENT = previous;
    delete require.cache[require.resolve('../src/config')];
    delete require.cache[require.resolve('../src/utils/commission-parity')];
  }
});

test('approveQuote adds commission to item + shipping total', async () => {
  const order = {
    id: 'ord-q',
    status: 'SHIPPING_FEE_SUBMITTED',
    productPrice: 100000n,
    shippingFee: 5000n,
    platformCommission: 0n,
    totalAmount: 105000n,
  };
  const state = fakeTx({ orders: [order] });

  const updated = await shipping.approveQuote({
    orderId: 'ord-q',
    approvedBy: 'buyer-1',
    actor: 'buyer',
  });

  assert.equal(updated.platformCommission, 3500n);
  assert.equal(updated.totalAmount, 108500n, '100,000 item + 5,000 shipping + 3,500 commission');
  assert.equal(updated.status, 'AWAITING_ESCROW_PAYMENT');
  assert.equal(state.orders[0].totalAmount, 108500n);
});
