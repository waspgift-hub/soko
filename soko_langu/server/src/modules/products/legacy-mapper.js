const crypto = require('crypto');

/**
 * Maps a Firestore `products` collection document to a Prisma Product
 * create payload, ready to run inside a transaction alongside a
 * User UID → SellerProfile.id resolution and a Category name → id lookup.
 *
 * Cloudinary media URLs are preserved in snapshot.legacyImages for a
 * separate Phase-F media migration; no ProductMedia rows are created here
 * because R2 keys do not map 1-to-1 from Cloudinary URLs.
 */
function mapFirestoreProductToPrisma(doc, { sellerProfileId, categoryId }) {
  if (!sellerProfileId) throw new Error('sellerProfileId required');
  if (!doc || typeof doc !== 'object') throw new Error('doc required');
  const name = String(doc.name || '').trim();
  if (!name) throw new Error('name required');
  const price = Math.round(Number(doc.price));
  if (!Number.isFinite(price) || price <= 0) throw new Error('price must be positive');

  return {
    title: name,
    slug: buildSlug(name),
    description: doc.description || null,
    categoryId: categoryId || null,
    price: BigInt(price),
    originalPrice: null,
    currency: doc.currency === 'TZS' ? 'TZS' : (doc.currency || 'TZS'),
    stock: Math.max(0, Math.round(Number(doc.stock) || 0)),
    status: doc.isActive === false ? 'draft' : 'published',
    condition: normaliseCondition(doc.condition),
    weightGrams: null,
    shippingRequired: true,
    createdAt: toCreatedAt(doc.createdAt),
    snapshot: buildSnapshot(doc),
  };
}

/**
 * Slug from product name.  Uses a random hex suffix so slugs never collide
 * across concurrent writes (same pattern as product-service.js).
 */
function buildSlug(name) {
  const base = String(name)
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 60) || 'product';
  return `${base}-${crypto.randomBytes(3).toString('hex')}`;
}

const VALID_CONDITIONS = new Set([
  'new', 'used_like_new', 'used_good', 'used_fair', 'refurbished',
]);

function normaliseCondition(raw) {
  const v = String(raw || 'new').toLowerCase().trim();
  return VALID_CONDITIONS.has(v) ? v : 'new';
}

function toCreatedAt(raw) {
  if (!raw) return new Date();
  if (raw instanceof Date) return raw;
  if (typeof raw === 'object' && typeof raw.toDate === 'function') return raw.toDate();
  if (typeof raw === 'number' || typeof raw === 'string') {
    const d = new Date(raw);
    return Number.isFinite(d.getTime()) ? d : new Date();
  }
  return new Date();
}

/**
 * ProductMedia rows from a Firestore product doc or a stored snapshot (both
 * carry `images[]` + `videoUrl`). Legacy media lives on Cloudinary as absolute
 * URLs; r2Key keeps the URL so the client renders it as-is while the R2
 * re-hosting stays a Phase F migration. No rows when there is no media.
 */
function mapFirestoreMediaToProductRows(doc) {
  const rows = [];
  if (!doc || typeof doc !== 'object') return rows;
  const images = Array.isArray(doc.images) ? doc.images : [];
  for (const [i, url] of images.entries()) {
    if (typeof url === 'string' && /^https?:\/\//.test(url)) {
      rows.push({ type: 'image', r2Key: url, sortOrder: i });
    }
  }
  if (typeof doc.videoUrl === 'string' && doc.videoUrl) {
    rows.push({ type: 'video', r2Key: doc.videoUrl, sortOrder: rows.length });
  }
  return rows;
}

/**
 * Snapshot carries legacy-only fields that have no direct Postgres column.
 * This preserves every original Firestore property so nothing is lost during
 * the migration window.
 */
function buildSnapshot(doc) {
  const out = {};
  const LEGACY_KEYS = [
    'searchName', 'searchKeywords', 'brand', 'barcode', 'location',
    'district', 'sellerId', 'sellerName', 'sellerPhone', 'sellerKycApproved',
    'images', 'imageMetadata', 'videoUrl',
    'isWholesale', 'wholesaleTiers', 'variants', 'attributes',
    'rating', 'reviewCount', 'viewCount', 'soldCount',
    'isBoosted', 'boostedUntil', 'boostTier',
    'isFeatured', 'featuredUntil',
    'category', 'subcategory',
    'isActive',
  ];
  for (const k of LEGACY_KEYS) {
    if (doc[k] !== undefined && doc[k] !== null) out[k] = doc[k];
  }
  return out;
}

module.exports = { mapFirestoreProductToPrisma, mapFirestoreMediaToProductRows, buildSlug, normaliseCondition, toCreatedAt };
