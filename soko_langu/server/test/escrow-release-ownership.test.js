const test = require('node:test');
const assert = require('node:assert/strict');

// Stub Firestore so releaseEscrow can run against an in-memory transaction doc.
const firebasePath = require.resolve('../src/config/firebase');
const docs = new Map();
require.cache[firebasePath] = {
  id: firebasePath,
  filename: firebasePath,
  loaded: true,
  exports: {
    getFirebaseAuth: () => null,
    getFirebaseFirestore: () => ({
      collection: (name) => ({
        doc: (id) => {
          const key = `${name}/${id}`;
          return {
            async get() {
              const d = docs.get(key);
              return { exists: !!d, data: () => (d ? { ...d } : undefined), ref: { update: async () => {} } };
            },
          };
        },
      }),
    }),
  },
};

const { getFirebaseFirestore } = require('../src/config/firebase');
const commerceStore = require('../src/services/commerce-store');

// Record what settleEscrowToSeller was asked to settle.
let lastSettle = null;
commerceStore.settleEscrowToSeller = async (o) => {
  lastSettle = o;
  return { alreadySettled: false, sellerReceives: o.amount - (o.commission || 0), orderId: o.orderId };
};

const { releaseEscrow } = require('../src/services/escrow-service');

test('releaseEscrow refuses when caller sellerId does not match the order seller', async () => {
  docs.set('transactions/o1', {
    orderId: 'o1',
    sellerId: 'seller-a',
    buyerId: 'buyer-1',
    amount: 10000,
    commission: 0,
    status: 'ESCROW_HELD',
  });

  await assert.rejects(
    () => releaseEscrow({ orderId: 'o1', sellerId: 'seller-b', idempotencyKey: 'k1', db: getFirebaseFirestore() }),
    /FORBIDDEN_SELLER/
  );
  assert.equal(lastSettle, null, 'settleEscrowToSeller must not be reached for wrong seller');
});

test('releaseEscrow proceeds when caller sellerId matches the order seller', async () => {
  docs.set('transactions/o2', {
    orderId: 'o2',
    sellerId: 'seller-a',
    buyerId: 'buyer-1',
    amount: 10000,
    commission: 500,
    status: 'ESCROW_HELD',
  });

  const result = await releaseEscrow({ orderId: 'o2', sellerId: 'seller-a', idempotencyKey: 'k2', db: getFirebaseFirestore() });
  assert.equal(result.success, true);
  assert.equal(lastSettle.sellerId, 'seller-a');
  assert.equal(lastSettle.orderId, 'o2');
  assert.equal(lastSettle.amount, 10000);
  assert.equal(lastSettle.commission, 500);
});
