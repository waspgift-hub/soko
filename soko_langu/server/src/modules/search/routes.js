const { Router } = require('express');
const { optionalAuth } = require('../../middleware/auth');
const { validate } = require('../../middleware/validation');
const { z } = require('zod');
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
    const results = await searchService.searchProducts(req.query);
    res.json({ success: true, data: results });
  }
);

module.exports = router;
