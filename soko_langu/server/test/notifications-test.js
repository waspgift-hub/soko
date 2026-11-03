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
        res.on('end', () => {
          try { resolve({ status: res.statusCode, body: JSON.parse(b) }); }
          catch { resolve({ status: res.statusCode, body: b }); }
        });
      },
    );
    r.on('error', reject);
    r.end();
  });
}

test('GET /api/v1/notifications rejects anonymous', async () => {
  const r = await req('GET', '/api/v1/notifications');
  assert.strictEqual(r.status, 401);
});

test('GET /api/v1/notifications/unread-count rejects anonymous', async () => {
  const r = await req('GET', '/api/v1/notifications/unread-count');
  assert.strictEqual(r.status, 401);
});

test('POST /api/v1/notifications/read-all rejects anonymous', async () => {
  const r = await req('POST', '/api/v1/notifications/read-all');
  assert.strictEqual(r.status, 401);
});

test('POST /api/v1/notifications/:id/read rejects anonymous', async () => {
  const r = await req('POST', '/api/v1/notifications/test-id/read');
  assert.strictEqual(r.status, 401);
});

test('DELETE /api/v1/notifications/:id rejects anonymous', async () => {
  const r = await req('DELETE', '/api/v1/notifications/test-id');
  assert.strictEqual(r.status, 401);
});

test('DELETE /api/v1/notifications (bulk) rejects anonymous', async () => {
  const r = await req('DELETE', '/api/v1/notifications');
  assert.strictEqual(r.status, 401);
});
