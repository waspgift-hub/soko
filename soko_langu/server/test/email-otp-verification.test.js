// Regression coverage for the email-OTP verification state and single-use
// enforcement.
//
// Two gaps this pins shut:
//
//  1. verifyEmailOtp answered { valid: true } without ever telling Firebase that
//     the address was proven. The user stayed emailVerified:false forever, so
//     the app's isEmailVerified() (repositories/auth_repository.dart) kept
//     reporting "not verified" for an address the user had just proved they own.
//
//  2. The code must be single-use. emailOtpLogin mints a Firebase custom token,
//     so a replayable code would let anyone who ever saw an email — including a
//     forwarded or shared mailbox — mint a fresh session indefinitely.

const { test } = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('crypto');

const state = { store: null, auth: null, updateCalls: [] };

const DB = require('../src/config/database');
const Firebase = require('../src/config/firebase');
const OtpStore = require('../src/services/otp-store');

// Patch BEFORE the controller binds them.
OtpStore.saveOtp = async (key, otpHash, ttl) => {
  state.store[key] = { otpHash, expiresAt: Date.now() + ttl * 1000, attempts: 0, used: false };
};
OtpStore.getOtp = async (key) => state.store[key] || null;
OtpStore.markUsed = async (key) => {
  if (state.store[key]) state.store[key].used = true;
  else state.store[`${key}:marked`] = true; // markUsed on an absent key still recorded
};
OtpStore.bumpAttempts = async (key) => {
  if (!state.store[key]) return 1;
  state.store[key].attempts += 1;
  return state.store[key].attempts;
};
OtpStore.clearOtp = async (key) => { delete state.store[key]; };
Firebase.getFirebaseAuth = () => state.auth;

const controller = require('../src/modules/auth/controller');

// Express defaults res.status() to 200 and res.json() writes the body without
// touching the status, so a 2xx assertion must not expect an explicit status
// code here — that is exactly how the real handler answers a success.
function makeRes() {
  return {
    statusCode: 200, body: null,
    status(c) { this.statusCode = c; return this; },
    json(p) { this.body = p; return this; },
  };
}

const hash = (v) => crypto.createHash('sha256').update(String(v)).digest('hex');

function seedAuth(overrides = {}) {
  state.store = {};
  state.updateCalls = [];
  state.auth = {
    getUserByEmail: async () => ({ uid: 'u-1', email: 'user@example.com', emailVerified: false }),
    updateUser: async (uid, props) => { state.updateCalls.push({ uid, props }); },
    createCustomToken: async (uid) => `token-for-${uid}`,
    ...overrides,
  };
}

const EMAIL = 'user@example.com';

test('a verified email is flagged emailVerified in Firebase', async () => {
  seedAuth();
  await OtpStore.saveOtp(`email:${EMAIL}`, hash('123456'), 300);

  const res = makeRes();
  await controller.verifyEmailOtp({ body: { email: EMAIL, otp: '123456' } }, res);

  assert.equal(res.statusCode, 200);
  assert.equal(res.body.valid, true);
  assert.deepEqual(state.updateCalls, [{ uid: 'u-1', props: { emailVerified: true } }],
    'the proof must be mirrored to Firebase or the app keeps reporting unverified');
});

test('an already-verified address is not written again', async () => {
  seedAuth({ getUserByEmail: async () => ({ uid: 'u-1', email: EMAIL, emailVerified: true }) });
  await OtpStore.saveOtp(`email:${EMAIL}`, hash('123456'), 300);

  const res = makeRes();
  await controller.verifyEmailOtp({ body: { email: EMAIL, otp: '123456' } }, res);

  assert.equal(res.statusCode, 200);
  assert.equal(state.updateCalls.length, 0, 'no redundant Firebase write');
});

test('a Firebase write failure still reports the verification as successful', async () => {
  // The OTP proof is authoritative and already consumed; failing the request here
  // would make the user retry with a spent code.
  seedAuth({ updateUser: async () => { throw new Error('Firebase unavailable'); } });
  await OtpStore.saveOtp(`email:${EMAIL}`, hash('123456'), 300);

  const res = makeRes();
  await controller.verifyEmailOtp({ body: { email: EMAIL, otp: '123456' } }, res);

  assert.equal(res.statusCode, 200);
  assert.equal(res.body.valid, true);
});

test('verifying an address with no Firebase account is not an error', async () => {
  const notFound = Object.assign(new Error('no user'), { code: 'auth/user-not-found' });
  seedAuth({ getUserByEmail: async () => { throw notFound; } });
  await OtpStore.saveOtp(`email:${EMAIL}`, hash('123456'), 300);

  const res = makeRes();
  await controller.verifyEmailOtp({ body: { email: EMAIL, otp: '123456' } }, res);

  assert.equal(res.statusCode, 200, 'verification-before-registration must still work');
  assert.equal(state.updateCalls.length, 0);
});

test('a wrong code does not mark the email verified', async () => {
  seedAuth();
  await OtpStore.saveOtp(`email:${EMAIL}`, hash('123456'), 300);

  const res = makeRes();
  await controller.verifyEmailOtp({ body: { email: EMAIL, otp: '999999' } }, res);

  assert.equal(res.statusCode, 400);
  assert.equal(res.body.error, 'auth_otp_invalid');
  assert.equal(state.updateCalls.length, 0, 'a failed proof must not flip the flag');
});

test('an expired code does not mark the email verified', async () => {
  seedAuth();
  await OtpStore.saveOtp(`email:${EMAIL}`, hash('123456'), 300);
  state.store[`email:${EMAIL}`].expiresAt = Date.now() - 1000;

  const res = makeRes();
  await controller.verifyEmailOtp({ body: { email: EMAIL, otp: '123456' } }, res);

  assert.equal(res.statusCode, 400);
  assert.equal(res.body.error, 'auth_otp_expired');
  assert.equal(state.updateCalls.length, 0);
});

// --- single use -------------------------------------------------------------

test('an email code cannot be replayed for a second login', async () => {
  seedAuth();
  await OtpStore.saveOtp(`email:${EMAIL}`, hash('123456'), 300);

  const first = makeRes();
  await controller.emailOtpLogin({ body: { email: EMAIL, otp: '123456' } }, first);
  assert.equal(first.statusCode, 200);
  assert.equal(first.body.success, true);
  assert.ok(first.body.token, 'a custom token is minted on success');

  // Replay: this is the security-relevant assertion. A custom token grants a
  // full session, so a replayable code would let anyone with access to the email
  // mint sessions forever.
  const replay = makeRes();
  await controller.emailOtpLogin({ body: { email: EMAIL, otp: '123456' } }, replay);
  assert.equal(replay.statusCode, 400, 'the code must be single-use');
  assert.equal(replay.body.success, undefined);
  assert.equal(replay.body.token, undefined, 'no second token may be minted');
});

test('a code consumed by verify cannot then be used to log in', async () => {
  seedAuth();
  await OtpStore.saveOtp(`email:${EMAIL}`, hash('123456'), 300);

  await controller.verifyEmailOtp({ body: { email: EMAIL, otp: '123456' } }, makeRes());

  const login = makeRes();
  await controller.emailOtpLogin({ body: { email: EMAIL, otp: '123456' } }, login);
  assert.equal(login.statusCode, 400, 'verifying must consume the code too');
  assert.equal(login.body.token, undefined);
});

test('a login for an address with no Firebase account is refused, not tokenized', async () => {
  const notFound = Object.assign(new Error('no user'), { code: 'auth/user-not-found' });
  seedAuth({ getUserByEmail: async () => { throw notFound; } });
  await OtpStore.saveOtp(`email:${EMAIL}`, hash('123456'), 300);

  const res = makeRes();
  await controller.emailOtpLogin({ body: { email: EMAIL, otp: '123456' } }, res);

  assert.equal(res.statusCode, 404);
  assert.equal(res.body.token, undefined, 'no auto-create on email OTP login');
});

test('the email key is normalised, so case cannot smuggle a second code', async () => {
  seedAuth();
  await OtpStore.saveOtp(`email:${EMAIL}`, hash('123456'), 300);

  const first = makeRes();
  await controller.emailOtpLogin({ body: { email: '  User@Example.COM ', otp: '123456' } }, first);
  assert.equal(first.statusCode, 200);

  const replay = makeRes();
  await controller.emailOtpLogin({ body: { email: 'USER@example.com', otp: '123456' } }, replay);
  assert.equal(replay.statusCode, 400, 'normalisation must not create a separate namespace');
});
