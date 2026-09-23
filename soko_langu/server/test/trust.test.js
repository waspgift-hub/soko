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

function req(method, path, headers = {}) {
  return new Promise((resolve, reject) => {
    const r = http.request(
      { host: 'localhost', port, path, method, headers: { 'Content-Type': 'application/json', ...headers } },
      (res) => {
        let b = '';
        res.on('data', (c) => (b += c));
        res.on('end', () => resolve({ status: res.statusCode, body: b }));
      },
    );
    r.on('error', reject);
    r.end();
  });
}

// NOTE: the public passport GET is optionalAuth and DB-backed; it is not
// exercised here because the test env has no local Postgres (a 504 DB-unreachable
// response is expected, and the store lazy-connect outlives the test harness).
// Auth-gated routes below reject before touching the DB.

test('reliability computation rejects anonymous callers', async () => {
  const r = await req('POST', '/api/v1/trust/sellers/00000000-0000-0000-0000-000000000000/reliability');
  assert.strictEqual(r.status, 401);
});

test('quality gates reject anonymous callers', async () => {
  const r = await req('GET', '/api/v1/trust/sellers/00000000-0000-0000-0000-000000000000/gates');
  assert.strictEqual(r.status, 401);
});