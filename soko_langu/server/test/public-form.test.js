const test = require('node:test');
const assert = require('node:assert');
const {
  normalizeEmail,
  isValidEmail,
  isSpam,
  hashValue,
  hashIp,
  randomToken,
} = require('../src/utils/public-form');

test('normalizeEmail trims and lowercases', () => {
  assert.strictEqual(normalizeEmail('  Asha@Example.COM '), 'asha@example.com');
  assert.strictEqual(normalizeEmail(null), '');
  assert.strictEqual(normalizeEmail(undefined), '');
});

test('isValidEmail accepts normal addresses and rejects malformed ones', () => {
  assert.strictEqual(isValidEmail('asha@example.com'), true);
  assert.strictEqual(isValidEmail('a.b+tag@sub.example.co.tz'), true);
  for (const bad of ['', 'asha', 'asha@', '@example.com', 'asha@example', 'a b@example.com']) {
    assert.strictEqual(isValidEmail(bad), false, `${bad} should be rejected`);
  }
});

test('isSpam catches a filled honeypot', () => {
  assert.strictEqual(isSpam({ website: 'http://spam.example' }), true);
  assert.strictEqual(isSpam({ company: 'Spam Ltd' }), true);
  assert.strictEqual(isSpam({ website: '   ' }), false);
});

test('isSpam rejects forms submitted faster than a human can type', () => {
  const started = Date.now() - 50;
  assert.strictEqual(isSpam({ formStartedAt: started }), true);
});

test('isSpam accepts a plausible elapsed time and missing timing', () => {
  const started = Date.now() - 5000;
  assert.strictEqual(isSpam({ formStartedAt: started }), false);
  // Old app builds do not send formStartedAt; they must keep working.
  assert.strictEqual(isSpam({}), false);
  assert.strictEqual(isSpam({ formStartedAt: '' }), false);
});

test('isSpam ignores a mildly future timestamp but rejects implausible ones', () => {
  const slightSkew = Date.now() + 1000;
  assert.strictEqual(isSpam({ formStartedAt: slightSkew }), false);
  const farFuture = Date.now() + 11 * 60 * 1000;
  assert.strictEqual(isSpam({ formStartedAt: farFuture }), true);
});

test('hashValue is stable, truncated sha-256 and never contains the input', () => {
  const one = hashValue('asha@example.com');
  const two = hashValue('asha@example.com');
  assert.strictEqual(one, two);
  assert.strictEqual(one.length, 32);
  assert.match(one, /^[a-f0-9]{32}$/);
  assert.notStrictEqual(hashValue('other@example.com'), one);
  assert.strictEqual(hashValue('asha@example.com', 8).length, 8);
});

test('hashIp hashes req.ip and falls back to the socket address', () => {
  const viaIp = hashIp({ ip: '203.0.113.9' });
  assert.strictEqual(viaIp, hashValue('203.0.113.9', 32));
  const viaSocket = hashIp({ connection: { remoteAddress: '198.51.100.4' } });
  assert.strictEqual(viaSocket, hashValue('198.51.100.4', 32));
  assert.strictEqual(hashIp({}), hashValue('unknown', 32));
});

test('randomToken returns distinct hex tokens of the requested byte length', () => {
  const a = randomToken();
  const b = randomToken();
  assert.notStrictEqual(a, b);
  assert.strictEqual(a.length, 64);
  assert.match(a, /^[a-f0-9]{64}$/);
  assert.strictEqual(randomToken(16).length, 32);
});
