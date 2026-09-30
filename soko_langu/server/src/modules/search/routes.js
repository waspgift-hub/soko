const { Router } = require('express');
const { optionalAuth } = require('../../middleware/auth');
const { validate } = require('../../middleware/validation');
const { z } = require('zod');
const cache = require('../../../cache');
const searchService = require('./search-service');

const router = Router();

// Search products
router.get(
  '/products',
  optionalAuth,
  validate({
    query: z.object({
      q: z.string().min(1).max(100).optional(),
      categoryId: z.string().uuid().optional(),
      minPrice: z.coerce.number().int().nonnegative().optional(),
      maxPrice: z.coerce.number().int().nonnegative().optional(),
      sort: z.enum(['relevance', 'price_asc', 'price_desc', 'newest']).default('relevance'),
      page: z.coerce.number().int().min(1).default(1),
      limit: z.coerce.number().int().min(1).max(50).default(20),
    }),
  }),
  async (req, res) => {
    // Cache result per exact filter set so repeat visitors share one Firestore
    // scan per window instead of each paying a full CAP=1000 read (Spark quota).
    // Short TTL keeps results fresh; single-flight
    // inside getOrCompute stops a cold-hits stampede.
    const key = `search:products:${JSON.stringify(req.query)}`;
    const data = await cache.getOrCompute(key, () =>
      searchService.searchProducts({
        ...req.query,
        ipAddress: req.ip,
        userAgent: req.headers['user-agent'] || '',
      }),
      30 * 1000);
    res.json({ success: true, data });
  }
);

module.exports = router;
