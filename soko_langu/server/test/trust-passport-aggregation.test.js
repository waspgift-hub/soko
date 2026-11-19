// A seller can be resolved from either a Postgres id or a Firebase UID, but
// orders only carry the Postgres id. These tests pin that distinction so a
// UID lookup cannot report zero history and hide an earned trust score.
const { test } = require('node:test');
const assert = require('node:assert/strict');

const DB = require('../src/config/database');
const Firebase = require('../src/config/firebase');

const state = { store: null, orderWhere: [], disputeWhere: [] };

DB.getStore = () => state.store;
Firebase.getFirebaseFirestore = () => ({
  collection: () => ({
    doc: () => ({ get: async () => ({ exists: false, data: () => null }) }),
  }),
});

const { getTrustPassport } = require('../src/modules/trust/trust-passport');

function createStore() {
  const seller = {
    id: 'sp-1',
    userId: 'firebase-uid-1',
    storeName: 'Duka Bora',
    storeSlug: 'duka-bora',
    verificationStatus: 'verified',
    reliabilityScore: 0.92,
  };

  return {
    sellerProfile: {
      findUnique: async ({ where }) =>
        (where.id === seller.id || where.userId === seller.userId ? seller : null),
    },
    order: {
      count: async ({ where }) => {
        state.orderWhere.push(where);
        if (where.sellerId !== seller.id) return 0;
        if (where.status === 'completed') return 2;
        if (where.status && Array.isArray(where.status.in)) return 2;
        if (where.dispatchedAt) return 2;
        return 3;
      },
    },
    dispute: {
      count: async ({ where }) => {
        state.disputeWhere.push(where);
        return where.order.sellerId === seller.id ? 1 : 0;
      },
    },
  };
}

test('aggregates history against the resolved Postgres seller id', async () => {
  state.store = createStore();
  state.orderWhere = [];
  state.disputeWhere = [];

  const passport = await getTrustPassport({ sellerId: 'firebase-uid-1' });

  assert.equal(passport.metrics.totalOrders, 3);
  assert.equal(passport.metrics.completedOrders, 2);
  assert.equal(passport.metrics.activeDisputes, 1);
  assert.equal(passport.metrics.fulfillmentRate, 2 / 3);
  assert.ok(state.orderWhere.every((where) => where.sellerId === 'sp-1'));
  assert.equal(state.disputeWhere[0].order.sellerId, 'sp-1');
});

test('returns the stored reliability score on its native 0..1 scale', async () => {
  state.store = createStore();

  const passport = await getTrustPassport({ sellerId: 'sp-1' });

  assert.equal(passport.seller.reliabilityScore, 0.92);
});
