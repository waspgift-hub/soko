'use strict';

const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const http = require('http');
const express = require('express');
const { requireUser } = require('../src/modules/legacy-compat/auth-helpers');

let server;
let port;

before(async () => {
  const app = express();
  app.get('/api/transaction-status/:orderId', async (req, res) => {
    try {
      const { orderId } = req.params;
      if (!orderId) return res.status(400).json({ error: 'Missing orderId' });
      const auth = await requireUser(req, res);
      if (!auth.ok) return;
      res.json({ leaked: true, orderId });
    } catch (e) {
      if (!res.headersSent) res.status(500).json({ error: 'Internal server error' });
    }
  });
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

function req(headers = {}) {
  return new Promise((resolve, reject) => {
    const r = http.request(
      {
        host: 'localhost',
        port,
        path: '/api/transaction-status/some-order',
        method: 'GET',
        headers,
      },
      (res) => {
        let b = '';
        res.on('data', (c) => (b += c));
        res.on('end', () => {
          try {
            resolve({ status: res.statusCode, body: JSON.parse(b) });
          } catch {
            resolve({ status: res.statusCode, body: b });
          }
        });
      },
    );
    r.on('error', reject);
    r.end();
  });
}

test('anonymous status lookup returns one 401 and never 500', async () => {
  const r = await req();
  assert.equal(r.status, 401);
  assert.equal(r.body.leaked, undefined);
  assert.ok(r.body.error);
});

test('malformed bearer returns a single client/auth error, never 500', async () => {
  const r = await req({ Authorization: 'Bearer not-a-real-token' });
  assert.ok([401, 403, 503].includes(r.status), `status=${r.status}`);
  assert.notEqual(r.status, 500);
  assert.equal(r.body.leaked, undefined);
});

test('legacy requireUser object is not a boolean pass', async () => {
  const res = {
    headersSent: false,
    statusCode: 200,
    body: null,
    status(c) {
      this.statusCode = c;
      return this;
    },
    json(p) {
      this.headersSent = true;
      this.body = p;
      return this;
    },
  };
  const auth = await requireUser({ headers: {} }, res);
  assert.equal(Boolean(auth), true);
  assert.equal(auth.ok, false);
  assert.equal(res.statusCode, 401);
});
