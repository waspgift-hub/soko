const crypto = require('crypto');
const { getPrisma } = require('../../config/database');

function httpError(status, message) {
  const err = new Error(message);
  err.status = status;
  return err;
}

function slugify(title) {
  const base = String(title || '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 60) || 'product';
  return `${base}-${crypto.randomBytes(3).toString('hex')}`;
}

const PUBLIC_SELECT = {
  id: true,
  title: true,
  slug: true,
  description: true,
  price: true,
  originalPrice: true,
  currency: true,
  stock: true,
  status: true,
  condition: true,
  createdAt: true,
  seller: { select: { id: true, storeName: true, storeSlug: true } },
  media: { orderBy: { sortOrder: 'asc' }, take: 4 },
};

async function requireSellerProfile(userId) {
  const prisma = getPrisma();
  const profile = await prisma.sellerProfile.findUnique({ where: { userId } });
  if (!profile) throw httpError(404, 'SELLER_PROFILE_NOT_FOUND');
  return profile;
}

async function createProduct({ sellerProfileId, data }) {
  const prisma = getPrisma();
  const snapshot = {
    title: data.title,
    description: data.description || null,
    price: data.price,
    originalPrice: data.originalPrice || null,
    currency: 'TZS',
    stock: data.stock ?? 0,
    condition: data.condition || 'new',
    categoryId: data.categoryId || null,
    weightGrams: data.weightGrams || null,
    shippingRequired: data.shippingRequired !== false,
  };
  try {
    return await prisma.product.create({
      data: {
        sellerId: sellerProfileId,
        title: snapshot.title,
        slug: slugify(snapshot.title),
        description: snapshot.description,
        categoryId: snapshot.categoryId,
        price: BigInt(snapshot.price),
        originalPrice: snapshot.originalPrice != null ? BigInt(snapshot.originalPrice) : null,
        stock: snapshot.stock,
        condition: snapshot.condition,
        weightGrams: snapshot.weightGrams,
        shippingRequired: snapshot.shippingRequired,
        status: 'draft',
        snapshot,
      },
    });
  } catch (e) {
    if (e.code === 'P2002') throw httpError(409, 'SLUG_CONFLICT_RETRY');
    throw e;
  }
}

async function getOwnedProduct({ id, sellerProfileId }) {
  const prisma = getPrisma();
  const product = await prisma.product.findFirst({
    where: { id, sellerId: sellerProfileId, deletedAt: null },
  });
  if (!product) throw httpError(404, 'PRODUCT_NOT_FOUND');
  return product;
}

async function updateProduct({ id, sellerProfileId, data }) {
  const prisma = getPrisma();
  await getOwnedProduct({ id, sellerProfileId });
  const allowed = ['title', 'description', 'categoryId', 'price', 'originalPrice', 'stock', 'condition', 'weightGrams', 'shippingRequired'];
  const patch = {};
  for (const key of allowed) {
    if (data[key] !== undefined) {
      if (key === 'price' || key === 'originalPrice') {
        patch[key] = data[key] != null ? BigInt(data[key]) : null;
      } else {
        patch[key] = data[key];
      }
    }
  }
  return prisma.product.update({ where: { id }, data: patch });
}

async function setStatus({ id, sellerProfileId, status }) {
  const prisma = getPrisma();
  const product = await getOwnedProduct({ id, sellerProfileId });
  if (status === 'published') {
    if (!product.title || Number(product.price) <= 0) {
      throw httpError(400, 'PUBLISH_REQUIRES_TITLE_AND_PRICE');
    }
  }
  return prisma.product.update({ where: { id }, data: { status } });
}

async function softDelete({ id, sellerProfileId }) {
  const prisma = getPrisma();
  await getOwnedProduct({ id, sellerProfileId });
  return prisma.product.update({ where: { id }, data: { status: 'deleted', deletedAt: new Date() } });
}

async function listProducts({ q, categoryId, minPrice, maxPrice, page = 1, limit = 20 }) {
  const prisma = getPrisma();
  const where = { status: 'published', deletedAt: null };
  if (categoryId) where.categoryId = categoryId;
  if (minPrice != null || maxPrice != null) {
    where.price = {};
    if (minPrice != null) where.price.gte = BigInt(minPrice);
    if (maxPrice != null) where.price.lte = BigInt(maxPrice);
  }
  if (q) {
    where.OR = [
      { title: { contains: q, mode: 'insensitive' } },
      { description: { contains: q, mode: 'insensitive' } },
    ];
  }
  const [items, total] = await Promise.all([
    prisma.product.findMany({
      where,
      select: PUBLIC_SELECT,
      orderBy: { createdAt: 'desc' },
      take: Number(limit),
      skip: (Number(page) - 1) * Number(limit),
    }),
    prisma.product.count({ where }),
  ]);
  return { items, pagination: { page: Number(page), limit: Number(limit), total } };
}

async function listSellerProducts({ sellerProfileId, page = 1, limit = 20 }) {
  const prisma = getPrisma();
  const where = { sellerId: sellerProfileId, deletedAt: null };
  const [items, total] = await Promise.all([
    prisma.product.findMany({
      where,
      include: { media: { orderBy: { sortOrder: 'asc' }, take: 4 } },
      orderBy: { updatedAt: 'desc' },
      take: Number(limit),
      skip: (Number(page) - 1) * Number(limit),
    }),
    prisma.product.count({ where }),
  ]);
  return { items, pagination: { page: Number(page), limit: Number(limit), total } };
}

async function getProduct(idOrSlug) {
  const prisma = getPrisma();
  const isUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(idOrSlug);
  const product = await prisma.product.findFirst({
    where: {
      ...(isUuid ? { OR: [{ id: idOrSlug }, { slug: idOrSlug }] } : { slug: idOrSlug }),
      status: 'published',
      deletedAt: null,
    },
    select: {
      ...PUBLIC_SELECT,
      category: { select: { id: true, name: true, slug: true } },
      snapshot: true,
    },
  });
  if (!product) throw httpError(404, 'PRODUCT_NOT_FOUND');
  return product;
}

async function attachMedia({ id, sellerProfileId, items }) {
  const prisma = getPrisma();
  await getOwnedProduct({ id, sellerProfileId });
  const rows = await Promise.all(
    items.map((m, i) =>
      prisma.productMedia.create({
        data: {
          productId: id,
          type: m.type || 'image',
          r2Key: m.r2Key,
          thumbnailR2Key: m.thumbnailR2Key || null,
          variantUrls: m.variantUrls || undefined,
          width: m.width || null,
          height: m.height || null,
          durationSeconds: m.durationSeconds || null,
          fileSizeBytes: m.fileSizeBytes != null ? BigInt(m.fileSizeBytes) : null,
          sortOrder: m.sortOrder != null ? m.sortOrder : i,
        },
      })
    )
  );
  return rows;
}

async function moderate({ id, status }) {
  const prisma = getPrisma();
  const product = await prisma.product.findUnique({ where: { id } });
  if (!product) throw httpError(404, 'PRODUCT_NOT_FOUND');
  return prisma.product.update({ where: { id }, data: { status } });
}

module.exports = {
  requireSellerProfile,
  createProduct,
  updateProduct,
  setStatus,
  softDelete,
  listProducts,
  listSellerProducts,
  getProduct,
  attachMedia,
  moderate,
};
