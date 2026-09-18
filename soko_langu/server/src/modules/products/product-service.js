const crypto = require('crypto');
const { getPrisma } = require('../../config/database');
const { getReadPrisma } = require('../../config/database');

function httpError(status, message) {
  const err = new Error(message);
  err.status = status;
  return err;
}

function slugify(title) {
  const base = String(title || '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 60) || 'product';
  return `${base}-${crypto.randomBytes(3).toString('hex')}`;
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const PUBLIC_SELECT = {
  id: true,
  title: true,
  slug: true,
  description: true,
  price: true,
  originalPrice: true,
  currency: true,
  stock: true,
  status: true,
  condition: true,
  createdAt: true,
  seller: { select: { id: true, storeName: true, storeSlug: true } },
  media: { orderBy: { sortOrder: 'asc' }, take: 4 },
  // List cards need the legacy-only metadata (boost/feature flags, category,
  // location, ratings) that has no Postgres column. Prisma cannot project
  // selected JSON keys (SelectionSetOnScalar is unimplemented for Postgres),
  // so the whole snapshot is returned — same contract as the detail endpoint.
  snapshot: true,
};

function buildListWhere({ q, categoryId, minPrice, maxPrice, boosted, featured, subcategory, sellerProfileId, ids }) {
  const where = { status: 'published', deletedAt: null };
  if (categoryId) where.categoryId = categoryId;
  if (sellerProfileId) where.sellerId = sellerProfileId;
  if (minPrice != null || maxPrice != null) {
    where.price = {};
    if (minPrice != null) where.price.gte = BigInt(minPrice);
    if (maxPrice != null) where.price.lte = BigInt(maxPrice);
  }
  const filters = [];
  if (q) {
    filters.push({
      OR: [
        { title: { contains: q, mode: 'insensitive' } },
        { description: { contains: q, mode: 'insensitive' } },
      ],
    });
  }
  // Batch by external id: the app hands back opaque legacy Firestore ids
  // (wishlist, recently-viewed) that map to neither the Postgres uuid nor the
  // slug, so match each form. uuid-shaped ids go against the id column; the
  // rest can only be slugs or legacy ids — Postgres rejects uuid-column
  // comparisons with mixed-shaped strings, so the sets stay typed.
  if (ids && ids.length) {
    const uuids = ids.filter((id) => UUID_RE.test(id));
    const others = ids.filter((id) => !UUID_RE.test(id));
    const orParts = [];
    if (uuids.length) orParts.push({ id: { in: uuids } });
    if (others.length) orParts.push({ slug: { in: others } });
    for (const id of ids) {
      orParts.push({ snapshot: { path: ['legacyId'], equals: id } });
    }
    filters.push({ OR: orParts });
  }
  // The legacy boost/feature/subcategory signals live in snapshot JSON during
  // the migration window; filter them with JSON path probes so the featured
  // carousel and category pages read from Postgres with Firestore semantics.
  if (boosted) filters.push({ snapshot: { path: ['isBoosted'], equals: true } });
  if (featured) filters.push({ snapshot: { path: ['isFeatured'], equals: true } });
  if (subcategory) filters.push({ snapshot: { path: ['subcategory'], equals: subcategory } });
  if (filters.length) where.AND = filters;
  return where;
}

// Public seller lookup accepts the Postgres SellerProfile id, the Postgres
// User id, or the legacy Firebase UID (Product.sellerId in the App still
// carries the UID via snapshot) so the seller shop resolves every form. The
// uuid-backed branches are only attempted for uuid-shaped inputs — a Firebase
// UID against a uuid column would fail Postgres' cast before any row matched.
async function resolveSellerProfile(idOrUid) {
  const prisma = getPrisma();
  const branches = [{ user: { firebaseUid: idOrUid } }];
  if (UUID_RE.test(idOrUid)) {
    branches.push({ id: idOrUid }, { userId: idOrUid });
  }
  return prisma.sellerProfile.findFirst({
    where: { OR: branches },
    select: { id: true },
  });
}

async function requireSellerProfile(userId) {
  const prisma = getPrisma();
  const profile = await prisma.sellerProfile.findUnique({ where: { userId } });
  if (!profile) throw httpError(404, 'SELLER_PROFILE_NOT_FOUND');
  return profile;
}

async function createProduct({ sellerProfileId, data }) {
  const prisma = getPrisma();
  const snapshot = {
    title: data.title,
    description: data.description || null,
    price: data.price,
    originalPrice: data.originalPrice || null,
    currency: 'TZS',
    stock: data.stock ?? 0,
    condition: data.condition || 'new',
    categoryId: data.categoryId || null,
    weightGrams: data.weightGrams || null,
    shippingRequired: data.shippingRequired !== false,
  };
  try {
    return await prisma.product.create({
      data: {
        sellerId: sellerProfileId,
        title: snapshot.title,
        slug: slugify(snapshot.title),
        description: snapshot.description,
        categoryId: snapshot.categoryId,
        price: BigInt(snapshot.price),
        originalPrice: snapshot.originalPrice != null ? BigInt(snapshot.originalPrice) : null,
        stock: snapshot.stock,
        condition: snapshot.condition,
        weightGrams: snapshot.weightGrams,
        shippingRequired: snapshot.shippingRequired,
        status: 'draft',
        snapshot,
      },
    });
  } catch (e) {
    if (e.code === 'P2002') throw httpError(409, 'SLUG_CONFLICT_RETRY');
    throw e;
  }
}

async function getOwnedProduct({ id, sellerProfileId }) {
  const prisma = getPrisma();
  const product = await prisma.product.findFirst({
    where: { id, sellerId: sellerProfileId, deletedAt: null },
  });
  if (!product) throw httpError(404, 'PRODUCT_NOT_FOUND');
  return product;
}

async function updateProduct({ id, sellerProfileId, data }) {
  const prisma = getPrisma();
  await getOwnedProduct({ id, sellerProfileId });
  const allowed = ['title', 'description', 'categoryId', 'price', 'originalPrice', 'stock', 'condition', 'weightGrams', 'shippingRequired'];
  const patch = {};
  for (const key of allowed) {
    if (data[key] !== undefined) {
      if (key === 'price' || key === 'originalPrice') {
        patch[key] = data[key] != null ? BigInt(data[key]) : null;
      } else {
        patch[key] = data[key];
      }
    }
  }
  return prisma.product.update({ where: { id }, data: patch });
}

async function setStatus({ id, sellerProfileId, status }) {
  const prisma = getPrisma();
  const product = await getOwnedProduct({ id, sellerProfileId });
  if (status === 'published') {
    if (!product.title || Number(product.price) <= 0) {
      throw httpError(400, 'PUBLISH_REQUIRES_TITLE_AND_PRICE');
    }
  }
  return prisma.product.update({ where: { id }, data: { status } });
}

async function softDelete({ id, sellerProfileId }) {
  const prisma = getPrisma();
  await getOwnedProduct({ id, sellerProfileId });
  return prisma.product.update({ where: { id }, data: { status: 'deleted', deletedAt: new Date() } });
}

async function listProducts({ q, categoryId, minPrice, maxPrice, boosted, featured, subcategory, sellerId, ids, page = 1, limit = 20 }) {
  // Catalog reads go through the read replica when one is configured: public
  // browsing tolerates lag and must never compete for primary connections.
  const prisma = getReadPrisma();
  let sellerProfileId;
  if (sellerId) {
    const profile = await resolveSellerProfile(sellerId);
    // No seller row means no products: a sentinel uuid keeps the count at zero
    // instead of widening the query to the whole catalog (and the column needs
    // uuid-shaped values or Postgres rejects the comparison).
    sellerProfileId = profile?.id || '00000000-0000-0000-0000-000000000000';
  }
  const where = buildListWhere({ q, categoryId, minPrice, maxPrice, boosted, featured, subcategory, sellerProfileId, ids });
  const [items, total] = await Promise.all([
    prisma.product.findMany({
      where,
      select: PUBLIC_SELECT,
      orderBy: { createdAt: 'desc' },
      take: Number(limit),
      skip: (Number(page) - 1) * Number(limit),
    }),
    prisma.product.count({ where }),
  ]);
  return { items, pagination: { page: Number(page), limit: Number(limit), total } };
}

async function listSellerProducts({ sellerProfileId, page = 1, limit = 20 }) {
  const prisma = getPrisma();
  const where = { sellerId: sellerProfileId, deletedAt: null };
  const [items, total] = await Promise.all([
    prisma.product.findMany({
      where,
      include: { media: { orderBy: { sortOrder: 'asc' }, take: 4 } },
      orderBy: { updatedAt: 'desc' },
      take: Number(limit),
      skip: (Number(page) - 1) * Number(limit),
    }),
    prisma.product.count({ where }),
  ]);
  return { items, pagination: { page: Number(page), limit: Number(limit), total } };
}

async function getProduct(idOrSlug) {
  const prisma = getReadPrisma();
  const isUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(idOrSlug);
  const product = await prisma.product.findFirst({
    where: {
      ...(isUuid ? { OR: [{ id: idOrSlug }, { slug: idOrSlug }] } : { slug: idOrSlug }),
      status: 'published',
      deletedAt: null,
    },
    select: {
      ...PUBLIC_SELECT,
      category: { select: { id: true, name: true, slug: true } },
      snapshot: true,
    },
  });
  if (!product) throw httpError(404, 'PRODUCT_NOT_FOUND');
  return product;
}

async function attachMedia({ id, sellerProfileId, items }) {
  const prisma = getPrisma();
  await getOwnedProduct({ id, sellerProfileId });
  const rows = await Promise.all(
    items.map((m, i) =>
      prisma.productMedia.create({
        data: {
          productId: id,
          type: m.type || 'image',
          r2Key: m.r2Key,
          thumbnailR2Key: m.thumbnailR2Key || null,
          variantUrls: m.variantUrls || undefined,
          width: m.width || null,
          height: m.height || null,
          durationSeconds: m.durationSeconds || null,
          fileSizeBytes: m.fileSizeBytes != null ? BigInt(m.fileSizeBytes) : null,
          sortOrder: m.sortOrder != null ? m.sortOrder : i,
        },
      })
    )
  );
  return rows;
}

async function moderate({ id, status }) {
  const prisma = getPrisma();
  const product = await prisma.product.findUnique({ where: { id } });
  if (!product) throw httpError(404, 'PRODUCT_NOT_FOUND');
  return prisma.product.update({ where: { id }, data: { status } });
}

module.exports = {
  requireSellerProfile,
  resolveSellerProfile,
  createProduct,
  updateProduct,
  setStatus,
  softDelete,
  buildListWhere,
  listProducts,
  listSellerProducts,
  getProduct,
  attachMedia,
  moderate,
};
