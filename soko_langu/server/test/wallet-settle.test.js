const { test } = require('node:test');
const assert = require('node:assert/strict');

const { releaseEscrowAndSettle } = require('../src/modules/escrow/escrow-release');
const { withdrawalPayoutPhone } = require('../src/modules/wallet/wallet-service');

// Minimal in-memory Prisma-like client covering the subset of tx.* calls that
// releaseEscrowAndSettle makes (escrowHold + escrowTransaction). Funds move
// through the injected Firestore `settle` spy, so no live Firebase is needed.
function createFakeTx(seed = {}) {
  const store = {
    escrowHold: seed.escrowHold ?? [],
    escrowTransaction: [],
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
  };

  Object.defineProperty(api, '_store', { value: store });
  return api;
}

const order = {
  id: 'or-settle-1',
  sellerId: 'seller-1',
  totalAmount: 100000n,
  platformCommission: 20000n,
};

function seedHolding(tx, { status = 'holding' } = {}) {
  tx._store.escrowHold.push({ id: 'eh-1', orderId: order.id, status });
}

test('releaseEscrowAndSettle credits the seller via the injected settle', async () => {
  const tx = createFakeTx();
  seedHolding(tx);
  const settleCalls = [];
  const settle = async (args) => {
    settleCalls.push(args);
    return { alreadySettled: false };
  };

  const result = await releaseEscrowAndSettle(tx, order, { settle });

  assert.deepEqual(settleCalls, [{
    orderId: order.id,
    sellerId: order.sellerId,
    amount: order.totalAmount,
    commission: order.platformCommission,
    idempotencyKey: 'settle_or-settle-1',
  }]);

  assert.equal(tx._store.escrowHold[0].status, 'released');
  assert.ok(tx._store.escrowHold[0].releasedAt, 'releasedAt must be stamped');

  const settlement = tx._store.escrowTransaction.find((e) => e.type === 'SETTLEMENT_TO_SELLER');
  assert.equal(settlement.amount, 80000n, 'seller entitlement = total - commission');
  const commission = tx._store.escrowTransaction.find((e) => e.type === 'COMMISSION_TO_PLATFORM');
  assert.equal(commission.amount, 20000n);
  assert.ok(result.escrowHold, 'returns the released hold');
});

test('releaseEscrowAndSettle skips the commission row when commission is zero', async () => {
  const tx = createFakeTx();
  seedHolding(tx);
  const settle = async () => ({ alreadySettled: false });
  const zeroOrder = { ...order, platformCommission: 0n };

  await releaseEscrowAndSettle(tx, zeroOrder, { settle });

  const types = tx._store.escrowTransaction.map((e) => e.type);
  assert.ok(types.includes('SETTLEMENT_TO_SELLER'));
  assert.ok(!types.includes('COMMISSION_TO_PLATFORM'));
});

test('releaseEscrowAndSettle is idempotent — a retry never re-releases', async () => {
  const tx = createFakeTx();
  seedHolding(tx);
  const settleCalls = [];
  const settle = async (args) => {
    settleCalls.push(args);
    return { alreadySettled: false };
  };

  await releaseEscrowAndSettle(tx, order, { settle });
  await releaseEscrowAndSettle(tx, order, { settle });

  assert.equal(settleCalls.length, 1, 'second call sees a released hold and settles nothing');
  assert.equal(tx._store.escrowTransaction.filter((e) => e.type === 'SETTLEMENT_TO_SELLER').length, 1);
});

test('releaseEscrowAndSettle closes the Prisma trace even when Firestore already settled', async () => {
  // Crash-between-stores retry: the hold is still 'holding' in Prisma but the
  // Firestore settle already ran. The hold must still be released and the
  // escrowTransaction still guarded against duplicates.
  const tx = createFakeTx();
  seedHolding(tx);
  const settle = async () => ({ alreadySettled: true });

  await releaseEscrowAndSettle(tx, order, { settle });
  tx._store.escrowHold[0].status = 'holding'; // simulate Prisma transaction rollback
  await releaseEscrowAndSettle(tx, order, { settle });

  assert.equal(tx._store.escrowHold[0].status, 'released');
  assert.equal(tx._store.escrowTransaction.filter((e) => e.type === 'SETTLEMENT_TO_SELLER').length, 1);
});

test('releaseEscrowAndSettle returns null when there is nothing to release', async () => {
  const tx = createFakeTx(); // no hold
  const settle = async () => {
    throw new Error('must not settle without a hold');
  };

  const result = await releaseEscrowAndSettle(tx, order, { settle });
  assert.equal(result, null);
});

test('withdrawalPayoutPhone prefers the phone captured at request time', async () => {
  assert.equal(
    await withdrawalPayoutPhone({ phoneNumber: '+255712345678', seller: { user: { phone: '+255700000000' } } }),
    '+255712345678',
  );
});

test('withdrawalPayoutPhone prefers the explicit userPhone over the profile', async () => {
  assert.equal(
    await withdrawalPayoutPhone({ seller: { user: { phone: '+255700000000' } } }, { userPhone: '+255722222222' }),
    '+255722222222',
  );
});

test('withdrawalPayoutPhone falls back to the profile phone for legacy rows', async () => {
  assert.equal(
    await withdrawalPayoutPhone({ seller: { user: { phone: '+255700000000' } } }),
    '+255700000000',
  );
});

test('withdrawalPayoutPhone falls back to the Firestore user phone via db', async () => {
  const db = {
    collection: (name) => ({
      doc: (id) => ({
        get: async () => ({ exists: true, data: () => ({ phone: '+255733333333' }) }),
      }),
    }),
  };
  assert.equal(await withdrawalPayoutPhone({ sellerId: 'sp-1' }, { db }), '+255733333333');
});

test('withdrawalPayoutPhone returns null when no phone source exists', async () => {
  assert.equal(await withdrawalPayoutPhone({}), null);
});