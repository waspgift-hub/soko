const crypto = require('crypto');
const { getStore } = require('../../config/database');
const { getReadStore } = require('../../config/database');

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
  seller: { select: { id: true, storeName: true, storeSlug: true, user: { select: { firebaseUid: true, phone: true } } } },
  media: { orderBy: { sortOrder: 'asc' }, take: 4 },
  // List cards need the legacy-only metadata (boost/feature flags, category,
  // location, ratings) that has no Postgres column. The store cannot project
  // selected JSON keys, so the whole snapshot is returned — same contract as
  // the detail endpoint.
  snapshot: true,
  // Sponsored campaigns: include the campaign id so the client can render the
  // "Sponsored" label and route clicks through the attribution endpoint.
  // Only active campaigns are returned; draft/expired ones are filtered out.
  sponsoredCampaigns: {
    where: { status: 'active' },
    select: { id: true, bidAmountTzs: true, startsAt: true, expiresAt: true },
    take: 1,
  },
};

function buildListWhere({ q, categoryId, minPrice, maxPrice, boosted, featured, subcategory, brand, sellerProfileId, ids }) {
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
  if (brand) filters.push({ snapshot: { path: ['brand'], equals: brand } });
  if (filters.length) where.AND = filters;
  return where;
}

// Public seller lookup accepts the Postgres SellerProfile id, the Postgres
// User id, or the legacy Firebase UID (Product.sellerId in the App still
// carries the UID via snapshot) so the seller shop resolves every form. The
// uuid-backed branches are only attempted for uuid-shaped inputs — a Firebase
// UID against a uuid column would fail Postgres' cast before any row matched.
async function resolveSellerProfile(idOrUid) {
  const store = getStore();
  const branches = [{ user: { firebaseUid: idOrUid } }];
  if (UUID_RE.test(idOrUid)) {
    branches.push({ id: idOrUid }, { userId: idOrUid });
  }
  return store.sellerProfile.findFirst({
    where: { OR: branches },
    select: { id: true },
  });
}

async function requireSellerProfile(userId) {
  const store = getStore();
  const profile = await store.sellerProfile.findUnique({
    where: { userId },
    select: { id: true, storeName: true },
  });
  if (!profile) throw httpError(404, 'SELLER_PROFILE_NOT_FOUND');
  return profile;
}

async function categoryName(id) {
  if (!id) return null;
  const category = await getReadStore().category.findUnique({
    where: { id },
    select: { name: true },
  });
  return category?.name ?? null;
}

async function getOwnedProduct({ id, sellerProfileId }) {
  const store = getStore();
  const product = await store.product.findFirst({
    where: { id, sellerId: sellerProfileId, deletedAt: null },
  });
  if (!product) throw httpError(404, 'PRODUCT_NOT_FOUND');
  return product;
}

// Legacy-only product fields that live in the JSON snapshot during the
// migration window (Firestore parity shape). The seller hub writes them for
// every listing so the app round-trips wholesale, variants, media and the
// other catalog metadata it reads today from Firestore docs.
const LEGACY_SNAPSHOT_KEYS = [
  'category',
  'subcategory',
  'brand',
  'location',
  'district',
  'barcode',
  'isWholesale',
  'wholesaleTiers',
  'variants',
  'attributes',
  'images',
  'imageMetadata',
  'videoUrl',
  'searchKeywords',
];

// Merges the caller-supplied legacy fields into the stored snapshot. Pure so
// the write tests can cover it without a database.
function applySnapshotPatch(base, data) {
  const snapshot = { ...(base || {}) };
  for (const key of LEGACY_SNAPSHOT_KEYS) {
    if (data[key] !== undefined) snapshot[key] = data[key];
  }
  return snapshot;
}

async function createProduct({ sellerProfileId, data, id }) {
  const store = getStore();
  const snapshot = {
    title: data.title,
    description: data.description || null,
    price: data.price,
    originalPrice: data.originalPrice || null,
    currency: 'TZS',
    stock: data.stock ?? 0,
    condition: data.condition || 'new',
    categoryId: data.categoryId || null,
    category: (await categoryName(data.categoryId)) || data.category || null,
    // Firestore-shape metadata for new v1 listings, so detail/edit and the
    // seller hub render exactly like a legacy Firestore product.
    ...applySnapshotPatch(
      {
        subcategory: null,
        location: null,
        district: null,
        isWholesale: false,
        wholesaleTiers: [],
        variants: [],
        attributes: {},
        images: [],
        imageMetadata: [],
        videoUrl: null,
        searchKeywords: [],
      },
      data
    ),
    weightGrams: data.weightGrams || null,
    shippingRequired: data.shippingRequired !== false,
    rating: 0,
    reviewCount: 0,
    viewCount: 0,
    soldCount: 0,
  };
  try {
    return await store.product.create({
      data: {
        // Firestore-first stores pass the pre-generated uuid so the products/
        // {id} doc and the money-facing row always share one identity.
        id: id || undefined,
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
  const store = getStore();
  const product = await store.product.findFirst({
    where: { id, sellerId: sellerProfileId, deletedAt: null },
  });
  if (!product) throw httpError(404, 'PRODUCT_NOT_FOUND');
  return product;
}

async function updateProduct({ id, sellerProfileId, data }) {
  const store = getStore();
  const owned = await getOwnedProduct({ id, sellerProfileId });
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
  const snapshot = applySnapshotPatch(owned.snapshot, data);
  if (data.categoryId !== undefined && data.categoryId !== null) {
    patch.categoryId = data.categoryId;
    snapshot.category = (await categoryName(data.categoryId)) ?? snapshot.category;
  }
  for (const key of ['title', 'description', 'price', 'stock', 'condition']) {
    if (data[key] !== undefined) snapshot[key] = data[key];
  }
  patch.snapshot = snapshot;
  return store.product.update({ where: { id }, data: patch });
}

async function setStatus({ id, sellerProfileId, status }) {
  const store = getStore();
  const product = await getOwnedProduct({ id, sellerProfileId });
  if (status === 'published') {
    if (!product.title || Number(product.price) <= 0) {
      throw httpError(400, 'PUBLISH_REQUIRES_TITLE_AND_PRICE');
    }
  }
  return store.product.update({ where: { id }, data: { status } });
}

async function softDelete({ id, sellerProfileId }) {
  const store = getStore();
  await getOwnedProduct({ id, sellerProfileId });
  return store.product.update({ where: { id }, data: { status: 'deleted', deletedAt: new Date() } });
}

// Flatten the seller relation into the client contract the legacy product doc
// already carried (sellerId = the Firebase UID, sellerPhone = the account
// phone). The app and web shop resolve store links, own-product checks and
// review-gating from these, so they must not be lost per listing.
function serializeProduct(product) {
  const seller = product?.seller;
  if (seller && typeof seller === 'object') {
    return {
      ...product,
      seller: {
        id: seller.id,
        storeName: seller.storeName,
        storeSlug: seller.storeSlug,
        sellerId: seller.user?.firebaseUid || null,
        sellerPhone: seller.user?.phone || null,
      },
    };
  }
  return product;
}

async function listProducts({ q, categoryId, minPrice, maxPrice, boosted, featured, subcategory, brand, sellerId, ids, page = 1, limit = 20 }) {
  // Catalog reads go through the read replica when one is configured: public
  // browsing tolerates lag and must never compete for primary connections.
  const store = getReadStore();
  let sellerProfileId;
  if (sellerId) {
    const profile = await resolveSellerProfile(sellerId);
    // No seller row means no products: a sentinel uuid keeps the count at zero
    // instead of widening the query to the whole catalog (and the column needs
    // uuid-shaped values or Postgres rejects the comparison).
    sellerProfileId = profile?.id || '00000000-0000-0000-0000-000000000000';
  }
  const where = buildListWhere({ q, categoryId, minPrice, maxPrice, boosted, featured, subcategory, brand, sellerProfileId, ids });

  // Fetch active sponsored product IDs so they can be surfaced first in the
  // listing (guideline 11.1: sponsored-first organic ranking). The sponsored
  // relation is included on each product row via PUBLIC_SELECT, but we also
  // need the ordering: active-sponsored first, then the rest.
  const now = new Date();
  const sponsoredIds = await store.sponsoredCampaign.findMany({
    where: {
      status: 'active',
      startsAt: { lte: now },
      expiresAt: { gte: now },
      placements: { some: { product: { ...(categoryId ? { categoryId } : {}) } } },
    },
    select: { placements: { select: { productId: true }, where: { productId: { not: null } } } },
    take: 50,
  });
  const sponsoredProductIdSet = new Set(
    sponsoredIds.flatMap((c) => c.placements.map((p) => p.productId).filter(Boolean))
  );

  const [items, total] = await Promise.all([
    store.product.findMany({
      where,
      select: PUBLIC_SELECT,
      orderBy: { createdAt: 'desc' },
      take: Number(limit),
      skip: (Number(page) - 1) * Number(limit),
    }),
    store.product.count({ where }),
  ]);

  // Re-rank: sponsored products first (sorted by bid amount desc), then
  // organic results. The client still receives the full pagination info; the
  // re-rank only affects the visible ordering within this page slice.
  const withSponsoredFlag = items.map((p) => ({
    ...p,
    isSponsored: sponsoredProductIdSet.has(p.id),
  }));

  withSponsoredFlag.sort((a, b) => {
    if (a.isSponsored && !b.isSponsored) return -1;
    if (!a.isSponsored && b.isSponsored) return 1;
    return 0;
  });

  return { items: withSponsoredFlag.map(serializeProduct), pagination: { page: Number(page), limit: Number(limit), total } };
}

async function listSellerProducts({ sellerProfileId, page = 1, limit = 20 }) {
  const store = getStore();
  const where = { sellerId: sellerProfileId, deletedAt: null };
  const [items, total] = await Promise.all([
    store.product.findMany({
      where,
      include: { media: { orderBy: { sortOrder: 'asc' }, take: 4 } },
      orderBy: { updatedAt: 'desc' },
      take: Number(limit),
      skip: (Number(page) - 1) * Number(limit),
    }),
    store.product.count({ where }),
  ]);
  return { items, pagination: { page: Number(page), limit: Number(limit), total } };
}

async function getProduct(idOrSlug) {
  const store = getReadStore();
  const isUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(idOrSlug);
  const product = await store.product.findFirst({
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
  return serializeProduct(product);
}

async function attachMedia({ id, sellerProfileId, items }) {
  const store = getStore();
  await getOwnedProduct({ id, sellerProfileId });
  const rows = await Promise.all(
    items.map((m, i) =>
      store.productMedia.create({
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
  const store = getStore();
  const product = await store.product.findUnique({ where: { id } });
  if (!product) throw httpError(404, 'PRODUCT_NOT_FOUND');
  return store.product.update({ where: { id }, data: { status } });
}

module.exports = {
  requireSellerProfile,
  resolveSellerProfile,
  getOwnedProduct,
  categoryName,
  createProduct,
  updateProduct,
  setStatus,
  softDelete,
  buildListWhere,
  applySnapshotPatch,
  listProducts,
  listSellerProducts,
  getProduct,
  attachMedia,
  moderate,
  serializeProduct,
};
