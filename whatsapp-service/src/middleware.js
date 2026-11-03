const crypto = require('crypto');
const rateLimit = require('express-rate-limit');
const config = require('./config');

function requireApiKey(req, res, next) {
  if (!config.apiKey) return next();
  const given = Buffer.from(String(req.get('x-api-key') || ''));
  const expected = Buffer.from(config.apiKey);
  const ok = given.length === expected.length && crypto.timingSafeEqual(given, expected);
  if (!ok) return res.status(401).json({ success: false, code: 'UNAUTHORIZED', error: 'Invalid or missing x-api-key' });
  return next();
}

const apiRateLimit = rateLimit({
  windowMs: 60 * 1000,
  limit: config.rateLimitPerMinute,
  standardHeaders: 'draft-7',
  legacyHeaders: false,
  handler: (req, res) => {
    res.status(429).json({ success: false, code: 'RATE_LIMITED', error: 'Too many requests, slow down' });
  },
});

function errorHandler(err, req, res, _next) {
  if (err.type === 'entity.parse.failed') {
    return res.status(400).json({ success: false, code: 'INVALID_JSON', error: 'Request body is not valid JSON' });
  }
  if (err.httpStatus) {
    return res.status(err.httpStatus).json({ success: false, code: err.code, error: err.message, graphCode: err.graphCode });
  }
  console.error('[server] unhandled error:', err);
  return res.status(500).json({ success: false, code: 'INTERNAL_ERROR', error: 'Internal server error' });
}

module.exports = { requireApiKey, apiRateLimit, errorHandler };
