// Seller-withdrawal payout safety.
//
// Every assertion here is about ONE thing: a seller's TSh must be paid at most
// once, and if the payout never happens the reservation must be returned in the
// same commit that records the failure. The pre-fix code failed both:
//
//   * `PAYOUT_RETRYABLE` contained `processing`, so every finance sweep re-called
//     `initiatePayout` for every in-flight withdrawal — one withdrawal, repeated
//     transfers.
//   * `_failWithdrawal` set `status: failed` + `refundLedgerWritten: true` in one
//     transaction and credited the wallet in a SECOND one, so a crash between
//     them left the money deducted and the anti-double-refund flag already set.
//
// Firestore, ClickPesa and Redis are all faked; nothing here touches a network.
const { test, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');

const FIREBASE_CONFIG = require.resolve('../src/config/firebase');
const PROVIDER_FACTORY = require.resolve('../src/modules/payments/provider-factory');
const CLICKPESA = require.resolve('../clickpesa');
const WALLET_SERVICE = require.resolve('../src/modules/wallet/wallet-service');

const locks = require('./helpers/locks');

/* ------------------------------------------------------------------ */
/* Firestore fake                                                      */
/* ------------------------------------------------------------------ */

const TS = Symbol('serverTimestamp');
const DELETE = Symbol('delete');

function resolveValue(v) {
  if (v === TS) return new Date(0);
  if (v === DELETE) return undefined;
  return v;
}

function applyPatch(current, patch) {
  const out = { ...(current || {}) };
  for (const [k, v] of Object.entries(patch)) {
    const resolved = resolveValue(v);
    if (resolved === undefined) delete out[k];
    else out[k] = resolved;
  }
  return out;
}

/**
 * Transactional Firestore fake.
 *
 * `runTransaction` buffers every write and applies them only if the callback
 * resolves, which is the property the withdrawal refund relies on: a throw part
 * way through leaves nothing behind. It also counts invocations so a test can
 * assert a refund did not need a second transaction.
 */
function createFakeDb(seed = {}) {
  const collections = new Map();

  const col = (name) => {
    if (!collections.has(name)) collections.set(name, new Map());
    return collections.get(name);
  };

  for (const [name, docs] of Object.entries(seed)) {
    const c = col(name);
    for (const [id, data] of Object.entries(docs)) c.set(id, { ...data });
  }

  function readRef(name, id) {
    const data = col(name).get(id);
    return { exists: data !== undefined, id, ref: { name, id }, data: () => (data ? { ...data } : undefined) };
  }

  function docRef(name, id) {
    const api = {
      name,
      id,
      async get() {
        return readRef(name, id);
      },
      async set(data, opts) {
        if (opts && opts.merge) col(name).set(id, applyPatch(col(name).get(id), data));
        else col(name).set(id, applyPatch({}, data));
      },
      async update(data) {
        if (col(name).get(id) === undefined) throw new Error(`${name}/${id} not found`);
        col(name).set(id, applyPatch(col(name).get(id), data));
      },
      async delete() {
        col(name).delete(id);
      },
    };
    return api;
  }

  const db = {
    _txCount: 0,
    collection: (name) => ({ doc: (id) => docRef(name, String(id)) }),

    async runTransaction(fn) {
      db._txCount += 1;
      const writes = [];
      const tx = {
        get: async (ref) => readRef(ref.name, ref.id),
        set: (ref, data, opts) => writes.push(() => docRef(ref.name, ref.id).set(data, opts)),
        update: (ref, data) => writes.push(() => docRef(ref.name, ref.id).update(data)),
        delete: (ref) => writes.push(() => docRef(ref.name, ref.id).delete()),
      };
      // If the callback rejects, nothing is applied — the rollback a real
      // Firestore transaction gives you for free.
      const result = await fn(tx);
      for (const w of writes) await w();
      return result;
    },
  };

  db.dump = (name) => Object.fromEntries([...col(name).entries()].map(([k, v]) => [k, { ...v }]));
  db.reset = () => {
    collections.clear();
    for (const [name, docs] of Object.entries(seed)) {
      const c = col(name);
      for (const [id, data] of Object.entries(docs)) c.set(id, { ...data });
    }
  };
  return db;
}

/* ------------------------------------------------------------------ */
/* Fixtures                                                            */
/* ------------------------------------------------------------------ */

const SELLER = 'seller-1';
const WITHDRAWAL_ID = 'w-1';
const AMOUNT = 50000;

function seedDb() {
  return createFakeDb({
    // Available balance 90_000 = 140_000 earned less the 50_000 already
    // reserved for this withdrawal.
    wallets: { [SELLER]: { sellerId: SELLER, availableBalance: 90000, pendingBalance: 0, totalWithdrawn: 0 } },
    withdrawals: {
      [WITHDRAWAL_ID]: {
        id: WITHDRAWAL_ID,
        sellerId: SELLER,
        amount: AMOUNT,
        status: 'reserved',
        provider: 'clickpesa',
        phoneNumber: '0754000000',
      },
    },
  });
}

let db;
let provider;
let gatewayPayouts;

function installStubs() {
  require.cache[FIREBASE_CONFIG] = {
    id: FIREBASE_CONFIG,
    filename: FIREBASE_CONFIG,
    loaded: true,
    exports: { getFirebaseFirestore: () => db },
  };
  require.cache[PROVIDER_FACTORY] = {
    id: PROVIDER_FACTORY,
    filename: PROVIDER_FACTORY,
    loaded: true,
    exports: { getProvider: () => provider },
  };
  // `processWithdrawal` lazily requires the root clickpesa client to ask whether
  // the gateway already holds a payout.
  require.cache[CLICKPESA] = {
    id: CLICKPESA,
    filename: CLICKPESA,
    loaded: true,
    exports: { clickpesaQueryPayouts: async (filters) => gatewayPayouts(filters) },
  };
  delete require.cache[WALLET_SERVICE];
}

function loadWalletService() {
  // eslint-disable-next-line global-require
  return require('../src/modules/wallet/wallet-service');
}

beforeEach(() => {
  db = seedDb();
  gatewayPayouts = () => ({ data: [] });
  provider = {
    calls: [],
    initiatePayout: async (opts) => {
      provider.calls.push(opts);
      return { id: 'cp-payout-1' };
    },
  };
  installStubs();
});

afterEach(() => {
  for (const k of [FIREBASE_CONFIG, PROVIDER_FACTORY, CLICKPESA, WALLET_SERVICE]) {
    delete require.cache[k];
  }
  locks.restoreLocks();
});

/* ------------------------------------------------------------------ */
/* Tests                                                               */
/* ------------------------------------------------------------------ */

test('a processing withdrawal is never re-dispatched to the gateway', async () => {
  locks.stubLocksAlwaysAvailable();
  await db.runTransaction(async (t) => {
    await t.update(db.collection('withdrawals').doc(WITHDRAWAL_ID), {
      status: 'processing',
      providerPayoutId: 'cp-payout-1',
    });
  });

  const result = await loadWalletService().processWithdrawal({ withdrawalId: WITHDRAWAL_ID });

  // The bug: `processing` was in the retryable set, so every sweep re-sent the
  // payout. Confirmation is the only thing allowed to move it now.
  assert.equal(provider.calls.length, 0, 'initiatePayout must not be called for a payout already accepted');
  assert.equal(result.status, 'processing');
});

test('a disbursing withdrawal whose payout the gateway already has is not re-sent', async () => {
  locks.stubLocksAlwaysAvailable();
  await db.runTransaction(async (t) => {
    await t.update(db.collection('withdrawals').doc(WITHDRAWAL_ID), { status: 'disbursing' });
  });
  gatewayPayouts = () => ({ data: [{ id: 'cp-payout-99', orderReference: `W${WITHDRAWAL_ID}`, status: 'SUCCESS' }] });

  const result = await loadWalletService().processWithdrawal({ withdrawalId: WITHDRAWAL_ID });

  assert.equal(provider.calls.length, 0, 'the gateway already has this payout');
  assert.equal(result.status, 'processing');
  assert.equal(result.providerPayoutId, 'cp-payout-99');
});

test('an unreachable gateway is treated as "maybe sent", never as safe to resend', async () => {
  locks.stubLocksAlwaysAvailable();
  await db.runTransaction(async (t) => {
    await t.update(db.collection('withdrawals').doc(WITHDRAWAL_ID), { status: 'disbursing' });
  });
  gatewayPayouts = () => { throw new Error('gateway timeout'); };

  await assert.rejects(
    () => loadWalletService().processWithdrawal({ withdrawalId: WITHDRAWAL_ID }),
    /PAYOUT_STATE_UNKNOWN/,
  );

  assert.equal(provider.calls.length, 0, 'must not send money on an unknown gateway state');
  const row = db.dump('withdrawals')[WITHDRAWAL_ID];
  assert.equal(row.needsManualReview, true);
  assert.equal(row.needsManualReviewReason, 'gateway_state_unknown');
  // The reservation is untouched: the payout may still be in flight.
  assert.equal(db.dump('wallets')[SELLER].availableBalance, 90000);
});

test('a disbursing withdrawal the gateway has never seen is dispatched', async () => {
  locks.stubLocksAlwaysAvailable();
  await db.runTransaction(async (t) => {
    await t.update(db.collection('withdrawals').doc(WITHDRAWAL_ID), { status: 'disbursing' });
  });
  gatewayPayouts = () => ({ data: [] });

  const result = await loadWalletService().processWithdrawal({ withdrawalId: WITHDRAWAL_ID });

  assert.equal(provider.calls.length, 1);
  assert.equal(provider.calls[0].orderReference, `W${WITHDRAWAL_ID}`);
  assert.equal(result.status, 'processing');
  assert.equal(result.providerPayoutId, 'cp-payout-1');
  // serializeWithdrawal is a whitelist, so the marker is asserted on the raw row.
  assert.ok(db.dump('withdrawals')[WITHDRAWAL_ID].payoutAttemptedAt);
});

test('a reserved withdrawal dispatches exactly once and stamps the attempt', async () => {
  locks.stubLocksAlwaysAvailable();
  const svc = loadWalletService();

  const first = await svc.processWithdrawal({ withdrawalId: WITHDRAWAL_ID });
  assert.equal(first.status, 'processing');
  assert.equal(provider.calls.length, 1);
  assert.ok(db.dump('withdrawals')[WITHDRAWAL_ID].payoutAttemptedAt);

  // A second sweep pass must be a no-op, not a second transfer.
  await svc.processWithdrawal({ withdrawalId: WITHDRAWAL_ID });
  assert.equal(provider.calls.length, 1, 'a second sweep must not send the payout again');
});

test('a definitive gateway rejection fails the withdrawal and refunds it in one commit', async () => {
  locks.stubLocksAlwaysAvailable();
  provider.initiatePayout = async () => {
    const err = new Error('INVALID_RECIPIENT');
    err.definitive = true;
    throw err;
  };

  await assert.rejects(() => loadWalletService().processWithdrawal({ withdrawalId: WITHDRAWAL_ID }));

  const row = db.dump('withdrawals')[WITHDRAWAL_ID];
  assert.equal(row.status, 'failed');
  assert.equal(row.failureReason, 'INVALID_RECIPIENT');

  // 90_000 + 50_000: the seller keeps the money a failed payout never sent.
  assert.equal(db.dump('wallets')[SELLER].availableBalance, 140000);

  const ledger = db.dump('walletTransactions');
  const refund = Object.entries(ledger).find(([, v]) => v.type === 'WITHDRAWAL_REFUNDED');
  assert.ok(refund, 'the refund must be journalled');
  assert.equal(refund[1].amount, AMOUNT);
  assert.equal(refund[1].idempotencyKey, refund[0]);
});

test('the refund is never applied twice', async () => {
  locks.stubLocksAlwaysAvailable();
  provider.initiatePayout = async () => {
    const err = new Error('INVALID_RECIPIENT');
    err.definitive = true;
    throw err;
  };
  const svc = loadWalletService();

  await assert.rejects(() => svc.processWithdrawal({ withdrawalId: WITHDRAWAL_ID }));
  assert.equal(db.dump('wallets')[SELLER].availableBalance, 140000);

  // A replayed failure (webhook redelivery, retried sweep) hits the terminal
  // state and returns instead of throwing — and must not credit again.
  const replay = await svc.processWithdrawal({ withdrawalId: WITHDRAWAL_ID });
  assert.equal(replay.status, 'failed');
  await svc.processWithdrawal({ withdrawalId: WITHDRAWAL_ID });

  assert.equal(db.dump('wallets')[SELLER].availableBalance, 140000, 'balance must not be credited repeatedly');
  const refunds = Object.values(db.dump('walletTransactions')).filter((v) => v.type === 'WITHDRAWAL_REFUNDED');
  assert.equal(refunds.length, 1, 'exactly one refund ledger entry');
});

test('a payout cannot be dispatched while the lock is unavailable', async () => {
  locks.stubLocksFailing('redis_unavailable');

  await assert.rejects(
    () => loadWalletService().processWithdrawal({ withdrawalId: WITHDRAWAL_ID }),
    /LOCK|Could not acquire lock/,
  );

  // Redis being down must stop the payout, not silently allow it.
  assert.equal(provider.calls.length, 0);
  assert.equal(db.dump('withdrawals')[WITHDRAWAL_ID].status, 'reserved');
});