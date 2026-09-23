const { getStore } = require('../../config/database');
const sponsoredService = require('../sponsored/sponsored-service');

// Slot positions (0-based) where a sponsored placement may appear on page 1.
// Kept sparse so paid placement never floods organic results.
const SPONSORED_SLOTS = [0, 3, 6];
const MAX_SPONSORED_PER_PAGE = SPONSORED_SLOTS.length;

/**
 * Search products via the Firestore store seam (case-insensitive matches on
 * title/description/slug). Returns ranked results respecting price/category filters.
 *
 * Active `search`-placement campaigns are interleaved at fixed slots on page 1
 * and marked with `isSponsored` + `sponsoredCampaign` so the client can show
 * the required Sponsored label. Organic ranking is otherwise untouched.
 */
async function searchProducts({ query, categoryId, minPrice, maxPrice, sort, page = 1, limit = 20, ipAddress, userAgent }) {
  const store = getStore();

  const where = {
    status: 'published',
    ...(query ? {
      OR: [
        { title: { contains: query, mode: 'insensitive' } },
        { description: { contains: query, mode: 'insensitive' } },
        { slug: { contains: query.toLowerCase() } },
      ],
    } : {}),
    ...(categoryId ? { categoryId } : {}),
    ...(minPrice != null ? { price: { gte: Number(minPrice) } } : {}),
    ...(maxPrice != null ? { price: { lte: Number(maxPrice) } } : {}),
  };

  const [products, total] = await Promise.all([
    store.product.findMany({
      where,
      include: {
        media: { orderBy: { sortOrder: 'asc' }, take: 1 },
        seller: { select: { storeName: true, storeSlug: true, reliabilityScore: true } },
        category: { select: { name: true, slug: true } },
      },
      orderBy:
        sort === 'price_asc'
          ? { price: 'asc' }
          : sort === 'price_desc'
            ? { price: 'desc' }
            : { createdAt: 'desc' },
      take: Number(limit),
      skip: (Number(page) - 1) * Number(limit),
    }),
    store.product.count({ where }),
  ]);

  let merged = products;
  if (Number(page) === 1) {
    try {
      const placements = await sponsoredService.getActivePlacements({
        categoryId,
        placement: 'search',
        limit: MAX_SPONSORED_PER_PAGE,
        ipAddress,
        userAgent,
      });
      merged = interleaveSponsored(products, placements, Number(limit));
    } catch (e) {
      // Sponsored is an enhancement: never let it break organic search.
      console.error('[Search] sponsored slotting failed:', e.message);
    }
  }

  return {
    products: merged,
    pagination: { page: Number(page), limit: Number(limit), total },
  };
}

// Merge active sponsored placements into organic results at fixed slots.
// Sponsored items are marked and de-duplicated against organic matches so a
// product never appears twice (and always carries its Sponsored label).
function interleaveSponsored(organic, campaigns, limit) {
  const sponsored = [];
  const seen = new Set();
  for (const campaign of campaigns || []) {
    for (const placement of campaign.placements || []) {
      const product = placement.product;
      if (!product || seen.has(product.id)) continue;
      seen.add(product.id);
      sponsored.push({
        ...product,
        isSponsored: true,
        sponsoredCampaign: { id: campaign.id },
      });
    }
  }
  if (sponsored.length === 0) return organic;

  const sponsoredIds = new Set(sponsored.map((p) => p.id));
  const organicFiltered = organic.filter((p) => !sponsoredIds.has(p.id));

  const result = [];
  let si = 0;
  let oi = 0;
  const maxSponsored = Math.min(sponsored.length, MAX_SPONSORED_PER_PAGE);
  while (result.length < limit && (oi < organicFiltered.length || si < maxSponsored)) {
    if (si < maxSponsored && SPONSORED_SLOTS.includes(result.length)) {
      result.push(sponsored[si++]);
    } else if (oi < organicFiltered.length) {
      result.push(organicFiltered[oi++]);
    } else {
      result.push(sponsored[si++]);
    }
  }
  return result;
}

/**
 * Exact-title priority helper: returns true if a product title matches exactly.
 */
function exactTitleMatch(product, query) {
  return product.title.toLowerCase() === String(query).toLowerCase();
}

module.exports = { searchProducts, exactTitleMatch };
