const { test } = require('node:test');
const assert = require('node:assert/strict');

const { ensureWallet, withdrawalPayoutPhone, creditLegacyBalance } = require('../src/modules/wallet/wallet-service');
const { releaseEscrowAndSettle } = require('../src/modules/handover/handover-service');

// Minimal in-memory Prisma-like client covering the subset of tx.* calls that
// releaseEscrowAndSettle/ensureWallet make. Kept tiny on purpose: the point is
// to prove the money math and the no-wallet money-loss regression, not to
// reimplement Prisma.
function createFakeTx(seed = {}) {
  const store = {
    escrowHold: seed.escrowHold ?? [],
    walletLedgerEntry: seed.walletLedgerEntry ?? [],
    escrowTransaction: [],
    wallet: seed.wallet ?? [],
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
        Object.assign(row, data);
        return row;
      },
    },
    walletLedgerEntry: {
      findFirst: async ({ where = {} }) => store.walletLedgerEntry.find((r) => whereMatch(r, where)) ?? null,
      create: async ({ data }) => {
        const row = { ...data };
        store.walletLedgerEntry.push(row);
        return row;
      },
    },
    escrowTransaction: {
      create: async ({ data }) => {
        const row = { ...data };
        store.escrowTransaction.push(row);
        return row;
      },
    },
    wallet: {
      findUnique: async ({ where }) => store.wallet.find((r) => r.sellerId === where.sellerId) ?? null,
      create: async ({ data }) => {
        const row = { sellerId: data.sellerId, availableBalance: 0, totalEarned: 0, totalWithdrawn: 0 };
        store.wallet.push(row);
        return row;
      },
      update: async ({ where, data }) => {
        const row = store.wallet.find((r) => r.id === where.id);
        Object.assign(row, data);
        return row;
      },
    },
  };

  // For assertions
  Object.defineProperty(api, '_store', { value: store });
  return api;
}

const order = {
  id: 'or-settle-1',
  sellerId: 'seller-no-wallet',
  totalAmount: 100000,
  platformCommission: 20000,
};

function seedHolding(tx) {
  tx._store.escrowHold.push({ id: 'eh-1', orderId: order.id, status: 'holding' });
}

test('ensureWallet creates the wallet row when missing', async () => {
  const tx = createFakeTx();
  const wallet = await ensureWallet(tx, 's1');
  assert.ok(wallet, 'wallet row must be created');
  assert.equal(wallet.sellerId, 's1');
  assert.equal(wallet.availableBalance, 0);
  assert.equal(tx._store.wallet.length, 1);
});

test('ensureWallet reuses the existing wallet row', async () => {
  const tx = createFakeTx({ wallet: [{ id: 'w-1', sellerId: 's2', availableBalance: 50000 }] });
  const wallet = await ensureWallet(tx, 's2');
  assert.equal(wallet.id, 'w-1');
  assert.equal(tx._store.wallet.length, 1, 'must not create a duplicate');
});

test('settlement credits the seller even when their wallet does not exist yet', async () => {
  // Regression: the old `if (wallet)` guard silently skipped the ledger credit
  // for sellers with no wallet row — the transaction completed and the money
  // was effectively lost.
  const tx = createFakeTx();
  seedHolding(tx);

  await releaseEscrowAndSettle(tx, order);

  assert.equal(tx._store.wallet.length, 1, 'wallet must be auto-created for seller');
  const wallet = tx._store.wallet[0];
  assert.equal(wallet.availableBalance, 80000, 'seller entitlement = total - commission');

  const entry = tx._store.walletLedgerEntry.find((e) => e.idempotencyKey === `settlement_${order.id}`);
  assert.ok(entry, 'settlement ledger entry must be posted');
  assert.equal(entry.amount, 80000);
  assert.equal(entry.balanceAfter, 80000);
  assert.equal(entry.type, 'ORDER_SETTLEMENT');

  const escrowTx = tx._store.escrowTransaction;
  assert.equal(escrowTx.filter((e) => e.type === 'SETTLEMENT_TO_SELLER').length, 1);
  assert.equal(escrowTx.filter((e) => e.type === 'COMMISSION_TO_PLATFORM').length, 1);
  assert.equal(escrowTx.find((e) => e.type === 'COMMISSION_TO_PLATFORM').amount, 20000);
});

test('settlement is idempotent — a retry never double-credits', async () => {
  const tx = createFakeTx();
  seedHolding(tx);

  await releaseEscrowAndSettle(tx, order);
  await releaseEscrowAndSettle(tx, order);

  assert.equal(tx._store.wallet.length, 1);
  assert.equal(tx._store.wallet[0].availableBalance, 80000, 'no second credit');
  const settled = tx._store.walletLedgerEntry.filter((e) => e.idempotencyKey === `settlement_${order.id}`);
  assert.equal(settled.length, 1);
});

test('settlement with an existing wallet increments its balance, not a new row', async () => {
  const tx = createFakeTx({
    wallet: [{ id: 'w-9', sellerId: order.sellerId, availableBalance: 10000, totalEarned: 10000 }],
  });
  seedHolding(tx);

  await releaseEscrowAndSettle(tx, order);

  assert.equal(tx._store.wallet.length, 1);
  assert.equal(tx._store.wallet[0].availableBalance, 90000);
  assert.equal(tx._store.wallet[0].totalEarned, 90000);
});

// Minimal Prisma-like client for creditLegacyBalance. Mirrors the released
// subset of wallet.walletLedgerEntry / wallet.wallet queries on in-memory rows.
function createCreditPrisma({ wallet = [], ledger = [] } = {}) {
  const state = { wallet, walletLedgerEntry: ledger };

  function match(row, where = {}) {
    return Object.entries(where).every(([k, v]) => row[k] === v);
  }

  const api = {
    walletLedgerEntry: {
      findFirst: async ({ where = {} }) => state.walletLedgerEntry.find((r) => match(r, where)) ?? null,
      findUnique: async ({ where = {} }) => state.walletLedgerEntry.find((r) => match(r, where)) ?? null,
      create: async ({ data }) => {
        const row = { ...data };
        state.walletLedgerEntry.push(row);
        return row;
      },
    },
    wallet: {
      findUnique: async ({ where }) => state.wallet.find((r) => r.sellerId === where.sellerId) ?? null,
      create: async ({ data }) => {
        const row = { sellerId: data.sellerId, availableBalance: BigInt(0), totalEarned: BigInt(0), totalWithdrawn: BigInt(0) };
        state.wallet.push(row);
        return row;
      },
      update: async ({ where, data }) => {
        const row = state.wallet.find((r) => r.id === where.id);
        Object.assign(row, data);
        return row;
      },
    },
  };
  return { $transaction: async (fn) => fn(api), _state: state };
}

test('creditLegacyBalance folds sellerBalance + withdrawn into the wallet', async () => {
  const prisma = createCreditPrisma();
  const res = await creditLegacyBalance({ sellerId: 'sp-legacy-1', amount: 50000, priorWithdrawn: 25000, db: prisma });

  assert.equal(res.alreadyMigrated, false);
  const wallet = prisma._state.wallet[0];
  assert.equal(wallet.availableBalance, BigInt(50000));
  assert.equal(wallet.totalWithdrawn, BigInt(25000), 'legacy withdrawn history is folded in');
  assert.equal(wallet.totalEarned, BigInt(75000), 'totalEarned = available + withdrawn stays consistent');

  const entry = prisma._state.walletLedgerEntry.find((e) => e.idempotencyKey === 'legacy_balance_sp-legacy-1');
  assert.ok(entry, 'legacy balance ledger entry must be posted');
  assert.equal(entry.type, 'LEGACY_BALANCE');
  assert.equal(entry.amount, 50000);
  assert.equal(entry.balanceAfter, BigInt(50000));
});

test('creditLegacyBalance is a no-op once already migrated', async () => {
  const prisma = createCreditPrisma({
    wallet: [{ id: 'w-legacy', sellerId: 'sp-legacy-2', availableBalance: BigInt(50000), totalEarned: BigInt(75000), totalWithdrawn: BigInt(25000) }],
    ledger: [{
      id: 'le-legacy',
      type: 'LEGACY_BALANCE',
      referenceId: 'sp-legacy-2',
      idempotencyKey: 'legacy_balance_sp-legacy-2',
    }],
  });

  const res = await creditLegacyBalance({ sellerId: 'sp-legacy-2', amount: 90000, priorWithdrawn: 25000, db: prisma });
  assert.equal(res.alreadyMigrated, true);
  assert.equal(prisma._state.wallet[0].availableBalance, BigInt(50000), 'no double credit');
  assert.equal(prisma._state.walletLedgerEntry.length, 1);
});

test('creditLegacyBalance rejects non-positive amounts without creating a wallet', async () => {
  const prisma = createCreditPrisma();
  await assert.rejects(
    creditLegacyBalance({ sellerId: 'sp-x', amount: 0, db: prisma }),
    (err) => err.status === 400
  );
  assert.equal(prisma._state.wallet.length, 0);
});

test('withdrawalPayoutPhone prefers the phone captured at request time', () => {
  assert.equal(
    withdrawalPayoutPhone({
      phoneNumber: '+255712345678',
      seller: { user: { phone: '+255700000000' } },
    }),
    '+255712345678',
  );
});

test('withdrawalPayoutPhone falls back to the profile phone for legacy rows', () => {
  assert.equal(
    withdrawalPayoutPhone({
      phoneNumber: null,
      seller: { user: { phone: '+255700000000' } },
    }),
    '+255700000000',
  );
});

test('withdrawalPayoutPhone returns null when no phone source exists', () => {
  assert.equal(withdrawalPayoutPhone({ phoneNumber: null }), null);
});