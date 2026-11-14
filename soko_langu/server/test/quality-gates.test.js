// Quality gates decide whether a seller gets full distribution. The reliability
// floor is the one gate whose units were wrong: the score is persisted as a
// 0..1 decimal, so a 0-100 threshold blocked every seller instead of only the
// bad ones. These tests pin the scale.
const { test } = require('node:test');
const assert = require('node:assert/strict');

const DB = require('../src/config/database');

const state = { store: null };
DB.getStore = () => state.store;

const {
  GATE_THRESHOLDS,
  evaluateQualityGates,
} = require('../src/modules/trust/quality-gates');

function seller(overrides = {}) {
  return {
    id: 'sp-1',
    userId: 'u-seller',
    verificationStatus: 'verified',
    reliabilityScore: 0.9,
    products: [],
    ...overrides,
  };
}

function createStore({ profile, products = {} } = {}) {
  return {
    sellerProfile: { findUnique: async () => profile },
    product: { findUnique: async ({ where }) => products[where.id] || null },
  };
}

test('the reliability floor is expressed on the stored 0..1 scale', () => {
  assert.equal(GATE_THRESHOLDS.highRiskSellerScore, 0.3);
});

test('a healthy verified seller passes every gate', async () => {
  state.store = createStore({ profile: seller() });
  const result = await evaluateQualityGates({ sellerId: 'sp-1' });
  assert.equal(result.allowed, true);
  assert.deepEqual(result.gates, []);
});

test('a low reliability score blocks distribution', async () => {
  state.store = createStore({ profile: seller({ reliabilityScore: 0.2 }) });
  const result = await evaluateQualityGates({ sellerId: 'sp-1' });
  assert.equal(result.allowed, false);
  assert.ok(result.gates.includes('RELIABILITY_SCORE'));
});

test('a perfect 1.0 score is never treated as high risk', async () => {
  state.store = createStore({ profile: seller({ reliabilityScore: 1 }) });
  const result = await evaluateQualityGates({ sellerId: 'sp-1' });
  assert.equal(result.allowed, true);
});

test('a brand-new seller (0 score) is gated until they build history', async () => {
  state.store = createStore({ profile: seller({ reliabilityScore: 0 }) });
  const result = await evaluateQualityGates({ sellerId: 'sp-1' });
  assert.equal(result.allowed, false);
  assert.ok(result.gates.includes('RELIABILITY_SCORE'));
});

test('an unverified seller is blocked on identity', async () => {
  state.store = createStore({ profile: seller({ verificationStatus: 'pending' }) });
  const result = await evaluateQualityGates({ sellerId: 'sp-1' });
  assert.equal(result.allowed, false);
  assert.ok(result.blocking.includes('IDENTITY_VERIFICATION'));
});

test('an unverified seller hits the listing cap', async () => {
  state.store = createStore({
    profile: seller({
      verificationStatus: 'pending',
      products: Array.from({ length: GATE_THRESHOLDS.maxNewSellerProducts }, (_, i) => ({ id: `p-${i}` })),
    }),
  });
  const result = await evaluateQualityGates({ sellerId: 'sp-1' });
  assert.ok(result.blocking.includes('NEW_SELLER_PRODUCT_CAP'));
});

test('a verified seller is not subject to the new-seller cap', async () => {
  state.store = createStore({
    profile: seller({
      products: Array.from({ length: GATE_THRESHOLDS.maxNewSellerProducts }, (_, i) => ({ id: `p-${i}` })),
    }),
  });
  const result = await evaluateQualityGates({ sellerId: 'sp-1' });
  assert.equal(result.gates.includes('NEW_SELLER_PRODUCT_CAP'), false);
  assert.equal(result.allowed, true);
});

test('a high-value listing with too few photos is blocked', async () => {
  state.store = createStore({
    profile: seller(),
    products: {
      'p-1': { id: 'p-1', price: BigInt(GATE_THRESHOLDS.highValueLimit + 1), media: [{ id: 'm-1' }] },
    },
  });
  const result = await evaluateQualityGates({ sellerId: 'sp-1', productId: 'p-1' });
  assert.ok(result.blocking.includes('HIGH_VALUE_PHOTOS'));
});

test('a high-value listing with enough photos passes', async () => {
  state.store = createStore({
    profile: seller(),
    products: {
      'p-1': {
        id: 'p-1',
        price: BigInt(GATE_THRESHOLDS.highValueLimit + 1),
        media: [{ id: 'm-1' }, { id: 'm-2' }],
      },
    },
  });
  const result = await evaluateQualityGates({ sellerId: 'sp-1', productId: 'p-1' });
  assert.equal(result.blocking.includes('HIGH_VALUE_PHOTOS'), false);
});

test('a missing seller is a not-found error', async () => {
  state.store = createStore({ profile: null });
  await assert.rejects(
    evaluateQualityGates({ sellerId: 'sp-missing' }),
    { message: 'SELLER_NOT_FOUND' },
  );
});
