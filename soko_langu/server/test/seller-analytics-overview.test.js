const { test } = require('node:test');
const assert = require('node:assert/strict');

// Hermetic overview test: the DTO must sum product snapshot views and count
// only the current month toward monthlyEarnings.
const state = { store: null };

const DB = require('../src/config/database');
const Firebase = require('../src/config/firebase');

DB.getStore = () => state.store;
Firebase.getFirebaseFirestore = () => null;

const { getSellerAnalyticsOverview } = require('../src/modules/seller-analytics/controller');

function createStore({ seller, products, orders }) {
  return {
    sellerProfile: {
      findUnique: async () => seller,
      findFirst: async () => null,
    },
    user: {
      findUnique: async () => ({ firebaseUid: 'fire-seller' }),
    },
    product: {
      findMany: async () => products,
    },
    boost: {
      findMany: async () => [],
    },
    order: {
      findMany: async () => orders,
    },
  };
}

test('overview sums snapshot views and current-month earnings only', async () => {
  const now = new Date();
  const old = new Date(now.getFullYear(), now.getMonth() - 11, 15);
  state.store = createStore({
    seller: { id: '123e4567-e89b-12d3-a456-426614174000', userId: 'u-seller' },
    products: [
      { id: 'p1', title: 'A', snapshot: JSON.stringify({ viewCount: 10, image: 'img-a' }) },
      { id: 'p2', title: 'B', snapshot: JSON.stringify({ viewCount: 5, image: 'img-b' }) },
    ],
    orders: [
      { status: 'completed', totalAmount: 100, createdAt: now },
      { status: 'completed', totalAmount: 50, createdAt: old },
    ],
  });

  let payload = null;
  const req = { params: { sellerId: '123e4567-e89b-12d3-a456-426614174000' } };
  const res = { json: async (body) => { payload = body; } };

  await getSellerAnalyticsOverview(req, res);

  assert.ok(payload.success);
  assert.equal(payload.data.totalProducts, 2);
  assert.equal(payload.data.totalProductViews, 15);
  assert.equal(payload.data.successfulOrders, 2);
  assert.equal(payload.data.monthlyEarnings, 100);
  assert.equal(payload.data.topProducts[0].productId, 'p1');
});
