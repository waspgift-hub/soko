// Phase 2 (Firestore-primary catalog writes): products/{id} is the
// authoritative listing doc the mobile app streams from (same legacy shape the
// mirror always wrote). The store seam row is kept so money modules (orders,
// wallet, sponsored, refunds) keep their uuid join.
// Writes land in Firestore first; a failed seam write aborts the operation
// because a listing without its money-facing row would orphan order math.
const crypto = require('crypto');
const { getFirebaseFirestore } = require('../../config/firebase');
const service = require('./product-service');
const { buildMirrorDoc } = require('./product-mirror');
const { publicUrl } = require('../media/cdn-service');

function httpError(status, message) {
  const err = new Error(message);
  err.status = status;
  return err;
}

function requireStore() {
  const db = getFirebaseFirestore();
  if (!db) throw httpError(503, 'CATALOG_STORE_UNAVAILABLE');
  return db;
}

function nowIso() {
  return new Date().toISOString();
}

// Pseudo-row the shared shape builder understands: same fields product-mirror
// consumes, so the app-facing doc and the mirror stay byte-identical in shape.
function listingPseudoRow({ id, data, category, status, createdAt }) {
  return {
    id,
    title: data.title,
    description: data.description ?? null,
    price: Number(data.price ?? 0),
    condition: data.condition || 'new',
    stock: data.stock ?? 0,
    status,
    createdAt,
    snapshot: {
      ...data,
      category: category || data.category || null,
      rating: 0,
      reviewCount: 0,
      soldCount: 0,
      viewCount: 0,
    },
  };
}

// Firestore-first listing create. Generates the uuid so the products/{id} doc
// and the seam row share one identity from the first write.
async function createListing({ sellerProfileId, sellerContext, data }) {
  const db = requireStore();
  const id = crypto.randomUUID();
  const category = data.categoryId ? await service.categoryName(data.categoryId) : null;
  const doc = buildMirrorDoc(listingPseudoRow({ id, data, category, status: 'draft', createdAt: new Date() }), sellerContext);

  try {
    await db.collection('products').doc(id).set({ ...doc, updatedAt: nowIso() });
  } catch (e) {
    throw httpError(500, 'CATALOG_WRITE_FAILED');
  }

  const product = await service.createProduct({ sellerProfileId, data, id });
  return { product, id };
}

// Patch the authoritative doc with the same whitelist the seam row uses:
// column-backed fields plus the flattened legacy keys living on the doc.
const COL_PATCH = {
  title: 'name',
  price: 'price',
  stock: 'stock',
  condition: 'condition',
};

const LEGACY_PATCH_KEYS = [
  'description', 'category', 'subcategory', 'brand', 'location', 'district',
  'barcode', 'isWholesale', 'wholesaleTiers', 'variants', 'attributes',
  'images', 'imageMetadata', 'videoUrl', 'searchKeywords',
];

function applyListingPatch(doc, data) {
  const next = { ...doc };
  for (const [col, dbKey] of Object.entries(COL_PATCH)) {
    if (data[col] !== undefined) {
      next[dbKey] = col === 'price' ? Number(data[col]) : data[col];
    }
  }
  if (data.title !== undefined) next.searchName = String(data.title).toLowerCase();
  for (const k of LEGACY_PATCH_KEYS) {
    if (data[k] !== undefined) next[k] = data[k];
  }
  next.updatedAt = nowIso();
  return next;
}

async function writeDoc(db, id, doc) {
  try {
    await db.collection('products').doc(id).set(doc, { merge: true });
  } catch (e) {
    throw httpError(500, 'CATALOG_WRITE_FAILED');
  }
}

async function readDoc(db, id) {
  const snap = await db.collection('products').doc(id).get();
  return snap.exists ? snap.data() : null;
}

// Firestore-first update. Authz (ownership) is checked against the seam first —
// never write to a doc the caller does not own.
async function updateListing({ productId, sellerProfileId, data, sellerContext }) {
  const db = requireStore();
  const owned = await service.getOwnedProduct({ id: productId, sellerProfileId });

  let doc = await readDoc(db, productId);
  if (doc) {
    let patched = applyListingPatch(doc, data);
    if (data.categoryId !== undefined && data.categoryId !== null) {
      patched.category = (await service.categoryName(data.categoryId)) ?? patched.category;
    }
    await writeDoc(db, productId, patched);
  } else {
    // Legacy row with no Firestore doc yet: adopt it as the authoritative doc.
    await writeDoc(db, productId, { ...buildMirrorDoc(owned, sellerContext), updatedAt: nowIso() });
  }

  return service.updateProduct({ id: productId, sellerProfileId, data });
}

// Firestore-first publish/unpublish: the app sees isActive flip immediately.
async function setListingPublished({ productId, sellerProfileId, status }) {
  const db = requireStore();
  await service.getOwnedProduct({ id: productId, sellerProfileId });

  const doc = await readDoc(db, productId);
  if (doc) await writeDoc(db, productId, { isActive: status === 'published', updatedAt: nowIso() });

  return service.setStatus({ id: productId, sellerProfileId, status });
}

// Firestore-first soft delete: hide from the app before retiring the row.
async function deleteListing({ productId, sellerProfileId }) {
  const db = requireStore();
  await service.getOwnedProduct({ id: productId, sellerProfileId });

  await db.collection('products').doc(productId).delete().catch(() => {});
  return service.softDelete({ id: productId, sellerProfileId });
}

// Attach R2 media. Firestore doc carries renderable public URLs (images[] +
// videoUrl) like the legacy catalog; the row keeps its ProductMedia rows.
async function attachListingMedia({ productId, sellerProfileId, items, sellerContext }) {
  const db = requireStore();
  const owned = await service.getOwnedProduct({ id: productId, sellerProfileId });

  let doc = await readDoc(db, productId);
  if (!doc) doc = buildMirrorDoc(owned, sellerContext);

  const images = new Set(Array.isArray(doc.images) ? doc.images : []);
  let imageMetadata = Array.isArray(doc.imageMetadata) ? [...doc.imageMetadata] : [];
  let videoUrl = doc.videoUrl || null;

  for (const m of items) {
    if (m.type === 'video') {
      videoUrl = publicUrl({ kind: 'video', key: m.r2Key });
    } else {
      const url = publicUrl({ kind: 'image', key: m.r2Key });
      images.add(url);
      if (m.width || m.height || m.thumbnailR2Key) {
        imageMetadata.push({
          url,
          width: m.width || null,
          height: m.height || null,
          thumbnailUrl: m.thumbnailR2Key ? publicUrl({ kind: 'thumbnail', key: m.thumbnailR2Key }) : null,
        });
      }
    }
  }

  await writeDoc(db, productId, { images: [...images], imageMetadata, videoUrl, updatedAt: nowIso() });
  return service.attachMedia({ id: productId, sellerProfileId, items });
}

// Firestore-first admin moderation: isActive mirrors the new status.
async function moderateListing({ productId, status }) {
  const db = requireStore();
  const doc = await readDoc(db, productId);
  if (doc) await writeDoc(db, productId, { isActive: status === 'published', updatedAt: nowIso() });
  return service.moderate({ id: productId, status });
}

module.exports = {
  createListing,
  updateListing,
  setListingPublished,
  deleteListing,
  attachListingMedia,
  moderateListing,
  applyListingPatch,
  listingPseudoRow,
};