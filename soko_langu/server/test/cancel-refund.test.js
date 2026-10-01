const { test } = require('node:test');
const assert = require('node:assert/strict');

// ---------------------------------------------------------------------------
// Module seams: refundOnCancel/cancelOrder call getStore(), getProvider(), the
// legacy mirror and OneSignal at runtime. Patch those dependencies BEFORE the
// service modules bind them, so the tests run hermetically with a fake Prisma
// and a fake payout provider (no network, no Postgres).
// ---------------------------------------------------------------------------
const state = {
  store: null,
  provider: null,
  payoutCalls: [],
};

const DB = require('../src/config/database');
const ProviderFactory = require('../src/modules/payments/provider-factory');
const Mirror = require('../src/modules/legacy-compat/presentation-mirror');
const Notify = require('../src/modules/legacy-compat/notify');

DB.getStore = () => state.store;
ProviderFactory.getProvider = () => state.provider;
Mirror.syncLegacyOrderStatus = async () => null;
Notify.sendOneSignalNotification = async () => null;
Notify.notifyAdmins = async () => null;

// Load the REAL refund-service (binds the patched deps), then swap
// refundOnCancel for a recording spy before loading order-service, which
// destructures it at require time.
const refundService = require('../src/modules/refunds/refund-service');
const { refundOnCancel, requestRefund, processRefund } = refundService;

const cancelCalls = [];
refundService.refundOnCancel = async (args) => {
  cancelCalls.push(args);
  return { refund: { id: 'r-spy', status: 'pending' }, order: { id: args.orderId, status: 'refund_pending' } };
};
const { cancelOrder } = require('../src/modules/orders/order-service');

function setProvider(handler) {
  state.payoutCalls = [];
  state.provider = { initiatePayout: async (payload) => handler(payload) };
}

// ---------------------------------------------------------------------------
// Fake in-memory Prisma covering the exact subset of tx.* / store.* calls the
// cancel/refund paths make. Mirrors wallet-settle.test.js: tiny on purpose.
// ---------------------------------------------------------------------------
function createFakePrisma(seed = {}) {
  const store = {
    order: (seed.order ?? []).map((r) => ({ ...r })),
    user: (seed.user ?? []).map((r) => ({ ...r })),
    sellerProfile: (seed.sellerProfile ?? []).map((r) => ({ ...r })),
    escrowHold: (seed.escrowHold ?? []).map((r) => ({ ...r })),
    refund: (seed.refund ?? []).map((r) => ({ ...r })),
    payment: (seed.payment ?? []).map((r) => ({ ...r })),
    payoutTransaction: [],
    escrowTransaction: [],
    notification: [],
  };
  let seq = 0;

  function whereMatch(row, where = {}) {
    return Object.entries(where).every(([key, expect]) => {
      if (expect && typeof expect === 'object' && !(expect instanceof Date) && 'in' in expect) {
        return expect.in.includes(row[key]);
      }
      return row[key] === expect;
    });
  }

  function applyInclude(row, include = {}) {
    const out = { ...row };
    for (const [rel, spec] of Object.entries(include)) {
      if (rel === 'seller') {
        const sp = store.sellerProfile.find((r) => r.id === row.sellerId) ?? null;
        out.seller = sp ? { ...sp } : null;
        if (sp && spec && typeof spec === 'object' && spec.include && spec.include.user) {
          const u = store.user.find((r) => r.id === sp.userId) ?? null;
          out.seller.user = u ? { ...u } : null;
        }
      }
    }
    return out;
  }

  function pick(row, select) {
    if (!row || !select) return row;
    const out = {};
    for (const key of Object.keys(select)) out[key] = row[key];
    return out;
  }

  // Prisma's atomic update operators. A plain Object.assign would store the
  // literal { increment: 500 } object in the field instead of adding to it,
  // which would make escrow arithmetic assertions silently meaningless.
  function applyData(row, data) {
    for (const [key, value] of Object.entries(data)) {
      if (value && typeof value === 'object' && !(value instanceof Date)) {
        if ('increment' in value) row[key] = (Number(row[key]) || 0) + value.increment;
        else if ('decrement' in value) row[key] = (Number(row[key]) || 0) - value.decrement;
        else if ('set' in value) row[key] = value.set;
        else row[key] = value;
      } else {
        row[key] = value;
      }
    }
    return row;
  }

  const api = {
    $transaction: async (fn) => fn(api),

    order: {
      findUnique: async ({ where, select, include } = {}) => {
        const row = store.order.find((r) => whereMatch(r, where)) ?? null;
        return select ? pick(applyInclude(row, include), select) : applyInclude(row, include);
      },
      findMany: async ({ where = {}, orderBy } = {}) => {
        const rows = store.order.filter((r) => whereMatch(r, where));
        if (orderBy) {
          const [key, dir] = Object.entries(orderBy)[0];
          rows.sort((a, b) => (dir === 'desc' ? String(b[key]).localeCompare(String(a[key])) : String(a[key]).localeCompare(String(b[key]))));
        }
        return rows;
      },
      update: async ({ where, data }) => {
        const row = store.order.find((r) => whereMatch(r, where));
        applyData(row, data);
        return row;
      },
      count: async () => store.order.length,
    },

    user: {
      findUnique: async ({ where, select } = {}) => {
        const row = store.user.find((r) => whereMatch(r, where)) ?? null;
        return pick(row, select);
      },
      findMany: async ({ where = {} } = {}) => store.user.filter((r) => whereMatch(r, where)),
    },

    sellerProfile: {
      findUnique: async ({ where, select } = {}) => {
        const row = store.sellerProfile.find((r) => whereMatch(r, where)) ?? null;
        return pick(row, select);
      },
    },

    escrowHold: {
      findFirst: async ({ where = {} } = {}) => store.escrowHold.find((r) => whereMatch(r, where)) ?? null,
      findUnique: async ({ where } = {}) => store.escrowHold.find((r) => whereMatch(r, where)) ?? null,
      update: async ({ where, data }) => {
        const row = store.escrowHold.find((r) => whereMatch(r, where));
        applyData(row, data);
        return row;
      },
    },

    refund: {
      findUnique: async ({ where } = {}) => store.refund.find((r) => whereMatch(r, where)) ?? null,
      findFirst: async ({ where = {} } = {}) => store.refund.find((r) => whereMatch(r, where)) ?? null,
      findMany: async ({ where = {}, orderBy } = {}) => {
        const rows = store.refund.filter((r) => whereMatch(r, where));
        if (orderBy) {
          const [key, dir] = Object.entries(orderBy)[0];
          rows.sort((a, b) => (dir === 'desc' ? String(b[key]).localeCompare(String(a[key])) : String(a[key]).localeCompare(String(b[key]))));
        }
        return rows;
      },
      create: async ({ data }) => {
        const row = { id: `r-${++seq}`, ...data };
        store.refund.push(row);
        return { ...row };
      },
      update: async ({ where, data }) => {
        const row = store.refund.find((r) => whereMatch(r, where));
        applyData(row, data);
        return { ...row };
      },
    },

    payment: {
      findUnique: async ({ where } = {}) => store.payment.find((r) => whereMatch(r, where)) ?? null,
      findFirst: async ({ where = {}, orderBy } = {}) => {
        const rows = store.payment.filter((r) => whereMatch(r, where));
        if (orderBy) {
          const [key, dir] = Object.entries(orderBy)[0];
          rows.sort((a, b) => (dir === 'desc' ? String(b[key]).localeCompare(String(a[key])) : String(a[key]).localeCompare(String(b[key]))));
        }
        return rows[0] ?? null;
      },
    },

    payoutTransaction: {
      findUnique: async ({ where } = {}) => store.payoutTransaction.find((r) => whereMatch(r, where)) ?? null,
      create: async ({ data }) => {
        const row = { id: `pt-${++seq}`, ...data };
        store.payoutTransaction.push(row);
        return { ...row };
      },
    },

    escrowTransaction: {
      findFirst: async ({ where = {} } = {}) => store.escrowTransaction.find((r) => whereMatch(r, where)) ?? null,
      findMany: async ({ where = {} } = {}) => store.escrowTransaction.filter((r) => whereMatch(r, where)),
      create: async ({ data }) => {
        const row = { id: `et-${++seq}`, ...data };
        store.escrowTransaction.push(row);
        return { ...row };
      },
    },

    notification: {
      create: async ({ data }) => {
        const row = { id: `n-${++seq}`, ...data };
        store.notification.push(row);
        return { ...row };
      },
    },
  };

  Object.defineProperty(api, '_store', { value: store });
  return api;
}

// ---------------------------------------------------------------------------
// Shared fixture: one escrow-held order with a paying buyer and its seller.
// ---------------------------------------------------------------------------
function seedEscrowOrder(status = 'ready_to_dispatch') {
  return {
    order: [{
      id: 'o1',
      orderNumber: 'SV202609170001',
      buyerId: 'u-buyer',
      sellerId: 'sp-1',
      status,
      totalAmount: 50000n,
      platformCommission: 10000n,
      createdAt: new Date('2026-09-17T09:00:00Z'),
      updatedAt: new Date('2026-09-17T09:00:00Z'),
    }],
    user: [
      { id: 'u-buyer', firebaseUid: 'fire-buyer', phone: '255712000001', role: 'buyer' },
      { id: 'u-seller', firebaseUid: 'fire-seller', phone: '255713000002', role: 'seller' },
    ],
    sellerProfile: [{ id: 'sp-1', userId: 'u-seller', shopName: 'Duka Moja' }],
    escrowHold: [{ id: 'eh-1', orderId: 'o1', status: 'holding', amount: 50000n, releasedToBuyer: 0n, releasedAt: null }],
    payment: [{ id: 'pay-1', orderId: 'o1', provider: 'clickpesa', status: 'completed', createdAt: '2026-09-17T10:00:00Z' }],
  };
}

function providerPayout(seed) {
  setProvider(async (payload) => {
    state.payoutCalls.push(payload);
    return { id: 'px-1', status: 'processing', received: payload };
  });
  state.store = createFakePrisma(seed);
}

// ---------------------------------------------------------------------------
// refundOnCancel: happy path
// ---------------------------------------------------------------------------
test('buyer cancel refunds full totalAmount and ends the order REFUNDED', async () => {
  providerPayout(seedEscrowOrder());
  const result = await refundOnCancel({
    orderId: 'o1',
    actorId: 'u-buyer',
    role: 'buyer',
    reason: 'Changed my mind',
  });

  assert.equal(result.refund.status, 'completed');
  assert.equal(result.refund.mode, 'full');
  assert.equal(result.refund.amount, 50000n);
  assert.equal(result.order.status, 'REFUNDED');

  const store = state.store._store;
  assert.equal(store.order[0].status, 'REFUNDED');
  assert.equal(store.escrowHold[0].status, 'released_to_buyer');
  assert.equal(store.escrowHold[0].releasedToBuyer, 50000n);
  assert.ok(store.escrowHold[0].releasedAt instanceof Date);

  assert.equal(store.escrowTransaction.length, 1);
  assert.equal(store.escrowTransaction[0].type, 'REFUND_TO_BUYER');
  assert.equal(store.escrowTransaction[0].amount, 50000n);
  assert.equal(store.escrowTransaction[0].escrowHoldId, 'eh-1');

  assert.equal(store.payoutTransaction.length, 1);
  assert.equal(store.payoutTransaction[0].refundId, result.refund.id);
  assert.equal(store.payoutTransaction[0].amount, 50000n);

  // Seller 'cancelled' row + buyer 'refund' row; no push (OneSignal patched).
  const types = store.notification.map((n) => n.type).sort();
  assert.deepEqual(types, ['cancelled', 'refund']);

  assert.equal(state.payoutCalls.length, 1);
  const p = state.payoutCalls[0];
  assert.equal(p.amount, 50000);
  assert.equal(p.phoneNumber, '255712000001');
  assert.ok(p.orderReference.startsWith('refund_SV202609170001_'));
});

test('escrow stays holding when the payout fails; order parks in REFUND_PENDING', async () => {
  setProvider(async () => {
    throw new Error('PAYOUT_DOWN');
  });
  state.store = createFakePrisma(seedEscrowOrder());

  const result = await refundOnCancel({ orderId: 'o1', actorId: 'u-buyer', role: 'buyer' });

  assert.equal(result.refund.status, 'failed');
  assert.match(result.refund.lastError, /PAYOUT_DOWN/);
  assert.equal(result.order.status, 'REFUND_PENDING');

  const store = state.store._store;
  assert.equal(store.order[0].status, 'REFUND_PENDING');
  assert.equal(store.escrowHold[0].status, 'holding');
  assert.equal(store.escrowHold[0].releasedToBuyer, 0n);
  assert.equal(store.payoutTransaction.length, 0);
  assert.equal(store.escrowTransaction.length, 0);
});

test('re-running a completed cancel does not double-payout', async () => {
  const seed = seedEscrowOrder();
  seed.order[0].status = 'refunded';
  seed.escrowHold[0] = { ...seed.escrowHold[0], status: 'released_to_buyer', releasedToBuyer: 50000n, releasedAt: new Date() };
  seed.refund = [{
    id: 'r1',
    orderId: 'o1',
    paymentId: 'pay-1',
    amount: 50000n,
    mode: 'full',
    reason: 'Changed my mind',
    correlationId: 'refund_SV202609170001_x1_0',
    requestedBy: 'u-buyer',
    status: 'completed',
  }];
  providerPayout(seed);

  const result = await refundOnCancel({ orderId: 'o1', actorId: 'u-buyer', role: 'buyer' });

  assert.equal(result.refund.status, 'completed');
  assert.equal(result.order.status, 'refunded');
  assert.equal(state.payoutCalls.length, 0, 'existing payoutTransaction short-circuits the payout');
  assert.equal(state.store._store.payoutTransaction.length, 0);
});

test('non-owner cannot trigger a refund', async () => {
  providerPayout(seedEscrowOrder());
  await assert.rejects(
    refundOnCancel({ orderId: 'o1', actorId: 'u-stranger', role: 'buyer' }),
    (err) => err.message === 'FORBIDDEN' && err.status === 403,
  );
});

// ---------------------------------------------------------------------------
// cancelOrder routing: escrow-held -> refundOnCancel, pre-escrow -> CANCELLED
// ---------------------------------------------------------------------------
test('escrow-held buyer cancel routes to refundOnCancel with role buyer', async () => {
  providerPayout(seedEscrowOrder('in_escrow'));
  await cancelOrder({ orderId: 'o1', actorId: 'u-buyer', reason: 'Buyer cancelled order' });

  assert.equal(cancelCalls.length, 1);
  assert.deepEqual(cancelCalls[0], { orderId: 'o1', actorId: 'u-buyer', role: 'buyer', reason: 'Buyer cancelled order' });
});

test('seller cannot cancel an escrow-held order', async () => {
  providerPayout(seedEscrowOrder());
  const before = cancelCalls.length;
  await assert.rejects(
    cancelOrder({ orderId: 'o1', actorId: 'u-seller' }),
    (err) => err.message === 'FORBIDDEN' && err.status === 403,
  );
  assert.equal(cancelCalls.length, before, 'refund path must not be reached');
});

test('pre-escrow cancel goes through the state machine, no refund', async () => {
  const seed = seedEscrowOrder('payment_pending');
  seed.escrowHold = [];
  providerPayout(seed);

  const before = cancelCalls.length;
  const updated = await cancelOrder({ orderId: 'o1', actorId: 'u-buyer', reason: 'Changed mind' });

  assert.equal(updated.status, 'CANCELLED');
  assert.equal(state.store._store.order[0].status, 'CANCELLED');
  assert.equal(cancelCalls.length, before, 'no refund for pre-escrow cancel');
});

// ---------------------------------------------------------------------------
// processRefund (admin path): money-safety ordering.
//
// This path had no coverage, which is how it got away with marking a full
// refund REFUNDED and the escrow hold released_to_buyer inside the transaction
// that commits BEFORE the provider payout. A failed payout therefore left the
// books claiming the buyer had been paid while the money never left ClickPesa,
// on an order that could no longer be retried.
// ---------------------------------------------------------------------------
function seedRefundRequest(amount = null) {
  const seed = seedEscrowOrder();
  seed.refund = [{
    id: 'r-1',
    orderId: 'o1',
    paymentId: 'pay-1',
    amount: 50000n,
    mode: 'full',
    status: 'pending',
    reason: 'Buyer asked for money back',
    correlationId: 'refund_SV202609170001',
    createdAt: new Date('2026-09-17T11:00:00Z'),
  }];
  return seed;
}

test('processRefund reaches REFUNDED only after the payout succeeds', async () => {
  providerPayout(seedRefundRequest());
  const result = await processRefund({ refundId: 'r-1', processedBy: 'admin-1' });

  assert.equal(result.refund.status, 'completed');
  assert.equal(result.order.status, 'REFUNDED');

  const store = state.store._store;
  assert.equal(store.order[0].status, 'REFUNDED');
  assert.equal(store.escrowHold[0].status, 'released_to_buyer');
  assert.equal(store.escrowHold[0].releasedToBuyer, 50000n);
  assert.equal(state.payoutCalls.length, 1, 'the payout must be attempted');
});

test('a failed payout leaves the order REFUND_PENDING and the escrow unreleased', async () => {
  setProvider(async () => { throw new Error('PAYOUT_DOWN'); });
  state.store = createFakePrisma(seedRefundRequest());

  const result = await processRefund({ refundId: 'r-1', processedBy: 'admin-1' });

  // Assert the STORED rows, not the snapshot processRefund returns: it returns
  // the record as it stood when the transaction set it to PROCESSING, while
  // markRefundFailed updates the row afterwards. What matters is that the
  // persisted state is retryable, and that nothing claims the money moved.
  const store = state.store._store;
  assert.equal(store.refund[0].status, 'failed');
  assert.match(store.refund[0].lastError, /PAYOUT_DOWN/);

  // The order must NOT be REFUNDED: that state means the buyer has the money.
  assert.notEqual(store.order[0].status, 'REFUNDED');
  assert.equal(store.order[0].status, 'REFUND_PENDING');
  // And the escrow must not claim the money was released to the buyer.
  assert.notEqual(store.escrowHold[0].status, 'released_to_buyer');
  assert.equal(store.escrowHold[0].releasedToBuyer, 0n);
  assert.equal(store.escrowHold[0].releasedAt, null);
  assert.equal(store.payoutTransaction.length, 0, 'no payout was recorded');
  assert.equal(result.finalState, 'REFUND_PENDING');
});

test('REFUND_PENDING stays refundable so a failed payout can be retried', () => {
  // The retry depends on this: if the failure parked the order somewhere
  // ineligible, an admin could not retry and the buyer would be owed money with
  // no way to release it.
  assert.ok(refundService.isRefundableEscrowState('REFUND_PENDING'));
});

test('a failed payout can be retried through processRefund', async () => {
  setProvider(async () => { throw new Error('PAYOUT_DOWN'); });
  state.store = createFakePrisma(seedRefundRequest());
  await processRefund({ refundId: 'r-1', processedBy: 'admin-1' });
  assert.equal(state.store._store.order[0].status, 'REFUND_PENDING');

  // Provider recovers; the second attempt must complete the refund.
  providerPayout(state.store._store ? seedFromStore(state.store._store) : null);
  const retry = await processRefund({ refundId: 'r-1', processedBy: 'admin-1' });
  assert.equal(retry.refund.status, 'completed');
  assert.equal(state.store._store.order[0].status, 'REFUNDED');
});

// Rebuilds a seed from the live fake store so the retry runs against the state
// the failed attempt actually left behind, not a fresh fixture.
function seedFromStore(store) {
  return {
    order: store.order,
    user: store.user,
    sellerProfile: store.sellerProfile,
    escrowHold: store.escrowHold,
    refund: store.refund,
    payment: store.payment,
  };
}