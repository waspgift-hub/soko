const { test } = require('node:test');
const assert = require('node:assert');
const { generateOtp, hashOtp, verifyOtp, generateQrPayload } = require('../src/modules/handover/otp-generator');

test('generateOtp returns numeric of requested length', () => {
  const otp = generateOtp(6);
  assert.match(otp, /^\d{6}$/);
});

test('generateOtp is cryptographically variable across calls', () => {
  const a = generateOtp(6);
  const b = generateOtp(6);
  // Extremely unlikely to collide on 6 numeric digits twice in a row.
  assert.notStrictEqual(a, b);
});

test('hashOtp produces a salt+hash pair', () => {
  const { hash, salt } = hashOtp('123456');
  assert.ok(hash.length === 64);
  assert.ok(salt.length > 0);
  assert.notStrictEqual(hash, '123456');
});

test('verifyOtp accepts correct and rejects wrong', () => {
  const { hash, salt } = hashOtp('111222');
  assert.strictEqual(verifyOtp('111222', hash, salt), true);
  assert.strictEqual(verifyOtp('000000', hash, salt), false);
});

test('verifyOtp is salts-specific (same otp, different salt fails)', () => {
  const { hash: h1, salt: s1 } = hashOtp('123456');
  const { salt: s2 } = hashOtp('123456');
  assert.strictEqual(verifyOtp('123456', h1, s1), true);
  assert.strictEqual(verifyOtp('123456', h1, s2), false);
});

test('generateQrPayload embeds order and expiry', () => {
  const payload = generateQrPayload({
    orderId: 'ord-1',
    orderNumber: 'SV2026',
    token: 'tok',
    expiresAt: new Date('2030-01-01T00:00:00Z'),
  });
  const parsed = JSON.parse(payload);
  assert.strictEqual(parsed.t, 'sokovibe-handover');
  assert.strictEqual(parsed.orderId, 'ord-1');
  assert.strictEqual(parsed.orderNumber, 'SV2026');
  assert.ok(parsed.exp);
});
