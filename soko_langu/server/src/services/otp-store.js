// Ephemeral OTP store: Redis primary (5-min TTL), in-memory fallback.
// OTPs must never touch durable tables; memory entries self-expire.
const crypto = require('crypto');
const { getRedis } = require('../config/redis');

const memory = new Map(); // key -> { otpHash, expiresAt, used, attempts }

// The memory fallback is per-process and only for degraded mode: cap it so a
// flood of distinct targets cannot grow the map without bound. FIFO eviction
// (Map preserves insertion order) is fine for 5-minute records.
const MEMORY_MAX_ENTRIES = parseInt(process.env.OTP_MEMORY_MAX || '5000', 10);

function boundedSet(key, record) {
  if (!memory.has(key) && memory.size >= MEMORY_MAX_ENTRIES) {
    const oldest = memory.keys().next();
    if (!oldest.done) memory.delete(oldest.value);
  }
  memory.set(key, record);
}

function withTimeout(promise, ms = 2500) {
  return Promise.race([
    promise,
    new Promise((_, reject) => setTimeout(() => reject(new Error('otp-store timeout')), ms)),
  ]);
}

function redisKey(key) {
  return `otp:${key}`;
}

// Salted OTP hash, stored as `saltHex:hashHex` where
// hashHex = SHA-256(`${saltHex}:${otp}`).
//
// WHY salted: the OTP space is ~1M values, so a bare SHA-256 is a rainbow
// table away from reversal if the store leaks. A 16-byte random salt per
// record makes precomputation useless; verification stays one hash plus a
// timing-safe compare.
function createOtpHash(otp) {
  const salt = crypto.randomBytes(16).toString('hex');
  const hash = crypto.createHash('sha256').update(`${salt}:${String(otp)}`).digest('hex');
  return `${salt}:${hash}`;
}

// Verifies a candidate OTP against a stored hash. Accepts the salted format
// above; unsalted legacy records (at most minutes old at rollout) still verify
// so an in-flight code is never broken by a deploy, and the next resend
// upgrades the record to the salted format.
function verifyOtpHash(otp, stored) {
  if (otp === undefined || otp === null || !stored) return false;
  const s = String(stored);
  const sep = s.indexOf(':');
  if (sep > 0) {
    const salt = s.slice(0, sep);
    const expected = s.slice(sep + 1);
    const candidate = crypto.createHash('sha256').update(`${salt}:${String(otp)}`).digest('hex');
    const a = Buffer.from(candidate, 'hex');
    const b = Buffer.from(expected, 'hex');
    return a.length === b.length && crypto.timingSafeEqual(a, b);
  }
  const candidate = crypto.createHash('sha256').update(String(otp)).digest('hex');
  const a = Buffer.from(candidate);
  const b = Buffer.from(s);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

// Seconds left on a record's own expiry, never extended by later writes.
// attempt bumps and used-flags must NOT lengthen an OTP's life: each wrong
// guess used to re-SETEX with a 60s floor, letting an attacker stretch a code
// indefinitely one guess at a time.
function remainingTtlSeconds(record) {
  return Math.max(Math.ceil((record.expiresAt - Date.now()) / 1000), 1);
}

async function saveOtp(key, otpHash, ttlSeconds = 300) {
  // A resend replaces the code but NOT the attempt counter: otherwise every
  // resend (3 per 15 min) reset the 5-guess lockout and brute force became
  // 5 tries x resends. Attempts carry over while the previous record is still
  // live and unconsumed.
  let attempts = 0;
  try {
    const prev = await getOtp(key);
    if (prev && !prev.used && Date.now() <= prev.expiresAt) {
      attempts = prev.attempts || 0;
    }
  } catch (_) {
    // A store read failure must never block issuing a fresh code.
  }
  const record = { otpHash, expiresAt: Date.now() + ttlSeconds * 1000, used: false, attempts };
  try {
    const redis = getRedis();
    if (redis) {
      await withTimeout(redis.setex(redisKey(key), ttlSeconds, JSON.stringify(record)));
      return true;
    }
  } catch (e) {
    console.error('[OTP-STORE] redis save failed, using memory:', e.message);
  }
  boundedSet(key, record);
  return true;
}

async function getOtp(key) {
  try {
    const redis = getRedis();
    if (redis) {
      const raw = await withTimeout(redis.get(redisKey(key)));
      if (raw) {
        const record = JSON.parse(raw);
        // Redis TTL is the primary expiry, but TTLs are only ever set from
        // expiresAt now — belt and suspenders against a record that outlives
        // its own deadline after a clock jump or manual persist.
        if (Date.now() > record.expiresAt) {
          await withTimeout(redis.del(redisKey(key))).catch(() => null);
          return null;
        }
        return record;
      }
    }
  } catch (e) {
    console.error('[OTP-STORE] redis read failed, using memory:', e.message);
  }
  const record = memory.get(key);
  if (!record) return null;
  if (Date.now() > record.expiresAt) {
    memory.delete(key);
    return null;
  }
  return record;
}

async function markUsed(key) {
  try {
    const redis = getRedis();
    if (redis) {
      const raw = await withTimeout(redis.get(redisKey(key)));
      if (raw) {
        const record = JSON.parse(raw);
        record.used = true;
        await withTimeout(redis.setex(redisKey(key), remainingTtlSeconds(record), JSON.stringify(record)));
      }
    }
  } catch (e) {
    console.error('[OTP-STORE] redis mark-used failed:', e.message);
  }
  const record = memory.get(key);
  if (record) record.used = true;
}

async function bumpAttempts(key) {
  const bump = (record) => {
    record.attempts = (record.attempts || 0) + 1;
    return record.attempts;
  };
  try {
    const redis = getRedis();
    if (redis) {
      const raw = await withTimeout(redis.get(redisKey(key)));
      if (raw) {
        const record = JSON.parse(raw);
        const attempts = bump(record);
        await withTimeout(redis.setex(redisKey(key), remainingTtlSeconds(record), JSON.stringify(record)));
        return attempts;
      }
    }
  } catch (e) {
    console.error('[OTP-STORE] redis attempts failed:', e.message);
  }
  const record = memory.get(key);
  if (!record) return 99;
  return bump(record);
}

// Removes an OTP that was stored but never delivered. Called when the SMS/email
// send fails AFTER the code was saved: leaving the record in place would make
// the user's next attempt collide with the 60s send cooldown (burned by the
// failed attempt) even though no code ever reached them, so a provider outage
// would lock users out for a minute per failed send.
async function clearOtp(key) {
  try {
    const redis = getRedis();
    if (redis) {
      await withTimeout(redis.del(redisKey(key)));
    }
  } catch (e) {
    console.error('[OTP-STORE] redis clear failed:', e.message);
  }
  memory.delete(key);
  return true;
}

module.exports = { saveOtp, getOtp, markUsed, bumpAttempts, clearOtp, createOtpHash, verifyOtpHash };
