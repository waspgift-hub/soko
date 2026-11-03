const { getPrisma } = require('../../config/database');
const { rankItem } = require('./feed-ranking');

/**
 * Feed service with cursor-based pagination.
 * Returns ranked FeedPost items (10-20 per request default).
 */
async function getFeed({ requesterId, cursor, limit = 15 }) {
  const prisma = getPrisma();

  const where = {
    ...(cursor ? { createdAt: { lt: new Date(cursor) } } : {}),
  };

  const posts = await prisma.feedPost.findMany({
    where,
    orderBy: { createdAt: 'desc' },
    take: Number(limit),
    include: {
      product: { include: { media: true } },
      user: { select: { id: true, displayName: true, avatarUrl: true } },
    },
  });

  // Rank in memory (scale-up later with a cache/worker)
  const ranked = posts
    .map((p) => ({
      ...p,
      rankScore: rankItem({
        watchTime: Number(p.engagementScore || 0),
        completionRate: Number(p.engagementScore || 0),
        productClickRate: Number(p.engagementScore || 0),
        purchaseSignal: Number(p.engagementScore || 0),
        shareRate: 0,
        engagementRate: Number(p.engagementScore || 0),
        createdAt: p.createdAt,
      }),
    }))
    .sort((a, b) => b.rankScore - a.rankScore);

  const nextCursor = ranked.length === Number(limit)
    ? new Date(ranked[ranked.length - 1].createdAt).toISOString()
    : null;

  return { items: ranked, nextCursor };
}

module.exports = { getFeed };
