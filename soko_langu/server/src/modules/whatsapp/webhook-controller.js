// WhatsApp Business Platform (Cloud API) webhook endpoint.
//
// GET  /api/webhooks/whatsapp  Meta verification handshake (hub.challenge)
// POST /api/webhooks/whatsapp  inbound messages, delivery statuses and errors
//
// The POST body is parsed as raw bytes because Meta signs the exact payload
// bytes, not a re-serialized object. The router mounts express.raw so that
// `req.body` is a Buffer here; the global express.json parser is mounted later
// in app.js and must not see this route first.
const crypto = require('crypto');
const config = require('../../config');
const { persistEvents, metaDate, docId, previewOf } = require('./webhook-store');

function expectedVerifyToken() {
  return config.whatsapp.verifyToken || process.env.WHATSAPP_WEBHOOK_VERIFY_TOKEN || '';
}

function safeEqual(left, right) {
  const a = Buffer.from(String(left || ''));
  const b = Buffer.from(String(right || ''));
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

// Meta's GET handshake: echo hub.challenge only when both mode and token match.
function verifyChallenge(req, res) {
  const mode = req.query['hub.mode'];
  const token = req.query['hub.verify_token'];
  const challenge = req.query['hub.challenge'];
  const expected = expectedVerifyToken();

  if (!expected) {
    // Never echo the challenge when the deployment has no token configured —
    // that would let anyone claim the webhook for this app.
    console.error('[WA_WEBHOOK] WHATSAPP_WEBHOOK_VERIFY_TOKEN is not configured');
    return res.status(503).type('text/plain').send('WEBHOOK_VERIFY_TOKEN_NOT_CONFIGURED');
  }
  if (mode !== 'subscribe') {
    return res.status(400).type('text/plain').send('INVALID_MODE');
  }
  if (!token || !safeEqual(token, expected)) {
    console.warn('[WA_WEBHOOK] verification rejected: token mismatch');
    return res.status(403).type('text/plain').send('INVALID_VERIFY_TOKEN');
  }
  if (!challenge) {
    return res.status(400).type('text/plain').send('MISSING_CHALLENGE');
  }
  return res.status(200).type('text/plain').send(String(challenge));
}

// `x-hub-signature-256` is HMAC-SHA256 over the raw request bytes, keyed with
// the Meta app secret (App Settings > Basic > App secret).
function verifySignature(rawBody, header) {
  const secret = config.whatsapp.appSecret || process.env.WHATSAPP_APP_SECRET;

  if (!secret) {
    if (config.nodeEnv === 'production') {
      return { ok: false, reason: 'WHATSAPP_APP_SECRET_NOT_CONFIGURED' };
    }
    // Local development without the Meta secret: accept so the handshake and
    // a manual curl can be exercised. Production always fails closed above.
    console.warn('[WA_WEBHOOK] WHATSAPP_APP_SECRET missing — accepting unsigned payload (development only)');
    return { ok: true, unverified: true };
  }

  if (typeof header !== 'string' || !/^sha256=[a-f0-9]{64}$/i.test(header)) {
    return { ok: false, reason: 'MISSING_OR_MALFORMED_SIGNATURE' };
  }

  const expected = crypto.createHmac('sha256', secret).update(rawBody).digest();
  const provided = Buffer.from(header.slice('sha256='.length), 'hex');
  if (provided.length !== expected.length) {
    return { ok: false, reason: 'SIGNATURE_LENGTH_MISMATCH' };
  }
  return crypto.timingSafeEqual(expected, provided)
    ? { ok: true }
    : { ok: false, reason: 'INVALID_SIGNATURE' };
}

function normalizeEvents(payload) {
  const events = [];
  const entries = Array.isArray(payload.entry) ? payload.entry : [];

  for (const entry of entries) {
    const changes = Array.isArray(entry.changes) ? entry.changes : [];
    for (const change of changes) {
      const value = change.value || {};
      const metadata = value.metadata || {};
      const phoneNumberId = metadata.phone_number_id || null;
      const displayPhoneNumber = metadata.display_phone_number || null;
      const names = new Map(
        (Array.isArray(value.contacts) ? value.contacts : [])
          .map((contact) => [contact.wa_id, contact.profile && contact.profile.name]),
      );

      for (const message of Array.isArray(value.messages) ? value.messages : []) {
        events.push({
          kind: 'message',
          docId: docId('msg', message.id),
          data: {
            kind: 'message',
            direction: 'inbound',
            wamid: message.id || null,
            from: message.from || null,
            contactName: names.get(message.from) || null,
            type: message.type || null,
            text: previewOf(message),
            metaTimestamp: metaDate(message.timestamp),
            phoneNumberId,
            displayPhoneNumber,
            payload: message,
          },
        });
      }

      for (const status of Array.isArray(value.statuses) ? value.statuses : []) {
        events.push({
          kind: 'status',
          docId: docId('status', `${status.id}_${status.status}`),
          data: {
            kind: 'status',
            direction: 'outbound',
            wamid: status.id || null,
            status: status.status || null,
            recipientId: status.recipient_id || null,
            conversation: status.conversation || null,
            pricing: status.pricing || null,
            errors: Array.isArray(status.errors) ? status.errors : null,
            metaTimestamp: metaDate(status.timestamp),
            phoneNumberId,
            displayPhoneNumber,
            payload: status,
          },
        });
      }

      // Account-level failures (e.g. a message was rejected before a status
      // object existed). They have no Meta id, so a random key is the only
      // dedup option; duplicates here are harmless audit rows.
      for (const error of Array.isArray(value.errors) ? value.errors : []) {
        events.push({
          kind: 'error',
          docId: docId('error', crypto.randomUUID()),
          data: {
            kind: 'error',
            phoneNumberId,
            displayPhoneNumber,
            code: error.code || null,
            title: error.title || null,
            message: error.message || null,
            errorData: error.error_data || null,
            payload: error,
          },
        });
      }
    }
  }

  return events;
}

async function receiveEvent(req, res) {
  const rawBody = Buffer.isBuffer(req.body)
    ? req.body
    : Buffer.from(req.body ? JSON.stringify(req.body) : '');

  const signature = verifySignature(rawBody, req.headers['x-hub-signature-256']);
  if (!signature.ok) {
    const status = signature.reason === 'WHATSAPP_APP_SECRET_NOT_CONFIGURED' ? 503 : 401;
    console.warn('[WA_WEBHOOK] rejected delivery:', signature.reason);
    return res.status(status).type('text/plain').send(signature.reason);
  }

  let payload;
  try {
    payload = JSON.parse(rawBody.toString('utf8'));
  } catch {
    return res.status(400).type('text/plain').send('INVALID_JSON');
  }

  const events = normalizeEvents(payload);
  const summary = {
    messages: events.filter((e) => e.kind === 'message').length,
    statuses: events.filter((e) => e.kind === 'status').length,
    errors: events.filter((e) => e.kind === 'error').length,
  };

  try {
    await persistEvents(events);
  } catch (error) {
    // A 5xx makes Meta retry. Every write is idempotent, so a retry after a
    // partial Firestore failure cannot duplicate rows.
    console.error('[WA_WEBHOOK] persist failed:', error.message);
    return res.status(500).type('text/plain').send('STORE_ERROR');
  }

  if (summary.messages || summary.statuses || summary.errors) {
    console.log('[WA_WEBHOOK]', JSON.stringify({ ...summary, unverified: !!signature.unverified }));
  }

  return res.status(200).type('text/plain').send('EVENT_RECEIVED');
}

module.exports = {
  verifyChallenge,
  receiveEvent,
  verifySignature,
  normalizeEvents,
};
