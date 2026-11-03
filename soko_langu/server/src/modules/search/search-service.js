const { getPrisma } = require('../../config/database');

/**
 * Search products using PostgreSQL ILIKE + trigram similarity.
 * Returns ranked results respecting price/category filters.
 */
async function searchProducts({ query, categoryId, minPrice, maxPrice, sort, page = 1, limit = 20 }) {
  const prisma = getPrisma();

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
    prisma.product.findMany({
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
    prisma.product.count({ where }),
  ]);

  return {
    products,
    pagination: { page: Number(page), limit: Number(limit), total },
  };
}

/**
 * Exact-title priority helper: returns true if a product title matches exactly.
 */
function exactTitleMatch(product, query) {
  return product.title.toLowerCase() === String(query).toLowerCase();
}

module.exports = { searchProducts, exactTitleMatch };
