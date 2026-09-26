const { test } = require('node:test');
const assert = require('node:assert/strict');

const state = { prisma: null };
const DB = require('../src/config/database');
const ProviderFactory = require('../src/modules/payments/provider-factory');

DB.getPrisma = () => state.prisma;
ProviderFactory.getProvider = () => ({
  initiatePayout: async () => ({ id: 'payout-1' }),
});

const walletService = require('../src/modules/wallet/wallet-service');
const { LEDGER_TYPES } = require('../src/modules/wallet/ledger-service');

function createFakePrisma({ walletSeed }) {
  const store = {
    wallet: walletSeed ? [walletSeed] : [],
    withdrawal: [],
    walletLedgerEntry: [],
    payoutTransaction: [],
  };

  const api = {
    $transaction: async (fn) => fn(api),

    wallet: {
      findUnique: async ({ where } = {}) =>
        store.wallet.find((r) =>
          ('id' in where ? r.id === where.id : true) &&
          ('sellerId' in where ? r.sellerId === where.sellerId : true)
        ) ?? null,
      create: async ({ data } = {}) => {
        const row = { id: `wal-${store.wallet.length + 1}`, availableBalance: BigInt(0), ...data };
        store.wallet.push(row);
        return row;
      },
      update: async ({ where, data } = {}) => {
        const row = store.wallet.find((r) => r.id === where.id);
        Object.assign(row, data);
        return row;
      },
    },

    withdrawal: {
      aggregate: async () => ({ _sum: { amount: null } }),
      create: async ({ data } = {}) => {
        const row = { id: `w-${store.withdrawal.length + 1}`, ...data };
        store.withdrawal.push(row);
        return row;
      },
    },

    walletLedgerEntry: {
      findUnique: async () => null,
      create: async ({ data } = {}) => {
        const row = { id: `le-${store.walletLedgerEntry.length + 1}`, ...data };
        store.walletLedgerEntry.push(row);
        return row;
      },
    },

    payoutTransaction: {
      create: async ({ data } = {}) => {
        const row = { id: `pt-${store.payoutTransaction.length + 1}`, ...data };
        store.payoutTransaction.push(row);
        return row;
      },
    },
  };

  Object.defineProperty(api, '_store', { value: store });
  return api;
}

test('requestWithdrawal debits the wallet ledger once, in the same transaction', async () => {
  const api = createFakePrisma({
    walletSeed: {
      id: 'wal-1',
      sellerId: 'sp-1',
      availableBalance: BigInt(100000),
      pendingBalance: BigInt(0),
      frozenBalance: BigInt(0),
      totalEarned: BigInt(0),
      totalWithdrawn: BigInt(0),
      status: 'active',
    },
  });
  state.prisma = api;

  const { withdrawal, wallet } = await walletService.requestWithdrawal({
    sellerId: 'sp-1',
    amount: 40000,
    phoneNumber: '255712345678',
  });

  assert.equal(String(withdrawal.amount), '40000');
  assert.equal(withdrawal.status, 'pending');
  assert.equal(withdrawal.phoneNumber, '255712345678');

  // Wallet balance debited atomically with the ledger entry.
  assert.equal(wallet.availableBalance, BigInt(60000));

  assert.equal(api._store.walletLedgerEntry.length, 1);
  const entry = api._store.walletLedgerEntry[0];
  assert.equal(entry.type, LEDGER_TYPES.WITHDRAWAL_DEBITED);
  assert.equal(entry.amount, BigInt(40000));
  assert.equal(entry.balanceAfter, BigInt(60000));
  assert.equal(entry.referenceType, 'withdrawal');
  assert.equal(entry.referenceId, withdrawal.id);
  assert.ok(entry.idempotencyKey.startsWith('ledger_withdrawal_'));
  assert.equal(entry.walletId, 'wal-1');
});

test('requestWithdrawal never debits when the balance is insufficient', async () => {
  const api = createFakePrisma({
    walletSeed: {
      id: 'wal-1',
      sellerId: 'sp-1',
      availableBalance: BigInt(20000),
      pendingBalance: BigInt(0),
      frozenBalance: BigInt(0),
      totalEarned: BigInt(0),
      totalWithdrawn: BigInt(0),
      status: 'active',
    },
  });
  state.prisma = api;

  await assert.rejects(
    walletService.requestWithdrawal({ sellerId: 'sp-1', amount: 40000 }),
    (err) => err.status === 400 && err.message === 'INSUFFICIENT_BALANCE'
  );

  assert.equal(api._store.wallet[0].availableBalance, BigInt(20000));
  assert.equal(api._store.walletLedgerEntry.length, 0);
  assert.equal(api._store.withdrawal.length, 0);
});

test('requestWithdrawal is rejected for a frozen wallet', async () => {
  const api = createFakePrisma({
    walletSeed: {
      id: 'wal-1',
      sellerId: 'sp-1',
      availableBalance: BigInt(100000),
      status: 'frozen',
    },
  });
  state.prisma = api;

  await assert.rejects(
    walletService.requestWithdrawal({ sellerId: 'sp-1', amount: 1000 }),
    (err) => err.status === 409 && err.message === 'WALLET_FROZEN'
  );
  assert.equal(api._store.walletLedgerEntry.length, 0);
});