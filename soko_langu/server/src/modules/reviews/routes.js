const { Router } = require('express');
const { authenticate, optionalAuth } = require('../../middleware/auth');
const reviewService = require('./review-service');

const router = Router();

// ---------------------------------------------------------------------------
// Public reads
// ---------------------------------------------------------------------------

// List reviews for a product (paginated, newest first).
router.get('/product/:productId', optionalAuth, async (req, res) => {
  try {
    const page = Math.max(1, parseInt(req.query.page || '1', 10));
    const limit = Math.min(50, Math.max(1, parseInt(req.query.limit || '20', 10)));
    const result = await reviewService.listProductReviews({ productId: req.params.productId, page, limit });
    res.json({ success: true, data: result });
  } catch (e) {
    res.status(500).json({ success: false, error: { code: 'REVIEW_LIST_FAILED', message: e.message } });
  }
});

// Seller rating summary (average + distribution) — public.
router.get('/seller/:sellerId/summary', async (req, res) => {
  try {
    const { getPrisma } = require('../../config/database');
    const prisma = getPrisma();
    const rows = await prisma.review.findMany({ where: { sellerId: req.params.sellerId }, select: { rating: true } });
    if (rows.length === 0) {
      return res.json({ success: true, data: { averageRating: 0, totalReviews: 0, fiveStar: 0, fourStar: 0, threeStar: 0, twoStar: 0, oneStar: 0 } });
    }
    let total = 0, f5 = 0, f4 = 0, f3 = 0, f2 = 0, f1 = 0;
    for (const r of rows) {
      total += r.rating;
      if (r.rating >= 5) f5++;
      else if (r.rating >= 4) f4++;
      else if (r.rating >= 3) f3++;
      else if (r.rating >= 2) f2++;
      else f1++;
    }
    res.json({
      success: true,
      data: {
        averageRating: total / rows.length,
        totalReviews: rows.length,
        fiveStar: f5,
        fourStar: f4,
        threeStar: f3,
        twoStar: f2,
        oneStar: f1,
      },
    });
  } catch (e) {
    res.status(500).json({ success: false, error: { code: 'SELLER_SUMMARY_FAILED', message: e.message } });
  }
});

// ---------------------------------------------------------------------------
// Authenticated writes
// ---------------------------------------------------------------------------

// Create or update the caller's review for a product (upsert by userId+productId).
router.post('/', authenticate, async (req, res) => {
  try {
    const { productId, rating, comment, sellerId } = req.body || {};
    if (!productId || rating == null) {
      return res.status(400).json({ success: false, error: { code: 'VALIDATION', message: 'productId and rating are required' } });
    }
    // userId/sellerId are opaque Firebase UIDs here (the client's own review
    // docs carry them, and the client compares them to currentUser.uid).
    const review = await reviewService.upsertReview({
      userId: req.firebaseUid,
      productId,
      sellerId,
      rating,
      comment: comment || null,
      userName: req.user.email?.split('@')[0] || 'Anonymous',
      userImage: null,
    });
    res.json({ success: true, data: review });
  } catch (e) {
    const status = e.status || 500;
    const code = e.code || 'REVIEW_UPSERT_FAILED';
    res.status(status).json({ success: false, error: { code, message: e.message } });
  }
});

// Current user's review for a product (checks if buyer already reviewed).
router.get('/product/:productId/me', authenticate, async (req, res) => {
  try {
    const review = await reviewService.getMyReview({ userId: req.firebaseUid, productId: req.params.productId });
    res.json({ success: true, data: review });
  } catch (e) {
    res.status(500).json({ success: false, error: { code: 'MY_REVIEW_FAILED', message: e.message } });
  }
});

// Toggle helpful.
router.post('/:id/helpful', authenticate, async (req, res) => {
  try {
    const result = await reviewService.toggleHelpful({ reviewId: req.params.id, userId: req.firebaseUid });
    res.json({ success: true, data: result });
  } catch (e) {
    const status = e.status || 500;
    const code = e.code || 'HELPFUL_FAILED';
    res.status(status).json({ success: false, error: { code, message: e.message } });
  }
});

// Seller reply.
router.post('/:id/reply', authenticate, async (req, res) => {
  try {
    const review = await reviewService.replyToReview({
      reviewId: req.params.id,
      userId: req.firebaseUid,
      sellerId: req.firebaseUid,
      reply: req.body.reply,
    });
    res.json({ success: true, data: review });
  } catch (e) {
    const status = e.status || 500;
    const code = e.code || 'REPLY_FAILED';
    res.status(status).json({ success: false, error: { code, message: e.message } });
  }
});

module.exports = router;