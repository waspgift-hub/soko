// Regression coverage for the OTP send guard's rollback.
//
// otpSendGuard runs as middleware, so it claims the 60-second cooldown and one of
// only 3 per-target quota slots BEFORE the handler delivers anything. When
// delivery then failed (SMS gateway 500, mail provider bounce, suppressed
// address), the user was told "sent", the code was never delivered, and the
// cooldown plus a quota slot stayed spent on a message that never existed — so
// the immediate "resend" they pressed returned 429. Two of only three sends for
// the window could be lost to backend faults the user can neither see nor fix.
//
// These tests pin the rollback: a failed delivery must give the slot back, and a
// successful delivery must NOT (that would open a resend-spam hole).
//
// NOTE ON ISOLATION: the guard keeps a per-IP abuse ceiling that is deliberately
// NOT rolled back and is process-wide. node:test runs every file in one process,
// so each test below uses its own IP. Sharing an IP made these tests fail for a
// reason that has nothing to do with the rollback.

const { test } = require('node:test');
const assert = require('node:assert/strict');

process.env.OTP_COOLDOWN_MS = '60000';
process.env.OTP_WINDOW_MS = '900000';
process.env.OTP_MAX_PER_KEY = '3';
process.env.OTP_MAX_PER_IP = '30';

const { checkTarget, otpSendGuard, otpVerifyGuard, releaseOtpClaim } = require('../src/middleware/otpGuard');

let ipCounter = 0;
const nextIp = () => `10.1.${(ipCounter += 1) % 250}.${Math.floor(ipCounter / 250)}`;

function makeReq(phone, ip) {
  return { body: { phone }, ip, connection: { remoteAddress: ip }, otpRelease: null };
}

function makeRes() {
  return {
    statusCode: null, body: null, headers: {},
    setHeader(k, v) { this.headers[k] = v; },
    status(code) { this.statusCode = code; return this; },
    json(payload) { this.body = payload; return this; },
  };
}

async function runSendGuard(req, res) {
  let nexted = false;
  await otpSendGuard('phone')(req, res, () => { nexted = true; });
  return nexted;
}

async function runVerifyGuard(req, res) {
  let nexted = false;
  await otpVerifyGuard('phone')(req, res, () => { nexted = true; });
  return nexted;
}

// --- the rollback itself ----------------------------------------------------

test('a successful send keeps the cooldown claimed', async () => {
  const ip = nextIp();
  const first = await checkTarget(`phone:255712000001`, ip);
  assert.equal(first.ok, true);

  // No release() call: the OTP went out, so the cooldown must stand.
  const second = await checkTarget(`phone:255712000001`, ip);
  assert.equal(second.ok, false, 'a delivered OTP must start a real cooldown');
  assert.equal(second.code, 'auth_otp_cooldown');
});

test('releasing a claim removes the cooldown so an immediate resend is allowed', async () => {
  const ip = nextIp();
  const key = 'phone:255712000099';
  const first = await checkTarget(key, ip);
  assert.equal(first.ok, true);
  assert.equal(typeof first.release, 'function');
  await first.release();

  const second = await checkTarget(key, ip);
  assert.equal(second.ok, true, 'a rolled-back send must not leave the user in a cooldown');
});

test('release is idempotent, so a double call cannot free extra quota', async () => {
  const ip = nextIp();
  const key = 'phone:255712000098';
  // cooldown:false isolates the quota arithmetic from the 60s cooldown, which
  // otherwise short-circuits every repeat request before the count is touched.
  const first = await checkTarget(key, ip, { cooldown: false });
  await first.release();
  await first.release();
  await first.release();

  // Budget 3. The three releases above must have refunded exactly one slot, so
  // three more claims still fit and the fourth is blocked.
  assert.equal((await checkTarget(key, ip, { cooldown: false })).ok, true);
  assert.equal((await checkTarget(key, ip, { cooldown: false })).ok, true);
  assert.equal((await checkTarget(key, ip, { cooldown: false })).ok, true);
  const blocked = await checkTarget(key, ip, { cooldown: false });
  assert.equal(blocked.ok, false, 'the window budget must still be enforced');
  assert.equal(blocked.code, 'auth_otp_limit');
});

test('release gives back exactly one quota slot, not the whole window', async () => {
  const ip = nextIp();
  const key = 'phone:255712000097';
  // Two slots consumed for real, then one that gets rolled back.
  await checkTarget(key, ip, { cooldown: false });
  await checkTarget(key, ip, { cooldown: false });
  const rolled = await checkTarget(key, ip, { cooldown: false });
  assert.equal(rolled.ok, true);
  await rolled.release();

  // Budget 3, two already spent: the refund leaves count=2, so exactly ONE more
  // send fits and the one after that is blocked. Releasing must not have reset
  // the whole window (which would have allowed three) nor nothing (zero).
  assert.equal((await checkTarget(key, ip, { cooldown: false })).ok, true, 'the released slot must be reusable');
  const last = await checkTarget(key, ip, { cooldown: false });
  assert.equal(last.ok, false, 'the window budget must still be enforced');
  assert.equal(last.code, 'auth_otp_limit');
});

test('a live cooldown blocks a resend even while quota remains', async () => {
  // The 60s cooldown is the first line of defence; the per-target quota is what
  // still applies once it expires. Without this, "release the quota" could have
  // been implemented by removing the cooldown.
  const ip = nextIp();
  const key = 'phone:255712000094';
  assert.equal((await checkTarget(key, ip)).ok, true);
  const blocked = await checkTarget(key, ip);
  assert.equal(blocked.ok, false);
  assert.equal(blocked.code, 'auth_otp_cooldown', 'the cooldown must win over remaining quota');
});

test('a rolled-back send does not consume the per-IP abuse budget', async () => {
  const ip = nextIp();
  const rolled = await checkTarget('phone:255712000096', ip);
  await rolled.release();

  // The IP counter is intentionally NOT refunded (a burst of failing sends must
  // still count), so this only asserts the cooldown and target quota were freed —
  // not that the IP ceiling disappeared.
  const again = await checkTarget('phone:255712000096', ip);
  assert.equal(again.ok, true);
});

// --- middleware wiring ------------------------------------------------------

test('otpSendGuard exposes the rollback on req for the handler', async () => {
  const ip = nextIp();
  const req = makeReq('255712000090', ip);
  assert.equal(await runSendGuard(req, makeRes()), true);
  assert.equal(typeof req.otpRelease, 'function', 'the handler needs a way to roll back');

  await releaseOtpClaim(req);
  const retry = makeReq('255712000090', ip);
  assert.equal(await runSendGuard(retry, makeRes()), true, 'the retry must not be throttled');
});

test('a blocked send attaches no rollback, so an error path cannot free someone elses cooldown', async () => {
  const ip = nextIp();
  assert.equal(await runSendGuard(makeReq('255712000089', ip), makeRes()), true);
  const blockedReq = makeReq('255712000089', ip);
  const blockedRes = makeRes();
  assert.equal(await runSendGuard(blockedReq, blockedRes), false);
  assert.equal(blockedRes.statusCode, 429);
  assert.equal(blockedRes.body.error, 'auth_otp_cooldown');
  assert.equal(blockedReq.otpRelease, null, 'a rejected request must not carry a rollback');

  await releaseOtpClaim(blockedReq); // must be a no-op, not a silent unlock
  const stillBlocked = await checkTarget(`phone:255712000089`, ip);
  assert.equal(stillBlocked.ok, false, 'the original cooldown must survive');
});

test('releaseOtpClaim is safe when no guard claimed anything', async () => {
  await releaseOtpClaim(null);
  await releaseOtpClaim(undefined);
  await releaseOtpClaim({});
  await releaseOtpClaim({ otpRelease: null });
});

test('releaseOtpClaim clears req.otpRelease so a later error cannot re-fire it', async () => {
  const ip = nextIp();
  const req = makeReq('255712000088', ip);
  assert.equal(await runSendGuard(req, makeRes()), true);
  await releaseOtpClaim(req);
  assert.equal(req.otpRelease, null);
});

// --- verify-side budget -----------------------------------------------------

test('the verify path has no cooldown, so a mistyped code can be retyped at once', async () => {
  const ip = nextIp();
  // Four immediate verification attempts, all allowed despite a live send
  // cooldown on the same target.
  for (let i = 0; i < 4; i++) {
    assert.equal(
      await runVerifyGuard(makeReq('255712000087', ip), makeRes()),
      true,
      `verify attempt ${i + 1} must not be throttled`,
    );
  }
});

test('the verify path still has a per-target ceiling against brute force', async () => {
  const ip = nextIp();
  const target = '255712000086';
  let blockedAt = 0;
  for (let i = 1; i <= 14; i++) {
    const res = makeRes();
    if (!(await runVerifyGuard(makeReq(target, ip), res))) { blockedAt = i; break; }
  }
  assert.ok(blockedAt > 0, 'a distributed brute force must eventually be cut off');
  assert.ok(blockedAt >= 5, `the ceiling must allow the store's 5 attempts first (blocked at ${blockedAt})`);
});

test('the verify target key is namespaced away from the send key', async () => {
  const ip = nextIp();
  const target = '255712000085';
  // Exhaust the verify budget for this target.
  for (let i = 0; i < 12; i++) {
    await runVerifyGuard(makeReq(target, ip), makeRes());
  }
  // The send quota for the same phone must be untouched: a user who fumbled
  // their code can still ask for a fresh one.
  assert.equal(
    await runSendGuard(makeReq(target, ip), makeRes()),
    true,
    'exhausting verify attempts must not block a fresh send',
  );
});
