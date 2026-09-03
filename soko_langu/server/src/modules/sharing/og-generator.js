const { getPrisma } = require('../../config/database');
const config = require('../../config');
const { ogTags, publicUrl } = require('../media/cdn-service');

/**
 * Generate OG meta tags for a product share route.
 * Route: /product/:slugOrId
 */
async function productOgMeta(slugOrId) {
  const prisma = getPrisma();
  const product = await prisma.product.findFirst({
    where: { OR: [{ slug: slugOrId }, { id: slugOrId }], status: 'published' },
    include: {
      media: { orderBy: { sortOrder: 'asc' }, take: 1 },
      seller: { select: { storeName: true } },
      category: { select: { name: true } },
    },
  });
  if (!product) return null;

  const imageUrl = product.media[0] ? publicUrl({ kind: 'image', key: product.media[0].r2Key }) : null;
  const price = Number(product.price).toLocaleString('en-TZ');
  const description = `${product.title} — TZS ${price}${product.seller?.storeName ? ` · ${product.seller.storeName}` : ''}`;

  return ogTags({
    title: product.title,
    description,
    imageUrl,
    type: 'product',
  });
}

/**
 * Generate OG meta tags for a seller share route.
 * Route: /seller/:username
 */
async function sellerOgMeta(username) {
  const prisma = getPrisma();
  const seller = await prisma.sellerProfile.findUnique({
    where: { storeSlug: username },
    include: { user: true },
  });
  if (!seller) return null;

  const description = `${seller.storeName} on Soko Vibe${seller.storeDescription ? ` — ${seller.storeDescription}` : ''}`;

  return ogTags({
    title: seller.storeName,
    description,
    imageUrl: seller.logoUrl,
    type: 'profile',
  });
}

module.exports = { productOgMeta, sellerOgMeta };
