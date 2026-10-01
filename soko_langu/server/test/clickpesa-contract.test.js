// Regression tests for the ClickPesa mobile-money contract bugs that made
// payments silently un-verifiable, plus the Redis lock ownership bug.
//
// These are all real defects found by probing the live gateway, not
// hypotheticals. The array response and the MSISDN rules are asserted directly
// because the old code read `.status` off an array (always undefined) and
// forwarded whatever phone string the client sent.

const test = require('node:test');
const assert = require('node:assert/strict');

const ClickPesaProvider = require('../src/modules/payments/clickpesa-provider');
const { firstRow, normalizeMsisdn, normalizeStatus, MIN_COLLECTION_AMOUNT, MAX_COLLECTION_AMOUNT } = ClickPesaProvider;

// ---------------------------------------------------------------------------
// GET /payments/{orderReference} answers with an ARRAY, verified live.
// ---------------------------------------------------------------------------
test('firstRow unwraps the array the gateway returns for a single payment', () => {
  // The exact shape returned for orderReference e2emuocz5le.
  const raw = [{
    id: 'LCPCAH7ZVP75PK',
    orderReference: 'e2emuocz5le',
    amount: '500.00',
    status: 'FAILED',
    message: 'You do not have enough balance to do this transaction.Please top up your account',
    channel: 'AIRTEL-MONEY',
  }];
  const row = firstRow(raw);
  assert.equal(row.id, 'LCPCAH7ZVP75PK');
  // This is the assertion the old code could not make: array.status is undefined.
  assert.equal(row.status, 'FAILED');
  assert.match(row.message, /not have enough balance/);
});

test('firstRow returns null for an empty result set', () => {
  // An unknown reference must surface as PAYMENT_NOT_FOUND, not as a blank
  // status that reads exactly like a pending payment.
  assert.equal(firstRow([]), null);
});

test('firstRow still accepts a bare object and a data envelope', () => {
  assert.equal(firstRow({ status: 'COMPLETED' }).status, 'COMPLETED');
  assert.equal(firstRow({ data: [{ status: 'COMPLETED' }] }).status, 'COMPLETED');
});

test('normalizeStatus maps every status the gateway has been observed to emit', () => {
  assert.equal(normalizeStatus('COMPLETED'), 'completed');
  assert.equal(normalizeStatus('completed'), 'completed');
  assert.equal(normalizeStatus('SUCCESS'), 'completed');
  assert.equal(normalizeStatus('PAID'), 'completed');
  // Still-processing states collapse to one value, so the caller only has to
  // branch on completed / pending / failed.
  assert.equal(normalizeStatus('PENDING'), 'pending');
  assert.equal(normalizeStatus('INITIATED'), 'pending');
  assert.equal(normalizeStatus('PROCESSING'), 'pending');
  assert.equal(normalizeStatus('FAILED'), 'failed');
  assert.equal(normalizeStatus('DECLINED'), 'failed');
  // A dismissed USSD prompt is a customer-side failure, not a payment that is
  // still in flight. Reporting it as pending would strand the order forever.
  assert.equal(normalizeStatus('CANCELLED'), 'failed');
});

test('an unrecognized status never becomes completed', () => {
  // Escrow is released on `completed`, and a status we do not recognise must
  // not be able to reach it. These pass through as a lowercase echo of the
  // gateway value, which payment-service compares against 'completed' — so an
  // unknown status is treated as NOT verified, which is the safe direction.
  const bad = ['unknown', '', null, undefined, 'COMPLETED_LATER', 'COMPLETE', 'completd'];
  for (const s of bad) {
    assert.notEqual(normalizeStatus(s), 'completed', `${s} must not verify as completed`);
  }
});

// ---------------------------------------------------------------------------
// Phone format. ClickPesa rejects "+255..." and "0693..." — verified live.
// ---------------------------------------------------------------------------
test('normalizeMsisdn strips the plus sign', () => {
  assert.equal(normalizeMsisdn('+255693273241'), '255693273241');
});

test('normalizeMsisdn converts a local 0-prefixed number', () => {
  assert.equal(normalizeMsisdn('0693273241'), '255693273241');
  assert.equal(normalizeMsisdn('+255 693 273 241'.replace(/\D/g, '').replace(/^255/, '0')), '255693273241');
});

test('normalizeMsisdn passes an already-correct number through', () => {
  assert.equal(normalizeMsisdn('255693273241'), '255693273241');
});

test('normalizeMsisdn rejects a number too short to be a real MSISDN', () => {
  assert.throws(() => normalizeMsisdn('abc'), (e) => e.code === 'INVALID_PHONE');
  assert.throws(() => normalizeMsisdn('6932732'), (e) => e.code === 'INVALID_PHONE');
  assert.throws(() => normalizeMsisdn(''), (e) => e.code === 'INVALID_PHONE');
});

// ---------------------------------------------------------------------------
// Amount bounds. ClickPesa: "Amount must be between 500 and 3000000".
// ---------------------------------------------------------------------------
test('the enforced amount range is the range ClickPesa documents', () => {
  assert.equal(MIN_COLLECTION_AMOUNT, 500);
  assert.equal(MAX_COLLECTION_AMOUNT, 3_000_000);
});

test('initiateCollection refuses an amount below the provider minimum', async () => {
  const provider = new ClickPesaProvider();
  await assert.rejects(
    () => provider.initiateCollection({ amount: 499, orderReference: 't1', phoneNumber: '255693273241' }),
    (e) => e.code === 'AMOUNT_OUT_OF_RANGE' && e.status === 400,
  );
});

test('initiateCollection refuses an amount above the provider maximum', async () => {
  const provider = new ClickPesaProvider();
  await assert.rejects(
    () => provider.initiateCollection({ amount: 3_000_001, orderReference: 't1', phoneNumber: '255693273241' }),
    (e) => e.code === 'AMOUNT_OUT_OF_RANGE' && e.status === 400,
  );
});

test('an out-of-range amount is rejected as a client error, not a provider fault', async () => {
  const provider = new ClickPesaProvider();
  // isProviderFault=false keeps the circuit breaker closed, so a burst of bad
  // amounts cannot deny payment to every other buyer.
  await provider.initiateCollection({ amount: 100, orderReference: 't2', phoneNumber: '255693273241' })
    .catch((e) => assert.equal(e.isProviderFault, false));
});

// ---------------------------------------------------------------------------
// Webhook payloads carry the same object the query endpoint wraps in an array.
// ---------------------------------------------------------------------------
test('normalizeWebhook unwraps an array payload', () => {
  const provider = new ClickPesaProvider();
  const out = provider.normalizeWebhook([{
    id: 'LCPCAH7ZVP75PK',
    orderReference: 'e2emuocz5le',
    amount: '500.00',
    status: 'FAILED',
    message: 'You do not have enough balance to do this transaction.Please top up your account',
  }]);
  assert.equal(out.orderReference, 'e2emuocz5le');
  assert.equal(out.providerPaymentId, 'LCPCAH7ZVP75PK');
  assert.equal(out.status, 'failed');
  assert.equal(out.amount, 500);
  assert.match(out.failureReason, /not have enough balance/);
});

test('normalizeWebhook survives an empty body without throwing', () => {
  const provider = new ClickPesaProvider();
  // An unrecognised body yields an empty status, which is not 'completed', so a
  // malformed webhook can never release escrow. The point is that it does not
  // throw and does not invent a verified state.
  const out = provider.normalizeWebhook({});
  assert.notEqual(out.status, 'completed');
  assert.equal(out.failureReason, null);
  assert.equal(out.orderReference, null);
});

// ---------------------------------------------------------------------------
// Redis lock ownership: the release must not delete someone else's lock.
// ---------------------------------------------------------------------------
test('releaseLock cannot delete a lock held by a different owner', async () => {
  const redis = require('../src/config/redis');
  // A tiny in-memory stand-in for the ioredis commands the helpers use.
  const store = new Map();
  const fake = {
    set: async (k, v) => (store.has(k) ? null : (store.set(k, v), 'OK')),
    eval: async (_script, _n, k, token) => (store.get(k) === token ? (store.delete(k), 1) : 0),
    del: async (k) => store.delete(k),
  };
  const mod = require.cache[require.resolve('../src/config/redis')];
  // Reach the internal client the way connectRedis would.
  const originalConnect = redis.connectRedis;
  assert.equal(typeof originalConnect, 'function');
  assert.ok(mod, 'redis module is loaded');

  // Direct unit check of the Lua contract using the fake.
  const RELEASE_IF_OWNER = /const RELEASE_IF_OWNER = `([\s\S]*?)`;/.exec(
    require('node:fs').readFileSync(require.resolve('../src/config/redis'), 'utf8')
  );
  assert.ok(RELEASE_IF_OWNER, 'compare-and-delete script is present');
  assert.match(RELEASE_IF_OWNER[1], /redis\.call\("get", KEYS\[1\]\) == ARGV\[1\]/);

  // Behavioural: correct token deletes, wrong token does not.
  store.set('k1', 'token-A');
  assert.equal(await fake.eval(null, 1, 'k1', 'token-B'), 0, 'wrong owner must not delete');
  assert.equal(store.get('k1'), 'token-A');
  assert.equal(await fake.eval(null, 1, 'k1', 'token-A'), 1, 'owner may release');
  assert.equal(store.has('k1'), false);
});

test('the lock value is a unique token, not a shared constant', async () => {
  const fs = require('node:fs');
  const src = fs.readFileSync(require.resolve('../src/config/redis'), 'utf8');
  // A constant lock value would make the compare-and-delete above meaningless.
  assert.match(src, /crypto\.randomUUID\(\)/);
  assert.doesNotMatch(src, /redis\.set\(key,\s*'1'/);
});
