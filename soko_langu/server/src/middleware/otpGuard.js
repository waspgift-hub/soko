// OTP send guard: per-phone/email cooldown + per-key quota + per-IP ceiling.
//
// WHY per-phone instead of the previous IP-only limiter:
//   - 1000 legit users behind the same NAT (campus, office, village WiFi)
//     previously shared ONE IP budget and nuked each other;
//   - abuse is per-target (bombing one victim's phone), so the quota must
//     attach to the phone/email, and the IP gets only a generous ceiling.
//
// Redis primary (`INCR`+`EXPIRE`, `SET NX PX`), in-memory fallback that
// mimics the same budgets so an absent Redis never silently opens the door.

const { getRedis } = require('../config/redis');

// Env-tunable so tests can shrink windows (each node:test file runs in its own
// process) without touching the production defaults below.
const COOLDOWN_MS = parseInt(process.env.OTP_COOLDOWN_MS || '60000', 10);
const WINDOW_MS = parseInt(process.env.OTP_WINDOW_MS || '900000', 10);   // quota window
const MAX_REQUEST_PER_KEY = parseInt(process.env.OTP_MAX_PER_KEY || '3', 10);
const MAX_REQUEST_PER_IP = parseInt(process.env.OTP_MAX_PER_IP || '30', 10);

// The verify path gets a deliberately different budget. It used to reuse the
// send guard's 60s cooldown, which meant a user who mistyped their 6-digit code
// was locked out for 60 seconds per attempt and throttled to 3 attempts per 15
// minutes ON TOP of the store's own 5-attempt lockout — so four ordinary typos
// cost the user a quarter of an hour. There is no cooldown here at all: the
// per-target counter is what stops a distributed brute force, and the store
// already locks the code after 5 wrong guesses.
const VERIFY_MAX_PER_KEY = parseInt(process.env.OTP_VERIFY_MAX_PER_KEY || '10', 10);

const memory = new Map(); // key -> { count, windowStart, cooldownUntil }

function memoryEntry(key) {
  const now = Date.now();
  const entry = memory.get(key) || { count: 0, windowStart: now, cooldownUntil: 0 };
  if (now - entry.windowStart > WINDOW_MS) {
    entry.count = 0;
    entry.windowStart = now;
  }
  return entry;
}

function redisReady() {
  const redis = getRedis();
  // ioredis is always constructed (lazyConnect), so only trust the fast path
  // when the connection actually reports READY — otherwise the INCR/SET would
  // queue indefinitely against a dead peer and hang every send-otp request.
  return redis && redis.status === 'ready';
}

async function redisIncrWindow(key) {
  if (!redisReady()) return null;
  const redis = getRedis();
  try {
    const count = await redis.incr(key);
    if (count === 1) await redis.expire(key, Math.ceil(WINDOW_MS / 1000));
    return count;
  } catch (e) {
    console.error('[OTP-GUARD] redis incr failed:', e.message);
    return null;
  }
}

async function redisClaimCooldown(key) {
  if (!redisReady()) return null;
  const redis = getRedis();
  try {
    const result = await redis.set(key, '1', 'NX', 'PX', COOLDOWN_MS);
    return result === 'OK';
  } catch (e) {
    console.error('[OTP-GUARD] redis cooldown failed:', e.message);
    return null;
  }
}

// Verifies quotas for a target key (phone:/email:) and falls back to memory.
// Returns { ok: true, release } or { ok: false, code, retryAfterMs }.
//
// `release` is the rollback for the cooldown and the per-target quota. The guard
// runs as middleware BEFORE the handler, so a delivery failure (SMS gateway 500,
// mail provider bounce, a rejected address) would otherwise leave the target
// sitting in a 60-second cooldown with one of only 3 quota slots already spent —
// for a code that never arrived. The user then waited out a cooldown caused by
// a backend fault they could not see or fix.
//
// The per-IP counter is deliberately NOT rolled back: it is a shared abuse
// ceiling, and a failed delivery is not evidence of abuse, so a burst of failing
// sends must still count against it.
async function checkTarget(key, ip, { cooldown = true, maxPerKey = MAX_REQUEST_PER_KEY } = {}) {
  if (redisReady()) {
    const count = await redisIncrWindow(`otpreq:${key}`);
    if (count !== null && count > maxPerKey) {
      return { ok: false, code: 'auth_otp_limit', retryAfterMs: WINDOW_MS };
    }
    const claimed = cooldown ? await redisClaimCooldown(`otpcooldown:${key}`) : true;
    if (claimed === false && count !== null) {
      return { ok: false, code: 'auth_otp_cooldown', retryAfterMs: COOLDOWN_MS };
    }
    const ipCount = await redisIncrWindow(`otpreqip:${ip}`);
    if (ipCount !== null && ipCount > MAX_REQUEST_PER_IP) {
      return { ok: false, code: 'auth_otp_limit', retryAfterMs: WINDOW_MS };
    }

    let released = false;
    return {
      ok: true,
      release: async () => {
        if (released) return;
        released = true;
        const redis = getRedis();
        try {
          if (claimed) await redis.del(`otpcooldown:${key}`);
          // DECR alone can leave a key with no TTL (or a negative count) if the
          // window expired between the INCR and now, which would then block the
          // target forever. Only decrement while there is something to
          // decrement, and drop the key entirely at zero.
          if (count !== null && count > 0) {
            const left = await redis.decr(`otpreq:${key}`);
            if (left <= 0) await redis.del(`otpreq:${key}`);
          }
        } catch (e) {
          console.error('[OTP-GUARD] release failed:', e.message);
        }
      },
    };
  }

  const now = Date.now();
  const target = memoryEntry(key);
  if (now < target.cooldownUntil) {
    return { ok: false, code: 'auth_otp_cooldown', retryAfterMs: now - target.cooldownUntil };
  }
  target.count += 1;
  if (target.count > maxPerKey) {
    memory.set(key, target);
    return { ok: false, code: 'auth_otp_limit', retryAfterMs: WINDOW_MS };
  }
  if (cooldown) target.cooldownUntil = now + COOLDOWN_MS;
  memory.set(key, target);

  const ipEntry = memoryEntry(`ip:${ip}`);
  ipEntry.count += 1;
  if (ipEntry.count > MAX_REQUEST_PER_IP) {
    memory.set(`ip:${ip}`, ipEntry);
    return { ok: false, code: 'auth_otp_limit', retryAfterMs: WINDOW_MS };
  }
  memory.set(`ip:${ip}`, ipEntry);

  let released = false;
  return {
    ok: true,
    release: async () => {
      if (released) return;
      released = true;
      const entry = memoryEntry(key);
      // Clamp: the window may have rolled over between the check and now.
      if (entry.cooldownUntil === now + COOLDOWN_MS) entry.cooldownUntil = 0;
      entry.count = Math.max(0, entry.count - 1);
      memory.set(key, entry);
    },
  };
}

function cleanPhone(phone) {
  return String(phone).replace(/\D/g, '');
}

// Express middleware: guard the send-otp-style routes. `kind` picks the target
// key extracted from req.body — 'phone' | 'email'. `field` overrides which body
// property holds the target: the KYC routes send it as `value` (the channel is
// already fixed by the URL), so without this they were never throttled at all —
// an authenticated seller could drive unlimited paid SMS.
function otpSendGuard(kind = 'phone', field = kind) {
  return async (req, res, next) => {
    const raw = req.body && req.body[field];
    if (!raw) return next();

    const key = kind === 'phone' ? `phone:${cleanPhone(raw)}` : `email:${String(raw).trim().toLowerCase()}`;
    const ip = req.ip || req.connection?.remoteAddress || 'unknown';

    const result = await checkTarget(key, ip).catch(() => ({ ok: true }));
    if (!result.ok) {
      res.setHeader('Retry-After', String(Math.max(1, Math.ceil((result.retryAfterMs || COOLDOWN_MS) / 1000))));
      return res.status(429).json({
        error: result.code,
        message: result.code === 'auth_otp_cooldown'
          ? 'Subiri sekunde chache kabla ya kutuma OTP nyingine.'
          : 'Umeomba mara nyingi sana. Jaribu baada ya dakika 15.',
        retryAfterMs: result.retryAfterMs,
        success: false,
      });
    }
    // Hand the rollback to the handler. It is called only when the OTP could not
    // be delivered, so a gateway fault does not cost the user their cooldown and
    // a quota slot for a code that was never sent.
    if (typeof result.release === 'function') req.otpRelease = result.release;
    next();
  };
}

// Verify-side guard for the KYC contact routes. The auth verify routes use the
// shared otpVerifyLimiter; the KYC ones had no attempt ceiling of their own, so
// the 5-attempt lockout lived only inside the service and was not applied on
// the send path at all.
function otpVerifyGuard(kind = 'phone', field = kind) {
  return async (req, res, next) => {
    const raw = req.body && req.body[field];
    if (!raw) return next();

    const key = kind === 'phone' ? `phone:${cleanPhone(raw)}` : `email:${String(raw).trim().toLowerCase()}`;
    const ip = req.ip || req.connection?.remoteAddress || 'unknown';

    const result = await checkTarget(`verify:${key}`, ip, {
      cooldown: false,
      maxPerKey: VERIFY_MAX_PER_KEY,
    }).catch(() => ({ ok: true }));
    if (!result.ok) {
      res.setHeader('Retry-After', String(Math.max(1, Math.ceil((result.retryAfterMs || WINDOW_MS) / 1000))));
      return res.status(429).json({
        error: result.code,
        message: 'Umejaribu mara nyingi sana. Subiri sekunde chache.',
        retryAfterMs: result.retryAfterMs,
        success: false,
      });
    }
    next();
  };
}

// Undoes a guard claim when the handler could not deliver the OTP. Safe to call
// when no claim was made (no-op) and safe to call more than once.
async function releaseOtpClaim(req) {
  if (!req || typeof req.otpRelease !== 'function') return;
  const release = req.otpRelease;
  req.otpRelease = null;
  await release().catch(() => null);
}

module.exports = { otpSendGuard, otpVerifyGuard, checkTarget, cleanPhone, releaseOtpClaim };