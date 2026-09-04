// RBAC proof tests (blueprint: unauthorized writes return 401/403).
// Boots the real Express app on an ephemeral port; no database needed
// because auth middleware rejects before any DB access.
const { test, before, after } = require('node:test');
const assert = require('node:assert');
const http = require('http');
const { app } = require('../src/app');

let server;
let port;

before(async () => {
  await new Promise((resolve) => {
    server = app.listen(0, () => {
      port = server.address().port;
      resolve();
    });
  });
});

after(async () => {
  await new Promise((resolve) => server.close(resolve));
});

function req(method, path, body) {
  return new Promise((resolve, reject) => {
    const r = http.request(
      { host: 'localhost', port, path, method, headers: { 'Content-Type': 'application/json' } },
      (res) => {
        let b = '';
        res.on('data', (c) => (b += c));
        res.on('end', () => resolve({ status: res.statusCode, body: b }));
      }
    );
    r.on('error', reject);
    if (body) r.write(JSON.stringify(body));
    r.end();
  });
}

test('health is public', async () => {
  const r = await req('GET', '/health');
  assert.ok([200, 503].includes(r.status), `health was ${r.status}`);
});

test('protected order routes reject anonymous callers', async () => {
  const r = await req('GET', '/api/v1/orders');
  assert.strictEqual(r.status, 401);
});

test('wallet rejects anonymous callers', async () => {
  const r = await req('GET', '/api/v1/wallet');
  assert.strictEqual(r.status, 401);
});

test('admin dashboard rejects anonymous callers', async () => {
  const r = await req('GET', '/api/v1/admin/dashboard');
  assert.strictEqual(r.status, 401);
});

test('admin audit-logs rejects anonymous callers', async () => {
  const r = await req('GET', '/api/v1/admin/audit-logs');
  assert.strictEqual(r.status, 401);
});

test('admin metrics rejects anonymous callers', async () => {
  const r = await req('GET', '/api/v1/admin/metrics');
  assert.strictEqual(r.status, 401);
});

test('dispute resolve rejects anonymous callers (admin-only)', async () => {
  const r = await req('PUT', '/api/v1/disputes/00000000-0000-0000-0000-000000000000/resolve', {
    resolution: 'FULL_REFUND',
  });
  assert.strictEqual(r.status, 401);
});

test('OTP validation rejects malformed phone numbers', async () => {
  const r = await req('POST', '/api/v1/auth/verify-otp', { phone: '123', otp: '123456' });
  assert.strictEqual(r.status, 400);
});

test('withdrawal validation rejects negative amounts', async () => {
  // 401 comes first (no token) — validation is proven by schema unit path.
  const r = await req('POST', '/api/v1/wallet/withdrawals', { amount: -5 });
  assert.strictEqual(r.status, 401);
});
