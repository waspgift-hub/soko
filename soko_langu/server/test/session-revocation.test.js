// Contract for services/session-revocation.js (logout-all enforcement).
//
// Logout-all stamps session_revocations/{uid}.revokedAt; any token minted
// BEFORE the stamp (Firebase auth_time, seconds) is dead on routes that
// enforce freshness. Refreshed ID tokens keep the session's original
// auth_time, so revocation survives silent refresh.

const test = require('node:test');
const assert = require('node:assert/strict');

const docs = new Map();
const tokenFor = { uid: 'legacy-user', auth_time: 0 };
const firebasePath = require.resolve('../src/config/firebase');
require.cache[firebasePath] = {
  id: firebasePath, filename: firebasePath, loaded: true,
  exports: {
    getFirebaseAuth: () => ({ verifyIdToken: async () => ({ ...tokenFor }) }),
    getFirebaseFirestore: () => ({
      collection: () => ({
        doc: (id) => ({
          set: async (data) => { docs.set(id, { ...(docs.get(id) || {}), ...data }); },
          get: async () => ({ exists: docs.has(id), data: () => docs.get(id) }),
        }),
      }),
    }),
  },
};

const { revokeUserSessions, getSessionRevokedAt, isSessionRevoked } = require('../src/services/session-revocation');

test('no stamp means no revocation', async () => {
  assert.equal(await getSessionRevokedAt('fresh-user'), 0);
  assert.equal(await isSessionRevoked('fresh-user', Math.floor(Date.now() / 1000)), false);
});

test('tokens minted before the stamp are revoked, newer ones are not', async () => {
  const before = Math.floor(Date.now() / 1000) - 100;
  assert.equal(await revokeUserSessions('user-1'), true);
  const stamp = await getSessionRevokedAt('user-1');
  assert.ok(stamp > 0);

  assert.equal(await isSessionRevoked('user-1', before), true, 'old session dies');
  assert.equal(
    await isSessionRevoked('user-1', Math.floor(Date.now() / 1000) + 60),
    false,
    'a fresh sign-in after logout-all passes',
  );
});

test('missing auth_time never revokes (fail-safe for odd tokens)', async () => {
  await revokeUserSessions('user-2');
  assert.equal(await isSessionRevoked('user-2', 0), false);
  assert.equal(await isSessionRevoked('user-2', null), false);
  assert.equal(await isSessionRevoked(null, 123), false);
});

test('legacy requireUser rejects a revoked session with 401', async () => {
  const { requireUser } = require('../src/modules/legacy-compat/auth-helpers');
  const res = { statusCode: 200, body: null, status(c) { this.statusCode = c; return this; }, json(p) { this.body = p; return this; } };
  const req = { headers: { authorization: 'Bearer any-token' } };

  tokenFor.uid = 'legacy-user';
  tokenFor.auth_time = Math.floor(Date.now() / 1000) - 100;
  let auth = await requireUser(req, { ...res });
  assert.equal(auth.ok, true, 'fresh session passes legacy gate');

  await revokeUserSessions('legacy-user');
  const res2 = { statusCode: 200, body: null, status(c) { this.statusCode = c; return this; }, json(p) { this.body = p; return this; } };
  auth = await requireUser(req, res2);
  assert.equal(auth.ok, false, 'revoked session fails legacy gate');
  assert.equal(res2.statusCode, 401);
  assert.equal(res2.body.error, 'SESSION_REVOKED');
});
