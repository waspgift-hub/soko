const { test } = require('node:test');
const assert = require('node:assert');
const totp = require('../src/services/totp');

test('TOTP generates 6-digit code', () => {
  const secret = totp.generateSecret();
  const codes = totp.totp(secret, 59000, 30, 6, 0);
  assert.equal(codes.length, 1);
  assert.match(codes[0], /^\d{6}$/);
});

test('TOTP verify accepts generated code', () => {
  const secret = totp.generateSecret();
  const now = 1234567890000;
  const code = totp.totp(secret, now, 30, 6, 0)[0];
  assert.equal(totp.verify(secret, code, now), true);
});

test('TOTP verify rejects wrong code', () => {
  const secret = totp.generateSecret();
  const now = 1234567890000;
  assert.equal(totp.verify(secret, '000000', now), false);
});

test('TOTP verify rejects non-6-digit', () => {
  const secret = totp.generateSecret();
  assert.equal(totp.verify(secret, '123', Date.now()), false);
});

test('base32 roundtrip', () => {
  const buf = Buffer.from('hello world');
  const enc = totp.base32Encode(buf);
  const dec = totp.base32Decode(enc);
  assert.deepStrictEqual(dec, buf);
});

test('otpauthUri format', () => {
  const uri = totp.otpauthUri({ secret: 'ABC', account: 'admin' });
  assert.ok(uri.startsWith('otpauth://totp/'));
  assert.ok(uri.includes('secret=ABC'));
});
