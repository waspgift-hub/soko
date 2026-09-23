// Firestore-only feed (Phase 4). The discovery feed the app renders is a
// client-side stream of the `products` collection, so this endpoint keeps the
// legacy `/api/v1/feed` contract but ranks product docs from Firestore instead
// of the Postgres FeedPost table. Ranking mirrors the app: boosted first, then
// recency, with the same clamp-to-0..1 rankItem scoring.
const { getFirebaseFirestore } = require('../../config/firebase');
const { rankItem } = require('./feed-ranking');

async function getFeed({ requesterId, cursor, limit = 15 }) {
  const db = getFirebaseFirestore();
  const take = Math.min(Math.max(1, Number(limit)), 50);

  let q = db
    .collection('products')
    .where('isActive', '==', true)
    .orderBy('createdAt', 'desc');
  if (cursor) q = q.startAfter(cursor);

  const snap = await q.limit(Math.min(take * 2, 100)).get();

  const posts = [];
  snap.forEach((doc) => {
    const d = doc.data();
    if (!d?.name || d.price == null) return;
    const c = d.createdAt;
    const createdAt = c != null && typeof c.toDate === 'function' ? c.toDate().toISOString() : (c instanceof Date ? c.toISOString() : String(c));
    posts.push({ ...d, id: doc.id, createdAt });
  });

  // Rank in memory (scale-up later with a cache/worker), mirroring the For You
  // sort: boosted listings first, then newest.
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
    .sort((a, b) => Number(b.isBoosted || false) - Number(a.isBoosted || false) || b.viewCount - a.viewCount)
    .slice(0, take);

  // Cursor = the ranked window's last createdAt, so the next page resumes from
  // a deterministic point rather than re-ranking the whole catalog.
  const nextCursor = ranked.length === take ? String(ranked[ranked.length - 1].createdAt) : null;

  const items = ranked.map((p) => ({
    id: p.id,
    sellerId: p.sellerId || null,
    userName: p.sellerName || 'Unknown',
    avatarUrl: p.sellerImage || null,
    product: {
      id: p.id,
      title: p.name,
      price: p.price,
      currency: p.currency,
      images: Array.isArray(p.media) ? p.media.map((m) => m.url || m) : [],
      video: p.video || null,
      viewCount: p.viewCount || 0,
      soldCount: p.soldCount || 0,
      isBoosted: Boolean(p.isBoosted),
      createdAt: p.createdAt,
    },
    rankScore: p.rankScore,
  }));

  return { items, nextCursor };
}

module.exports = { getFeed };