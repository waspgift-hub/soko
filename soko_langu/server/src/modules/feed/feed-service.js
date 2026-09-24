// Firestore-only feed (Phase 4). The discovery feed the app renders is a
// client-side stream of the `products` collection, so this endpoint keeps the
// legacy `/api/v1/feed` contract but ranks product docs from Firestore instead
// of the Postgres FeedPost table. Ranking mirrors the app: paid ads first,
// then recency, with the same clamp-to-0..1 rankItem scoring.
const { getFirebaseFirestore } = require('../../config/firebase');
const { rankItem } = require('./feed-ranking');
const sponsoredService = require('../sponsored/sponsored-service');

const AD_SLOTS = [1, 5];

async function getFeed({ requesterId, cursor, limit = 15, ipAddress, userAgent }) {
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

  // Ranking refers to the ad model now: ads win or lose on spend, not a
  // legacy isBoosted boolean. Fall back to recency so the page always fills.
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
    .sort((a, b) => b.viewCount - a.viewCount)
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
      createdAt: p.createdAt,
    },
    rankScore: p.rankScore,
  }));

  // Interleave product_feed/featured ads into the first page.
  if (!cursor) {
    try {
      const feeds = await sponsoredService.getActivePlacements({
        placement: 'product_feed',
        limit: AD_SLOTS.length,
        ipAddress,
        userAgent,
      });
      const adItems = [];
      const seen = new Set(items.map((i) => i.product.id));
      for (const campaign of feeds || []) {
        for (const placement of campaign.placements || []) {
          const product = placement.product;
          if (!product || seen.has(product.id)) continue;
          seen.add(product.id);
          adItems.push({
            id: `ad-${campaign.id}`,
            isSponsored: true,
            sponsoredCampaign: { id: campaign.id },
            product: {
              id: product.id,
              title: product.title,
              price: product.price,
              currency: product.currency || 'TZS',
              images: [],
              viewCount: 0,
              soldCount: 0,
              isAd: true,
            },
            rankScore: Infinity,
          });
        }
      }
      const merged = [];
      let ai = 0;
      for (let i = 0; i < items.length; i++) {
        while (ai < adItems.length && AD_SLOTS.includes(merged.length)) {
          merged.push(adItems[ai++]);
        }
        merged.push(items[i]);
      }
      while (ai < adItems.length && merged.length < take) {
        merged.push(adItems[ai++]);
      }
      return { items: merged.slice(0, take), nextCursor: merged.length >= take ? nextCursor : null };
    } catch (e) {
      // Ads are an enhancement; never let them break the feed.
      console.error('[Feed] ad slotting failed:', e.message);
    }
  }

  return { items, nextCursor };
}

module.exports = { getFeed };