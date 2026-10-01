const { test } = require('node:test');
const assert = require('node:assert/strict');

// Mirror regression: dispatch, delivery, and OTP issue all move the
// authoritative Postgres order forward, so each must also update the legacy
// Firestore presentation mirror that Flutter streams.
const state = { store: null };
const mirrored = [];

const DB = require('../src/config/database');
const Mirror = require('../src/modules/legacy-compat/presentation-mirror');

DB.getStore = () => state.store;
Mirror.syncLegacyOrderStatus = async (order) => {
  mirrored.push({ ...order });
};

const { ORDER_STATES } = require('../src/modules/orders/order-state-machine');
const { markDispatched, markDelivered } = require('../src/modules/orders/order-service');
const { issueOtp } = require('../src/modules/handover/handover-service');

function createStore(order) {
  const rows = { order: { ...order } };
  let seq = 0;
  const tx = {
    order: {
      findUnique: async () => ({ ...rows.order }),
      update: async ({ data }) => {
        Object.assign(rows.order, data);
        return { ...rows.order };
      },
    },
    auditLog: {
      create: async () => ({ id: `audit-${++seq}` }),
    },
    otpCredential: {
      updateMany: async () => ({ count: 0 }),
      create: async ({ data }) => ({ id: `cred-${++seq}`, ...data }),
    },
  };
  return {
    $transaction: async (fn) => fn(tx),
    _rows: rows,
  };
}

test('markDispatched mirrors DISPATCHED to the legacy presentation docs', async () => {
  mirrored.length = 0;
  state.store = createStore({
    id: 'o-dispatch',
    buyerId: 'u-buyer',
    sellerId: 'sp-1',
    status: ORDER_STATES.ESCROW_HELD,
  });

  const updated = await markDispatched({
    orderId: 'o-dispatch',
    sellerId: 'sp-1',
    courierName: 'Courier',
    trackingNumber: 'TRACK-1',
  });

  assert.equal(updated.status, ORDER_STATES.DISPATCHED);
  assert.equal(mirrored.length, 1);
  assert.equal(mirrored[0].id, 'o-dispatch');
  assert.equal(mirrored[0].status, ORDER_STATES.DISPATCHED);
});

test('markDelivered mirrors DELIVERED to the legacy presentation docs', async () => {
  mirrored.length = 0;
  state.store = createStore({
    id: 'o-delivered',
    buyerId: 'u-buyer',
    sellerId: 'sp-1',
    status: ORDER_STATES.DISPATCHED,
  });

  const updated = await markDelivered({ orderId: 'o-delivered', actorId: 'sp-1' });

  assert.equal(updated.status, ORDER_STATES.DELIVERED);
  assert.equal(mirrored.length, 1);
  assert.equal(mirrored[0].id, 'o-delivered');
  assert.equal(mirrored[0].status, ORDER_STATES.DELIVERED);
});

test('issueOtp mirrors OTP_PENDING to the legacy presentation docs', async () => {
  mirrored.length = 0;
  state.store = createStore({
    id: 'o-otp',
    orderNumber: 'SV202609300001',
    buyerId: 'u-buyer',
    sellerId: 'sp-1',
    status: ORDER_STATES.DISPATCHED,
  });

  const result = await issueOtp({ orderId: 'o-otp', issuedBy: 'u-buyer', userRole: 'buyer' });

  assert.ok(result.otp);
  assert.ok(result.qrToken);
  assert.equal(mirrored.length, 1);
  assert.equal(mirrored[0].id, 'o-otp');
  assert.equal(mirrored[0].status, ORDER_STATES.OTP_PENDING);
});
