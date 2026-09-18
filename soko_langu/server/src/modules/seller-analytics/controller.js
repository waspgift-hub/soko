// Seller analytics bridge — Phase F.
// Replaces legacy Firestore fan-out GET /api/seller-analytics/:sellerId with a
// Postgres aggregate under /api/v1. DTO matches Flutter SellerAnalytics.fromApi.
const { getPrisma } = require('../../config/database');

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function toNum(v) {
  const n = typeof v === 'bigint' ? Number(v) : Number(v);
  return Number.isFinite(n) ? n : 0;
}

function snapshotViews(snapshot) {
  try {
    const s = typeof snapshot === 'string' ? JSON.parse(snapshot) : snapshot;
    return toNum(s.viewCount || (s.statistics && s.statistics.views) || 0);
  } catch (_) {
    return 0;
  }
}

function snapshotImage(snapshot) {
  try {
    const s = typeof snapshot === 'string' ? JSON.parse(snapshot) : snapshot;
    return s.image || (s.images && s.images[0]) || null;
  } catch (_) {
    return null;
  }
}

const PAID = ['paid', 'paid_escrow_hold', 'paid_escrow_held', 'dispatched', 'delivered', 'delivery_confirmed', 'confirmed', 'completed', 'successful'];
const FAILED = ['failed', 'refunded', 'cancelled', 'expired'];

async function resolveSeller(prisma, sellerId) {
  if (UUID_RE.test(sellerId)) {
    const byId = await prisma.sellerProfile
      .findUnique({ where: { id: sellerId }, select: { id: true } })
      .catch(() => null);
    if (byId) return byId;
  }
  return prisma.sellerProfile
    .findFirst({ where: { snapshot: { path: ['legacyId'], equals: sellerId } }, select: { id: true } })
    .catch(() => null);
}

async function resolveBoost(prisma, boostId) {
  if (UUID_RE.test(boostId)) {
    const byId = await prisma.boost
      .findUnique({ where: { id: boostId }, select: { id: true } })
      .catch(() => null);
    if (byId) return byId;
  }
  return prisma.boost
    .findFirst({ where: { snapshot: { path: ['legacyId'], equals: boostId } }, select: { id: true } })
    .catch(() => null);
}

// GET /sellers/:sellerId/analytics/overview
async function getSellerAnalyticsOverview(req, res) {
  const prisma = getPrisma();
  const { sellerId } = req.params;
  const now = new Date();
  try {
    const seller = await resolveSeller(prisma, sellerId);
    if (!seller) return res.status(404).json({ success: false, error: 'Muuzaji haipatikani' });

    const [products, boosts, orders, reviews] = await Promise.all([
      prisma.product.findMany({
        where: { sellerId: seller.id, deletedAt: null },
        select: { id: true, title: true, snapshot: true },
      }),
      prisma.boost.findMany({
        where: { sellerId: seller.id },
        select: { impressions: true, clicks: true },
      }),
      prisma.order.findMany({
        where: { sellerId: seller.id },
        select: { status: true, totalAmount: true, createdAt: true },
      }),
      prisma.review.findMany({
        where: { sellerId: seller.id },
        select: { rating: true },
      }),
    ]);

    const boostsByProduct = await prisma.boost.findMany({
      where: { sellerId: seller.id, productId: { not: null } },
      select: { productId: true, impressions: true },
    });

    let totalProductViews = 0;
    for (const p of products) totalProductViews += snapshotViews(p.snapshotapse);
    const totalProducts = products.length;
    let boostImpressions = 0;
    let boostClicks = 0;
    for (const b of boosts) {
      boostImpressions += toNum(b.impressions);
      boostClicks += toNum(b.clicks);
    }
    let boostLocation = {};
    let genderMap = {};

    const monthlyBuckets = [];
    for (let i = 11; i >= 0; i--) {
      const d = new Date(now.getFullYear(), now.getMonth() - i, 1);
      monthlyBuckets.push({
        key: d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0'),
        date: d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-15',
        count: 0,
      });
    }
    const salesByKey = {};
    const earningsByKey = {};
    for (const b of monthlyBuckets) {
      salesByKey[b.key] = 0;
      earningsByKey[b.key] = 0;
    }

    let totalOrders = orders.length;
    let successfulOrders = 0;
    let failedOrders = 0;
    let monthlyEarnings = 0;
    for (const o of orders) {
      const amount = toNum(o.totalAmount);
      if (PAID.includes(o.status)) {
        successfulOrders++;
        monthlyEarnings += amount;
        const d = o.createdAt;
        const key = d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0');
        if (salesByKey[key] !== undefined) {
          salesByKey[key]++;
          earningsByKey[key] += amount;
        }
      } else if (FAILED.includes(o.status)) {
        failedOrders++;
      }
    }

    const monthlySales = monthlyBuckets.map((b) => ({ date: b.date, count: salesByKey[b.key] }));
    const monthlyEarningsArr = monthlyBuckets.map((b) => ({
      date: b.date,
      earnings: Math.round(earningsByKey[b.key]),
    }));

    let totalReviews = reviews.length;
    let positiveReviews = 0;
    let negativeReviews = 0;
    let avgRatingSum = 0;
    for (const r of reviews) {
      avgRatingSum += toNum(r.rating);
      if (Number(r.rating) >= 4) positiveReviews++;
      else if (Number(r.rating) <= 2) negativeReviews++;
    }
    const averageRating = totalReviews ? Math.round((avgRatingSum / totalReviews) * 10) / 10 : 0;

    const topProducts = products
      .map((p) => ({
        productId: p.id,
        productName: p.title,
        productImage: snapshotImage(p.snapshot),
        viewCount: snapshotViews(p.snapshot),
        locationBreakdown: {},
      }))
      .sort((a, b) => b.viewCount - a.viewCount)
      .slice(0, 5);

    res.json({
      success: true,
      data: {
        sellerId: seller.id,
        totalProducts,
        totalProductViews,
        genderBreakdown: genderMap,
        locationBreakdown: {},
        ageBreakdown: {},
        boostImpressions,
        boostLocationBreakdown: boostLocation,
        monthlyEarnings: Math.round(monthlyEarnings),
        totalOrders,
        successfulOrders,
        failedOrders,
        totalTransactions: totalOrders,
        successfulTransactions: successfulOrders,
        failedTransactions: failedOrders,
        averageRating,
        totalReviews,
        positiveReviews,
        negativeReviews,
        topProducts,
        monthlySales,
        monthlyEarningsArr,
        lastUpdated: now.toISOString(),
      },
    });
  } catch (error) {
    console.error('[SELLER-ANALYTICS] overview error:', error.message || error);
    res.status(500).json({ success: false, error: 'Kushindwa kupata analytics za muuzaji' });
  }
}

// POST /boosts/:id/impressions
async function recordBoostImpression(req, res) {
  const prisma = getPrisma();
  const { id } = req.params;
  try {
    const boost = await resolveBoost(prisma, id);
    if (!boost) return res.status(404).json({ success: false, error: 'Boost haipatikani' });
    const updated = await prisma.boost.update({
      where: { id: boost.id },
      data: { impressions: { increment: 1 } },
      select: { id: true, impressions: true, clicks: true },
    });
    res.json({ success: true, data: updated });
  } catch (error) {
    res.status(500).json({ success: false, error: 'Kushindwa kurekodi impression' });
  }
}

// POST /boosts/:id/clicks
async function recordBoostClick(req, res) {
  const prisma = getPrisma();
  const { id } = req.params;
  try {
    const boost = await resolveBoost(prisma, id);
    if (!boost) return res.status(404).json({ success: false, error: 'Boost haipatikani' });
    const updated = await prisma.boost.update({
      where: { id: boost.id },
      data: { clicks: { increment: 1 } },
      select: { id: true, impressions: true, clicks: true },
    });
    res.json({ success: true, data: updated });
  } catch (error) {
    res.status(500).json({ success: false, error: 'Kushindwa kurekodi click' });
  }
}

module.exports = { getSellerAnalyticsOverview, recordBoostImpression, recordBoostClick };
