// Unit checks for the WhatsApp webhook surface: challenge handshake, HMAC
// verification, and payload normalization. Persistence is covered by the
// Firestore-backed smoke test run against a real deployment.
process.env.NODE_ENV = 'development';
process.env.WHATSAPP_WEBHOOK_VERIFY_TOKEN = 'test-token';
process.env.WHATSAPP_APP_SECRET = 'test-secret';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('crypto');
const { verifyChallenge, verifySignature, normalizeEvents } = require('../src/modules/whatsapp/webhook-controller');

function response() {
  return {
    statusCode: 200,
    body: null,
    status(code) {
      this.statusCode = code;
      return this;
    },
    type() {
      return this;
    },
    send(body) {
      this.body = body;
      return this;
    },
  };
}

test('GET handshake echoes the challenge for the configured token', () => {
  const res = response();
  verifyChallenge(
    { query: { 'hub.mode': 'subscribe', 'hub.verify_token': 'test-token', 'hub.challenge': 'abc123' } },
    res,
  );
  assert.equal(res.statusCode, 200);
  assert.equal(res.body, 'abc123');
});

test('GET handshake rejects a wrong token and a wrong mode', () => {
  const wrongToken = response();
  verifyChallenge(
    { query: { 'hub.mode': 'subscribe', 'hub.verify_token': 'nope', 'hub.challenge': 'abc123' } },
    wrongToken,
  );
  assert.equal(wrongToken.statusCode, 403);

  const wrongMode = response();
  verifyChallenge(
    { query: { 'hub.mode': 'unsubscribe', 'hub.verify_token': 'test-token', 'hub.challenge': 'abc123' } },
    wrongMode,
  );
  assert.equal(wrongMode.statusCode, 400);
});

test('POST signature accepts only the exact signed bytes', () => {
  const raw = Buffer.from(JSON.stringify({ entry: [] }));
  const signature = `sha256=${crypto.createHmac('sha256', 'test-secret').update(raw).digest('hex')}`;

  assert.equal(verifySignature(raw, signature).ok, true);
  assert.equal(verifySignature(Buffer.from('{"entry":[1]}'), signature).ok, false);
  assert.equal(verifySignature(raw, undefined).ok, false);
  assert.equal(verifySignature(raw, 'sha1=deadbeef').ok, false);
});

test('normalizes inbound messages, statuses and account errors', () => {
  const events = normalizeEvents({
    entry: [{
      changes: [{
        value: {
          metadata: { phone_number_id: '123', display_phone_number: '255700000000' },
          contacts: [{ wa_id: '255711111111', profile: { name: 'Juma' } }],
          messages: [{
            from: '255711111111',
            id: 'wamid.ABC',
            timestamp: '1700000000',
            type: 'text',
            text: { body: 'Habari' },
          }],
          statuses: [{ id: 'wamid.DEF', status: 'delivered', timestamp: '1700000001' }],
          errors: [{ code: 131000, title: 'Rejected' }],
        },
      }],
    }],
  });

  assert.equal(events.length, 3);
  assert.equal(events[0].kind, 'message');
  assert.equal(events[0].docId, 'msg_wamid.ABC');
  assert.equal(events[0].data.text, 'Habari');
  assert.equal(events[0].data.contactName, 'Juma');
  assert.equal(events[1].kind, 'status');
  assert.equal(events[1].docId, 'status_wamid.DEF_delivered');
  assert.equal(events[2].kind, 'error');
});
