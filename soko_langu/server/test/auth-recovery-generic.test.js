// Anti-enumeration + recovery contract for the auth controller.
//
//  1. reset-password-by-phone answers success for unknown phones (no 404
//     oracle): the OTP already proved number control, so a 404 would only
//     reveal account existence.
//  2. reset for a known phone rotates the password, revokes sessions, mails
//     the account mailbox, and audits the change.
//  3. Weak new passwords are rejected with a machine code.
//  4. otp-sign-in answers 403 for unknown AND non-admin mailboxes alike.

const test = require('node:test');
const assert = require('node:assert/strict');

const state = {
  auth: null,
  dbUser: null,
  updateCalls: [],
  audits: [],
  revoked: [],
  mails: [],
};

const redisPath = require.resolve('../src/config/redis');
require.cache[redisPath] = {
  id: redisPath, filename: redisPath, loaded: true,
  exports: { getRedis: () => null },
};

const firebasePath = require.resolve('../src/config/firebase');
require.cache[firebasePath] = {
  id: firebasePath, filename: firebasePath, loaded: true,
  exports: { getFirebaseAuth: () => state.auth, getFirebaseFirestore: () => null },
};

const mailerPath = require.resolve('../src/services/mailer');
require.cache[mailerPath] = {
  id: mailerPath, filename: mailerPath, loaded: true,
  exports: { sendMail: async (...a) => { state.mails.push(a); return true; } },
};

const queuePath = require.resolve('../src/services/queue');
require.cache[queuePath] = {
  id: queuePath, filename: queuePath, loaded: true,
  exports: { getNotificationQueue: () => { throw new Error('no redis in tests'); } },
};

const sessionsPath = require.resolve('../src/services/session-revocation');
require.cache[sessionsPath] = {
  id: sessionsPath, filename: sessionsPath, loaded: true,
  exports: { revokeUserSessions: async (uid) => { state.revoked.push(uid); return true; } },
};

const DB = require('../src/config/database');
// Patched BEFORE the controller binds it: the seam row + audit sink.
DB.getStore = () => ({
  user: { findFirst: async () => state.dbUser },
  auditLog: { create: async ({ data }) => { state.audits.push(data); return { id: 'a1' }; } },
});

const controller = require('../src/modules/auth/controller');
const { saveOtp, createOtpHash } = require('../src/services/otp-store');

const PHONE = '255712345678';
const notFound = () => Object.assign(new Error('no user'), { code: 'auth/user-not-found' });

function seedAuth(overrides = {}) {
  state.updateCalls = [];
  state.audits = [];
  state.revoked = [];
  state.mails = [];
  state.dbUser = null;
  state.auth = {
    getUserByEmail: async () => { throw notFound(); },
    getUser: async () => { throw notFound(); },
    updateUser: async (uid, props) => { state.updateCalls.push({ uid, props }); },
    createCustomToken: async (uid) => `token-for-${uid}`,
    ...overrides,
  };
}

function makeRes() {
  return {
    statusCode: 200, body: null,
    status(c) { this.statusCode = c; return this; },
    json(p) { this.body = p; return this; },
    setHeader() {},
  };
}

function makeReq(body) {
  return { body, headers: {}, ip: '9.9.9.9' };
}

async function seedPhoneOtp(code = '123456') {
  await saveOtp(`phone:${PHONE.replace(/\D/g, '')}`, createOtpHash(code), 300);
}

test('reset for an unknown phone succeeds generically (no oracle)', async () => {
  seedAuth();
  await seedPhoneOtp();
  const res = makeRes();
  await controller.resetPasswordByPhone(makeReq({ phone: PHONE, otp: '123456', newPassword: 'Str0ngpass1' }), res);

  assert.equal(res.statusCode, 200);
  assert.equal(res.body.success, true, 'unknown phones get the same success shape');
  assert.equal(state.updateCalls.length, 0, 'nothing to rotate without an account');
  assert.ok(state.audits.some((a) => a.action === 'password_reset_no_account'), 'the probe is audited');
});

test('reset for a known phone rotates, revokes, mails and audits', async () => {
  seedAuth({
    getUser: async () => ({ uid: 'u-1', email: 'user@example.com' }),
  });
  state.dbUser = { firebaseUid: 'u-1' };
  await seedPhoneOtp();
  const res = makeRes();
  await controller.resetPasswordByPhone(makeReq({ phone: PHONE, otp: '123456', newPassword: 'Str0ngpass1' }), res);

  assert.equal(res.statusCode, 200);
  assert.equal(res.body.success, true);
  assert.deepEqual(state.updateCalls, [{ uid: 'u-1', props: { password: 'Str0ngpass1' } }]);
  assert.deepEqual(state.revoked, ['u-1'], 'recovery kills old sessions');
  assert.equal(state.mails.length, 1, 'the mailbox is warned');
  assert.ok(state.audits.some((a) => a.action === 'password_changed'), 'the change is audited');
});

test('a weak new password is rejected with a machine code', async () => {
  seedAuth();
  await seedPhoneOtp();
  for (const weak of ['short1', 'allletters', '12345678']) {
    const res = makeRes();
    await controller.resetPasswordByPhone(makeReq({ phone: PHONE, otp: '123456', newPassword: weak }), res);
    assert.equal(res.statusCode, 400, `${weak} must be rejected`);
    assert.ok(['auth_password_weak', 'auth_password_too_short'].includes(res.body.error), `machine code for ${weak}`);
  }
  assert.equal(state.updateCalls.length, 0, 'no rotation on weak passwords');
});

test('admin sign-in is 403 for unknown mailboxes (not 404)', async () => {
  seedAuth();
  const { saveOtp: save, createOtpHash: h } = require('../src/services/otp-store');
  await save('email:admin@example.com', h('123456'), 300);
  const res = makeRes();
  await controller.otpSignIn(makeReq({ email: 'admin@example.com', otp: '123456' }), res);

  assert.equal(res.statusCode, 403);
  assert.equal(res.body.error, 'ADMIN_REQUIRED');
});

test('admin sign-in is 403 for valid OTP but non-admin accounts', async () => {
  seedAuth({
    getUserByEmail: async () => ({ uid: 'u-2', email: 'user@example.com' }),
  });
  // The stubbed seam (bound at controller load) returns the role above, so
  // the Firestore fallback branch is never reached.
  state.dbUser = { role: 'user' };
  const { saveOtp: save, createOtpHash: h } = require('../src/services/otp-store');
  await save('email:user@example.com', h('123456'), 300);
  const res = makeRes();
  await controller.otpSignIn(makeReq({ email: 'user@example.com', otp: '123456' }), res);

  assert.equal(res.statusCode, 403);
  assert.equal(res.body.error, 'ADMIN_REQUIRED');
  assert.equal(res.body.customToken, undefined, 'no token for non-admins');
});
