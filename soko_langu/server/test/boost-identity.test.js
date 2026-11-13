// Regression: every boost purchase answered 403 "User ID mismatch".
//
// /api/boost-product demanded that the request body echo `userId`, but the
// client stopped sending it in 81fb4f4, so the guard rejected every purchase
// before a payment was ever started. Identity must come from the verified ID
// token; a *different* echoed value is still a forgery attempt.
const { test } = require('node:test');
const assert = require('node:assert/strict');

const { resolveRequestIdentity } = require('../src/modules/legacy-compat/feature-compat');

const decoded = { uid: 'fire-uid-1' };

test('an absent userId resolves to the token owner', () => {
  assert.deepEqual(resolveRequestIdentity(decoded, undefined), {
    ok: true,
    userId: 'fire-uid-1',
  });
  assert.deepEqual(resolveRequestIdentity(decoded, null), {
    ok: true,
    userId: 'fire-uid-1',
  });
  assert.deepEqual(resolveRequestIdentity(decoded, ''), {
    ok: true,
    userId: 'fire-uid-1',
  });
});

test('an echoed userId matching the token is accepted', () => {
  assert.deepEqual(resolveRequestIdentity(decoded, 'fire-uid-1'), {
    ok: true,
    userId: 'fire-uid-1',
  });
});

test('an echoed userId for another account is refused', () => {
  assert.deepEqual(resolveRequestIdentity(decoded, 'someone-else'), { ok: false });
});

test('a decoded token without a uid never authenticates', () => {
  assert.deepEqual(resolveRequestIdentity({}, 'fire-uid-1'), { ok: false });
  assert.deepEqual(resolveRequestIdentity(null, undefined), { ok: false });
});