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

test('POST /api/v1/reviews rejects anonymous', async () => {
  const r = await req('POST', '/api/v1/reviews', {}, { productId: 'p1', rating: 5 });
  assert.strictEqual(r.status, 401);
});

test('GET /api/v1/reviews/product/:productId/me rejects anonymous', async () => {
  const r = await req('GET', '/api/v1/reviews/product/p1/me');
  assert.strictEqual(r.status, 401);
});

test('POST /api/v1/reviews/:id/helpful rejects anonymous', async () => {
  const r = await req('POST', '/api/v1/reviews/r1/helpful');
  assert.strictEqual(r.status, 401);
});

test('POST /api/v1/reviews/:id/reply rejects anonymous', async () => {
  const r = await req('POST', '/api/v1/reviews/r1/reply', {}, { reply: 'Thanks!' });
  assert.strictEqual(r.status, 401);
});