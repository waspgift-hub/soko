// A verified-purchase badge is a trust claim: it tells every shopper that the
// reviewer actually received the item. Before this rule the server always wrote
// `isVerifiedPurchase: false`, and the reviewed seller came straight from the
// request body, so a review could be attributed to anyone. These tests pin the
// new contract: the badge and the seller come from a settled order the server
// can see, and a review cannot exist without one (except the separate,
// always-unverified seller-trust vote).
const { test, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');

const FIREBASE = require.resolve('../src/config/firebase');
const DATABASE = require.resolve('../src/config/database');
const REVIEW_STORE = require.resolve('../src/modules/reviews/review-store');

let db;
let orders;
let reviewStore;

function installStubs() {
  require.cache[FIREBASE] = {
    id: FIREBASE,
    filename: FIREBASE,
    loaded: true,
    exports: { getFirebaseFirestore: () => db },
  };
  require.cache[DATABASE] = {
    id: DATABASE,
    filename: DATABASE,
    loaded: true,
    exports: {
      getStore: () => ({
        order: {
          findMany: async ({ where }) => orders.filter((o) => o.buyerId === where.buyerId),
        },
      }),
    },
  };
  delete require.cache[REVIEW_STORE];
  reviewStore = require(REVIEW_STORE);
}

function matches(doc, filter) {
  const value = filter.field.split('.').reduce((acc, key) => (acc == null ? acc : acc[key]), doc);
  return value === filter.val;
}

function makeDb() {
  const collections = new Map();
  const col = (name) => {
    if (!collections.has(name)) collections.set(name, new Map());
    return collections.get(name);
  };

  const query = (name, filters) => ({
    where(field, op, val) {
      assert.equal(op, '==');
      return query(name, [...filters, { field, op, val }]);
    },
    orderBy() {
      return this;
    },
    limit() {
      return this;
    },
    async get() {
      const docs = [...col(name).entries()].filter(([, doc]) => filters.every((f) => matches(doc, f)));
      return {
        empty: docs.length === 0,
        size: docs.length,
        docs: docs.map(([id, doc]) => ({ id, exists: true, data: () => ({ ...doc }) })),
        data: () => ({ count: docs.length }),
      };
    },
    count() {
      return this;
    },
  });

  return {
    collection(name) {
      return {
        doc(id) {
          const key = String(id);
          return {
            async get() {
              const doc = col(name).get(key);
              return { id: key, exists: Boolean(doc), data: () => (doc ? { ...doc } : undefined) };
            },
            async set(value, options) {
              const previous = col(name).get(key) || {};
              col(name).set(key, options && options.merge ? { ...previous, ...value } : { ...value });
            },
            async update(value) {
              const previous = col(name).get(key) || {};
              col(name).set(key, { ...previous, ...value });
            },
          };
        },
        where(field, op, val) {
          return query(name, [{ field, op, val }]);
        },
        count() {
          return query(name, []);
        },
      };
    },
    _collection: col,
  };
}

function settledOrder(overrides = {}) {
  return {
    id: 'order-1',
    buyerId: 'buyer-1',
    sellerId: 'seller-1',
    status: 'COMPLETED',
    productSnapshot: { productId: 'product-1' },
    ...overrides,
  };
}

function reviews() {
  return [...db._collection('reviews').values()];
}

beforeEach(() => {
  orders = [];
  db = makeDb();
  installStubs();
});

afterEach(() => {
  for (const key of [FIREBASE, DATABASE, REVIEW_STORE]) delete require.cache[key];
});

test('a buyer with no order cannot review a product', async () => {
  await assert.rejects(
    reviewStore.upsertReview({
      userId: 'buyer-1',
      productId: 'product-1',
      sellerId: 'seller-1',
      rating: 5,
      comment: 'Great',
    }),
    { code: 'PURCHASE_REQUIRED', status: 403 },
  );
  assert.equal(reviews().length, 0);
});

test('an unpaid or in-flight order does not verify a purchase', async () => {
  for (const status of ['PAID', 'DISPATCHED', 'IN_TRANSIT', 'CANCELLED', 'REFUNDED', 'pending_payment']) {
    orders = [settledOrder({ status })];
    await assert.rejects(
      reviewStore.upsertReview({
        userId: 'buyer-1',
        productId: 'product-1',
        sellerId: 'seller-1',
        rating: 4,
        comment: '',
      }),
      { code: 'PURCHASE_REQUIRED' },
    );
  }
  assert.equal(reviews().length, 0);
});

test('another buyer order cannot verify this buyer', async () => {
  orders = [settledOrder({ buyerId: 'someone-else' })];
  await assert.rejects(
    reviewStore.upsertReview({
      userId: 'buyer-1',
      productId: 'product-1',
      rating: 5,
    }),
    { code: 'PURCHASE_REQUIRED' },
  );
});

test('a completed order verifies the review and records the order', async () => {
  orders = [settledOrder()];
  const review = await reviewStore.upsertReview({
    userId: 'buyer-1',
    productId: 'product-1',
    sellerId: 'forged-seller',
    rating: 5,
    comment: 'As described',
    userName: 'Amina',
  });

  assert.equal(review.isVerifiedPurchase, true);
  assert.equal(review.orderId, 'order-1');
  // The order wins over the request body.
  assert.equal(review.sellerId, 'seller-1');
});

test('delivered, delivery_confirmed and wallet_credited all qualify', async () => {
  for (const status of ['delivered', 'DELIVERY_CONFIRMED', 'WALLET_CREDITED']) {
    orders = [settledOrder({ id: 'order-' + status, status })];
    const review = await reviewStore.upsertReview({
      userId: 'buyer-1',
      productId: 'product-1',
      rating: 5,
    });
    assert.equal(review.isVerifiedPurchase, true, status);
    assert.equal(review.orderId, 'order-' + status, status);
  }
});

test('a legacy top-level productId is accepted as purchase evidence', async () => {
  orders = [{ id: 'legacy-order', buyerId: 'buyer-1', sellerId: 'seller-1', status: 'completed', productId: 'product-1' }];
  const review = await reviewStore.upsertReview({
    userId: 'buyer-1',
    productId: 'product-1',
    rating: 4,
  });
  assert.equal(review.isVerifiedPurchase, true);
});

test('an order for a different product does not verify', async () => {
  orders = [settledOrder({ productSnapshot: { productId: 'other-product' } })];
  await assert.rejects(
    reviewStore.upsertReview({ userId: 'buyer-1', productId: 'product-1', rating: 5 }),
    { code: 'PURCHASE_REQUIRED' },
  );
});

test('a seller cannot review their own product', async () => {
  orders = [settledOrder({ sellerId: 'buyer-1' })];
  await assert.rejects(
    reviewStore.upsertReview({ userId: 'buyer-1', productId: 'product-1', rating: 5 }),
    { code: 'SELF_REVIEW' },
  );
});

test('the rating is validated before the purchase lookup', async () => {
  await assert.rejects(
    reviewStore.upsertReview({ userId: 'buyer-1', productId: 'product-1', rating: 0 }),
    { code: 'INVALID_RATING' },
  );
});

test('editing a review keeps one document and keeps it verified', async () => {
  orders = [settledOrder()];
  const first = await reviewStore.upsertReview({
    userId: 'buyer-1',
    productId: 'product-1',
    rating: 5,
    comment: 'First',
  });
  const second = await reviewStore.upsertReview({
    userId: 'buyer-1',
    productId: 'product-1',
    rating: 3,
    comment: 'Edited',
  });

  assert.equal(second.id, first.id);
  assert.equal(reviews().length, 1);
  assert.equal(second.rating, 3);
  assert.equal(second.isVerifiedPurchase, true);
});

test('a standalone seller-trust vote needs no order but is never verified', async () => {
  const review = await reviewStore.upsertReview({
    userId: 'buyer-1',
    productId: 'seller_seller-9',
    sellerId: 'forged-seller',
    rating: 5,
  });

  assert.equal(review.isVerifiedPurchase, false);
  assert.equal(review.orderId, null);
  assert.equal(review.sellerId, 'seller-9');
  // No junk `products/seller_uid` document is created for a trust vote.
  assert.equal(db._collection('products').size, 0);
});

test('a seller cannot cast a trust vote for themselves', async () => {
  await assert.rejects(
    reviewStore.upsertReview({ userId: 'seller-9', productId: 'seller_seller-9', rating: 5 }),
    { code: 'SELF_REVIEW' },
  );
});

test('findSettledPurchase ignores unsettled rows and matches the buyer', async () => {
  orders = [
    settledOrder({ id: 'paid', status: 'PAID' }),
    settledOrder({ id: 'other', buyerId: 'other' }),
    settledOrder({ id: 'settled', status: 'completed' }),
  ];
  const purchase = await reviewStore.findSettledPurchase({ userId: 'buyer-1', productId: 'product-1' });
  assert.equal(purchase.id, 'settled');
});

test('missing identifiers never resolve a purchase', async () => {
  assert.equal(await reviewStore.findSettledPurchase({ userId: '', productId: 'p' }), null);
  assert.equal(await reviewStore.findSettledPurchase({ userId: 'u', productId: '' }), null);
});
