const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const { server, TOKEN } = require('../server');

function request(path, method, body, token = TOKEN) {
  return new Promise((resolve, reject) => {
    const data = body ? JSON.stringify(body) : '';
    const req = http.request({ hostname: '127.0.0.1', port: server.address().port, path, method, headers: {
      'Content-Type': 'application/json',
      'X-Pair-Token': token,
      'Content-Length': Buffer.byteLength(data),
    }}, res => {
      let raw = '';
      res.on('data', c => raw += c);
      res.on('end', () => resolve({ status: res.statusCode, body: raw ? JSON.parse(raw) : {} }));
    });
    req.on('error', reject);
    req.end(data);
  });
}

test.before(() => new Promise(resolve => {
  if (server.listening) return resolve();
  server.listen(0, '127.0.0.1', resolve);
}));

test.after(() => new Promise(resolve => server.close(resolve)));

test('E2E: health and LAN pairing token are enforced', async () => {
  const health = await request('/health', 'GET', null, 'wrong');
  assert.equal(health.status, 200);
  assert.equal(health.body.ok, true);

  const denied = await request('/pair', 'POST', {} , 'wrong');
  assert.equal(denied.status, 401);

  const paired = await request('/pair', 'POST', {});
  assert.equal(paired.status, 200);
  assert.ok(paired.body.sessionId);
});

test('E2E: phone submits *123# and receives menu, then selects option', async () => {
  const paired = await request('/pair', 'POST', {});
  const first = await request('/ussd', 'POST', { sessionId: paired.body.sessionId, code: '*123#' });
  assert.equal(first.status, 200);
  assert.equal(first.body.status, 'CONTINUE');
  assert.match(first.body.text, /Nunua/);
  assert.deepEqual(first.body.options, ['1', '2', '3', '4']);

  const second = await request('/ussd', 'POST', { sessionId: paired.body.sessionId, code: '1' });
  assert.equal(second.status, 200);
  assert.match(second.body.text, /Bidhaa mpya/);
});
