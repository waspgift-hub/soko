const { describe, it } = require('node:test');
const assert = require('node:assert/strict');

const FIREBASE = require.resolve('../src/config/firebase');
const COMMERCE = require.resolve('../src/services/commerce-store');
const AUTH_HELPERS = require.resolve('../src/modules/legacy-compat/auth-helpers');

describe('requireAdmin MFA fail-closed', () => {
  it('returns ok:false and 401 when the store errors during MFA check', async () => {
    let calls = 0;
    require.cache[FIREBASE] = {
      id: FIREBASE,
      filename: FIREBASE,
      loaded: true,
      exports: {
        getFirebaseAuth: () => ({
          verifyIdToken: async () => ({ uid: 'admin-uid', email: 'admin@example.com', auth_time: 1 }),
        }),
      },
    };
    require.cache[COMMERCE] = {
      id: COMMERCE,
      filename: COMMERCE,
      loaded: true,
      exports: {
        getDocument: async () => {
          calls += 1;
          if (calls === 1) {
            return { isAdmin: true, role: 'admin', email: 'admin@example.com', mfa: { enabled: true, secret: 'x' } };
          }
          throw new Error('store down');
        },
      },
    };
    delete require.cache[AUTH_HELPERS];
    const { requireAdmin } = require(AUTH_HELPERS);

    const res = {
      headersSent: false,
      status(code) { this._status = code; return this; },
      json(body) { this._body = body; this.headersSent = true; return this; },
    };
    const req = { headers: { authorization: 'Bearer token', 'x-admin-totp': '123456' } };

    const result = await requireAdmin(req, res);
    assert.equal(result.ok, false);
    assert.equal(res._status, 401);
    assert.equal(res._body.error, 'MFA_REQUIRED');

    delete require.cache[AUTH_HELPERS];
    delete require.cache[FIREBASE];
    delete require.cache[COMMERCE];
  });
});
