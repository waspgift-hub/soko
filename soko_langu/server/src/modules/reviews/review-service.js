const { getPrisma } = require('../../config/database');

function httpError(status, code, message) {
  const e = new Error(message);
  e.status = status;
  e.code = code;
  return e;
}

function toPublic(review) {
  return {
    id: review.id,
    productId: review.productId,
    sellerId: review.sellerId,
    userId: review.userId,
    userName: review.userName,
    userImage: review.userImage,
    rating: review.rating,
    comment: review.comment,
    images: review.images || [],
    helpfulCount: review.helpfulCount,
    likedBy: review.likedBy || [],
    isVerifiedPurchase: review.isVerifiedPurchase,
    sellerReply: review.sellerReply,
    sellerReplyAt: review.sellerReplyAt ? review.sellerReplyAt.toISOString() : null,
    createdAt: review.createdAt.toISOString(),
  };
}

/**
 * Product reviews (paginated, newest first). Reads by opaque productId
 * (legacy Firestore doc id or Postgres UUID — both are plain strings).
 */
async function listProductReviews({ productId, page = 1, limit = 20 }) {
  const prisma = getPrisma();
  const [rows, total] = await Promise.all([
    prisma.review.findMany({
      where: { productId },
      orderBy: { createdAt: 'desc' },
      skip: (page - 1) * limit,
      take: limit,
    }),
    prisma.review.count({ where: { productId } }),
  ]);
  return { reviews: rows.map(toPublic), pagination: { page, limit, total } };
}

/** The current user's review for a product (or null). */
async function getMyReview({ userId, productId }) {
  const prisma = getPrisma();
  const row = await prisma.review.findFirst({
    where: { productId, userId },
    orderBy: { createdAt: 'desc' },
  });
  return row ? toPublic(row) : null;
}

/**
 * Upsert a review for (productId, userId). Enforces:
 *  - rating 1..5
 *  - sellers may not review their own product (sellerId check)
 *  - one review per buyer per product (update when it exists)
 * Returns the public review row. Recomputes the product's aggregate rating
 * mirror fields via the snapshot MV (fire-and-forget, never blocks the write).
 */
async function upsertReview({ userId, productId, sellerId, rating, comment, userName, userImage }) {
  const prisma = getPrisma();

  if (sellerId && sellerId === userId) {
    throw httpError(400, 'SELF_REVIEW', 'Sellers cannot rate their own products');
  }

  const ratingInt = Math.round(rating);
  if (!Number.isFinite(ratingInt) || ratingInt < 1 || ratingInt > 5) {
    throw httpError(400, 'INVALID_RATING', 'rating must be a number between 1 and 5');
  }

  const existing = await prisma.review.findFirst({
    where: { productId, userId },
    orderBy: { createdAt: 'desc' },
  });

  const data = {
    productId,
    sellerId: String(sellerId || ''),
    userId,
    userName: String(userName || 'Anonymous').slice(0, 100),
    userImage: userImage || null,
    rating: ratingInt,
    comment: comment != null ? String(comment).slice(0, 5000) : null,
  };

  let row;
  if (existing) {
    row = await prisma.review.update({
      where: { id: existing.id },
      data: { ...data, images: existing.images || [] },
    });
  } else {
    row = await prisma.review.create({
      data: { ...data, images: [] },
    });
  }

  recomputeProductRating(productId).catch(() => {});
  return toPublic(row);
}

/** Toggle the caller into/out of the helpful likedBy list on a review. */
async function toggleHelpful({ reviewId, userId }) {
  const prisma = getPrisma();
  const row = await prisma.review.findUnique({ where: { id: reviewId } });
  if (!row) throw httpError(404, 'REVIEW_NOT_FOUND', 'Review not found');

  const likedBy = row.likedBy || [];
  const has = likedBy.includes(userId);
  const next = has ? likedBy.filter((id) => id !== userId) : [...likedBy, userId];
  const updated = await prisma.review.update({
    where: { id: reviewId },
    data: {
      likedBy: next,
      helpfulCount: Math.max(0, (row.helpfulCount || 0) + (has ? -1 : 1)),
    },
  });
  return { helpfulCount: updated.helpfulCount, likedBy: updated.likedBy, liked: !has };
}

/**
 * Seller reply. Only the seller who owns the product may reply; the caller
 * is resolved by Firebase UID (userId), which is the sellerId stored on the
 * review when the product was reviewed.
 */
async function replyToReview({ reviewId, userId, sellerId, reply }) {
  const prisma = getPrisma();
  const row = await prisma.review.findUnique({ where: { id: reviewId } });
  if (!row) throw httpError(404, 'REVIEW_NOT_FOUND', 'Review not found');
  if (row.sellerId !== userId) {
    throw httpError(403, 'NOT_SELLER', 'Only the product seller may reply');
  }
  if (reply != null && String(reply).trim().length > 2000) {
    throw httpError(400, 'REPLY_TOO_LONG', 'Reply must be 2000 characters or fewer');
  }
  const updated = await prisma.review.update({
    where: { id: reviewId },
    data: {
      sellerReply: String(reply || '').trim() || null,
      sellerReplyAt: String(reply || '').trim() ? new Date() : null,
    },
  });
  return toPublic(updated);
}

async function recomputeProductRating(productId) {
  const prisma = getPrisma();
  const agg = await prisma.review.aggregate({
    where: { productId },
    _avg: { rating: true },
    _count: { _all: true },
  });
  // The Product.snapshot carries the legacy rating/reviewCount mirror fields;
  // update them so Firestore-facing Product API responses stay in sync.
  await prisma.product.updateMany({
    where: { id: productId },
    data: {
      snapshot: {
        ...((await prisma.product.findUnique({ where: { id: productId } }))?.snapshot || {}),
        rating: agg._avg.rating || 0,
        reviewCount: agg._count._all,
      },
    },
  }).catch(() => {});
}

module.exports = {
  listProductReviews,
  getMyReview,
  upsertReview,
  toggleHelpful,
  replyToReview,
};