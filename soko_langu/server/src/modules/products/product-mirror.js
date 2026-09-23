// Shape builder for the app-facing product doc, shared by the Firestore-first
// product store and its migration tests. `buildMirrorDoc` produces the legacy
// `products/{id}` shape from either a Postgres row or a pseudo-row (Phase 2
// listings) so every writer emits byte-identical docs.

// Builds the legacy Firestore document shape from a Postgres product row.
// Pure: unit tests cover it without a database. `createdAt` is emitted as an
// ISO string so the app reads a stable serializable value.
function buildMirrorDoc(product, sellerContext) {
  const snap = product.snapshot || {};
  const sellerName =
    sellerContext?.sellerName ||
    snap.sellerName ||
    null;
  const sellerPhone = sellerContext?.sellerPhone || snap.sellerPhone || null;
  return {
    name: snap.title || product.title || '',
    searchName: String(snap.title || product.title || '').toLowerCase(),
    description: snap.description || product.description || '',
    price: Number(product.price ?? snap.price ?? 0),
    currency: snap.currency || 'TZS',
    images: Array.isArray(snap.images) ? snap.images : [],
    imageMetadata: snap.imageMetadata || [],
    videoUrl: snap.videoUrl || null,
    sellerId: sellerContext?.sellerFirebaseUid || snap.sellerId || null,
    sellerName,
    sellerPhone,
    category: snap.category || null,
    subcategory: snap.subcategory || null,
    location: snap.location || null,
    district: snap.district || null,
    stock: product.stock ?? snap.stock ?? 0,
    isWholesale: Boolean(snap.isWholesale),
    wholesaleTiers: snap.wholesaleTiers || [],
    variants: snap.variants || [],
    attributes: snap.attributes || {},
    brand: snap.brand || null,
    condition: product.condition || snap.condition || 'new',
    rating: snap.rating ?? 0,
    reviewCount: snap.reviewCount ?? 0,
    soldCount: snap.soldCount ?? 0,
    viewCount: snap.viewCount ?? 0,
    isActive: product.status === 'published',
    isFeatured: Boolean(snap.isFeatured),
    isBoosted: Boolean(snap.isBoosted),
    boostedUntil: snap.boostedUntil || null,
    featuredUntil: snap.featuredUntil || null,
    boostTier: snap.boostTier || null,
    sellerKycApproved: Boolean(snap.sellerKycApproved),
    searchKeywords: snap.searchKeywords || [],
    barcode: snap.barcode || null,
    legacyId: product.id,
    createdAt: product.createdAt
      ? product.createdAt.toISOString()
      : new Date().toISOString(),
  };
}

module.exports = {
  buildMirrorDoc,
};