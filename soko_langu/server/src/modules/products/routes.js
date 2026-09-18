const { Router } = require('express');
const { authenticate, authenticateAdmin, requireActive, verifyAdmin } = require('../../middleware/auth');
const { validate } = require('../../middleware/validation');
const { z } = require('zod');
const service = require('./product-service');
const { mirrorProduct, mirrorProductDelete } = require('./product-mirror');
const { getReadPrisma } = require('../../config/database');
const { writeAudit, auditFromReq } = require('../../services/audit');
const cache = require('../../../cache');

const router = Router();

// Legacy catalog metadata the seller hub sends alongside every listing (the
// add/edit screens store it on Firestore docs today). These live in snapshot
// JSON until their Postgres columns land, so new v1 listings round-trip the
// exact shape the app reads.
const legacyFields = {
  category: z.string().max(80).optional(),
  subcategory: z.string().max(80).optional(),
  brand: z.string().max(80).optional(),
  location: z.string().max(120).optional(),
  district: z.string().max(120).optional(),
  barcode: z.string().max(100).nullable().optional(),
  isWholesale: z.boolean().optional(),
  wholesaleTiers: z
    .array(
      z.object({
        minQuantity: z.coerce.number().int().min(1),
        pricePerUnit: z.number().min(0),
      })
    )
    .max(10)
    .optional(),
  variants: z
    .array(
      z.object({
        name: z.string().min(1).max(80),
        value: z.string().min(1).max(80),
        priceAdjustment: z.number().optional(),
        stock: z.coerce.number().int().min(0),
      })
    )
    .max(20)
    .optional(),
  attributes: z.record(z.any()).optional(),
  images: z.array(z.string().min(1).max(500)).max(12).optional(),
  imageMetadata: z.array(z.record(z.any())).max(12).optional(),
  videoUrl: z.string().max(500).nullable().optional(),
  searchKeywords: z.array(z.string().min(1).max(60)).max(60).optional(),
};

// Condition accepts the app's literal values ('used' included) plus the v1
// vocabulary; the column is a free VarChar so nothing constrains it.
const CONDITION_ENUM = ['new', 'used', 'refurbished', 'used_like_new', 'used_good', 'used_fair'];

const productBody = z.object({
  title: z.string().min(3).max(200),
  description: z.string().max(5000).optional(),
  categoryId: z.string().uuid().optional(),
  price: z.number().int().positive(),
  originalPrice: z.number().int().positive().optional(),
  stock: z.number().int().min(0).default(0),
  condition: z.enum(CONDITION_ENUM).default('new'),
  weightGrams: z.number().int().positive().optional(),
  shippingRequired: z.boolean().default(true),
  ...legacyFields,
});

const productPatch = z.object({
  title: z.string().min(3).max(200).optional(),
  description: z.string().max(5000).optional(),
  categoryId: z.string().uuid().nullable().optional(),
  price: z.number().int().positive().optional(),
  originalPrice: z.number().int().positive().nullable().optional(),
  stock: z.number().int().min(0).optional(),
  condition: z.enum(CONDITION_ENUM).optional(),
  weightGrams: z.number().int().positive().nullable().optional(),
  shippingRequired: z.boolean().optional(),
  ...legacyFields,
});

// Every mutation echoes the Postgres row into the legacy Firestore products
// doc so boosts/comments/deep-link reads keying off {uuid} keep working.
function sellerContext(profile, req) {
  return { sellerFirebaseUid: req.user?.firebaseUid || null, sellerName: profile?.storeName || null };
}

function serviceError(res, e) {
  return res.status(e.status || 500).json({ error: e.message || 'Product operation failed' });
}

// A write to a product invalidates its detail entry by id and slug plus every
// filtered list. Runs after the response so a slow Redis scan never blocks
// the mutation; the next read simply re-warms the value.
function invalidateProductCache(product) {
  const id = product?.id;
  const slug = product?.slug;
  if (id) cache.del(`catalog:product:v1:${id}`);
  if (slug) cache.del(`catalog:product:v1:${slug}`);
  cache.delPattern('catalog:list:v1:*');
}

// Public catalog
router.get(
  '/',
  validate({
    query: z.object({
      q: z.string().max(100).optional(),
      categoryId: z.string().uuid().optional(),
      sellerId: z.string().min(1).max(128).optional(),
      brand: z.string().min(1).max(80).optional(),
      ids: z
        .preprocess(
          (v) => {
            if (typeof v !== 'string') return undefined;
            return v
              .split(',')
              .map((s) => s.trim())
              .filter(Boolean)
              .slice(0, 50);
          },
          z.array(z.string().min(1).max(200)).max(50).optional()
        )
        .optional(),
      minPrice: z.coerce.number().int().min(0).optional(),
      maxPrice: z.coerce.number().int().min(0).optional(),
      boosted: z.enum(['1', 'true', '0', 'false']).transform((v) => v === '1' || v === 'true').optional(),
      featured: z.enum(['1', 'true', '0', 'false']).transform((v) => v === '1' || v === 'true').optional(),
      subcategory: z.string().max(80).optional(),
      page: z.coerce.number().int().min(1).default(1),
      limit: z.coerce.number().int().min(1).max(50).default(20),
    }),
  }),
  async (req, res) => {
    // Key the cache entry on the full filter set so distinct listings stay
    // separate; single-flight prevents a herd from re-running the same query.
    const key = `catalog:list:v1:${JSON.stringify(req.query)}`;
    const data = await cache.getOrCompute(key, () => service.listProducts(req.query), 30 * 1000);
    res.json({ success: true, data });
  }
);

// Public categories
router.get('/categories', async (req, res) => {
  const prisma = getReadPrisma();
  // Category list is near-static and shared by every visitor: route it through
  // the two-tier cache so the in-memory copy (and then Redis) absorbs the
  // cluster-wide read before Prisma is ever called. Single-flight inside
  // getOrCompute collapses a thundering herd into one DB query per expiry.
  const data = await cache.getOrCompute('catalog:categories:v1', async () => {
    const categories = await prisma.category.findMany({
      where: { isActive: true },
      select: { id: true, name: true, slug: true, parentId: true, iconUrl: true, sortOrder: true },
      orderBy: { sortOrder: 'asc' },
    });
    return categories;
  }, 3600 * 1000);
  res.json({ success: true, data });
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
    const data = await cache.getOrCompute(
      `catalog:product:v1:${req.params.idOrSlug}`,
      () => service.getProduct(req.params.idOrSlug),
      30 * 1000
    );
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
      invalidateProductCache(product);
      await mirrorProduct(product, sellerContext(profile, req));
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
      invalidateProductCache(product);
      await mirrorProduct(product, sellerContext(profile, req));
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
    invalidateProductCache(product);
    await mirrorProduct(product, sellerContext(profile, req));
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
    invalidateProductCache(product);
    await mirrorProduct(product, sellerContext(profile, req));
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
      invalidateProductCache({ id: req.params.id });
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
    invalidateProductCache(product);
    await mirrorProductDelete(req.params.id);
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
  authenticateAdmin,
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
      invalidateProductCache(product);
      // Admin moderation has no seller context; the mirror falls back to the
      // snapshot's stored seller fields (buildMirrorDoc handles empty ctx).
      await mirrorProduct(product, {});
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
