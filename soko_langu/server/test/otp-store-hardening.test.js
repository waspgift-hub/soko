// Hardening contract for services/otp-store.js (auth security upgrade).
//
//  1. Salted hashes: same OTP, different record => different stored hash, and
//     a store leak is not a rainbow table for the 6-digit space.
//  2. Attempts survive a resend: resending must not reset the 5-guess lockout.
//  3. Guesses never extend the TTL: bumpAttempts/markUsed preserve expiresAt.
//  4. Expiry is enforced on read, on both backends.
//  5. The in-memory fallback is bounded.
//
// Runs against the REAL store with Redis stubbed out (memory path), so the
// logic above is genuinely exercised.

process.env.OTP_MEMORY_MAX = '10';

const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');

const redisPath = require.resolve('../src/config/redis');
require.cache[redisPath] = {
  id: redisPath, filename: redisPath, loaded: true,
  exports: { getRedis: () => null },
};

const {
  saveOtp, getOtp, markUsed, bumpAttempts, clearOtp, createOtpHash, verifyOtpHash,
} = require('../src/services/otp-store');

test('a correct OTP verifies against its salted hash', () => {
  const stored = createOtpHash('123456');
  assert.ok(verifyOtpHash('123456', stored));
});

test('a wrong OTP does not verify', () => {
  const stored = createOtpHash('123456');
  assert.equal(verifyOtpHash('999999', stored), false);
  assert.equal(verifyOtpHash('', stored), false);
  assert.equal(verifyOtpHash(undefined, stored), false);
});

test('two issuances of the same OTP hash differently (random salt)', () => {
  const a = createOtpHash('123456');
  const b = createOtpHash('123456');
  assert.notEqual(a, b, 'identical OTPs must not share a stored hash');
  assert.ok(a.includes(':'), 'salted format is salt:hash');
  assert.ok(verifyOtpHash('123456', a));
  assert.ok(verifyOtpHash('123456', b));
});

test('a legacy unsalted record still verifies (deploy-safe rollout)', () => {
  const legacy = crypto.createHash('sha256').update('123456').digest('hex');
  assert.ok(verifyOtpHash('123456', legacy));
  assert.equal(verifyOtpHash('999999', legacy), false);
});

test('attempts survive a resend instead of resetting the lockout', async () => {
  await saveOtp('hardening:resend', createOtpHash('111111'), 300);
  await bumpAttempts('hardening:resend');
  await bumpAttempts('hardening:resend');

  await saveOtp('hardening:resend', createOtpHash('222222'), 300);
  const rec = await getOtp('hardening:resend');
  assert.equal(rec.attempts, 2, 'resend must carry the attempt counter over');
  assert.ok(verifyOtpHash('222222', rec.otpHash), 'the NEW code verifies');
  assert.equal(verifyOtpHash('111111', rec.otpHash), false, 'the OLD code does not');
  await clearOtp('hardening:resend');
});

test('guesses and used-flags never extend the TTL', async () => {
  await saveOtp('hardening:ttl', createOtpHash('111111'), 300);
  const before = (await getOtp('hardening:ttl')).expiresAt;
  await bumpAttempts('hardening:ttl');
  await bumpAttempts('hardening:ttl');
  await markUsed('hardening:ttl');
  const after = (await getOtp('hardening:ttl')).expiresAt;
  assert.equal(after, before, 'expiresAt must be immutable after issuance');
  await clearOtp('hardening:ttl');
});

test('an expired record reads as null', async () => {
  await saveOtp('hardening:expired', createOtpHash('111111'), 0);
  assert.equal(await getOtp('hardening:expired'), null);
});

test('the in-memory fallback is bounded (FIFO eviction)', async () => {
  for (let i = 0; i < 12; i++) {
    await saveOtp(`hardening:bound:${i}`, createOtpHash('111111'), 300);
  }
  const last = await getOtp('hardening:bound:11');
  assert.ok(last, 'newest record survives');
  const first = await getOtp('hardening:bound:0');
  assert.equal(first, null, 'oldest record was evicted past the cap');
  for (let i = 0; i < 12; i++) await clearOtp(`hardening:bound:${i}`);
});
