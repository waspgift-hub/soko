// Hermetic tests for the wallet-deposit gap fix:
//   1) POST /api/wallet/deposit — the feature-compat port of
//      server/index.js:7984 (USSD push + BillPay control number)
//   2) confirmLegacyDeposit — the v1 webhook `dep` branch that credits the
//      Firestore user walletBalance and finalizes deposits/{ref}
// Third-party modules (firebase-admin, clickpesa, config, notify, cache) are
// stubbed in require.cache; the Firestore facade is an in-memory fake.
const { describe, it, before, after, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const express = require('express');

const UID = 'walletOwner1';

const FIREBASE_ADMIN = require.resolve('firebase-admin');
const CONFIG = require.resolve('../src/config');
const CONFIG_FIREBASE = require.resolve('../src/config/firebase');
const NOTIFY = require.resolve('../src/modules/legacy-compat/notify');
const CACHE = require.resolve('../cache');
const CLICKPESA = require.resolve('../clickpesa');
const FEATURE_COMPAT = require.resolve('../src/modules/legacy-compat/feature-compat');
const DEPOSIT_CONFIRM = require.resolve('../src/modules/payments/legacy-deposit-confirm');

const TS = '::TS';
const WEBHOOK_URL = 'https://cp-webhook.test/v1';

const fakeAdmin = {
  firestore: {
    FieldValue: {
      serverTimestamp: () => TS,
      increment: (n) => ({ __op: 'increment', amount: n }),
    },
  },
  auth: () => ({
    verifyIdToken: async (token) => {
      if (token === 'token-good') return { uid: UID };
      throw new Error('Invalid token');
    },
  }),
};

function fakeDb() {
  const collections = new Map();
  const db = {
    _data: collections,
    collection(name) {
      if (!collections.has(name)) collections.set(name, new Map());
      const col = collections.get(name);
      return {
        doc(id) {
          return {
            get: async () => ({ exists: col.has(id), data: () => col.get(id) }),
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

function fakeCache() {
  return {
    get: async () => undefined,
    set: async () => undefined,
    del: async () => undefined,
    delPattern: async () => undefined,
    getOrCompute: async (k, fn) => fn(),
    setRedisClient: () => undefined,
  };
}

function clickpesaMock() {
  const mock = {
    calls: { collect: [], billPay: [] },
    billPayResponse: { success: true, id: 'cpb-77', billPayNumber: '9911223344' },
  };
  mock.clickpesaCollect = async (opts) => {
    mock.calls.collect.push(opts);
    return { id: 'cp-ref-1' };
  };
  mock.clickpesaPaymentStatus = async () => ({ success: true, status: 'SUCCESS' });
  mock.clickpesaCreateBillPayOrder = async (opts) => {
    mock.calls.billPay.push(opts);
    return mock.billPayResponse;
  };
  mock.calcGatewayFee = (method, amount) => (method === 'billpay' ? Math.round(amount * 0.01) : 0);
  mock.ALL_PAYMENT_METHODS = [];
  return mock;
}

const clickpesa = clickpesaMock();

function installStubs() {
  const stub = (path, exports) => {
    require.cache[path] = { id: path, filename: path, loaded: true, exports };
  };
  stub(FIREBASE_ADMIN, fakeAdmin);
  stub(CONFIG, {
    nodeEnv: 'test',
    clickpesa: { collectionWebhookUrl: WEBHOOK_URL },
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
  stub(CACHE, fakeCache());
  stub(CLICKPESA, clickpesa);
}

const MODULE_KEYS = [FEATURE_COMPAT, DEPOSIT_CONFIRM];
afterEach(() => {
  // Only our modules re-load; the dependency stubs stay installed so nothing
  // ever touches the real firebase/clickpesa during this file.
  for (const k of MODULE_KEYS) delete require.cache[k];
});

let server;
let base;

function startApp(router) {
  const app = express();
  app.use(express.json());
  app.use('/api', router);
  return new Promise((resolve) => {
    const srv = app.listen(0, '127.0.0.1', () => {
      resolve({ server: srv, base: `http://127.0.0.1:${srv.address().port}` });
    });
  });
}

async function postJson(path, body, headers = {}) {
  const res = await fetch(`${base}${path}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', ...headers },
    body: JSON.stringify(body),
  });
  return { status: res.status, json: await res.json() };
}

before(async () => {
  installStubs();
  delete require.cache[FEATURE_COMPAT];
  const router = require(FEATURE_COMPAT)({ admin: fakeAdmin, db });
  ({ server, base } = await startApp(router));
});

after(async () => {
  if (server) await new Promise((resolve) => server.close(resolve));
});

function authHeaders() {
  return { authorization: 'Bearer token-good' };
}

describe('POST /api/wallet/deposit', () => {
  it('rejects requests without a token', async () => {
    const { status, json } = await postJson('/api/wallet/deposit', { userId: UID, amount: 1000, phone: '0754123456' });
    assert.equal(status, 401);
    assert.equal(json.error, 'Unauthorized');
  });

  it('rejects invalid tokens', async () => {
    const { status } = await postJson('/api/wallet/deposit', { userId: UID, amount: 1000, phone: '0754123456' }, { authorization: 'Bearer nope' });
    assert.equal(status, 403);
  });

  it('rejects a userId that does not match the token', async () => {
    const { status, json } = await postJson('/api/wallet/deposit', { userId: 'someoneElse', amount: 1000, phone: '0754123456' }, authHeaders());
    assert.equal(status, 403);
    assert.equal(json.error, 'userId mismatch');
  });

  it('requires amount and phone', async () => {
    const noAmount = await postJson('/api/wallet/deposit', { userId: UID, phone: '0754123456' }, authHeaders());
    assert.equal(noAmount.status, 400);
    assert.equal(noAmount.json.error, 'amount is required');

    const noPhone = await postJson('/api/wallet/deposit', { userId: UID, amount: 1000 }, authHeaders());
    assert.equal(noPhone.status, 400);
    assert.equal(noPhone.json.error, 'phone is required');
  });

  it('creates a pending deposit doc and fires the USSD push', async () => {
    const before = (db._data.get('deposits')?.size || 0);
    const { status, json } = await postJson('/api/wallet/deposit', {
      userId: UID, phone: '0754 123 456', amount: 2500, method: 'ussd',
    }, authHeaders());

    assert.equal(status, 200);
    assert.equal(json.success, true);
    assert.equal(json.method, 'ussd');
    assert.match(json.depositRef, /^dep/);

    const docs = (db._data.get('deposits')?.size || 0);
    assert.equal(docs, before + 1);

    const dep = readDoc('deposits', json.depositRef);
    assert.equal(dep.userId, UID);
    assert.equal(dep.phone, '255754123456');
    assert.equal(dep.amount, 2500);
    assert.equal(dep.processingFee, 0);
    assert.equal(dep.totalCharge, 2500);
    assert.equal(dep.status, 'pending');
    assert.equal(dep.paymentMethod, 'ClickPesa');
    assert.ok(dep.createdAt instanceof Date);

    await new Promise((resolve) => setTimeout(resolve, 0));
    const collect = clickpesa.calls.collect[clickpesa.calls.collect.length - 1];
    assert.equal(collect.amount, 2500);
    assert.equal(collect.orderReference, json.depositRef);
    assert.equal(collect.phoneNumber, '255754123456');
    assert.equal(collect.callbackUrl, WEBHOOK_URL);
    assert.equal(readDoc('deposits', json.depositRef).clickpesaReference, 'cp-ref-1');
    assert.equal(readDoc('deposits', json.depositRef).ussdSent, true);
  });

  it('normalizes an already-255 phone and strips non-digits', async () => {
    const r1 = await postJson('/api/wallet/deposit', {
      userId: UID, phone: '255712345678', amount: 1000,
    }, authHeaders());
    const r2 = await postJson('/api/wallet/deposit', {
      userId: UID, phone: '+255 (754) 123-4567', amount: 1000,
    }, authHeaders());
    assert.equal(readDoc('deposits', r1.json.depositRef).phone, '255712345678');
    assert.equal(readDoc('deposits', r2.json.depositRef).phone, '2557541234567');
  });

  it('returns a BillPay control number and persists fee + reference', async () => {
    const { status, json } = await postJson('/api/wallet/deposit', {
      userId: UID, phone: '0754123456', amount: 2000, method: 'billpay',
    }, authHeaders());

    assert.equal(status, 200);
    assert.equal(json.success, true);
    assert.equal(json.method, 'billpay');
    assert.equal(json.billPayNumber, '9911223344');
    assert.equal(json.clickpesaId, 'cpb-77');
    assert.equal(json.gatewayFee, 20);
    assert.equal(json.totalCharge, 2020);

    const dep = readDoc('deposits', json.depositRef);
    assert.equal(dep.status, 'pending');
    assert.equal(dep.paymentMethod, 'BillPay');
    assert.equal(dep.amount, 2000);
    assert.equal(dep.gatewayFee, 20);
    assert.equal(dep.totalCharge, 2020);
    assert.equal(dep.billPayNumber, '9911223344');
    assert.equal(dep.clickpesaReference, 'cpb-77');
  });

  it('wraps a BillPay API failure as 502', async () => {
    const original = clickpesa.billPayResponse;
    clickpesa.billPayResponse = { success: false, error: 'cannot be processed' };
    try {
      const { status, json } = await postJson('/api/wallet/deposit', {
        userId: UID, phone: '0754123456', amount: 500, method: 'billpay',
      }, authHeaders());
      assert.equal(status, 502);
      assert.match(json.error, /BillPay error/);
    } finally {
      clickpesa.billPayResponse = original;
    }
  });
});

describe('confirmLegacyDeposit (webhook dep_ branch)', () => {
  let confirm;
  before(() => {
    delete require.cache[DEPOSIT_CONFIRM];
    confirm = require(DEPOSIT_CONFIRM).confirmLegacyDeposit;
  });

  it('credits the wallet balance on completion', async () => {
    db._data.set('deposits', new Map([['dep1', { userId: UID, amount: 5000, status: 'pending' }]]));
    db._data.set('users', new Map([[UID, { walletBalance: 1000 }]]));

    const result = await confirm({ orderReference: 'dep1', status: 'completed', providerPaymentId: 'cp-x' });
    assert.equal(result.status, 'COMPLETED');
    assert.equal(readDoc('deposits', 'dep1').status, 'completed');
    assert.equal(readDoc('deposits', 'dep1').clickpesaReference, 'cp-x');
    assert.equal(readDoc('users', UID).walletBalance, 6000);
  });

  it('is idempotent — a replayed completion never credits twice', async () => {
    const result = await confirm({ orderReference: 'dep1', status: 'completed', providerPaymentId: 'cp-x2' });
    assert.equal(result.status, 'SKIPPED_ALREADY_FINAL');
    assert.equal(readDoc('users', UID).walletBalance, 6000);
  });

  it('marks a deposit failed with the reason', async () => {
    db._data.set('deposits', new Map([['dep2', { userId: UID, amount: 1500, status: 'pending' }]]));

    const result = await confirm({ orderReference: 'dep2', status: 'failed', failureReason: 'User declined' });
    assert.equal(result.status, 'FAILED');
    assert.equal(readDoc('deposits', 'dep2').status, 'failed');
    assert.equal(readDoc('deposits', 'dep2').failureReason, 'User declined');
  });

  it('no-ops for an unknown reference', async () => {
    const result = await confirm({ orderReference: 'dep-missing', status: 'completed' });
    assert.equal(result.status, 'NOOP_NOT_FOUND');
  });

  it('skips non-terminal webhook checkpoints', async () => {
    db._data.set('deposits', new Map([['dep3', { userId: UID, amount: 900, status: 'pending' }]]));
    const result = await confirm({ orderReference: 'dep3', status: 'pending' });
    assert.equal(result.status, 'SKIPPED_UNSUPPORTED');
    assert.equal(readDoc('deposits', 'dep3').status, 'pending');
  });
});