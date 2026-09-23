const { test } = require('node:test');
const assert = require('node:assert/strict');

const { OrderStateMachine, ORDER_STATES } = require('../src/modules/orders/order-state-machine');
const { completeAfterCredentialVerified } = require('../src/modules/handover/handover-service');

// Fake Prisma client covering the tx calls the completion chain makes:
// order.update, escrowHold, escrowTransaction, receipt, auditLog. Money moves
// through the injected Firestore `settle` spy, so no live Firebase is needed.
function createFlowTx(seed = {}) {
  const orders = seed.orders ?? [];
  const store = {
    orders,
    escrowHold: seed.escrowHold ?? [],
    escrowTransaction: [],
    receipts: [],
    auditLogs: [],
  };

  function whereMatch(row, where) {
    if (!where) return true;
    return Object.entries(where).every(([key, expect]) => {
      if (expect && typeof expect === 'object' && 'in' in expect) {
        return expect.in.includes(row[key]);
      }
      return row[key] === expect;
    });
  }

  const api = {
    order: {
      update: async ({ where, data }) => {
        const row = store.orders.find((r) => r.id === where.id);
        if (!row) throw new Error('order not found');
        Object.assign(row, data);
        return row;
      },
    },
    escrowHold: {
      findFirst: async ({ where = {} }) => store.escrowHold.find((r) => whereMatch(r, where)) ?? null,
      update: async ({ where, data }) => {
        const row = store.escrowHold.find((r) => r.id === where.id);
        if (!row) throw new Error('escrowHold not found');
        Object.assign(row, data);
        return row;
      },
    },
    escrowTransaction: {
      findFirst: async ({ where = {} }) => store.escrowTransaction.find((r) => whereMatch(r, where)) ?? null,
      create: async ({ data }) => {
        const row = { ...data };
        store.escrowTransaction.push(row);
        return row;
      },
    },
    receipt: {
      create: async ({ data }) => {
        const row = { ...data };
        store.receipts.push(row);
        return row;
      },
    },
    auditLog: {
      create: async ({ data }) => {
        const row = { ...data };
        store.auditLogs.push(row);
        return row;
      },
    },
  };

  Object.defineProperty(api, '_store', { value: store });
  return api;
}

function seededOrder(overrides = {}) {
  return {
    id: 'or-flow-1',
    orderNumber: 'SV202501010001',
    buyerId: 'buyer-1',
    sellerId: 'seller-1',
    status: ORDER_STATES.OTP_PENDING,
    totalAmount: 150000n,
    platformCommission: 0n,
    currency: 'TZS',
    ...overrides,
  };
}

test('state machine: deliver states arm the OTP handover', () => {
  for (const from of [
    ORDER_STATES.DISPATCHED,
    ORDER_STATES.IN_TRANSIT,
    ORDER_STATES.OUT_FOR_DELIVERY,
    ORDER_STATES.DELIVERY_ATTEMPTED,
    ORDER_STATES.ARRIVED,
    ORDER_STATES.DELIVERED,
    ORDER_STATES.INSPECTION_PERIOD,
  ]) {
    const machine = new OrderStateMachine(from);
    assert.ok(machine.canTransition(ORDER_STATES.OTP_PENDING), `${from} -> OTP_PENDING`);
  }
});

test('state machine: OTP completion path is DELIVERY_CONFIRMED -> COMPLETED only', () => {
  const machine = new OrderStateMachine(ORDER_STATES.OTP_PENDING);
  assert.ok(machine.canTransition(ORDER_STATES.DELIVERY_CONFIRMED));
  assert.ok(!machine.canTransition(ORDER_STATES.COMPLETED), 'COMPLETED is not reachable straight from OTP_PENDING');

  machine.transition(ORDER_STATES.DELIVERY_CONFIRMED, { actor: 'buyer' });
  assert.equal(machine.getFinancialRule(), 'SETTLEMENT_AUTHORIZED');
  machine.transition(ORDER_STATES.COMPLETED, { actor: 'system' });
  assert.equal(machine.state, ORDER_STATES.COMPLETED);
});

test('state machine: only the buyer (or system) confirms delivery from OTP_PENDING', () => {
  for (const actor of ['buyer', 'system']) {
    assert.doesNotThrow(() =>
      new OrderStateMachine(ORDER_STATES.OTP_PENDING).transition(ORDER_STATES.DELIVERY_CONFIRMED, { actor }),
      `actor ${actor} may complete an OTP-pending order`,
    );
  }
  for (const actor of ['seller', 'admin', 'courier']) {
    assert.throws(
      () => new OrderStateMachine(ORDER_STATES.OTP_PENDING).transition(ORDER_STATES.DELIVERY_CONFIRMED, { actor }),
      `actor ${actor} must not release settlement`,
    );
  }
});

test('completion chain releases escrow, credits the seller and writes a receipt', async () => {
  const order = seededOrder();
  const tx = createFlowTx({ orders: [order] });
  tx._store.escrowHold.push({ id: 'eh-flow', orderId: order.id, status: 'holding' });
  const settleCalls = [];
  const settle = async (args) => {
    settleCalls.push(args);
    return { alreadySettled: false };
  };

  const result = await completeAfterCredentialVerified(tx, order, 'buyer-1', 'OTP', { settle });

  assert.equal(result.status, 'COMPLETED');
  assert.equal(tx._store.orders[0].status, ORDER_STATES.COMPLETED);
  assert.ok(tx._store.orders[0].completedAt, 'completedAt must be stamped');

  // Money: the full escrow total moves to the seller (commission zero).
  assert.deepEqual(settleCalls, [{
    orderId: order.id,
    sellerId: order.sellerId,
    amount: 150000n,
    commission: 0n,
    idempotencyKey: 'settle_or-flow-1',
  }]);
  const settlement = tx._store.escrowTransaction.find((e) => e.type === 'SETTLEMENT_TO_SELLER');
  assert.equal(settlement.amount, 150000n, 'seller entitlement = total - commission');

  assert.equal(tx._store.escrowHold[0].status, 'released');
  assert.equal(tx._store.receipts.length, 1);
  assert.equal(tx._store.receipts[0].purchaserId, 'buyer-1');
  assert.equal(tx._store.receipts[0].amount, 150000n);
});

test('completion chain rejects orders that never armed a credential', async () => {
  const order = seededOrder({ status: ORDER_STATES.DISPATCHED });
  const tx = createFlowTx({ orders: [order] });

  await assert.rejects(
    completeAfterCredentialVerified(tx, order, 'buyer-1', 'OTP'),
    (err) => err.status === 409 && /INVALID_ORDER_STATE/.test(err.message),
  );
});

test('completion chain watches a held escrow and records nothing when there is no hold', async () => {
  const order = seededOrder();
  const tx = createFlowTx({ orders: [order] }); // deliberately no escrowHold row
  const settleCalls = [];
  const settle = async (args) => {
    settleCalls.push(args);
    return { alreadySettled: false };
  };

  await completeAfterCredentialVerified(tx, order, 'buyer-1', 'OTP', { settle });

  assert.equal(settleCalls.length, 0, 'no hold means no money moves');
  assert.equal(tx._store.escrowTransaction.length, 0);
  assert.equal(tx._store.orders[0].status, ORDER_STATES.COMPLETED);
});