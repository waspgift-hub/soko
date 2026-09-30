// otpGuard — cooldown behaviour (memory fallback path).
// Runs WITHOUT a Redis server: ioredis is lazyConnect, so the guard must take
// the in-memory path and never hang on a dead connection.
process.env.OTP_COOLDOWN_MS = '60000';
process.env.OTP_WINDOW_MS = '900000';

const test = require('node:test');
const assert = require('node:assert/strict');

const { checkTarget } = require('../src/middleware/otpGuard');

test('first OTP request for a phone is allowed', async () => {
  const result = await checkTarget('phone:255700000001', '10.0.0.1');
  assert.ok(result.ok);
});

test('immediate resend to the same phone hits the 60s cooldown', async () => {
  const first = await checkTarget('phone:255700000002', '10.0.0.2');
  assert.ok(first.ok);

  const second = await checkTarget('phone:255700000002', '10.0.0.2');
  assert.equal(second.ok, false);
  assert.equal(second.code, 'auth_otp_cooldown');
  assert.ok(second.retryAfterMs <= 60000);
});

test('different phones are not blocked by one phone cooldown', async () => {
  await checkTarget('phone:255700000003', '10.0.0.3');
  const other = await checkTarget('phone:255700000004', '10.0.0.3');
  assert.ok(other.ok);
});