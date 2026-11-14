// Phase 3 (Firestore-ONLY reviews): reviews are app-facing data no money
// module reads, so Postgres is dropped entirely — `reviews/{id}` is the single
// store. sellerId/userId are Firebase UIDs (the client compares them to
// currentUser.uid), matching the legacy Firestore review docs the app already
// parsed. Firestore indexes (productId,userId), (sellerId,createdAt),
// (productId,createdAt) exist in firestore.indexes.json.
const crypto = require('crypto');
const { getFirebaseFirestore } = require('../../config/firebase');
const { getStore } = require('../../config/database');
const { ORDER_STATES, canonicalStatusOf } = require('../orders/order-state-machine');

// Order states in which the buyer demonstrably received the goods. A review is
// only trustworthy when the server can tie it to one of these orders; the
// client's own claim is never enough. `DELIVERED` counts because a courier or
// admin attested the handover, and that is the exact moment the app prompts the
// buyer to rate. The later settlement states stay eligible forever.
const SETTLED_ORDER_STATUSES = new Set([
  ORDER_STATES.DELIVERED,
  ORDER_STATES.DELIVERY_CONFIRMED,
  ORDER_STATES.COMPLETED,
  ORDER_STATES.WALLET_CREDITED,
]);

// The public-profile "rate this seller" button has no product behind it, so it
// posts a synthetic id (`seller_<uid>`). It stays a separate, always-unverified
// trust signal instead of silently borrowing product-review rules.
const SELLER_TRUST_PREFIX = 'seller_';

function httpError(status, code, message) {
  const e = new Error(message);
  e.status = status;
  e.code = code;
  return e;
}

function requireStore() {
  const db = getFirebaseFirestore();
  if (!db) throw httpError(503, 'REVIEW_STORE_UNAVAILABLE', 'Review store unavailable');
  return db;
}

// Normalize createdAt read from multiple writer eras (ISO strings from this
// store, Date/Timestamp from legacy docs) into the public ISO contract.
function iso(value) {
  if (value == null) return null;
  if (typeof value === 'object' && typeof value.toDate === 'function') return value.toDate().toISOString();
  if (value instanceof Date) return value.toISOString();
  return String(value);
}

function toPublic(doc) {
  return {
    id: doc.id,
    productId: doc.productId,
    sellerId: doc.sellerId,
    userId: doc.userId,
    userName: doc.userName,
    userImage: doc.userImage,
    rating: doc.rating,
    comment: doc.comment,
    images: doc.images || [],
    helpfulCount: doc.helpfulCount || 0,
    likedBy: doc.likedBy || [],
    isVerifiedPurchase: Boolean(doc.isVerifiedPurchase),
    orderId: doc.orderId || null,
    sellerReply: doc.sellerReply,
    sellerReplyAt: iso(doc.sellerReplyAt),
    createdAt: iso(doc.createdAt),
  };
}

function isSellerTrustProductId(productId) {
  return typeof productId === 'string'
    && productId.startsWith(SELLER_TRUST_PREFIX)
    && productId.length > SELLER_TRUST_PREFIX.length;
}

function sellerIdFromTrustProduct(productId) {
  return productId.slice(SELLER_TRUST_PREFIX.length);
}

function orderContainsProduct(order, productId) {
  const snap = order && order.productSnapshot;
  if (snap && String(snap.productId || '') === String(productId)) return true;
  // Older rows (and a few legacy writers) keep the product id at the top level.
  return String((order && order.productId) || '') === String(productId);
}

/**
 * Find the caller's own settled order that contains `productId`.
 *
 * This is the server-side proof behind the verified-purchase badge. `buyerId`
 * is an equality filter (indexed by default) and the status/product checks run
 * in memory so every legacy status spelling goes through the same
 * canonicalization as the rest of the order pipeline.
 */
async function findSettledPurchase({ userId, productId }) {
  if (!userId || !productId) return null;
  const store = getStore();
  const orders = await store.order.findMany({ where: { buyerId: userId } });
  for (const order of orders) {
    if (!SETTLED_ORDER_STATUSES.has(canonicalStatusOf(order.status))) continue;
    if (orderContainsProduct(order, productId)) return order;
  }
  return null;
}

// Paginated list, newest first. Firestore has no offset, so the page is read
// by taking up to (page-1)*limit + limit+1 docs and slicing; total comes from
// the count aggregation so pagination meta stays exact.
async function listProductReviews({ productId, page = 1, limit = 20 }) {
  const db = requireStore();
  const col = db.collection('reviews');
  const base = col.where('productId', '==', productId);

  const [countSnap, snap] = await Promise.all([
    base.count().get(),
    base.orderBy('createdAt', 'desc').limit((Number(page) - 1) * Number(limit) + Number(limit) + 1).get(),
  ]);

  const start = (Number(page) - 1) * Number(limit);
  const docs = snap.docs
    .slice(start, start + Number(limit))
    .map((d) => toPublic({ ...d.data(), id: d.id }));
  return { reviews: docs, pagination: { page: Number(page), limit: Number(limit), total: countSnap.data().count } };
}

async function getMyReview({ userId, productId }) {
  const db = requireStore();
  // (productId,userId) is unique per buyer so at most one doc matches; the
  // composite index serves the equality query without an ordering clause.
  const snap = await db.collection('reviews')
    .where('productId', '==', productId)
    .where('userId', '==', userId)
    .limit(1)
    .get();
  if (snap.empty) return null;
  return toPublic({ ...snap.docs[0].data(), id: snap.docs[0].id });
}

// Upsert a review. The verified-purchase badge and the seller the review is
// attributed to are derived from a settled order on the server; the caller can
// never award itself a badge or point a review at another seller. After the
// write the product doc's rating/reviewCount are recomputed so the Firestore
// catalog stays the source the app sorts by.
async function upsertReview({ userId, productId, sellerId, rating, comment, userName, userImage }) {
  const db = requireStore();

  const ratingInt = Math.round(rating);
  if (!Number.isFinite(ratingInt) || ratingInt < 1 || ratingInt > 5) {
    throw httpError(400, 'INVALID_RATING', 'rating must be a number between 1 and 5');
  }

  let resolvedSellerId;
  let orderId = null;
  let isVerifiedPurchase = false;

  if (isSellerTrustProductId(productId)) {
    resolvedSellerId = sellerIdFromTrustProduct(productId);
    if (resolvedSellerId === userId) {
      throw httpError(400, 'SELF_REVIEW', 'Sellers cannot rate themselves');
    }
  } else {
    const purchase = await findSettledPurchase({ userId, productId });
    if (!purchase) {
      throw httpError(403, 'PURCHASE_REQUIRED', 'Only buyers with a completed order can review this product');
    }
    // The order is the source of truth for who sold the item; the request body
    // is ignored so a forged `sellerId` cannot move ratings between sellers.
    resolvedSellerId = purchase.sellerId || sellerId || '';
    if (resolvedSellerId && resolvedSellerId === userId) {
      throw httpError(400, 'SELF_REVIEW', 'Sellers cannot rate their own products');
    }
    orderId = purchase.id || null;
    isVerifiedPurchase = true;
  }

  const data = {
    productId,
    sellerId: String(resolvedSellerId || ''),
    userId,
    userName: String(userName || 'Anonymous').slice(0, 100),
    userImage: userImage || null,
    rating: ratingInt,
    comment: comment != null ? String(comment).slice(0, 5000) : null,
    orderId,
    isVerifiedPurchase,
  };

  const existing = await getMyReview({ userId, productId });
  const now = iso(new Date());
  let id;
  if (existing) {
    id = existing.id;
    // An edit may add verification but must never remove it or forget which
    // order proved the purchase.
    const keepVerified = existing.isVerifiedPurchase && !isVerifiedPurchase;
    await db.collection('reviews').doc(id).set(
      {
        ...data,
        ...(keepVerified
          ? { isVerifiedPurchase: true, orderId: existing.orderId || orderId }
          : {}),
        images: existing.images || [],
        updatedAt: now,
      },
      { merge: true }
    );
  } else {
    id = crypto.randomUUID();
    await db.collection('reviews').doc(id).set({
      ...data,
      images: [],
      helpfulCount: 0,
      likedBy: [],
      sellerReply: null,
      sellerReplyAt: null,
      createdAt: now,
      updatedAt: now,
    });
  }

  // Synthetic seller-trust ids are not real products; recomputing them would
  // create a junk `products/{seller_uid}` document.
  if (!isSellerTrustProductId(productId)) {
    recomputeProductRating(productId).catch(() => {});
  }
  const saved = await db.collection('reviews').doc(id).get();
  return toPublic({ ...saved.data(), id });
}

// Toggle the caller into/out of the helpful likedBy list on a review.
async function toggleHelpful({ reviewId, userId }) {
  const db = requireStore();
  const ref = db.collection('reviews').doc(reviewId);
  const snap = await ref.get();
  if (!snap.exists) throw httpError(404, 'REVIEW_NOT_FOUND', 'Review not found');

  const likedBy = snap.data().likedBy || [];
  const has = likedBy.includes(userId);
  const next = has ? likedBy.filter((id) => id !== userId) : [...likedBy, userId];

  await ref.update({
    likedBy: next,
    helpfulCount: Math.max(0, (snap.data().helpfulCount || 0) + (has ? -1 : 1)),
  });
  return { helpfulCount: (snap.data().helpfulCount || 0) + (has ? -1 : 1), likedBy: next, liked: !has };
}

// Seller reply. Only the product seller (review.sellerId === userId) may reply.
async function replyToReview({ reviewId, userId, sellerId, reply }) {
  const db = requireStore();
  const ref = db.collection('reviews').doc(reviewId);
  const snap = await ref.get();
  if (!snap.exists) throw httpError(404, 'REVIEW_NOT_FOUND', 'Review not found');

  const row = snap.data();
  if (row.sellerId !== userId) {
    throw httpError(403, 'NOT_SELLER', 'Only the product seller may reply');
  }
  if (reply != null && String(reply).trim().length > 2000) {
    throw httpError(400, 'REPLY_TOO_LONG', 'Reply must be 2000 characters or fewer');
  }

  const text = String(reply || '').trim();
  await ref.update({
    sellerReply: text || null,
    sellerReplyAt: text ? iso(new Date()) : null,
  });
  return toPublic({ ...row, ...(await ref.get()).data(), id: reviewId });
}

// Recompute a product's rating + reviewCount on its Firestore catalog doc so
// the app's sort-by-reviewCount and rating badge stay correct. Best-effort.
async function recomputeProductRating(productId) {
  const db = requireStore();
  const snap = await db.collection('reviews')
    .where('productId', '==', productId)
    .limit(500)
    .get();
  let sum = 0;
  let count = 0;
  for (const d of snap.docs) {
    sum += Number(d.data().rating || 0);
    count++;
  }
  const rating = count ? Math.round((sum / count) * 100) / 100 : 0;
  await db.collection('products').doc(productId).set({ rating, reviewCount: count }, { merge: true }).catch(() => {});
}

// Public seller rating summary: average + star distribution (Firestore reads).
async function sellerRatingSummary({ sellerId }) {
  const db = requireStore();
  const snap = await db.collection('reviews').where('sellerId', '==', sellerId).get();
  let total = 0;
  const stars = { fiveStar: 0, fourStar: 0, threeStar: 0, twoStar: 0, oneStar: 0 };
  for (const d of snap.docs) {
    const rating = Number(d.data().rating || 0);
    total += rating;
    if (rating >= 5) stars.fiveStar++;
    else if (rating >= 4) stars.fourStar++;
    else if (rating >= 3) stars.threeStar++;
    else if (rating >= 2) stars.twoStar++;
    else stars.oneStar++;
  }
  const n = snap.size;
  return {
    averageRating: n ? total / n : 0,
    totalReviews: n,
    ...stars,
  };
}

module.exports = {
  listProductReviews,
  getMyReview,
  upsertReview,
  toggleHelpful,
  replyToReview,
  sellerRatingSummary,
  toPublic,
  // Exported so the verified-purchase rule is covered directly by tests.
  SETTLED_ORDER_STATUSES,
  findSettledPurchase,
  isSellerTrustProductId,
};
