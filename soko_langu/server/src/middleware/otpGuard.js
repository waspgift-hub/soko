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
// Returns { ok: true } or { ok: false, code, retryAfterMs }.
async function checkTarget(key, ip) {
  if (redisReady()) {
    const count = await redisIncrWindow(`otpreq:${key}`);
    if (count !== null && count > MAX_REQUEST_PER_KEY) {
      return { ok: false, code: 'auth_otp_limit', retryAfterMs: WINDOW_MS };
    }
    const claimed = await redisClaimCooldown(`otpcooldown:${key}`);
    if (claimed === false && count !== null) {
      return { ok: false, code: 'auth_otp_cooldown', retryAfterMs: COOLDOWN_MS };
    }
    const ipCount = await redisIncrWindow(`otpreqip:${ip}`);
    if (ipCount !== null && ipCount > MAX_REQUEST_PER_IP) {
      return { ok: false, code: 'auth_otp_limit', retryAfterMs: WINDOW_MS };
    }
    return { ok: true };
  }

  const now = Date.now();
  const target = memoryEntry(key);
  if (now < target.cooldownUntil) {
    return { ok: false, code: 'auth_otp_cooldown', retryAfterMs: now - target.cooldownUntil };
  }
  target.count += 1;
  if (target.count > MAX_REQUEST_PER_KEY) {
    memory.set(key, target);
    return { ok: false, code: 'auth_otp_limit', retryAfterMs: WINDOW_MS };
  }
  target.cooldownUntil = now + COOLDOWN_MS;
  memory.set(key, target);

  const ipEntry = memoryEntry(`ip:${ip}`);
  ipEntry.count += 1;
  if (ipEntry.count > MAX_REQUEST_PER_IP) {
    memory.set(`ip:${ip}`, ipEntry);
    return { ok: false, code: 'auth_otp_limit', retryAfterMs: WINDOW_MS };
  }
  memory.set(`ip:${ip}`, ipEntry);
  return { ok: true };
}

function cleanPhone(phone) {
  return String(phone).replace(/\D/g, '');
}

// Express middleware: guard the send-otp-style routes. `kind` picks the target
// key extracted from req.body — 'phone' | 'email'.
function otpSendGuard(kind = 'phone') {
  return async (req, res, next) => {
    const raw = req.body && req.body[kind];
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
    next();
  };
}

module.exports = { otpSendGuard, checkTarget, cleanPhone };