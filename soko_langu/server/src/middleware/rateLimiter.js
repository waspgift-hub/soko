const crypto = require('crypto');
const { getRedis } = require('../config/redis');
const { jsonError } = require('../utils/http');

// Behind the Cloudflare Worker, req.ip is a Cloudflare edge IP shared by many
// users (mobile CGNAT makes it worse), so per-IP limits would throttle
// strangers together — or never fire at all. When the edge proves itself with
// the shared EDGE_SECRET (timing-safe compare), trust cf-connecting-ip, which
// Cloudflare sets and which cannot be spoofed through the worker.
// Direct-to-origin traffic, or an unset EDGE_SECRET, keeps keying on the
// socket IP exactly as before — no behaviour change until both sides opt in.
function edgeVerified(req) {
  const secret = process.env.EDGE_SECRET;
  const presented = req.headers && req.headers['x-soko-edge'];
  if (!secret || !presented) return false;
  const a = Buffer.from(String(presented));
  const b = Buffer.from(secret);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

function clientIp(req) {
  if (edgeVerified(req)) {
    const cfIp = req.headers['cf-connecting-ip'];
    if (cfIp) return String(cfIp).split(',')[0].trim();
  }
  return req.ip || (req.connection && req.connection.remoteAddress) || 'unknown';
}

// In-memory fallback when Redis is unavailable
const memoryStore = new Map();

// Cleanup memory store every 5 minutes
setInterval(() => {
  const now = Date.now();
  for (const [key, data] of memoryStore.entries()) {
    if (now - data.windowStart > 60000) {
      memoryStore.delete(key);
    }
  }
}, 300000).unref();

function rateLimit(options = {}) {
  const {
    windowMs = 60000,
    max = 100,
    keyGenerator = (req) => clientIp(req),
    skip = () => false,
    message = 'Too many requests',
  } = options;

  return async (req, res, next) => {
    if (skip(req)) {
      return next();
    }

    const key = `ratelimit:${keyGenerator(req)}`;
    const redis = getRedis();
    
    let current = 0;
    let ttl = 0;

    if (redis && redis.status === 'ready') {
      try {
        const multi = redis.multi();
        multi.incr(key);
        multi.pttl(key);
        
        const results = await multi.exec();
        current = results[0][1];
        ttl = results[1][1];
        
        if (ttl === -1) {
          await redis.pexpire(key, windowMs);
          ttl = windowMs;
        }
      } catch (error) {
        // Fallback to memory
        const data = memoryStore.get(key) || { count: 0, windowStart: Date.now() };
        const elapsed = Date.now() - data.windowStart;
        
        if (elapsed > windowMs) {
          data.count = 0;
          data.windowStart = Date.now();
        }
        
        data.count++;
        memoryStore.set(key, data);
        current = data.count;
        ttl = windowMs - elapsed;
      }
    } else {
      // Memory fallback
      const data = memoryStore.get(key) || { count: 0, windowStart: Date.now() };
      const elapsed = Date.now() - data.windowStart;
      
      if (elapsed > windowMs) {
        data.count = 0;
        data.windowStart = Date.now();
      }
      
      data.count++;
      memoryStore.set(key, data);
      current = data.count;
      ttl = windowMs - elapsed;
    }

    res.setHeader('X-RateLimit-Limit', max);
    res.setHeader('X-RateLimit-Remaining', Math.max(0, max - current));
    res.setHeader('X-RateLimit-Reset', Math.ceil((Date.now() + ttl) / 1000));

    if (current > max) {
      return jsonError(res, { status: 429, code: 'RATE_LIMITED', message });
    }

    next();
  };
}

// Pre-configured rate limiters
const generalLimiter = rateLimit({ max: 100, windowMs: 60000 });
// Admin dashboard calls several endpoints (stats/analytics/timeseries/online/
// finance) on first paint plus per-section lazy loads — allow a wider burst so
// a legitimate admin session is never mistaken for a crawler.
const adminLimiter = rateLimit({ max: 300, windowMs: 60000 });
const authLimiter = rateLimit({ max: 10, windowMs: 900000 });
const paymentLimiter = rateLimit({ max: 5, windowMs: 60000 });
const searchLimiter = rateLimit({ max: 30, windowMs: 60000 });
// LLM calls are far slower and far costlier than a Firestore read, and each one
// may consume two provider calls when failover fires. Tighter than
// generalLimiter so one abusive client cannot drain both providers' quota.
// Per-IP, not per-user: this middleware runs before the route verifies the
// Firebase token, so no uid is available to key on. The Flutter app enforces a
// per-device limit on top (30 chat / 60 summary per hour, groq_service.dart).
const aiLimiter = rateLimit({ max: 20, windowMs: 60000 });

// Security-specific limiters (per plan Phase 12.3)
const otpRequestLimiter = rateLimit({ max: 100, windowMs: 60000 });      // loose global ceiling; per-target guard lives in otpGuard
const otpVerifyLimiter = rateLimit({ max: 30, windowMs: 900000 });        // 30/15min per source; real brute-force guard is the 5-attempt cap per OTP key
const checkoutLimiter = rateLimit({ max: 5, windowMs: 60000 });          // 5/min per user
const withdrawalLimiter = rateLimit({ max: 3, windowMs: 3600000 });      // 3/hour per seller
const loginLimiter = rateLimit({ max: 5, windowMs: 900000 });            // 5/15min per email
const commentLimiter = rateLimit({ max: 10, windowMs: 60000 });          // 10/min per user
const messageLimiter = rateLimit({ max: 30, windowMs: 60000 });          // 30/min per user

module.exports = {
  rateLimit,
  generalLimiter,
  adminLimiter,
  authLimiter,
  paymentLimiter,
  searchLimiter,
  aiLimiter,
  otpRequestLimiter,
  otpVerifyLimiter,
  checkoutLimiter,
  withdrawalLimiter,
  loginLimiter,
  commentLimiter,
  messageLimiter,
};
