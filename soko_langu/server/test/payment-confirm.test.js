const { test } = require('node:test');
const assert = require('node:assert/strict');

// ---------------------------------------------------------------------------
// Module seams: confirmCollection calls getPrisma(), getProvider(), the legacy
// mirror and OneSignal at runtime. Patch those BEFORE loading the service so
// the money path runs hermetically on a fake Prisma — the fake has NO vapor
// ledgerAccount/ledgerEntry collections, so any residual call to them would
// throw and fail the test.
// ---------------------------------------------------------------------------
const state = { prisma: null };
const DB = require('../src/config/database');
const ProviderFactory = require('../src/modules/payments/provider-factory');
const Mirror = require('../src/modules/legacy-compat/presentation-mirror');
const Notify = require('../src/modules/legacy-compat/notify');

DB.getPrisma = () => state.prisma;
ProviderFactory.getProvider = () => ({
  queryCollectionStatus: async () => ({ status: 'completed', providerPaymentId: 'q-pid' }),
});
Mirror.syncLegacyOrderStatus = async () => null;
Notify.sendOneSignalNotification = async () => null;
Notify.notifyAdmins = async () => null;

const paymentService = require('../src/modules/payments/payment-service');
const { ORDER_STATES, OrderStateMachine } = require('../src/modules/orders/order-state-machine');

// ---------------------------------------------------------------------------
// Fake in-memory Prisma covering the confirmCollection subset exactly.
// ---------------------------------------------------------------------------
function createFakePrisma(seed = {}) {
  const store = {
    order: (seed.order ?? []).map((r) => ({ ...r })),
    payment: (seed.payment ?? []).map((r) => ({ ...r })),
    escrowHold: [],
    escrowTransaction: [],
    refund: [],
    sellerProfile: (seed.sellerProfile ?? []).map((r) => ({ ...r })),
    user: (seed.user ?? []).map((r) => ({ ...r })),
    notification: [],
  };

  function whereMatch(row, where = {}) {
    return Object.entries(where).every(([key, expect]) => {
      if (expect && typeof expect === 'object' && !(expect instanceof Date)) {
        if ('in' in expect) return expect.in.includes(row[key]);
      }
      return row[key] === expect;
    });
  }

  const api = {
    $transaction: async (fn) => fn(api),

    order: {
      findFirst: async ({ where } = {}) => store.order.find((r) => whereMatch(r, where)) ?? null,
      update: async ({ where, data } = {}) => {
        const row = store.order.find((r) => r.id === where.id);
        Object.assign(row, data);
        return row;
      },
    },
    payment: {
      findFirst: async ({ where, orderBy } = {}) => {
        const rows = store.payment.filter((r) => whereMatch(r, where));
        if (orderBy && orderBy.createdAt) {
          rows.sort((a, b) => (orderBy.createdAt === 'desc'
            ? new Date(b.createdAt) - new Date(a.createdAt)
            : new Date(a.createdAt) - new Date(b.createdAt)));
        }
        return rows[0] ?? null;
      },
      findUnique: async ({ where } = {}) => store.payment.find((r) => r.id === where.id) ?? null,
      update: async ({ where, data } = {}) => {
        const row = store.payment.find((r) => r.id === where.id);
        Object.assign(row, data);
        return row;
      },
    },
    escrowHold: {
      create: async ({ data } = {}) => {
        const row = { id: `eh-${store.escrowHold.length + 1}`, ...data };
        store.escrowHold.push(row);
        return row;
      },
    },
    refund: {
      findFirst: async ({ where } = {}) =>
        store.refund.find((r) => whereMatch(r, where)) ?? null,
      create: async ({ data } = {}) => {
        const row = { id: `ref-${store.refund.length + 1}`, ...data };
        store.refund.push(row);
        return row;
      },
    },
    sellerProfile: {
      findUnique: async ({ where, include } = {}) => {
        const row = store.sellerProfile.find((r) => r.id === where.id) ?? null;
        if (!row || !include || !include.user) return row;
        const user = store.user.find((u) => u.id === row.userId) ?? null;
        return { ...row, user: user ? { ...user } : null };
      },
    },
    notification: {
      create: async ({ data } = {}) => {
        const row = { id: `nt-${store.notification.length + 1}`, ...data };
        store.notification.push(row);
        return row;
      },
    },
  };

  Object.defineProperty(api, '_store', { value: store });
  return api;
}

const ORDER_NUMBER = 'SV202609260001';

function seedPaidScenario() {
  const prisma = createFakePrisma({
    order: [{
      id: 'or-1',
      orderNumber: ORDER_NUMBER,
      buyerId: 'buyer-1',
      sellerId: 'sp-1',
      status: ORDER_STATES.PAYMENT_PROCESSING,
      totalAmount: BigInt(60000),
      platformCommission: BigInt(0),
      productPrice: BigInt(60000),
    }],
    payment: [{
      id: 'pay-1',
      orderId: 'or-1',
      provider: 'clickpesa',
      amount: BigInt(60000),
      status: 'initiated',
      providerReference: 'PR-1',
      createdAt: new Date('2026-09-26T10:00:00Z'),
      idempotencyKey: 'init_x',
    }],
    sellerProfile: [{
      id: 'sp-1',
      userId: 'seller-user-1',
      storeName: 'Duka Bora',
    }],
    user: [{
      id: 'seller-user-1',
      firebaseUid: 'fb-seller-1',
    }],
  });
  state.prisma = prisma;
  return prisma;
}

test('confirmCollection funds the escrow once and parks the order PAID_IN_ESCROW', async () => {
  const prisma = seedPaidScenario();

  const result = await paymentService.confirmCollection({
    orderReference: ORDER_NUMBER,
    providerPaymentId: 'cp-pid-1',
    amount: 60000,
  });

  assert.equal(result.status, 'VERIFIED');
  assert.equal(result.order.status, ORDER_STATES.PAID_IN_ESCROW);
  assert.ok(result.order.paidAt);

  assert.equal(prisma._store.escrowHold.length, 1);
  assert.equal(prisma._store.escrowHold[0].amount, BigInt(60000));
  assert.equal(prisma._store.escrowHold[0].status, 'holding');
  assert.equal(prisma._store.escrowHold[0].paymentId, 'pay-1');

  const payment = prisma._store.payment[0];
  assert.equal(payment.status, 'completed');
  assert.equal(payment.providerPaymentId, 'cp-pid-1');
  assert.ok(payment.verifiedAt);

  // Seller notified so they dispatch.
  assert.equal(prisma._store.notification.length, 1);
  assert.equal(prisma._store.notification[0].userId, 'seller-user-1');
});

test('confirmCollection is idempotent — second delivery is a no-op', async () => {
  const prisma = seedPaidScenario();

  const first = await paymentService.confirmCollection({
    orderReference: ORDER_NUMBER,
    providerPaymentId: 'cp-pid-1',
  });
  assert.equal(first.status, 'VERIFIED');

  const second = await paymentService.confirmCollection({
    orderReference: ORDER_NUMBER,
    providerPaymentId: 'cp-pid-1',
  });
  assert.equal(second.status, 'ALREADY_IN_ESCROW');
  assert.equal(prisma._store.escrowHold.length, 1, 'no second hold');
  assert.equal(prisma._store.payment[0].status, 'completed');
});

test('confirmCollection rejects a provider amount that differs from the server amount', async () => {
  const prisma = seedPaidScenario();

  await assert.rejects(
    paymentService.confirmCollection({
      orderReference: ORDER_NUMBER,
      providerPaymentId: 'cp-pid-1',
      amount: 59999,
    }),
    (err) => err.status === 409 && String(err.message).startsWith('PAYMENT_AMOUNT_MISMATCH')
  );

  assert.equal(prisma._store.escrowHold.length, 0, 'no escrow on mismatch');
  assert.equal(prisma._store.payment[0].status, 'initiated');
  assert.equal(prisma._store.order[0].status, ORDER_STATES.PAYMENT_PROCESSING);
});

test('confirmCollection rejects when the order is not in a pay state', async () => {
  const prisma = seedPaidScenario();
  prisma._store.order[0].status = ORDER_STATES.AWAITING_SELLER_SHIPPING;

  await assert.rejects(
    paymentService.confirmCollection({ orderReference: ORDER_NUMBER, providerPaymentId: 'cp-pid-1' }),
    (err) => err.status === 409 && String(err.message).startsWith('INVALID_ORDER_STATE')
  );
  assert.equal(prisma._store.escrowHold.length, 0);
});

test('late provider completion after cancel captures money and parks REFUND_PENDING', async () => {
  const prisma = createFakePrisma({
    order: [{
      id: 'or-2',
      orderNumber: 'SV202609260002',
      buyerId: 'buyer-2',
      sellerId: 'sp-2',
      status: ORDER_STATES.CANCELLED,
      totalAmount: BigInt(50000),
      productPrice: BigInt(50000),
    }],
    payment: [{
      id: 'pay-2',
      orderId: 'or-2',
      provider: 'clickpesa',
      amount: BigInt(50000),
      status: 'initiated',
      providerReference: 'PR-2',
      createdAt: new Date('2026-09-26T11:00:00Z'),
      idempotencyKey: 'init_y',
    }],
  });
  state.prisma = prisma;

  const result = await paymentService.confirmCollection({
    orderReference: 'SV202609260002',
    providerPaymentId: 'cp-pid-late',
    amount: 50000,
  });

  assert.equal(result.status, 'REFUND_PARKED');
  assert.equal(result.order.status, ORDER_STATES.REFUND_PENDING);
  assert.equal(prisma._store.escrowHold.length, 1, 'captured into a hold');
  assert.equal(prisma._store.payment[0].status, 'completed');
  assert.equal(prisma._store.refund.length, 1, 'refund obligation opened');
  assert.equal(prisma._store.refund[0].mode, 'full');
  assert.equal(prisma._store.refund[0].amount, BigInt(50000));
  assert.equal(prisma._store.refund[0].status, 'pending');
  assert.equal(prisma._store.refund[0].paymentId, 'pay-2');
  assert.ok(prisma._store.refund[0].correlationId.startsWith('refund_SV202609260002_'));
});

test('late recovery also covers EXPIRED and PAYMENT_FAILED pre-escrow orders', async () => {
  for (const status of [ORDER_STATES.EXPIRED, ORDER_STATES.PAYMENT_FAILED]) {
    const prisma = createFakePrisma({
      order: [{
        id: 'or-late',
        orderNumber: `SVX${status.slice(0, 6)}`,
        buyerId: 'buyer-3',
        sellerId: 'sp-3',
        status,
        totalAmount: BigInt(40000),
        productPrice: BigInt(40000),
      }],
      payment: [{
        id: 'pay-late',
        orderId: 'or-late',
        provider: 'clickpesa',
        amount: BigInt(40000),
        status: 'initiated',
        providerReference: 'PR-3',
        createdAt: new Date('2026-09-26T12:00:00Z'),
        idempotencyKey: 'init_z',
      }],
    });
    state.prisma = prisma;

    const result = await paymentService.confirmCollection({
      orderReference: prisma._store.order[0].orderNumber,
      providerPaymentId: 'cp-pid-late',
    });
    assert.equal(result.status, 'REFUND_PARKED', `for ${status}`);
    assert.equal(result.order.status, ORDER_STATES.REFUND_PENDING);
    assert.equal(prisma._store.escrowHold.length, 1);
    assert.equal(prisma._store.refund.length, 1);
  }
});

test('state machine allows the refund recovery transitions and forbids misuse', () => {
  const fromStates = [ORDER_STATES.CANCELLED, ORDER_STATES.EXPIRED, ORDER_STATES.PAYMENT_FAILED];
  for (const from of fromStates) {
    const m = new OrderStateMachine(from);
    assert.ok(m.canTransition(ORDER_STATES.REFUND_PENDING), `${from} -> REFUND_PENDING`);
    m.transition(ORDER_STATES.REFUND_PENDING, { actor: 'system' });
    assert.equal(m.state, ORDER_STATES.REFUND_PENDING);
  }
  // Money-release only through the refund path: CANCELLED can never go paid.
  const m = new OrderStateMachine(ORDER_STATES.CANCELLED);
  assert.ok(!m.canTransition(ORDER_STATES.PAID_IN_ESCROW));
  assert.ok(!m.canTransition(ORDER_STATES.COMPLETED));
});