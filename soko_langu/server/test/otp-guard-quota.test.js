// otpGuard — quota/IP-ceiling behaviour with a tight cooldown + window so the
// test runs in milliseconds (separate process = isolated env from the
// cooldown test file).
process.env.OTP_COOLDOWN_MS = '10';
process.env.OTP_WINDOW_MS = '900000';
process.env.OTP_MAX_PER_KEY = '3';
process.env.OTP_MAX_PER_IP = '2';

const test = require('node:test');
const assert = require('node:assert/strict');

const { checkTarget } = require('../src/middleware/otpGuard');

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

test('per-phone quota: 3 sends allowed, 4th rejected even after cooldown', async () => {
  const key = 'phone:255700000010';
  for (let i = 0; i < 3; i += 1) {
    const r = await checkTarget(key, `10.1.0.${i}`); // distinct source so IP never trips first
    assert.ok(r.ok, `send ${i + 1} should pass`);
    await sleep(20);
  }
  const blocked = await checkTarget(key, '10.1.0.9');
  assert.equal(blocked.ok, false);
  assert.equal(blocked.code, 'auth_otp_limit');
});

test('per-IP ceiling: 3rd OTP request from the same IP is rejected', async () => {
  // Distinct targets so the per-key cooldown/quota never trips.
  await checkTarget('phone:255700000011', '10.2.0.1');
  await checkTarget('phone:255700000012', '10.2.0.1');
  const blocked = await checkTarget('phone:255700000013', '10.2.0.1');
  assert.equal(blocked.ok, false);
  assert.equal(blocked.code, 'auth_otp_limit');
});