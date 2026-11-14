// Withdrawals are the cash-out path: every balance and limit check can pass
// while an attacker who hijacked the account sends the money to their own
// phone. Identity verification is the gate that closes that hole, so it is
// asserted before the money path is ever reached.
const { test, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const locks = require('./helpers/locks');

locks.stubLocksAlwaysAvailable();

const FIREBASE = require.resolve('../src/config/firebase');
const DATABASE = require.resolve('../src/config/database');
const COMMERCE = require.resolve('../src/services/commerce-store');
const PROVIDER = require.resolve('../src/modules/payments/provider-factory');
const WALLET = require.resolve('../src/modules/wallet/wallet-service');

const WALLET_LOOKUP_REACHED = new Error('WALLET_LOOKUP_REACHED');

let fakeDb;
let store;
let setCalls;
let walletService;

function installStubs() {
  fakeDb = {
    collection: () => ({
      doc: () => ({
        set: async () => {
          setCalls += 1;
        },
      }),
    }),
  };
  require.cache[FIREBASE] = {
    id: FIREBASE,
    filename: FIREBASE,
    loaded: true,
    exports: { getFirebaseFirestore: () => fakeDb },
  };
  require.cache[DATABASE] = {
    id: DATABASE,
    filename: DATABASE,
    loaded: true,
    exports: { getStore: () => store },
  };
  require.cache[COMMERCE] = {
    id: COMMERCE,
    filename: COMMERCE,
    loaded: true,
    exports: {
      COLLECTIONS: { withdrawals: 'withdrawals' },
      getWallet: async () => {
        throw WALLET_LOOKUP_REACHED;
      },
      sumWithdrawalsToday: async () => 0,
      serializeWithdrawal: (row) => row,
    },
  };
  require.cache[PROVIDER] = {
    id: PROVIDER,
    filename: PROVIDER,
    loaded: true,
    exports: { getProvider: () => ({}) },
  };
  delete require.cache[WALLET];
  walletService = require(WALLET);
}

function kycStore(row, profile = { id: 'u-1', userId: 'u-1' }) {
  return {
    sellerProfile: { findUnique: async () => profile },
    kycApplication: { findUnique: async () => row },
  };
}

beforeEach(() => {
  setCalls = 0;
  store = kycStore(null);
  installStubs();
});

afterEach(() => {
  for (const key of [FIREBASE, DATABASE, COMMERCE, PROVIDER, WALLET]) {
    delete require.cache[key];
  }
});

test('a seller with no KYC application cannot withdraw', async () => {
  await assert.rejects(
    walletService.requestWithdrawal({ sellerId: 'u-1', amount: 1000 }),
    { message: 'KYC_REQUIRED' },
  );
  assert.equal(setCalls, 0);
});

test('a pending KYC application cannot withdraw', async () => {
  store = kycStore({ userId: 'u-1', status: 'pending', approved: false });
  await assert.rejects(
    walletService.requestWithdrawal({ sellerId: 'u-1', amount: 1000 }),
    { message: 'KYC_REQUIRED' },
  );
  assert.equal(setCalls, 0);
});

test('a rejected or revoked KYC application cannot withdraw', async () => {
  for (const status of ['rejected', 'revoked']) {
    store = kycStore({ userId: 'u-1', status, approved: false });
    await assert.rejects(
      walletService.requestWithdrawal({ sellerId: 'u-1', amount: 1000 }),
      { message: 'KYC_REQUIRED' },
    );
  }
  assert.equal(setCalls, 0);
});

test('an approved status with a stale approved flag cannot withdraw', async () => {
  store = kycStore({ userId: 'u-1', status: 'approved', approved: false });
  await assert.rejects(
    walletService.requestWithdrawal({ sellerId: 'u-1', amount: 1000 }),
    { message: 'KYC_REQUIRED' },
  );
});

test('an approved KYC application passes the gate', async () => {
  store = kycStore({ userId: 'u-1', status: 'approved', approved: true });
  await assert.rejects(
    walletService.requestWithdrawal({ sellerId: 'u-1', amount: 1000 }),
    { message: 'WALLET_LOOKUP_REACHED' },
  );
});

test('the gate resolves the seller profile to its user id', async () => {
  let lookedUp = null;
  store = {
    sellerProfile: { findUnique: async () => ({ id: 'sp-1', userId: 'u-9' }) },
    kycApplication: {
      findUnique: async ({ where }) => {
        lookedUp = where.userId;
        return null;
      },
    },
  };

  await assert.rejects(
    walletService.assertWithdrawalKyc('sp-1'),
    { message: 'KYC_REQUIRED' },
  );
  assert.equal(lookedUp, 'u-9');
});

test('a missing seller profile falls back to the id as the KYC key', async () => {
  let lookedUp = null;
  store = {
    sellerProfile: { findUnique: async () => null },
    kycApplication: {
      findUnique: async ({ where }) => {
        lookedUp = where.userId;
        return { status: 'approved', approved: true };
      },
    },
  };

  await assert.doesNotReject(walletService.assertWithdrawalKyc('u-1'));
  assert.equal(lookedUp, 'u-1');
});

test('an invalid amount is still rejected before the KYC lookup', async () => {
  store = {
    sellerProfile: { findUnique: async () => { throw new Error('should not be read'); } },
    kycApplication: { findUnique: async () => { throw new Error('should not be read'); } },
  };
  await assert.rejects(
    walletService.requestWithdrawal({ sellerId: 'u-1', amount: 0 }),
    { message: 'INVALID_AMOUNT' },
  );
});
