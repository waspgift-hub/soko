// Creation-time risk detection. These tests pin the two behaviours that matter
// independently of the payout gate: self-dealing is stopped before an order
// exists, and velocity is recorded/alerted without blocking a legitimate buyer.
const { test } = require('node:test');
const assert = require('node:assert/strict');

const {
  RISK_THRESHOLDS,
  RISK_SIGNALS,
  evaluateOrderRisk,
  raiseFraudAlerts,
  toMillis,
} = require('../src/modules/trust/order-risk');

const NOW = new Date('2026-11-14T12:00:00.000Z');
const minutesAgo = (n) => new Date(NOW.getTime() - n * 60 * 1000);
const hoursAgo = (n) => new Date(NOW.getTime() - n * 60 * 60 * 1000);

function order(overrides = {}) {
  return {
    id: 'o-1',
    buyerId: 'buyer-1',
    sellerId: 'sp-1',
    status: 'PENDING_SHIPPING_FEE',
    placedAt: minutesAgo(1),
    ...overrides,
  };
}

function store({ orders = [], sellerProfiles = [], users = [], alerts = [] } = {}) {
  return {
    order: {
      findMany: async ({ where }) => orders.filter((o) => o.buyerId === where.buyerId),
    },
    sellerProfile: {
      findUnique: async ({ where }) => sellerProfiles.find((p) => p.id === where.id) || null,
    },
    user: {
      findUnique: async ({ where }) => users.find((u) => u.id === where.id) || null,
    },
    fraudAlert: {
      create: async ({ data }) => {
        alerts.push(data);
        return data;
      },
    },
    _alerts: alerts,
  };
}

test('buyer and seller on the same account is blocked', async () => {
  const result = await evaluateOrderRisk(
    store({ sellerProfiles: [{ id: 'sp-1', userId: 'buyer-1' }] }),
    { buyerId: 'buyer-1', sellerId: 'sp-1', now: NOW },
  );
  assert.equal(result.blocked, true);
  assert.deepEqual(result.signals, [RISK_SIGNALS.SELF_DEALING]);
  assert.equal(result.score, 3);
});

test('self-dealing is detected when only the collapsed profile id is present', async () => {
  const result = await evaluateOrderRisk(
    store({ sellerProfiles: [{ id: 'buyer-1' }] }),
    { buyerId: 'buyer-1', sellerId: 'buyer-1', now: NOW },
  );
  assert.equal(result.blocked, true);
  assert.deepEqual(result.signals, [RISK_SIGNALS.SELF_DEALING]);
});

test('a different seller is not self-dealing', async () => {
  const result = await evaluateOrderRisk(
    store({ sellerProfiles: [{ id: 'sp-1', userId: 'seller-1' }] }),
    { buyerId: 'buyer-1', sellerId: 'sp-1', now: NOW },
  );
  assert.equal(result.blocked, false);
  assert.deepEqual(result.signals, []);
});

test('a buyer order burst is recorded', async () => {
  const orders = Array.from({ length: RISK_THRESHOLDS.burstOrderLimit }, (_, i) => order({ id: `o-${i}` }));
  const result = await evaluateOrderRisk(store({ orders }), { buyerId: 'buyer-1', sellerId: 'sp-1', now: NOW });
  assert.ok(result.signals.includes(RISK_SIGNALS.RAPID_ORDER_BURST));
  assert.equal(result.blocked, false);
});

test('orders older than the burst window do not trigger it', async () => {
  const orders = Array.from({ length: RISK_THRESHOLDS.burstOrderLimit }, (_, i) => (
    order({ id: `o-${i}`, placedAt: minutesAgo(RISK_THRESHOLDS.burstWindowMinutes + 1) })
  ));
  const result = await evaluateOrderRisk(store({ orders }), { buyerId: 'buyer-1', sellerId: 'sp-1', now: NOW });
  assert.equal(result.signals.includes(RISK_SIGNALS.RAPID_ORDER_BURST), false);
});

test('repeated trading with one seller is recorded', async () => {
  const orders = Array.from({ length: RISK_THRESHOLDS.pairOrderLimit }, (_, i) => (
    order({ id: `o-${i}`, sellerId: 'sp-1', placedAt: hoursAgo(2) })
  ));
  const result = await evaluateOrderRisk(store({ orders }), { buyerId: 'buyer-1', sellerId: 'sp-1', now: NOW });
  assert.ok(result.signals.includes(RISK_SIGNALS.REPEAT_BUYER_SELLER_PAIR));
});

test('repeated orders with other sellers are not a pair signal', async () => {
  const orders = Array.from({ length: RISK_THRESHOLDS.pairOrderLimit }, (_, i) => (
    order({ id: `o-${i}`, sellerId: `sp-${i}`, placedAt: hoursAgo(2) })
  ));
  const result = await evaluateOrderRisk(store({ orders }), { buyerId: 'buyer-1', sellerId: 'sp-1', now: NOW });
  assert.equal(result.signals.includes(RISK_SIGNALS.REPEAT_BUYER_SELLER_PAIR), false);
});

test('a brand-new account placing several orders is flagged', async () => {
  const orders = Array.from({ length: RISK_THRESHOLDS.newAccountOrderLimit }, (_, i) => order({ id: `o-${i}` }));
  const result = await evaluateOrderRisk(
    store({ orders, users: [{ id: 'buyer-1', createdAt: hoursAgo(1) }] }),
    { buyerId: 'buyer-1', sellerId: 'sp-9', now: NOW },
  );
  assert.ok(result.signals.includes(RISK_SIGNALS.BUYER_NEW_ACCOUNT_BURST));
});

test('an established account is not flagged for the same order count', async () => {
  const orders = Array.from({ length: RISK_THRESHOLDS.newAccountOrderLimit }, (_, i) => order({ id: `o-${i}` }));
  const result = await evaluateOrderRisk(
    store({ orders, users: [{ id: 'buyer-1', createdAt: hoursAgo(24 * 30) }] }),
    { buyerId: 'buyer-1', sellerId: 'sp-9', now: NOW },
  );
  assert.equal(result.signals.includes(RISK_SIGNALS.BUYER_NEW_ACCOUNT_BURST), false);
});

test('a normal first order has no signals', async () => {
  const result = await evaluateOrderRisk(
    store({ sellerProfiles: [{ id: 'sp-1', userId: 'seller-1' }], users: [{ id: 'buyer-1', createdAt: hoursAgo(72) }] }),
    { buyerId: 'buyer-1', sellerId: 'sp-1', now: NOW },
  );
  assert.deepEqual(result.signals, []);
  assert.equal(result.score, 0);
  assert.equal(result.blocked, false);
});

test('a missing buyer short-circuits to no risk', async () => {
  const result = await evaluateOrderRisk(store(), { buyerId: null, sellerId: 'sp-1', now: NOW });
  assert.deepEqual(result.signals, []);
  assert.equal(result.blocked, false);
});

test('alerts carry the admin panel shape', async () => {
  const alerts = [];
  const written = await raiseFraudAlerts(store({ sellerProfiles: [{ id: 'sp-1', storeName: 'Amina Shop' }], alerts }), {
    signals: [RISK_SIGNALS.RAPID_ORDER_BURST],
    details: [{ code: RISK_SIGNALS.RAPID_ORDER_BURST, severity: 'medium', detail: 'too fast' }],
    buyerId: 'buyer-1',
    sellerId: 'sp-1',
    productId: 'product-1',
    orderId: 'order-1',
    orderNumber: 'SV1',
    now: NOW,
  });

  assert.equal(written, 1);
  assert.equal(alerts.length, 1);
  assert.equal(alerts[0].type, RISK_SIGNALS.RAPID_ORDER_BURST);
  assert.equal(alerts[0].severity, 'medium');
  assert.equal(alerts[0].sellerName, 'Amina Shop');
  assert.equal(alerts[0].orderId, 'order-1');
  assert.equal(alerts[0].buyerId, 'buyer-1');
  assert.equal(alerts[0].resolved, false);
  assert.deepEqual(alerts[0].detectedAt, NOW);
});

test('alerts never break a checkout when no model or signals exist', async () => {
  assert.equal(await raiseFraudAlerts({}, { signals: [] }), 0);
  assert.equal(await raiseFraudAlerts({}, { signals: ['X'], details: [] }), 0);
});

test('timestamps from all writer eras normalize to milliseconds', () => {
  assert.equal(toMillis(new Date('2026-11-14T12:00:00.000Z')), NOW.getTime());
  assert.equal(toMillis('2026-11-14T12:00:00.000Z'), NOW.getTime());
  assert.equal(toMillis({ toDate: () => new Date('2026-11-14T12:00:00.000Z') }), NOW.getTime());
  assert.equal(toMillis(null), null);
  assert.equal(toMillis('not-a-date'), null);
});
