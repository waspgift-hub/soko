const { getRedis } = require('../config/redis');

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
    keyGenerator = (req) => req.ip || req.connection.remoteAddress || 'unknown',
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
      return res.status(429).json({ error: message });
    }

    next();
  };
}

// Pre-configured rate limiters
const generalLimiter = rateLimit({ max: 100, windowMs: 60000 });
const authLimiter = rateLimit({ max: 10, windowMs: 900000 });
const paymentLimiter = rateLimit({ max: 5, windowMs: 60000 });
const searchLimiter = rateLimit({ max: 30, windowMs: 60000 });

// Security-specific limiters (per plan Phase 12.3)
const otpRequestLimiter = rateLimit({ max: 3, windowMs: 900000 });      // 3/15min per phone
const otpVerifyLimiter = rateLimit({ max: 5, windowMs: 900000 });        // 5/15min per phone
const checkoutLimiter = rateLimit({ max: 5, windowMs: 60000 });          // 5/min per user
const withdrawalLimiter = rateLimit({ max: 3, windowMs: 3600000 });      // 3/hour per seller
const loginLimiter = rateLimit({ max: 5, windowMs: 900000 });            // 5/15min per email
const commentLimiter = rateLimit({ max: 10, windowMs: 60000 });          // 10/min per user
const messageLimiter = rateLimit({ max: 30, windowMs: 60000 });          // 30/min per user

module.exports = {
  rateLimit,
  generalLimiter,
  authLimiter,
  paymentLimiter,
  searchLimiter,
  otpRequestLimiter,
  otpVerifyLimiter,
  checkoutLimiter,
  withdrawalLimiter,
  loginLimiter,
  commentLimiter,
  messageLimiter,
};
