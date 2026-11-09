// Regression tests for the AzamPay mobile-money contract.
//
// These assert the provider-shaping logic (array unwrapping, MSISDN rules,
// status mapping, amount bounds) that the rest of the system depends on. They
// do not call the gateway; they run hermetically.

const test = require('node:test');
const assert = require('node:assert/strict');

const AzamPayProvider = require('../src/modules/payments/azampay-provider');
const { firstRow, normalizeMsisdn, normalizeStatus, MIN_COLLECTION_AMOUNT, MAX_COLLECTION_AMOUNT } = AzamPayProvider;

// ---------------------------------------------------------------------------
// GET /payments/{orderReference} answers with an ARRAY, same shape as ClickPesa.
// ---------------------------------------------------------------------------
test('firstRow unwraps the array the gateway returns for a single payment', () => {
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
  assert.equal(row.status, 'FAILED');
  assert.match(row.message, /not have enough balance/);
});

test('firstRow returns null for an empty result set', () => {
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
  assert.equal(normalizeStatus('SETTLED'), 'completed');
  assert.equal(normalizeStatus('PENDING'), 'pending');
  assert.equal(normalizeStatus('INITIATED'), 'pending');
  assert.equal(normalizeStatus('PROCESSING'), 'pending');
  assert.equal(normalizeStatus('FAILED'), 'failed');
  assert.equal(normalizeStatus('DECLINED'), 'failed');
  assert.equal(normalizeStatus('CANCELLED'), 'failed');
  assert.equal(normalizeStatus('EXPIRED'), 'failed');
  assert.equal(normalizeStatus('REJECTED'), 'failed');
});

test('an unrecognized status never becomes completed', () => {
  const bad = ['unknown', '', null, undefined, 'COMPLETED_LATER', 'COMPLETE', 'completd'];
  for (const s of bad) {
    assert.notEqual(normalizeStatus(s), 'completed', `${s} must not verify as completed`);
  }
});

// ---------------------------------------------------------------------------
// Phone format. AzamPay accepts country-code-prefixed MSISDN without plus.
// ---------------------------------------------------------------------------
test('normalizeMsisdn strips the plus sign', () => {
  assert.equal(normalizeMsisdn('+255693273241'), '255693273241');
});

test('normalizeMsisdn converts a local 0-prefixed number', () => {
  assert.equal(normalizeMsisdn('0693273241'), '255693273241');
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
// Amount bounds.
//
// AzamPay collection range matches ClickPesa's measured range (500 - 3,000,000 TZS).
// ---------------------------------------------------------------------------
test('the enforced amount range', () => {
  assert.equal(MIN_COLLECTION_AMOUNT, 500);
  assert.equal(MAX_COLLECTION_AMOUNT, 3_000_000);
});

test('initiateCollection refuses an amount below the provider minimum', async () => {
  const provider = new AzamPayProvider();
  await assert.rejects(
    () => provider.initiateCollection({ amount: 499, orderReference: 't1', phoneNumber: '255693273241' }),
    (e) => e.code === 'AMOUNT_OUT_OF_RANGE' && e.status === 400,
  );
});

test('initiateCollection refuses an amount above the provider maximum', async () => {
  const provider = new AzamPayProvider();
  await assert.rejects(
    () => provider.initiateCollection({ amount: 3_000_001, orderReference: 't1', phoneNumber: '255693273241' }),
    (e) => e.code === 'AMOUNT_OUT_OF_RANGE' && e.status === 400,
  );
});

// ---------------------------------------------------------------------------
// Webhook payloads carry the same object the query endpoint wraps in an array.
// ---------------------------------------------------------------------------
test('normalizeWebhook unwraps an array payload', () => {
  const provider = new AzamPayProvider();
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
  const provider = new AzamPayProvider();
  const out = provider.normalizeWebhook({});
  assert.notEqual(out.status, 'completed');
  assert.equal(out.failureReason, null);
  assert.equal(out.orderReference, null);
});

// ---------------------------------------------------------------------------
// verifyWebhook is fail-closed: a missing secret rejects every callback.
// ---------------------------------------------------------------------------
test('verifyWebhook returns false when the webhook secret is unset', () => {
  const provider = new AzamPayProvider();
  // Temporarily unset the env so the test is deterministic regardless of shell.
  const prev = process.env.AZAMPAY_WEBHOOK_SECRET;
  delete process.env.AZAMPAY_WEBHOOK_SECRET;
  try {
    assert.equal(provider.verifyWebhook({ amount: 500, status: 'SUCCESS' }, 'sig'), false);
  } finally {
    if (prev !== undefined) process.env.AZAMPAY_WEBHOOK_SECRET = prev;
  }
});
