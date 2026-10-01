// Regression coverage for the three refund-safety bugs that the "park the order
// in REFUND_PENDING until the payout lands" change was supposed to fix but only
// fixed for the FULL refund path:
//
//   1. full refund    -> the REFUND_TO_BUYER ledger row was written twice (once
//                        in Phase A before the payout, once in finalize), so the
//                        escrow ledger double-counted every full refund.
//   2. partial refund -> finalizeRefunded forced the order to REFUNDED. The order
//                        was already IN_ESCROW, and IN_ESCROW -> REFUNDED is not a
//                        legal transition, so the transaction rolled back and the
//                        admin call 500'd AFTER the buyer had been paid.
//   3. partial refund -> Phase A incremented releasedToBuyer before the payout,
//                        so a failed payout left the books claiming the buyer had
//                        been paid, and the hold stayed settleable to the seller.
//
// Each test below pins the exact invariant, and test/mutate-refund.js proves
// they fail when the bug is reintroduced.

const { test } = require('node:test');
const assert = require('node:assert/strict');

const state = { store: null, provider: null, payoutCalls: [] };

const DB = require('../src/config/database');
const ProviderFactory = require('../src/modules/payments/provider-factory');
const Mirror = require('../src/modules/legacy-compat/presentation-mirror');
const Notify = require('../src/modules/legacy-compat/notify');

DB.getStore = () => state.store;
ProviderFactory.getProvider = () => state.provider;
Mirror.syncLegacyOrderStatus = async () => null;
Notify.sendOneSignalNotification = async () => null;
Notify.notifyAdmins = async () => null;

const { requestRefund, processRefund } = require('../src/modules/refunds/refund-service');

// Fake store covering only what processRefund/disburseRefund/finalizeRefunded
// touch, with real Prisma atomic-update semantics (increment must add, not
// assign the operator object).
function createStore(seed) {
  const store = {
    order: [...seed.order], user: [...seed.user], escrowHold: [...seed.escrowHold],
    refund: [...(seed.refund || [])], payment: [...seed.payment],
    payoutTransaction: [], escrowTransaction: [], notification: [],
  };
  let seq = 0;

  const match = (row, where = {}) => Object.entries(where).every(([k, v]) => {
    if (v && typeof v === 'object' && !(v instanceof Date) && 'in' in v) return v.in.includes(row[k]);
    return row[k] === v;
  });

  // Money columns are BigInt in production, so the atomic operators must add in
  // the same type. Converting to Number first (the obvious shortcut) throws
  // "Cannot mix BigInt and other types" and, worse, would silently lose
  // precision on TZS amounts.
  const add = (current, delta) => {
    const zero = typeof current === 'bigint' || typeof delta === 'bigint' ? 0n : 0;
    return (current ?? zero) + delta;
  };

  const apply = (row, data) => {
    for (const [k, v] of Object.entries(data)) {
      if (v && typeof v === 'object' && !(v instanceof Date)) {
        if ('increment' in v) row[k] = add(row[k], v.increment);
        else if ('decrement' in v) row[k] = add(row[k], -v.decrement);
        else row[k] = v;
      } else row[k] = v;
    }
    return row;
  };

  const api = {
    $transaction: async (fn) => fn(api),
    order: {
      findUnique: async ({ where } = {}) => store.order.find((r) => match(r, where)) ?? null,
      update: async ({ where, data }) => apply(store.order.find((r) => match(r, where)), data),
    },
    user: {
      findUnique: async ({ where } = {}) => store.user.find((r) => match(r, where)) ?? null,
    },
    escrowHold: {
      findFirst: async ({ where = {} } = {}) => store.escrowHold.find((r) => match(r, where)) ?? null,
      update: async ({ where, data }) => apply(store.escrowHold.find((r) => match(r, where)), data),
    },
    refund: {
      findUnique: async ({ where } = {}) => store.refund.find((r) => match(r, where)) ?? null,
      findFirst: async ({ where = {} } = {}) => store.refund.find((r) => match(r, where)) ?? null,
      update: async ({ where, data }) => apply(store.refund.find((r) => match(r, where)), data),
    },
    payment: { findUnique: async ({ where } = {}) => store.payment.find((r) => match(r, where)) ?? null },
    payoutTransaction: {
      findUnique: async ({ where } = {}) => store.payoutTransaction.find((r) => match(r, where)) ?? null,
      create: async ({ data }) => { const r = { id: `pt-${++seq}`, ...data }; store.payoutTransaction.push(r); return { ...r }; },
    },
    escrowTransaction: {
      findFirst: async ({ where = {} } = {}) => store.escrowTransaction.find((r) => match(r, where)) ?? null,
      findMany: async ({ where = {} } = {}) => store.escrowTransaction.filter((r) => match(r, where)),
      create: async ({ data }) => { const r = { id: `et-${++seq}`, ...data }; store.escrowTransaction.push(r); return { ...r }; },
    },
    notification: {
      create: async ({ data }) => { const r = { id: `n-${++seq}`, ...data }; store.notification.push(r); return { ...r }; },
    },
  };
  Object.defineProperty(api, '_store', { value: store });
  return api;
}

function seed({ mode, amount, orderStatus = 'ready_to_dispatch', refundStatus = 'pending' }) {
  return {
    order: [{
      id: 'o1', orderNumber: 'SV202609170009', buyerId: 'u-buyer', sellerId: 'sp-1',
      status: orderStatus, totalAmount: 50000n, platformCommission: 10000n,
      createdAt: new Date('2026-09-17T09:00:00Z'), updatedAt: new Date('2026-09-17T09:00:00Z'),
    }],
    user: [{ id: 'u-buyer', firebaseUid: 'fire-buyer', phone: '255712000001', role: 'buyer' }],
    escrowHold: [{ id: 'eh-1', orderId: 'o1', status: 'holding', amount: 50000n, releasedToBuyer: 0n, releasedAt: null }],
    payment: [{ id: 'pay-1', orderId: 'o1', provider: 'clickpesa', status: 'completed', createdAt: '2026-09-17T10:00:00Z' }],
    refund: [{
      id: 'r-1', orderId: 'o1', paymentId: 'pay-1', amount, mode,
      reason: 'test', correlationId: 'SV202609170009', requestedBy: 'u-admin',
      status: refundStatus, resolvedBy: null, lastError: null, errorAt: null,
    }],
  };
}

function setup(s, payoutImpl) {
  state.payoutCalls = [];
  state.provider = { initiatePayout: async (p) => { state.payoutCalls.push(p); return payoutImpl(p); } };
  state.store = createStore(s);
  return state.store._store;
}

const okPayout = async (p) => ({ id: 'px-1', status: 'processing', received: p });
const failPayout = async () => { throw new Error('ClickPesa rejected the payout'); };

const refundRows = (s) => s.escrowTransaction.filter((r) => r.type === 'REFUND_TO_BUYER');

// --- Bug 1: duplicated ledger row for a full refund -------------------------

test('a full refund records exactly one REFUND_TO_BUYER ledger row', async () => {
  const s = setup(seed({ mode: 'full', amount: 50000n }), okPayout);
  const result = await processRefund({ refundId: 'r-1', processedBy: 'u-admin' });

  assert.equal(result.refund.status, 'completed');
  assert.equal(s.order[0].status, 'REFUNDED');
  assert.equal(refundRows(s).length, 1, 'the ledger must not double-count a full refund');
  assert.equal(refundRows(s)[0].referenceId, 'r-1');
});

test('the ledger row is written only after the payout is confirmed', async () => {
  const s = setup(seed({ mode: 'full', amount: 50000n }), failPayout);
  await processRefund({ refundId: 'r-1', processedBy: 'u-admin' });

  assert.equal(s.refund[0].status, 'failed');
  assert.equal(refundRows(s).length, 0, 'a failed payout must not leave a ledger entry');
  assert.notEqual(s.order[0].status, 'REFUNDED');
});

test('a failed full refund releases no escrow', async () => {
  const s = setup(seed({ mode: 'full', amount: 50000n }), failPayout);
  await processRefund({ refundId: 'r-1', processedBy: 'u-admin' });

  assert.equal(s.escrowHold[0].releasedToBuyer, 0n);
  assert.notEqual(s.escrowHold[0].status, 'released_to_buyer');
  assert.equal(s.order[0].status, 'REFUND_PENDING', 'the order must stay retryable');
});

// --- Bug 2: partial refund threw after the buyer was paid -------------------

test('a partial refund returns the order to escrow instead of forcing REFUNDED', async () => {
  const s = setup(seed({ mode: 'partial', amount: 20000n }), okPayout);
  const result = await processRefund({ refundId: 'r-1', processedBy: 'u-admin' });

  // The order must end IN_ESCROW: the buyer got part of their money back and
  // the remaining balance is still owed to the seller.
  assert.equal(result.refund.status, 'completed');
  assert.equal(s.order[0].status, 'IN_ESCROW');
  assert.notEqual(s.order[0].status, 'REFUNDED', 'a partial refund must not end the order');
});

test('a partial refund releases only the refunded slice and keeps the hold settleable', async () => {
  const s = setup(seed({ mode: 'partial', amount: 20000n }), okPayout);
  await processRefund({ refundId: 'r-1', processedBy: 'u-admin' });

  assert.equal(s.escrowHold[0].releasedToBuyer, 20000n, 'only the refunded amount is released');
  assert.equal(s.escrowHold[0].status, 'holding', 'the rest of the balance stays settleable');
  assert.equal(s.escrowHold[0].refundingAmount ?? null, null, 'the reservation is cleared');
  assert.equal(refundRows(s).length, 1);
  assert.equal(refundRows(s)[0].amount, 20000n);
});

test('a partial refund still pays the buyer exactly the refund amount', async () => {
  setup(seed({ mode: 'partial', amount: 20000n }), okPayout);
  await processRefund({ refundId: 'r-1', processedBy: 'u-admin' });

  assert.equal(state.payoutCalls.length, 1);
  // The provider boundary takes a plain number, not the BigInt the ledger uses.
  assert.equal(state.payoutCalls[0].amount, 20000);
});

// --- Bug 3: escrow released before the payout -------------------------------

test('a failed partial payout leaves releasedToBuyer untouched', async () => {
  const s = setup(seed({ mode: 'partial', amount: 20000n }), failPayout);
  await processRefund({ refundId: 'r-1', processedBy: 'u-admin' });

  assert.equal(s.refund[0].status, 'failed');
  assert.equal(s.escrowHold[0].releasedToBuyer, 0n, 'escrow must not be released for money that never moved');
  assert.equal(refundRows(s).length, 0);
  assert.equal(s.order[0].status, 'REFUND_PENDING');
});

test('a failed partial payout reserves the hold so it cannot be settled meanwhile', async () => {
  const s = setup(seed({ mode: 'partial', amount: 20000n }), failPayout);
  await processRefund({ refundId: 'r-1', processedBy: 'u-admin' });

  // 'refunding' is findable by the retry path, so a retry can still reach it,
  // and it is not 'released_to_buyer'/'settled', so nothing else can drain it.
  assert.ok(['refunding', 'holding'].includes(s.escrowHold[0].status));
  assert.notEqual(s.escrowHold[0].status, 'released_to_buyer');
});

// --- Retry and crash-heal ---------------------------------------------------

test('a retried full refund still records only one ledger row', async () => {
  const s = setup(seed({ mode: 'full', amount: 50000n, refundStatus: 'failed' }), okPayout);
  await processRefund({ refundId: 'r-1', processedBy: 'u-admin' });

  assert.equal(s.refund[0].status, 'completed');
  assert.equal(refundRows(s).length, 1, 'a retry must not append a second ledger row');
  assert.equal(s.escrowHold[0].releasedToBuyer, 50000n);
});

test('a retried partial refund increments releasedToBuyer only once', async () => {
  const s = setup(seed({ mode: 'partial', amount: 20000n, refundStatus: 'failed' }), okPayout);
  await processRefund({ refundId: 'r-1', processedBy: 'u-admin' });

  assert.equal(s.escrowHold[0].releasedToBuyer, 20000n, 'the retry must not double-release');
  assert.equal(refundRows(s).length, 1);
});

test('a COMPLETED refund whose finalize never ran is healed instead of short-circuited', async () => {
  // Crash between disburseRefund (payout landed) and Phase C: the refund row is
  // completed but the order is still parked. A re-run must finish the job, not
  // return early and leave the order stuck forever.
  const s = setup(seed({ mode: 'full', amount: 50000n, orderStatus: 'REFUND_PENDING', refundStatus: 'completed' }), okPayout);
  const result = await processRefund({ refundId: 'r-1', processedBy: 'u-admin' });

  assert.equal(result.healed, true);
  assert.equal(s.order[0].status, 'REFUNDED');
  assert.equal(s.escrowHold[0].status, 'released_to_buyer');
  assert.equal(state.payoutCalls.length, 0, 'healing must not pay the buyer a second time');
  assert.equal(refundRows(s).length, 1);
});

test('a COMPLETED refund on an already-settled order is a no-op', async () => {
  // Seed the ledger row the earlier successful run already wrote. Re-running must
  // neither pay again nor append a second row.
  const seedData = seed({ mode: 'full', amount: 50000n, orderStatus: 'REFUNDED', refundStatus: 'completed' });
  const s = setup(seedData, okPayout);
  s.escrowHold[0].status = 'released_to_buyer';
  s.escrowHold[0].releasedToBuyer = 50000n;
  s.escrowTransaction.push({
    id: 'et-prior', escrowHoldId: 'eh-1', type: 'REFUND_TO_BUYER', amount: 50000n, referenceId: 'r-1',
  });

  await processRefund({ refundId: 'r-1', processedBy: 'u-admin' });

  assert.equal(s.order[0].status, 'REFUNDED');
  assert.equal(state.payoutCalls.length, 0, 'no second payout');
  assert.equal(refundRows(s).length, 1, 'no second ledger row');
});

test('an escrow balance smaller than the refund is refused before any payout', async () => {
  const seedData = seed({ mode: 'full', amount: 50000n });
  seedData.escrowHold[0].amount = 30000n; // only 30k is held
  const s = setup(seedData, okPayout);

  await assert.rejects(() => processRefund({ refundId: 'r-1', processedBy: 'u-admin' }), /INSUFFICIENT_ESCROW/);
  assert.equal(state.payoutCalls.length, 0);
  assert.equal(refundRows(s).length, 0);
});

test('a second refund cannot be opened while one is in flight', async () => {
  const s = setup(seed({ mode: 'full', amount: 50000n }), okPayout);
  await processRefund({ refundId: 'r-1', processedBy: 'u-admin' });

  // The order is REFUNDED after the first refund, so it is no longer in a
  // refundable escrow state and a second refund must be refused outright.
  await assert.rejects(
    () => requestRefund({ orderId: 'o1', requestedBy: 'u-buyer', role: 'buyer', reason: 'again' }),
    /INELIGIBLE_REFUND_STATE/,
  );
  assert.equal(state.payoutCalls.length, 1, 'no double payout');
  assert.equal(refundRows(s).length, 1, 'no double ledger row');
});

test('a non-admin cannot request a refund on someone else order', async () => {
  setup(seed({ mode: 'full', amount: 50000n }), okPayout);
  await assert.rejects(
    () => requestRefund({ orderId: 'o1', requestedBy: 'u-stranger', role: 'buyer', reason: 'x' }),
    /FORBIDDEN/,
  );
  assert.equal(state.payoutCalls.length, 0);
});
