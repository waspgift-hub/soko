// Regression tests for the KYC contact-OTP flow, which could never succeed.
//
// otp-store.saveOtp persists { otpHash, expiresAt, used, attempts } but
// kyc-service.verifyContactOtp read `record.value`, which is always undefined.
// Buffer.from(undefined) threw a TypeError that the route reported as
// "KYC_PHONE_OTP_INVALID" for every code, so no seller could ever verify their
// phone or email.
//
// These tests run against the real services with only the two network edges
// (SMS, mail) and Firestore stubbed out, so the store/verify contract itself is
// genuinely exercised.

const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');

// Capture the OTP the service generates instead of sending it anywhere.
const smsPath = require.resolve('../src/services/sms-service');
const mailerPath = require.resolve('../src/services/mailer');
const firebasePath = require.resolve('../src/config/firebase');
const redisPath = require.resolve('../src/config/redis');

let captured = { sms: [], mail: [] };

// Proxy so the stub answers whatever method name the service actually calls
// (sendSms / sendSMS), instead of guessing one and silently calling the real
// SMS gateway from a test.
require.cache[smsPath] = {
  id: smsPath, filename: smsPath, loaded: true,
  exports: new Proxy({}, { get: () => async (...a) => { captured.sms.push(a); return { sent: true }; } }),
};
require.cache[mailerPath] = {
  id: mailerPath, filename: mailerPath, loaded: true,
  exports: new Proxy({}, { get: () => async (...a) => { captured.mail.push(a); return { sent: true }; } }),
};
// No Firebase credentials in the test env: the contact-verified mirror is
// best-effort, so returning null is the honest stand-in.
require.cache[firebasePath] = {
  id: firebasePath, filename: firebasePath, loaded: true,
  exports: { getFirebaseFirestore: () => null, getFirebaseAuth: () => null, initializeFirebase: () => {} },
};
// Force the in-memory OTP path. Without this, every store call waits out the
// 2.5s Redis timeout before falling back, and ioredis keeps the event loop
// alive so the test file never exits.
require.cache[redisPath] = {
  id: redisPath, filename: redisPath, loaded: true,
  exports: { getRedis: () => null, acquireLock: async () => ({ acquired: true, skipped: true, token: null }), releaseLock: async () => {}, connectRedis: async () => {}, disconnectRedis: async () => {} },
};

const kyc = require('../src/modules/kyc/kyc-service');
const { saveOtp, getOtp } = require('../src/services/otp-store');

const USER = 'kyc-test-user-1';

// Mirrors hashContactOtp so the test can seed a store record directly.
const sha256 = (v) => crypto.createHash('sha256').update(String(v)).digest('hex');

function otpFromMessage(text) {
  const m = String(text).match(/\b(\d{6})\b/);
  assert.ok(m, `no 6-digit OTP found in message: ${text}`);
  return m[1];
}

// The stubs record positional args, so index rather than assume named fields.
function otpFromSms(i = 0) {
  const call = captured.sms[i];
  assert.ok(call, 'no SMS was sent');
  return otpFromMessage(call.slice(1).join(' '));
}

function otpFromMail(i = 0) {
  const call = captured.mail[i];
  assert.ok(call, 'no email was sent');
  return otpFromMessage(call.slice(1).join(' '));
}

test.beforeEach(() => { captured = { sms: [], mail: [] }; });

test('the stored record uses otpHash, which is what verify reads', async () => {
  await saveOtp(`kyc:phone:${USER}`, sha256('123456'), 300);
  const record = await getOtp(`kyc:phone:${USER}`);
  // If this key is ever renamed, verifyContactOtp must be renamed with it —
  // the old mismatch is exactly what broke verification.
  assert.ok(record.otpHash, 'record must expose otpHash');
  assert.equal(record.value, undefined, 'record must not use a "value" key');
  assert.equal(record.otpHash, sha256('123456'));
});

test('a correct phone OTP is accepted', async () => {
  const sent = await kyc.sendContactOtp({ userId: USER, channel: 'phone', value: '255693273241' });
  assert.ok(sent.sent, 'sendContactOtp must report a send');
  const otp = otpFromSms();

  const result = await kyc.verifyContactOtp({
    userId: USER, channel: 'phone', value: '255693273241', otp,
  });
  assert.deepEqual(result, { verified: true, channel: 'phone' });
});

test('a correct email OTP is accepted', async () => {
  const sent = await kyc.sendContactOtp({ userId: USER, channel: 'email', value: 'waspgift@gmail.com' });
  assert.ok(sent.sent, 'sendContactOtp must report a send');
  const otp = otpFromMail();

  const result = await kyc.verifyContactOtp({
    userId: USER, channel: 'email', value: 'waspgift@gmail.com', otp,
  });
  assert.equal(result.verified, true);
});

test('a wrong OTP is rejected as invalid, not as a server error', async () => {
  await kyc.sendContactOtp({ userId: USER, channel: 'phone', value: '255693273242' });
  const otp = otpFromSms();
  const wrong = otp === '000000' ? '111111' : '000000';

  await assert.rejects(
    () => kyc.verifyContactOtp({ userId: USER, channel: 'phone', value: '255693273242', otp: wrong }),
    (e) => e.code === 'KYC_OTP_INVALID',
  );
});

test('an OTP cannot be reused after it is verified', async () => {
  await kyc.sendContactOtp({ userId: USER, channel: 'phone', value: '255693273243' });
  const otp = otpFromSms();
  await kyc.verifyContactOtp({ userId: USER, channel: 'phone', value: '255693273243', otp });
  await assert.rejects(
    () => kyc.verifyContactOtp({ userId: USER, channel: 'phone', value: '255693273243', otp }),
    (e) => e.code === 'KYC_OTP_INVALID',
  );
});

test('verification without a sent OTP is rejected', async () => {
  await assert.rejects(
    () => kyc.verifyContactOtp({ userId: 'never-sent-otp', channel: 'phone', value: '255000000000', otp: '123456' }),
    (e) => e.code === 'KYC_OTP_INVALID',
  );
});
