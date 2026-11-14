// Trust cluster: delivery authorization, delivery evidence, auto-release
// safeguards, and dispute role derivation.
//
// These are the rules that stand between an escrow balance and a payout, so the
// tests assert the *refusals* as carefully as the happy paths.
const { test } = require('node:test');
const assert = require('node:assert/strict');
require('./helpers/locks').stubLocksAlwaysAvailable();

const DB = require('../src/config/database');
const Mirror = require('../src/modules/legacy-compat/presentation-mirror');
const EscrowRelease = require('../src/modules/escrow/escrow-release');

const state = { store: null };
DB.getStore = () => state.store;
Mirror.syncLegacyOrderStatus = async () => {};

const releaseCalls = [];
EscrowRelease.releaseEscrowAndSettle = async (tx, order, opts = {}) => {
  releaseCalls.push({ orderId: order.id, reason: opts.reason });
  return { id: 'hold-1' };
};

const {
  ORDER_STATES,
  OrderStateMachine,
} = require('../src/modules/orders/order-state-machine');
const {
  deliveryActorFor,
  assertCanMarkDelivered,
} = require('../src/modules/orders/delivery-authorization');
const {
  markDelivered,
  completeOrder,
  disputeOrder,
} = require('../src/modules/orders/order-service');
const {
  hasVerifiedDelivery,
  evaluateAutoRelease,
} = require('../src/modules/disputes/auto-release-service');
const { fileDispute } = require('../src/modules/disputes/dispute-service');
const escrowService = require('../src/services/escrow-service');

const READ_MUST_NOT_HAPPEN = Symbol('read_must_not_happen');

function goodSeller(overrides = {}) {
  return {
    id: 'sp-1',
    userId: 'u-seller',
    reliabilityScore: 0.9,
    verificationStatus: 'verified',
    ...overrides,
  };
}

function goodUser(overrides = {}) {
  return {
    id: 'u-seller',
    firebaseUid: 'fire-seller',
    accountStatus: 'active',
    ...overrides,
  };
}

function baseOrder(overrides = {}) {
  return {
    id: 'o-1',
    orderNumber: 'SV202611140001',
    buyerId: 'u-buyer',
    sellerId: 'sp-1',
    status: ORDER_STATES.DELIVERED,
    deliveredAt: new Date(),
    deliveredBy: 'u-courier',
    deliveredByRole: 'courier',
    trackingNumber: 'TRK-1',
    courierName: 'Courier Co',
    shippingAddressSnapshot: { city: 'Dar es Salaam' },
    ...overrides,
  };
}

// Minimal Prisma-shaped transaction. `disputes`/`holds` are only surfaced when
// the caller asks for includes, matching the store facade.
function makeTx(order, { seller = goodSeller(), user = goodUser(), openReport = null } = {}) {
  const row = { ...order };
  const updates = [];
  const disputes = [];
  const holds = [];
  const tx = {
    order: {
      findUnique: async (args = {}) => {
        const copy = { ...row };
        if (args.include) {
          copy.dispute = disputes;
          copy.escrowHold = holds;
        }
        return copy;
      },
      update: async ({ data }) => {
        Object.assign(row, data);
        updates.push({ ...data });
        return { ...row };
      },
      create: async ({ data }) => ({ id: 'order-new', ...data }),
    },
    sellerProfile: {
      findUnique: async () => {
        if (seller === READ_MUST_NOT_HAPPEN) {
          throw new Error('sellerProfile read unexpectedly');
        }
        return seller;
      },
    },
    user: {
      findUnique: async () => {
        if (user === READ_MUST_NOT_HAPPEN) throw new Error('user read unexpectedly');
        return user;
      },
    },
    moderationReport: {
      findFirst: async () => openReport,
    },
    dispute: {
      create: async ({ data }) => {
        const created = { id: `dispute-${disputes.length + 1}`, ...data };
        disputes.push(created);
        return created;
      },
    },
    escrowHold: {
      findFirst: async () => holds.find((h) => h.status === 'holding') || null,
      update: async ({ where, data }) => {
        const hold = holds.find((h) => h.id === where.id);
        if (hold) Object.assign(hold, data);
        return hold;
      },
    },
    auditLog: {
      create: async ({ data }) => ({ id: 'audit-1', ...data }),
    },
  };
  return { tx, row, updates, disputes, holds };
}

function createStore(order, opts) {
  const built = makeTx(order, opts);
  return {
    $transaction: async (fn) => fn(built.tx),
    order: { findUnique: async () => ({ ...built.row }) },
    _row: built.row,
    _updates: built.updates,
    _disputes: built.disputes,
    _holds: built.holds,
  };
}

/* ------------------------------------------------------------------ */
/* delivery authorization                                             */
/* ------------------------------------------------------------------ */

test('deliveryActorFor maps only independent roles to a delivery actor', () => {
  assert.equal(deliveryActorFor('admin'), 'admin');
  assert.equal(deliveryActorFor('super_admin'), 'admin');
  assert.equal(deliveryActorFor('courier'), 'courier');
  assert.equal(deliveryActorFor('seller'), null);
  assert.equal(deliveryActorFor('buyer'), null);
  assert.equal(deliveryActorFor(undefined), null);
});

test('assertCanMarkDelivered refuses a seller and a buyer', () => {
  const order = baseOrder();
  assert.throws(
    () => assertCanMarkDelivered(order, { userId: 'sp-1', role: 'seller' }),
    { message: 'SELLER_CANNOT_MARK_DELIVERED' },
  );
  assert.throws(
    () => assertCanMarkDelivered(order, { userId: 'u-buyer', role: 'buyer' }),
    { message: 'SELLER_CANNOT_MARK_DELIVERED' },
  );
});

test('assertCanMarkDelivered binds the courier to the assigned parcel', () => {
  const order = baseOrder({ courierId: 'u-courier' });

  assert.equal(
    assertCanMarkDelivered(order, { userId: 'u-courier', role: 'courier' }),
    'courier',
  );
  assert.throws(
    () => assertCanMarkDelivered(order, { userId: 'u-other', role: 'courier' }),
    { message: 'NOT_ASSIGNED_COURIER' },
  );
});

test('assertCanMarkDelivered leaves pre-assignment orders actionable', () => {
  const order = baseOrder({ courierId: undefined });
  assert.equal(
    assertCanMarkDelivered(order, { userId: 'u-any-courier', role: 'courier' }),
    'courier',
  );
  assert.equal(
    assertCanMarkDelivered(order, { userId: 'u-admin', role: 'admin' }),
    'admin',
  );
});

/* ------------------------------------------------------------------ */
/* state machine                                                      */
/* ------------------------------------------------------------------ */

test('the state machine no longer lets a seller reach DELIVERED', () => {
  const machine = new OrderStateMachine(ORDER_STATES.IN_TRANSIT);
  assert.throws(
    () => machine.transition(ORDER_STATES.DELIVERED, { actor: 'seller' }),
    /Actor seller cannot transition to DELIVERED/,
  );

  assert.doesNotThrow(() =>
    new OrderStateMachine(ORDER_STATES.IN_TRANSIT).transition(
      ORDER_STATES.DELIVERED,
      { actor: 'courier' },
    ),
  );
  assert.doesNotThrow(() =>
    new OrderStateMachine(ORDER_STATES.IN_TRANSIT).transition(
      ORDER_STATES.DELIVERED,
      { actor: 'admin' },
    ),
  );
  assert.doesNotThrow(() =>
    new OrderStateMachine(ORDER_STATES.IN_TRANSIT).transition(
      ORDER_STATES.DELIVERED,
      { actor: 'system' },
    ),
  );
});

/* ------------------------------------------------------------------ */
/* markDelivered                                                      */
/* ------------------------------------------------------------------ */

test('markDelivered rejects a seller actor even if it reaches the service', async () => {
  state.store = createStore(baseOrder({ status: ORDER_STATES.DISPATCHED }));
  await assert.rejects(
    markDelivered({ orderId: 'o-1', actorId: 'sp-1', actor: 'seller' }),
    { message: 'SELLER_CANNOT_MARK_DELIVERED' },
  );
  assert.equal(state.store._row.status, ORDER_STATES.DISPATCHED);
});

test('markDelivered records the courier attestation as delivery evidence', async () => {
  state.store = createStore(baseOrder({ status: ORDER_STATES.DISPATCHED }));

  const updated = await markDelivered({
    orderId: 'o-1',
    actorId: 'u-courier',
    actor: 'courier',
  });

  assert.equal(updated.status, ORDER_STATES.DELIVERED);
  assert.equal(updated.deliveredBy, 'u-courier');
  assert.equal(updated.deliveredByRole, 'courier');
  assert.ok(updated.deliveredAt instanceof Date);
});

test('markDelivered walks DISPATCHED through IN_TRANSIT to DELIVERED', async () => {
  state.store = createStore(baseOrder({ status: ORDER_STATES.DISPATCHED }));
  const updated = await markDelivered({
    orderId: 'o-1',
    actorId: 'u-admin',
    actor: 'admin',
  });
  assert.equal(updated.status, ORDER_STATES.DELIVERED);
  assert.equal(updated.deliveredByRole, 'admin');
});

test('markDelivered refuses a state that is not in transit', async () => {
  state.store = createStore(baseOrder({ status: ORDER_STATES.ESCROW_HELD }));
  await assert.rejects(
    markDelivered({ orderId: 'o-1', actorId: 'u-courier', actor: 'courier' }),
    /INVALID_DELIVERY_STATE:ESCROW_HELD/,
  );
});

test('markDelivered refuses an already delivered order', async () => {
  state.store = createStore(baseOrder({ status: ORDER_STATES.DELIVERED }));
  await assert.rejects(
    markDelivered({ orderId: 'o-1', actorId: 'u-courier', actor: 'courier' }),
    /INVALID_DELIVERY_STATE:DELIVERED/,
  );
});

/* ------------------------------------------------------------------ */
/* delivery evidence + auto-release safeguards                        */
/* ------------------------------------------------------------------ */

test('hasVerifiedDelivery trusts an independent attestor, POD or handover proof', () => {
  assert.equal(hasVerifiedDelivery(baseOrder()), true);
  assert.equal(
    hasVerifiedDelivery(baseOrder({ deliveredByRole: 'admin', deliveredBy: 'u-admin' })),
    true,
  );
  assert.equal(
    hasVerifiedDelivery(
      baseOrder({ deliveredByRole: null, otpVerifiedAt: new Date() }),
    ),
    true,
  );
  assert.equal(
    hasVerifiedDelivery(baseOrder({ deliveredByRole: null, podPhotoKey: 'r2/pod.jpg' })),
    true,
  );
  assert.equal(
    hasVerifiedDelivery(
      baseOrder({ deliveredByRole: null, deliveryProof: { note: 'left at gate' } }),
    ),
    true,
  );
});

test('hasVerifiedDelivery refuses a seller stamp and a bare deliveredAt', () => {
  assert.equal(
    hasVerifiedDelivery(baseOrder({ deliveredByRole: 'seller', deliveredBy: 'sp-1' })),
    false,
  );
  assert.equal(
    hasVerifiedDelivery(baseOrder({ deliveredByRole: undefined, deliveredBy: undefined })),
    false,
  );
  assert.equal(
    hasVerifiedDelivery(baseOrder({ deliveredAt: null, deliveredByRole: 'courier' })),
    false,
  );
});

test('evaluateAutoRelease passes a fully evidenced order', async () => {
  const { tx } = makeTx(baseOrder());
  const result = await evaluateAutoRelease(tx, 'o-1');
  assert.deepEqual(result, { canRelease: true, missingSafeguards: [], fraudSignals: [] });
});

test('evaluateAutoRelease reports a missing order', async () => {
  const tx = { order: { findUnique: async () => null } };
  const result = await evaluateAutoRelease(tx, 'missing');
  assert.equal(result.canRelease, false);
  assert.deepEqual(result.missingSafeguards, ['ORDER_NOT_FOUND']);
});

test('evaluateAutoRelease refuses a seller-attested delivery', async () => {
  const { tx } = makeTx(
    baseOrder({ deliveredByRole: 'seller', deliveredBy: 'sp-1' }),
  );
  const result = await evaluateAutoRelease(tx, 'o-1');
  assert.equal(result.canRelease, false);
  assert.ok(result.missingSafeguards.includes('VERIFIED_DELIVERY'));
});

test('evaluateAutoRelease refuses an open dispute', async () => {
  const built = makeTx(baseOrder());
  built.disputes.push({ id: 'd-1', status: 'open' });
  const result = await evaluateAutoRelease(built.tx, 'o-1');
  assert.equal(result.canRelease, false);
  assert.ok(result.missingSafeguards.includes('NO_ACTIVE_DISPUTE'));
});

test('evaluateAutoRelease requires an address snapshot and dispatch evidence', async () => {
  const { tx } = makeTx(
    baseOrder({
      shippingAddressSnapshot: null,
      trackingNumber: null,
      courierName: null,
    }),
  );
  const result = await evaluateAutoRelease(tx, 'o-1');
  assert.ok(result.missingSafeguards.includes('CORRECT_RECIPIENT_ADDRESS'));
  assert.ok(result.missingSafeguards.includes('SELLER_DISPATCH_EVIDENCE'));
});

test('evaluateAutoRelease flags self-dealing between buyer and seller', async () => {
  const { tx } = makeTx(baseOrder({ buyerId: 'u-seller' }));
  const result = await evaluateAutoRelease(tx, 'o-1');
  assert.equal(result.canRelease, false);
  assert.ok(result.missingSafeguards.includes('NO_CRITICAL_FRAUD_SIGNAL'));
  assert.deepEqual(result.fraudSignals, ['SELF_DEALING']);
});

test('evaluateAutoRelease flags a high-risk seller', async () => {
  const { tx } = makeTx(baseOrder(), {
    seller: goodSeller({ reliabilityScore: 0.1 }),
  });
  const result = await evaluateAutoRelease(tx, 'o-1');
  assert.deepEqual(result.fraudSignals, ['SELLER_HIGH_RISK']);
  assert.equal(result.canRelease, false);
});

test('evaluateAutoRelease does not treat a new seller as high risk', async () => {
  const { tx } = makeTx(baseOrder(), {
    seller: goodSeller({ reliabilityScore: 0 }),
  });
  const result = await evaluateAutoRelease(tx, 'o-1');
  assert.deepEqual(result.fraudSignals, []);
  assert.equal(result.canRelease, true);
});

test('evaluateAutoRelease flags a restricted seller account', async () => {
  const { tx } = makeTx(baseOrder(), {
    user: goodUser({ accountStatus: 'suspended' }),
  });
  const result = await evaluateAutoRelease(tx, 'o-1');
  assert.deepEqual(result.fraudSignals, ['SELLER_ACCOUNT_RESTRICTED']);
  assert.equal(result.canRelease, false);
});

test('evaluateAutoRelease flags an unresolved moderation report', async () => {
  const { tx } = makeTx(baseOrder(), {
    openReport: { id: 'report-1', status: 'reviewing' },
  });
  const result = await evaluateAutoRelease(tx, 'o-1');
  assert.deepEqual(result.fraudSignals, ['SELLER_OPEN_MODERATION_REPORT']);
  assert.equal(result.canRelease, false);
});

/* ------------------------------------------------------------------ */
/* completeOrder                                                      */
/* ------------------------------------------------------------------ */

test('completeOrder blocks an auto-release with failed safeguards', async () => {
  state.store = createStore(
    baseOrder({ deliveredByRole: 'seller', deliveredBy: 'sp-1' }),
  );
  releaseCalls.length = 0;

  const result = await completeOrder({ orderId: 'o-1', method: 'AUTO_RELEASE' });

  assert.equal(result.status, 'BLOCKED');
  assert.ok(result.missingSafeguards.includes('VERIFIED_DELIVERY'));
  assert.equal(releaseCalls.length, 0);
  assert.equal(state.store._row.status, ORDER_STATES.DELIVERED);
});

test('completeOrder blocks an auto-release with a fraud signal', async () => {
  state.store = createStore(baseOrder({ buyerId: 'u-seller' }));
  releaseCalls.length = 0;

  const result = await completeOrder({ orderId: 'o-1', method: 'AUTO_RELEASE' });

  assert.equal(result.status, 'BLOCKED');
  assert.deepEqual(result.fraudSignals, ['SELF_DEALING']);
  assert.equal(releaseCalls.length, 0);
});

test('completeOrder pays out a verified auto-release', async () => {
  state.store = createStore(baseOrder());
  releaseCalls.length = 0;

  const result = await completeOrder({ orderId: 'o-1', method: 'AUTO_RELEASE' });

  assert.equal(result.status, 'COMPLETED');
  assert.equal(result.order.status, ORDER_STATES.COMPLETED);
  assert.equal(releaseCalls.length, 1);
  assert.equal(releaseCalls[0].reason, 'auto_release');
});

test('completeOrder skips safeguards when the buyer already confirmed', async () => {
  state.store = createStore(
    baseOrder({
      status: ORDER_STATES.DELIVERY_CONFIRMED,
      deliveredAt: null,
      deliveredByRole: null,
    }),
    { seller: READ_MUST_NOT_HAPPEN, user: READ_MUST_NOT_HAPPEN },
  );
  releaseCalls.length = 0;

  const result = await completeOrder({ orderId: 'o-1', method: 'AUTO_RELEASE' });

  assert.equal(result.status, 'COMPLETED');
  assert.equal(releaseCalls.length, 1);
  assert.equal(releaseCalls[0].reason, 'auto_release');
});

test('completeOrder keeps OTP completion independent of the timer safeguards', async () => {
  state.store = createStore(
    baseOrder({ deliveredByRole: 'seller', deliveredBy: 'sp-1' }),
  );
  releaseCalls.length = 0;

  const result = await completeOrder({ orderId: 'o-1', method: 'OTP_VERIFY' });

  assert.equal(result.status, 'COMPLETED');
  assert.equal(releaseCalls[0].reason, 'buyer_confirmed');
});

test('completeOrder is idempotent once the order is completed', async () => {
  state.store = createStore(baseOrder({ status: ORDER_STATES.COMPLETED }));
  const result = await completeOrder({ orderId: 'o-1', method: 'AUTO_RELEASE' });
  assert.equal(result.status, 'ALREADY_COMPLETED');
});

test('completeOrder refuses a state that is not settlement-ready', async () => {
  state.store = createStore(baseOrder({ status: ORDER_STATES.DISPATCHED }));
  await assert.rejects(
    completeOrder({ orderId: 'o-1', method: 'AUTO_RELEASE' }),
    /INVALID_ORDER_STATE:DISPATCHED/,
  );
});

/* ------------------------------------------------------------------ */
/* legacy /orders/:id/transition                                      */
/* ------------------------------------------------------------------ */

function fakeFirestore(order) {
  const writes = [];
  const orderRef = {
    get: async () => ({ exists: true, data: () => ({ ...order }) }),
    update: async (patch) => {
      writes.push({ ...patch });
      Object.assign(order, patch);
    },
  };
  return {
    writes,
    collection(name) {
      if (name === 'orders') return { doc: () => orderRef };
      return {
        doc: () => ({
          get: async () => ({ exists: false }),
          update: async () => {},
        }),
      };
    },
  };
}

test('legacy transition refuses a seller marking delivery', async () => {
  const db = fakeFirestore({
    buyerId: 'u-buyer',
    sellerId: 'u-seller',
    status: ORDER_STATES.IN_TRANSIT,
    trackingNumber: 'TRK-1',
  });
  await assert.rejects(
    escrowService.transitionOrder({
      orderId: 'o-legacy',
      newStatus: 'DELIVERED',
      uid: 'u-seller',
      db,
    }),
    { message: 'SELLER_CANNOT_MARK_DELIVERED' },
  );
  assert.equal(db.writes.length, 0);
});

test('legacy transition requires dispatch evidence before delivery', async () => {
  const db = fakeFirestore({
    buyerId: 'u-buyer',
    sellerId: 'u-seller',
    status: ORDER_STATES.IN_TRANSIT,
  });
  await assert.rejects(
    escrowService.transitionOrder({
      orderId: 'o-legacy',
      newStatus: 'DELIVERED',
      uid: 'u-buyer',
      db,
    }),
    { message: 'DELIVERY_REQUIRES_DISPATCH' },
  );
  assert.equal(db.writes.length, 0);
});

test('legacy transition lets the buyer confirm a dispatched delivery', async () => {
  const db = fakeFirestore({
    buyerId: 'u-buyer',
    sellerId: 'u-seller',
    status: ORDER_STATES.IN_TRANSIT,
    dispatchedAt: new Date(),
  });
  const result = await escrowService.transitionOrder({
    orderId: 'o-legacy',
    newStatus: 'DELIVERED',
    uid: 'u-buyer',
    db,
  });
  assert.equal(result.status, ORDER_STATES.DELIVERED);
  assert.equal(db.writes[0].status, ORDER_STATES.DELIVERED);
});

test('legacy transition still forbids client-set financial states', async () => {
  const db = fakeFirestore({
    buyerId: 'u-buyer',
    sellerId: 'u-seller',
    status: ORDER_STATES.DELIVERED,
  });
  await assert.rejects(
    escrowService.transitionOrder({
      orderId: 'o-legacy',
      newStatus: 'COMPLETED',
      uid: 'u-seller',
      db,
    }),
    { message: 'CLIENT_CANNOT_SET_FINANCIAL_STATE' },
  );
});

/* ------------------------------------------------------------------ */
/* dispute role derivation                                            */
/* ------------------------------------------------------------------ */

test('a buyer who also sells still files as the buyer', async () => {
  const store = createStore(
    baseOrder({ status: ORDER_STATES.DISPATCHED }),
    { seller: { id: 'sp-buyer', userId: 'u-buyer' } },
  );
  state.store = store;

  const dispute = await fileDispute({
    orderId: 'o-1',
    filedBy: 'u-buyer',
    reason: 'WRONG_ITEM',
    description: 'Received the wrong item',
  });

  assert.equal(dispute.orderId, 'o-1');
  assert.equal(store._disputes.length, 1);
});

test('a buyer cannot borrow the seller-only reason BUYER_FRAUD', async () => {
  const store = createStore(
    baseOrder({ status: ORDER_STATES.DISPATCHED }),
    { seller: { id: 'sp-buyer', userId: 'u-buyer' } },
  );
  state.store = store;

  await assert.rejects(
    fileDispute({
      orderId: 'o-1',
      filedBy: 'u-buyer',
      reason: 'BUYER_FRAUD',
      description: 'claim',
    }),
    { message: 'REASON_NOT_ALLOWED_FOR_ROLE:buyer' },
  );
  assert.equal(store._disputes.length, 0);
});

test('a caller-supplied admin role cannot widen the reason list', async () => {
  const store = createStore(
    baseOrder({ status: ORDER_STATES.DISPATCHED }),
    { seller: { id: 'sp-buyer', userId: 'u-buyer' } },
  );
  state.store = store;

  await assert.rejects(
    fileDispute({
      orderId: 'o-1',
      filedBy: 'u-buyer',
      reason: 'BUYER_FRAUD',
      description: 'claim',
      role: 'admin',
    }),
    { message: 'REASON_NOT_ALLOWED_FOR_ROLE:buyer' },
  );
});

test('the seller files BUYER_FRAUD on their own order', async () => {
  const store = createStore(
    baseOrder({ status: ORDER_STATES.DISPATCHED }),
    { seller: { id: 'sp-1', userId: 'u-seller' } },
  );
  state.store = store;

  const dispute = await fileDispute({
    orderId: 'o-1',
    filedBy: 'u-seller',
    reason: 'BUYER_FRAUD',
    description: 'Buyer swapped the item',
  });

  assert.equal(dispute.reason, 'BUYER_FRAUD');
});

test('a non-participant cannot file a dispute', async () => {
  const store = createStore(
    baseOrder({ status: ORDER_STATES.DISPATCHED }),
    { seller: null },
  );
  state.store = store;

  await assert.rejects(
    fileDispute({
      orderId: 'o-1',
      filedBy: 'u-stranger',
      reason: 'WRONG_ITEM',
      description: 'not my order',
    }),
    { message: 'FORBIDDEN' },
  );
});

test('disputeOrder derives the role from ownership, not from a seller profile', async () => {
  const store = createStore(
    baseOrder({ status: ORDER_STATES.DISPATCHED }),
    { seller: { id: 'sp-buyer', userId: 'u-buyer' } },
  );
  state.store = store;

  const dispute = await disputeOrder({
    orderId: 'o-1',
    filedBy: 'u-buyer',
    reason: 'WRONG_ITEM',
    description: 'wrong item',
  });

  assert.equal(dispute.reason, 'WRONG_ITEM');

  await assert.rejects(
    disputeOrder({
      orderId: 'o-1',
      filedBy: 'u-buyer',
      reason: 'BUYER_FRAUD',
      description: 'claim',
    }),
    { message: 'REASON_NOT_ALLOWED_FOR_ROLE:buyer' },
  );
});
