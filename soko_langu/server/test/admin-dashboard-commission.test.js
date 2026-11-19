// Platform commission must come from a server-side SUM over settled orders.
// The app previously summed the whole Firestore transactions mirror, which was
// unbounded and counted refunded/disputed orders as earnings.
const { test } = require('node:test');
const assert = require('node:assert/strict');

const DB = require('../src/config/database');
const Firebase = require('../src/config/firebase');
const commerceStore = require('../src/services/commerce-store');

const state = { aggregateCalls: [], countCalls: [] };

DB.getStore = () => ({
  user: { count: async () => 10 },
  order: {
    count: async (args) => {
      state.countCalls.push(args);
      return 20;
    },
    aggregate: async (args) => {
      state.aggregateCalls.push(args);
      return { _sum: { platformCommission: 5000 } };
    },
  },
  dispute: { count: async () => 1 },
  escrowHold: {
    aggregate: async () => ({ _sum: { amount: 9000 } }),
  },
  product: { count: async () => 30 },
});

Firebase.getFirebaseFirestore = () => ({});
commerceStore.countDocuments = async () => null;
commerceStore.listDocuments = async () => null;

const { getDashboard } = require('../src/modules/admin/admin-service');

test('dashboard reports commission totals and bounded period aggregates', async () => {
  state.aggregateCalls = [];
  state.countCalls = [];

  const { kpis } = await getDashboard();

  assert.equal(kpis.commissionRevenue, '5000');
  assert.equal(kpis.commissionRevenueToday, '5000');
  assert.equal(kpis.commissionRevenueThisMonth, '5000');
  assert.equal(kpis.commissionOrders, 20);

  const commissionAggregates = state.aggregateCalls.filter(
    (call) => call._sum && call._sum.platformCommission,
  );
  assert.equal(commissionAggregates.length, 3);
  assert.ok(
    commissionAggregates.every(
      (call) => call.where.status.in.join(',') === 'completed,wallet_credited',
    ),
  );
  assert.ok(commissionAggregates[1].where.createdAt.gte instanceof Date);
  assert.ok(commissionAggregates[2].where.createdAt.gte instanceof Date);

  const commissionCount = state.countCalls.find(
    (call) =>
      call &&
      call.where &&
      call.where.status &&
      call.where.status.in.join(',') === 'completed,wallet_credited',
  );
  assert.ok(commissionCount);
});
