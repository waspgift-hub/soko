const { Router } = require('express');
const { authenticate, requireActive, verifyAdmin } = require('../../middleware/auth');
const { validate } = require('../../middleware/validation');
const { z } = require('zod');
const service = require('./product-service');
const { getPrisma } = require('../../config/database');
const { writeAudit, auditFromReq } = require('../../services/audit');

const router = Router();

const productBody = z.object({
  title: z.string().min(3).max(200),
  description: z.string().max(5000).optional(),
  categoryId: z.string().uuid().optional(),
  price: z.number().int().positive(),
  originalPrice: z.number().int().positive().optional(),
  stock: z.number().int().min(0).default(0),
  condition: z.enum(['new', 'used_like_new', 'used_good', 'used_fair', 'refurbished']).default('new'),
  weightGrams: z.number().int().positive().optional(),
  shippingRequired: z.boolean().default(true),
});

const productPatch = z.object({
  title: z.string().min(3).max(200).optional(),
  description: z.string().max(5000).optional(),
  categoryId: z.string().uuid().optional(),
  price: z.number().int().positive().optional(),
  originalPrice: z.number().int().positive().nullable().optional(),
  stock: z.number().int().min(0).optional(),
  condition: z.enum(['new', 'used_like_new', 'used_good', 'used_fair', 'refurbished']).optional(),
  weightGrams: z.number().int().positive().nullable().optional(),
  shippingRequired: z.boolean().optional(),
});

function serviceError(res, e) {
  return res.status(e.status || 500).json({ error: e.message || 'Product operation failed' });
}

// Public catalog
router.get(
  '/',
  validate({
    query: z.object({
      q: z.string().max(100).optional(),
      categoryId: z.string().uuid().optional(),
      minPrice: z.coerce.number().int().min(0).optional(),
      maxPrice: z.coerce.number().int().min(0).optional(),
      page: z.coerce.number().int().min(1).default(1),
      limit: z.coerce.number().int().min(1).max(50).default(20),
    }),
  }),
  async (req, res) => {
    const data = await service.listProducts(req.query);
    res.json({ success: true, data });
  }
);

// Public categories
router.get('/categories', async (req, res) => {
  const prisma = getPrisma();
  const categories = await prisma.category.findMany({
    where: { isActive: true },
    select: { id: true, name: true, slug: true, parentId: true, iconUrl: true, sortOrder: true },
    orderBy: { sortOrder: 'asc' },
  });
  res.json({ success: true, data: categories });
});

// Seller's own products (drafts included)
router.get('/seller', authenticate, requireActive, async (req, res) => {
  try {
    const profile = await service.requireSellerProfile(req.user.id);
    const data = await service.listSellerProducts({
      sellerProfileId: profile.id,
      page: req.query.page,
      limit: req.query.limit,
    });
    res.json({ success: true, data });
  } catch (e) {
    serviceError(res, e);
  }
});

// Public detail by id or slug
router.get('/:idOrSlug', async (req, res) => {
  try {
    const data = await service.getProduct(req.params.idOrSlug);
    res.json({ success: true, data });
  } catch (e) {
    serviceError(res, e);
  }
});

// Create draft (seller)
router.post(
  '/',
  authenticate,
  requireActive,
  validate({ body: productBody }),
  async (req, res) => {
    try {
      const profile = await service.requireSellerProfile(req.user.id);
      const product = await service.createProduct({
        sellerProfileId: profile.id,
        data: req.body,
      });
      await writeAudit({
        ...auditFromReq(req),
        action: 'product.create',
        entityType: 'product',
        entityId: product.id,
      });
      res.status(201).json({ success: true, data: product });
    } catch (e) {
      serviceError(res, e);
    }
  }
);

// Update (seller owner)
router.put(
  '/:id',
  authenticate,
  requireActive,
  validate({ body: productPatch }),
  async (req, res) => {
    try {
      const profile = await service.requireSellerProfile(req.user.id);
      const product = await service.updateProduct({
        id: req.params.id,
        sellerProfileId: profile.id,
        data: req.body,
      });
      res.json({ success: true, data: product });
    } catch (e) {
      serviceError(res, e);
    }
  }
);

// Publish / unpublish (seller owner)
router.post('/:id/publish', authenticate, requireActive, async (req, res) => {
  try {
    const profile = await service.requireSellerProfile(req.user.id);
    const product = await service.setStatus({
      id: req.params.id,
      sellerProfileId: profile.id,
      status: 'published',
    });
    await writeAudit({
      ...auditFromReq(req),
      action: 'product.publish',
      entityType: 'product',
      entityId: product.id,
    });
    res.json({ success: true, data: product });
  } catch (e) {
    serviceError(res, e);
  }
});

router.post('/:id/unpublish', authenticate, requireActive, async (req, res) => {
  try {
    const profile = await service.requireSellerProfile(req.user.id);
    const product = await service.setStatus({
      id: req.params.id,
      sellerProfileId: profile.id,
      status: 'draft',
    });
    res.json({ success: true, data: product });
  } catch (e) {
    serviceError(res, e);
  }
});

// Attach R2 media (seller owner)
router.post(
  '/:id/media',
  authenticate,
  requireActive,
  validate({
    body: z.object({
      items: z
        .array(
          z.object({
            type: z.enum(['image', 'video']).default('image'),
            r2Key: z.string().min(1),
            thumbnailR2Key: z.string().optional(),
            variantUrls: z.record(z.string()).optional(),
            width: z.number().int().positive().optional(),
            height: z.number().int().positive().optional(),
            durationSeconds: z.number().positive().optional(),
            fileSizeBytes: z.number().int().positive().optional(),
            sortOrder: z.number().int().min(0).optional(),
          })
        )
        .min(1)
        .max(10),
    }),
  }),
  async (req, res) => {
    try {
      const profile = await service.requireSellerProfile(req.user.id);
      const rows = await service.attachMedia({
        id: req.params.id,
        sellerProfileId: profile.id,
        items: req.body.items,
      });
      res.status(201).json({ success: true, data: rows });
    } catch (e) {
      serviceError(res, e);
    }
  }
);

// Soft delete (seller owner)
router.delete('/:id', authenticate, requireActive, async (req, res) => {
  try {
    const profile = await service.requireSellerProfile(req.user.id);
    const product = await service.softDelete({ id: req.params.id, sellerProfileId: profile.id });
    await writeAudit({
      ...auditFromReq(req),
      action: 'product.delete',
      entityType: 'product',
      entityId: product.id,
    });
    res.json({ success: true, data: product });
  } catch (e) {
    serviceError(res, e);
  }
});

// Moderate (admin): published/suspended/rejected/draft
router.put(
  '/:id/moderate',
  authenticate,
  verifyAdmin,
  validate({
    body: z.object({
      status: z.enum(['draft', 'published', 'suspended', 'rejected']),
      reason: z.string().max(500).optional(),
    }),
  }),
  async (req, res) => {
    try {
      const product = await service.moderate({ id: req.params.id, status: req.body.status });
      await writeAudit({
        ...auditFromReq(req),
        action: 'product.moderate',
        entityType: 'product',
        entityId: product.id,
        newState: { status: req.body.status, reason: req.body.reason || null },
      });
      res.json({ success: true, data: product });
    } catch (e) {
      serviceError(res, e);
    }
  }
);

module.exports = router;
