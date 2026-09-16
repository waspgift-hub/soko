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

function req(method, path, headers = {}, body) {
  return new Promise((resolve, reject) => {
    const r = http.request(
      { host: 'localhost', port, path, method, headers: { 'Content-Type': 'application/json', ...headers } },
      (res) => {
        let b = '';
        res.on('data', (c) => (b += c));
        res.on('end', () => {
          try { resolve({ status: res.statusCode, body: JSON.parse(b) }); }
          catch { resolve({ status: res.statusCode, body: b }); }
        });
      },
    );
    r.on('error', reject);
    r.end(body ? JSON.stringify(body) : undefined);
  });
}

test('POST /api/v1/kyc/submit rejects anonymous', async () => {
  const r = await req('POST', '/api/v1/kyc/submit', {}, { fullName: 'Asha Juma', idType: 'kyc_id_national', idNumber: '123' });
  assert.strictEqual(r.status, 401);
});

test('GET /api/v1/kyc/status/:userId rejects anonymous', async () => {
  const r = await req('GET', '/api/v1/kyc/status/u1');
  assert.strictEqual(r.status, 401);
});

test('GET /api/v1/kyc/admin/applications rejects no secret', async () => {
  const r = await req('GET', '/api/v1/kyc/admin/applications');
  assert.strictEqual(r.status, 401);
});

test('POST /api/v1/kyc/admin/:userId/review rejects no secret', async () => {
  const r = await req('POST', '/api/v1/kyc/admin/u1/review', {}, { approve: true });
  assert.strictEqual(r.status, 401);
});

test('POST /api/v1/kyc/admin/:userId/revoke rejects no secret', async () => {
  const r = await req('POST', '/api/v1/kyc/admin/u1/revoke', {}, { reason: 'Fraud' });
  assert.strictEqual(r.status, 401);
});

test('DELETE /api/v1/kyc/admin/:userId rejects no secret', async () => {
  const r = await req('DELETE', '/api/v1/kyc/admin/u1');
  assert.strictEqual(r.status, 401);
});