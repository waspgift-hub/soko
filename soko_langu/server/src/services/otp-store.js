// Ephemeral OTP store: Redis primary (5-min TTL), in-memory fallback.
// OTPs must never touch durable tables; memory entries self-expire.
const { getRedis } = require('../config/redis');

const memory = new Map(); // key -> { otpHash, expiresAt, used, attempts }

function withTimeout(promise, ms = 2500) {
  return Promise.race([
    promise,
    new Promise((_, reject) => setTimeout(() => reject(new Error('otp-store timeout')), ms)),
  ]);
}

function redisKey(key) {
  return `otp:${key}`;
}

async function saveOtp(key, otpHash, ttlSeconds = 300) {
  const record = { otpHash, expiresAt: Date.now() + ttlSeconds * 1000, used: false, attempts: 0 };
  try {
    const redis = getRedis();
    if (redis) {
      await withTimeout(redis.setex(redisKey(key), ttlSeconds, JSON.stringify(record)));
      return true;
    }
  } catch (e) {
    console.error('[OTP-STORE] redis save failed, using memory:', e.message);
  }
  memory.set(key, record);
  return true;
}

async function getOtp(key) {
  try {
    const redis = getRedis();
    if (redis) {
      const raw = await withTimeout(redis.get(redisKey(key)));
      if (raw) return JSON.parse(raw);
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
        const ttl = await withTimeout(redis.ttl(redisKey(key)));
        await withTimeout(redis.setex(redisKey(key), Math.max(Number(ttl) || 60, 60), JSON.stringify(record)));
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
        const ttl = await withTimeout(redis.ttl(redisKey(key)));
        await withTimeout(redis.setex(redisKey(key), Math.max(Number(ttl) || 60, 60), JSON.stringify(record)));
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

module.exports = { saveOtp, getOtp, markUsed, bumpAttempts };
