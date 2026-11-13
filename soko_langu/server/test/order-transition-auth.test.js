const { test } = require('node:test');
const assert = require('node:assert/strict');
const { transitionOrder } = require('../src/services/escrow-service');

function memoryDb(seed) {
  const rows = new Map(Object.entries(seed));
  function doc(key) {
    return {
      async get() {
        if (!rows.has(key)) return { exists: false, data: () => undefined };
        return { exists: true, data: () => ({ ...rows.get(key) }) };
      },
      async update(patch) {
        rows.set(key, { ...rows.get(key), ...patch });
      },
    };
  }
  return {
    rows,
    collection(name) {
      return { doc(id) { return doc(`${name}/${id}`); } };
    },
  };
}

test('a non-participant cannot change an order status', async () => {
  const db = memoryDb({
    'orders/o1': { status: 'DRAFT', buyerId: 'buyer', sellerId: 'seller' },
  });
  await assert.rejects(
    () => transitionOrder({ orderId: 'o1', newStatus: 'PENDING_PAYMENT', uid: 'stranger', db }),
    /FORBIDDEN/,
  );
  assert.equal(db.rows.get('orders/o1').status, 'DRAFT');
});

test('an order with no participants cannot be transitioned', async () => {
  const db = memoryDb({ 'orders/o2': { status: 'DRAFT' } });
  await assert.rejects(
    () => transitionOrder({ orderId: 'o2', newStatus: 'PENDING_PAYMENT', uid: 'buyer', db }),
    /FORBIDDEN/,
  );
});

test('a buyer cannot write a paid or refunded status', async () => {
  const db = memoryDb({
    'orders/o3': { status: 'DRAFT', buyerId: 'buyer', sellerId: 'seller' },
  });
  await assert.rejects(
    () => transitionOrder({ orderId: 'o3', newStatus: 'PAID', uid: 'buyer', db }),
    /CLIENT_CANNOT_SET_FINANCIAL_STATE/,
  );
  await assert.rejects(
    () => transitionOrder({ orderId: 'o3', newStatus: 'REFUNDED', uid: 'buyer', db }),
    /CLIENT_CANNOT_SET_FINANCIAL_STATE/,
  );
  assert.equal(db.rows.get('orders/o3').status, 'DRAFT');
});

test('a participant can make a legal non-financial transition', async () => {
  const db = memoryDb({
    'orders/o4': { status: 'DRAFT', buyerId: 'buyer', sellerId: 'seller' },
  });
  const result = await transitionOrder({
    orderId: 'o4',
    newStatus: 'pending_payment',
    uid: 'seller',
    db,
  });
  assert.equal(result.status, 'PENDING_PAYMENT');
  assert.equal(db.rows.get('orders/o4').status, 'PENDING_PAYMENT');
  assert.equal(db.rows.get('orders/o4').statusChangedBy, 'seller');
});
