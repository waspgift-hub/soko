const { Router } = require('express');
const { z } = require('zod');
const { rateLimit } = require('../../middleware/rateLimiter');
const { validate } = require('../../middleware/validation');
const { verifyTurnstile } = require('../../utils/turnstile');
const { createRequest } = require('./controller');

const router = Router();

// 5/hour per IP keeps spam/bulk scraping of the public form in check.
const deletionRequestLimiter = rateLimit({ max: 5, windowMs: 60 * 60 * 1000 });

const deletionRequestSchema = z.object({
  fullName: z.string().trim().min(1).max(120).optional(),
  email: z.string().trim().toLowerCase().max(254).email('Invalid email address'),
  phone: z.string().trim().max(20).optional(),
  reason: z.string().trim().max(2000).optional(),
  website: z.string().optional().default(''),
  'cf-turnstile-response': z.string().optional(),
  turnstileToken: z.string().optional(),
  turnstile_token: z.string().optional(),
});

router.post(
  '/requests',
  deletionRequestLimiter,
  // Honeypot: bots fill the hidden "website" field â€” acknowledge silently so we
  // never save their payload, while real users pass through untouched.
  (req, res, next) => {
    if (req.body && typeof req.body.website === 'string' && req.body.website.length > 0) {
      return res.status(201).json({ success: true });
    }
    next();
  },
  async (req, res, next) => {
    const turnstile = await verifyTurnstile(req, { expectedAction: 'data_deletion' });
    if (!turnstile.ok) {
      return res.status(turnstile.status || 403).json({
        success: false,
        error: turnstile.code || 'TURNSTILE_FAILED',
        message: turnstile.message || 'Bot verification failed. Please try again.',
      });
    }
    return next();
  },
  validate({ body: deletionRequestSchema }),
  createRequest
);

module.exports = router;