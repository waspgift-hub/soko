const admin = require('firebase-admin');
const { getFirebaseFirestore } = require('../../config/firebase');

// Presentation mirror (Postgres truth -> Firestore shape), same pattern as the
// orders presentation-mirror: keep the legacy Firestore `products/{id}` doc in
// lockstep with the authoritative Postgres row so the client-owned consumers
// that still key off a Firestore product doc by opaque id (boosts, comments,
// admin moderation, deep-link reads) keep working for products created via the
// v1 API after the catalog migrated.

// Builds the legacy Firestore document shape from a Postgres product row.
// Pure: unit tests cover it without a database. `createdAt` is emitted as an
// ISO string here and swapped for a real Timestamp by [mirrorProduct].
function buildMirrorDoc(product, sellerContext) {
  const snap = product.snapshot || {};
  const sellerName =
    sellerContext?.sellerName ||
    snap.sellerName ||
    null;
  const sellerPhone = snap.sellerPhone || null;
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

async function mirrorProduct(product, sellerContext) {
  const store = getFirebaseFirestore();
  if (!store || !product?.id) return;
  const doc = buildMirrorDoc(product, sellerContext);
  const createdAt =
    product.createdAt instanceof Date ? product.createdAt : new Date();
  doc.createdAt = admin.firestore.Timestamp.fromDate(createdAt);
  try {
    await store.collection('products').doc(product.id).set(doc, { merge: true });
  } catch (e) {
    // Never block the primary Postgres write on a disposable mirror.
    console.warn(`[mirror] product ${product.id} not synced: ${e.message}`);
  }
}

async function mirrorProductDelete(id) {
  const store = getFirebaseFirestore();
  if (!store) return;
  try {
    await store.collection('products').doc(id).delete();
  } catch (e) {
    console.warn(`[mirror] product ${id} not removed: ${e.message}`);
  }
}

module.exports = {
  buildMirrorDoc,
  mirrorProduct,
  mirrorProductDelete,
};