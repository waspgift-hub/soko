const { Router } = require('express');
const { z } = require('zod');
const { rateLimit } = require('../../middleware/rateLimiter');
const { validate } = require('../../middleware/validation');
const { createRequest } = require('./controller');

const router = Router();

// 5/hour per IP keeps spam/bulk scraping of the public form in check.
const deletionRequestLimiter = rateLimit({ max: 5, windowMs: 60 * 60 * 1000 });

const deletionRequestSchema = z.object({
  fullName: z.string().trim().min(1).max(120).optional(),
  email: z.string().trim().toLowerCase().max(254).email('Invalid email address'),
  phone: z.string().trim().max(20).optional(),
  reason: z.string().trim().max(2000).optional(),
});

router.post(
  '/requests',
  deletionRequestLimiter,
  // Honeypot: bots fill the hidden "website" field — acknowledge silently so we
  // never save their payload, while real users pass through untouched.
  (req, res, next) => {
    if (req.body && typeof req.body.website === 'string' && req.body.website.length > 0) {
      return res.status(201).json({ success: true });
    }
    next();
  },
  validate({ body: deletionRequestSchema }),
  createRequest
);

module.exports = router;