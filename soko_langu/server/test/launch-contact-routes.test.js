// Route-level tests for the waitlist and contact forms. The Firestore and mail
// seams are replaced in the require cache so the tests exercise the real
// validation, consent, token and storage logic without touching a database or
// sending mail.
const test = require('node:test');
const assert = require('node:assert');
const http = require('node:http');
const express = require('express');

const state = {
  docs: new Map(),
  added: [],
  emails: [],
};

function reset() {
  state.docs.clear();
  state.added.length = 0;
  state.emails.length = 0;
}

const commerceStore = {
  serverTimestamp: () => new Date('2026-11-09T00:00:00Z'),
  getDocument: async (collection, id) => {
    const doc = state.docs.get(`${collection}/${id}`);
    return doc ? { id, ...doc } : null;
  },
  setDocument: async (collection, id, data) => {
    state.docs.set(`${collection}/${id}`, { ...data });
  },
  upsertDocument: async (collection, id, data) => {
    const key = `${collection}/${id}`;
    state.docs.set(key, { ...(state.docs.get(key) || {}), ...data });
  },
  updateDocument: async (collection, id, data) => {
    const key = `${collection}/${id}`;
    state.docs.set(key, { ...(state.docs.get(key) || {}), ...data });
  },
  addDocument: async (collection, data) => {
    const id = `doc-${state.added.length + 1}`;
    state.added.push({ collection, id, data });
    state.docs.set(`${collection}/${id}`, { id, ...data });
    return id;
  },
  listDocuments: async (collection, { where = [] } = {}) => {
    const out = [];
    for (const [key, doc] of state.docs.entries()) {
      if (!key.startsWith(`${collection}/`)) continue;
      const id = key.slice(collection.length + 1);
      const matches = where.every((clause) => doc[clause.field] === clause.value);
      if (matches) out.push({ id, ...doc });
    }
    return out;
  },
};

const mailer = {
  sendMail: async (to, subject, html) => {
    state.emails.push({ to, subject, html });
    return true;
  },
};

function stub(modulePath, exports) {
  const resolved = require.resolve(modulePath);
  require.cache[resolved] = {
    id: resolved,
    filename: resolved,
    loaded: true,
    exports,
  };
}

stub('../src/services/commerce-store', commerceStore);
stub('../src/services/mailer', mailer);
stub('../src/middleware/rateLimiter', {
  rateLimit: () => (req, res, next) => next(),
});

const launchRouter = require('../src/modules/launch/routes');
const contactRouter = require('../src/modules/contact/routes');

const app = express();
app.use(express.json());
app.use('/api/v1/launch', launchRouter);
app.use('/api/v1/contact', contactRouter);

let server;
let base;

test.before(async () => {
  server = http.createServer(app);
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  base = `http://127.0.0.1:${server.address().port}`;
});

test.after(() => new Promise((resolve) => server.close(resolve)));

test.beforeEach(reset);

async function post(path, body) {
  const res = await fetch(`${base}${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  let json = null;
  try { json = await res.json(); } catch { /* non-json */ }
  return { status: res.status, json };
}

function tokenFromLastEmail() {
  const last = state.emails[state.emails.length - 1];
  const match = last && last.html.match(/token=([a-f0-9]+)/i);
  return match ? match[1] : null;
}

test('subscribe records consent, hashes the IP and sends a confirmation', async () => {
  const res = await post('/api/v1/launch/subscribe', {
    email: '  Asha@Example.com ',
    name: 'Asha',
    consent: true,
    preferredLanguage: 'en',
    userType: 'buyer',
    formStartedAt: Date.now() - 5000,
  });

  assert.strictEqual(res.status, 201);
  assert.strictEqual(res.json.data.status, 'subscribed');

  const doc = state.docs.get('landing_waitlist/asha@example.com');
  assert.ok(doc, 'subscriber is stored under the normalised email');
  assert.strictEqual(doc.email, 'asha@example.com');
  assert.strictEqual(doc.consent, true);
  assert.strictEqual(doc.userType, 'buyer');
  assert.strictEqual(doc.preferredLanguage, 'en');
  assert.strictEqual(doc.status, 'subscribed');
  assert.match(doc.consentIpHash, /^[a-f0-9]{32}$/);
  assert.match(doc.unsubscribeTokenHash, /^[a-f0-9]{32}$/);
  assert.ok(!Object.prototype.hasOwnProperty.call(doc, 'ip'), 'raw IP is never stored');
  assert.strictEqual(state.emails.length, 1);
  assert.match(state.emails[0].subject, /Soko Vibe/);
  assert.ok(tokenFromLastEmail(), 'confirmation carries an unsubscribe token');
});

test('a duplicate signup is idempotent and never re-sends the list twice', async () => {
  const body = { email: 'asha@example.com', consent: true, formStartedAt: Date.now() - 5000 };
  await post('/api/v1/launch/subscribe', body);
  const res = await post('/api/v1/launch/subscribe', body);

  assert.strictEqual(res.status, 200);
  assert.strictEqual(res.json.data.status, 'duplicate');
  assert.strictEqual(state.emails.length, 1, 'only the first signup sends a confirmation');
  const doc = state.docs.get('landing_waitlist/asha@example.com');
  assert.strictEqual(doc.duplicateSignupCount, 1);
});

test('unsubscribe invalidates the token and a later signup is fresh consent', async () => {
  await post('/api/v1/launch/subscribe', {
    email: 'asha@example.com',
    consent: true,
    formStartedAt: Date.now() - 5000,
  });
  const token = tokenFromLastEmail();
  assert.ok(token);

  const off = await post('/api/v1/launch/unsubscribe', { token });
  assert.strictEqual(off.status, 200);
  assert.strictEqual(state.docs.get('landing_waitlist/asha@example.com').status, 'unsubscribed');

  const replay = await post('/api/v1/launch/unsubscribe', { token });
  assert.strictEqual(replay.status, 200, 'unsubscribing twice is not an error');

  const again = await post('/api/v1/launch/subscribe', {
    email: 'asha@example.com',
    consent: true,
    formStartedAt: Date.now() - 5000,
  });
  assert.strictEqual(again.status, 201);
  assert.strictEqual(again.json.data.status, 'subscribed');
  assert.strictEqual(state.docs.get('landing_waitlist/asha@example.com').status, 'subscribed');
  assert.strictEqual(state.emails.length, 2, 'a fresh consent gets a fresh confirmation');
});

test('unsubscribe rejects an unknown token', async () => {
  const res = await post('/api/v1/launch/unsubscribe', { token: 'a'.repeat(64) });
  assert.strictEqual(res.status, 404);
  assert.strictEqual(res.json.code, 'UNSUBSCRIBE_INVALID');
});

test('waitlist rejects missing consent and bad email before storing anything', async () => {
  let res = await post('/api/v1/launch/subscribe', { email: 'asha@example.com', consent: false });
  assert.strictEqual(res.status, 400);
  assert.strictEqual(res.json.code, 'CONSENT_REQUIRED');

  res = await post('/api/v1/launch/subscribe', { email: 'bad', consent: true });
  assert.strictEqual(res.status, 400);
  assert.strictEqual(res.json.code, 'INVALID_EMAIL');
  assert.strictEqual(state.docs.size, 0);
  assert.strictEqual(state.emails.length, 0);
});

test('a honeypot submission is a silent success and stores nothing', async () => {
  const res = await post('/api/v1/launch/subscribe', {
    email: 'asha@example.com',
    consent: true,
    website: 'https://spam.example',
  });
  assert.strictEqual(res.status, 200);
  assert.strictEqual(res.json.success, true);
  assert.strictEqual(state.docs.size, 0);
  assert.strictEqual(state.emails.length, 0);
});

test('contact stores the message and notifies support without auto-replying', async () => {
  const res = await post('/api/v1/contact', {
    name: 'Asha',
    email: 'Asha@Example.com',
    subject: 'buyer',
    message: 'I need help understanding how buyer protection will work.',
    consent: true,
    preferredLanguage: 'en',
    formStartedAt: Date.now() - 5000,
  });

  assert.strictEqual(res.status, 201);
  const row = state.added.find((entry) => entry.collection === 'landing_contact_messages');
  assert.ok(row);
  assert.strictEqual(row.data.email, 'asha@example.com');
  assert.strictEqual(row.data.consent, true);
  assert.strictEqual(row.data.status, 'new');
  assert.match(row.data.ipHash, /^[a-f0-9]{32}$/);
  assert.ok(!Object.prototype.hasOwnProperty.call(row.data, 'ip'));

  assert.strictEqual(state.emails.length, 1);
  assert.match(state.emails[0].to, /support@/);
  assert.match(state.emails[0].subject, /Website/);
});

test('contact rejects missing consent and a short message', async () => {
  let res = await post('/api/v1/contact', {
    name: 'Asha',
    email: 'asha@example.com',
    subject: 'general',
    message: 'This message is long enough to be valid.',
    consent: false,
  });
  assert.strictEqual(res.status, 400);
  assert.strictEqual(res.json.code, 'CONSENT_REQUIRED');

  res = await post('/api/v1/contact', {
    name: 'Asha',
    email: 'asha@example.com',
    subject: 'general',
    message: 'short',
    consent: true,
  });
  assert.strictEqual(res.status, 400);
  assert.strictEqual(state.added.length, 0);
  assert.strictEqual(state.emails.length, 0);
});

test('contact notification failure still stores the message', async () => {
  const original = mailer.sendMail;
  mailer.sendMail = async () => false;
  try {
    const res = await post('/api/v1/contact', {
      name: 'Asha',
      email: 'asha@example.com',
      subject: 'privacy',
      message: 'Please delete the marketing record tied to my address.',
      consent: true,
      formStartedAt: Date.now() - 5000,
    });
    assert.strictEqual(res.status, 201);
    const row = state.added.find((entry) => entry.collection === 'landing_contact_messages');
    assert.ok(row);
  } finally {
    mailer.sendMail = original;
  }
});
