// Hermetic tests for confirmLegacyTransaction, the v1 webhook branch that
// finalizes legacy `transactions`-collection money: product boosts (type
// 'boost') and the one-time KYC verification fee (type 'kyc_fee'). Deps are
// stubbed in require.cache; Firestore is an in-memory fake with batch support.
const { describe, it, before, after, afterEach } = require('node:test');
const assert = require('node:assert/strict');

const UID = 'sellerTx1';

const FIREBASE_ADMIN = require.resolve('firebase-admin');
const CONFIG = require.resolve('../src/config');
const CONFIG_FIREBASE = require.resolve('../src/config/firebase');
const NOTIFY = require.resolve('../src/modules/legacy-compat/notify');
const CACHE = require.resolve('../cache');
const CLICKPESA = require.resolve('../clickpesa');
const LEACY_TX_CONFIRM = require.resolve('../src/modules/payments/legacy-transaction-confirm');
const DEPOSIT_CONFIRM = require.resolve('../src/modules/payments/legacy-deposit-confirm');

const TS = '::TS';
const fakeAdmin = {
  firestore: {
    FieldValue: {
      serverTimestamp: () => TS,
      increment: (n) => ({ __op: 'increment', amount: n }),
    },
    Timestamp: {
      fromDate: (d) => ({ seconds: Math.floor(d.getTime() / 1000), nanoseconds: 0 }),
    },
  },
  auth: () => ({
    verifyIdToken: async () => ({ uid: UID }),
  }),
};

function fakeDb() {
  const collections = new Map();
  const db = {
    _data: collections,
    _failBatchNext: false,
    collection(name) {
      if (!collections.has(name)) collections.set(name, new Map());
      const col = collections.get(name);
      // Attach the ref to every snapshot so batch/update semantics work like
      // the real Firestore DocumentSnapshot.ref does.
      const docRef = (id) => {
        const read = {
          get: async () => ({ exists: col.has(id), data: () => col.get(id), ref: read }),
          set: async (d) => {
            const normalized = { ...d };
            for (const [k, v] of Object.entries(normalized)) {
              if (v === TS) normalized[k] = new Date(0);
              if (v && v.__op === 'increment') normalized[k] = v.amount;
            }
            col.set(id, normalized);
          },
          update: async (d) => {
            if (!col.has(id)) throw new Error(`doc ${id} not found`);
            const cur = { ...col.get(id) };
            for (const [k, v] of Object.entries(d)) {
              if (v && v.__op === 'increment') {
                cur[k] = (Number(cur[k]) || 0) + v.amount;
              } else if (v === TS) {
                cur[k] = new Date(0);
              } else {
                cur[k] = v;
              }
            }
            col.set(id, cur);
          },
          delete: async () => { col.delete(id); },
        };
        return read;
      };
      return {
        doc: docRef,
        add: async (data) => {
          const id = `${name}_${(db.__addSeq = (db.__addSeq || 0) + 1)}`;
          col.set(id, { ...data });
          return { id };
        },
      };
    },
    batch() {
      const ops = [];
      return {
        update(ref, data) { ops.push({ ref, data }); },
        commit: async () => {
          if (db._failBatchNext) {
            db._failBatchNext = false;
            throw new Error('BATCH_FAIL');
          }
          for (const op of ops) await op.ref.update(op.data);
        },
      };
    },
  };
  return db;
}

const db = fakeDb();

function readDoc(col, id) {
  const m = db._data.get(col);
  return m ? m.get(id) : undefined;
}

function seed(col, id, data) {
  if (!db._data.has(col)) db._data.set(col, new Map());
  db._data.get(col).set(id, { ...data });
}

function stub(path, exports) {
  require.cache[path] = { id: path, filename: path, loaded: true, exports };
}

before(() => {
  stub(FIREBASE_ADMIN, fakeAdmin);
  stub(CONFIG, {
    nodeEnv: 'test',
    clickpesa: { collectionWebhookUrl: 'https://cp-webhook.test/v1' },
    security: { adminSecret: 's3cret' },
    business: { platformCommissionPercent: 10 },
    sms: {},
    oneSignal: {},
  });
  stub(CONFIG_FIREBASE, {
    getFirebaseAuth: () => fakeAdmin.auth(),
    getFirebaseFirestore: () => db,
  });
  stub(NOTIFY, {
    sendOneSignalNotification: async () => undefined,
    notifyAdmins: async () => undefined,
  });
  stub(CACHE, {
    get: async () => undefined,
    set: async () => undefined,
    del: async () => undefined,
    delPattern: async () => undefined,
    getOrCompute: async (k, fn) => fn(),
    setRedisClient: () => undefined,
  });
  stub(CLICKPESA, {
    clickpesaCollect: async () => ({ id: 'cp' }),
    clickpesaPaymentStatus: async () => ({ success: true, status: 'SUCCESS' }),
    clickpesaCreateBillPayOrder: async () => ({ success: true, billPayNumber: '1' }),
    calcGatewayFee: () => 0,
    ALL_PAYMENT_METHODS: [],
  });

  delete require.cache[LEACY_TX_CONFIRM];
});

after(() => {
  for (const k of [FIREBASE_ADMIN, CONFIG, CONFIG_FIREBASE, NOTIFY, CACHE, CLICKPESA, LEACY_TX_CONFIRM, DEPOSIT_CONFIRM]) {
    delete require.cache[k];
  }
});

let confirm;
before(() => {
  confirm = require(LEACY_TX_CONFIRM).confirmLegacyTransaction;
});

afterEach(() => {
  db._failBatchNext = false;
});

describe('confirmLegacyTransaction — boost', () => {
  it('atomically completes the boost and activates the product', async () => {
    seed('transactions', 'boost1', {
      type: 'boost', userId: UID, productId: 'prodA', tier: 'silver', amount: 3000, status: 'pending', buyerPhone: '255712345678',
    });
    seed('products', 'prodA', { name: 'Tumbler', isBoosted: false, boostedUntil: null });

    const result = await confirm({ orderReference: 'boost1', status: 'completed', providerPaymentId: 'cp-z' });

    assert.equal(result.status, 'COMPLETED');
    assert.equal(result.type, 'boost');

    const tx = readDoc('transactions', 'boost1');
    assert.equal(tx.status, 'completed');
    assert.equal(tx.clickpesaReference, 'cp-z');

    const product = readDoc('products', 'prodA');
    assert.equal(product.isBoosted, true);
    assert.equal(product.boostTier, 'silver');
    assert.equal(product.isFeatured, true);
    assert.ok(product.boostedUntil.seconds > Date.now() / 1000);
    assert.equal(product.featuredUntil.seconds, product.boostedUntil.seconds);

    const revenue = [...db._data.get('revenue_transactions').values()][0];
    assert.equal(revenue.type, 'boost');
    assert.equal(revenue.transactionId, 'boost1');
    assert.equal(revenue.amount, 3000);
  });

  it('is idempotent — a replayed completion never re-boosts', async () => {
    const beforeBoostUntil = readDoc('products', 'prodA').boostedUntil.seconds;
    const result = await confirm({ orderReference: 'boost1', status: 'completed', providerPaymentId: 'cp-z2' });
    assert.equal(result.status, 'SKIPPED_ALREADY_FINAL');
    assert.equal(readDoc('products', 'prodA').boostedUntil.seconds, beforeBoostUntil);
  });

  it('leaves the transaction pending when the atomic batch fails', async () => {
    seed('transactions', 'boost2', {
      type: 'boost', userId: UID, productId: 'prodB', tier: 'bronze', amount: 1500, status: 'pending',
    });
    seed('products', 'prodB', { name: 'Chai', isBoosted: false });
    db._failBatchNext = true;

    const result = await confirm({ orderReference: 'boost2', status: 'completed' });
    assert.equal(result.status, 'COMPLETED_BATCH_FAILED');
    assert.equal(readDoc('transactions', 'boost2').status, 'pending');
    assert.notEqual(readDoc('products', 'prodB').isBoosted, true);
  });

  it('marks the boost failed with the reason', async () => {
    seed('transactions', 'boost3', {
      type: 'boost', userId: UID, productId: 'prodC', tier: 'bronze', amount: 1500, status: 'pending',
    });
    const result = await confirm({ orderReference: 'boost3', status: 'failed', failureReason: 'User declined' });
    assert.equal(result.status, 'FAILED');
    assert.equal(readDoc('transactions', 'boost3').status, 'failed');
    assert.equal(readDoc('transactions', 'boost3').failureReason, 'User declined');
  });

  it('recovers a failed boost when ClickPesa later confirms success', async () => {
    seed('products', 'prodC', { name: 'Chai', isBoosted: false, boostedUntil: null });
    const result = await confirm({ orderReference: 'boost3', status: 'completed', providerPaymentId: 'cp-recovered' });
    assert.equal(result.status, 'COMPLETED');
    assert.equal(readDoc('transactions', 'boost3').status, 'completed');
    assert.equal(readDoc('transactions', 'boost3').clickpesaReference, 'cp-recovered');
    assert.equal(readDoc('products', 'prodC').isBoosted, true);
  });
});

describe('confirmLegacyTransaction — KYC fee', () => {
  it('completes the fee receipt', async () => {
    seed('transactions', 'kyc1', {
      type: 'kyc_fee', userId: UID, amount: 15000, status: 'pending', buyerPhone: '255712345678',
    });
    const result = await confirm({ orderReference: 'kyc1', status: 'completed', providerPaymentId: 'cp-k' });
    assert.equal(result.status, 'COMPLETED');
    assert.equal(result.type, 'kyc_fee');
    const tx = readDoc('transactions', 'kyc1');
    assert.equal(tx.status, 'completed');
    assert.equal(tx.clickpesaReference, 'cp-k');
    const revenue = [...db._data.get('revenue_transactions').values()].find((r) => r.transactionId === 'kyc1');
    assert.equal(revenue.type, 'kyc_fee');
    assert.equal(revenue.amount, 15000);
  });

  it('is idempotent', async () => {
    const result = await confirm({ orderReference: 'kyc1', status: 'completed' });
    assert.equal(result.status, 'SKIPPED_ALREADY_FINAL');
  });
});

describe('confirmLegacyTransaction — guards', () => {
  it('no-ops for an unknown reference', async () => {
    const result = await confirm({ orderReference: 'boost-missing', status: 'completed' });
    assert.equal(result.status, 'NOOP_NOT_FOUND');
  });

  it('skips non-terminal webhook checkpoints', async () => {
    seed('transactions', 'boost5', {
      type: 'boost', userId: UID, status: 'pending', tier: 'bronze',
    });
    const result = await confirm({ orderReference: 'boost5', status: 'pending' });
    assert.equal(result.status, 'SKIPPED_UNSUPPORTED');
    assert.equal(readDoc('transactions', 'boost5').status, 'pending');
  });

  it('skips transaction types that belong to the escrow path', async () => {
    seed('transactions', 'other1', { type: 'purchase', status: 'pending' });
    const result = await confirm({ orderReference: 'other1', status: 'completed' });
    assert.equal(result.status, 'SKIPPED_UNKNOWN_TYPE');
    assert.equal(readDoc('transactions', 'other1').status, 'pending');
  });
});