// Phase B: idempotent backfill of Firestore `products` → Postgres products table.
// Dry-run by default; pass --commit to write. Idempotent: skips products where
// title + sellerProfileId already exist (upsert on seller+title unique pair
// would require a composite index, so we simply skip).
//
// Usage:
//   node scripts/migrate-products.js              # dry-run
//   node scripts/migrate-products.js --commit     # write to Postgres
//   node scripts/migrate-products.js --limit 50   # cap batch size

require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });

const admin = require('firebase-admin');
const { PrismaClient } = require('@prisma/client');
const { mapFirestoreProductToPrisma, mapFirestoreMediaToProductRows } = require('../src/modules/products/legacy-mapper');

if (!process.env.DATABASE_URL) {
  console.error('FATAL: DATABASE_URL not set');
  process.exit(1);
}
if (!process.env.FIREBASE_SERVICE_ACCOUNT_JSON) {
  console.error('FATAL: FIREBASE_SERVICE_ACCOUNT_JSON not set');
  process.exit(1);
}

const COMMIT = process.argv.includes('--commit');
const LIMIT = (() => {
  const idx = process.argv.indexOf('--limit');
  if (idx !== -1) {
    const v = parseInt(process.argv[idx + 1], 10);
    if (Number.isFinite(v) && v > 0) return v;
  }
  return Infinity;
})();

const prisma = new PrismaClient({ datasources: { db: { url: process.env.DATABASE_URL } } });
admin.initializeApp({
  credential: admin.credential.cert(JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON)),
});
const firestore = admin.firestore();

// ── UID → SellerProfile resolution cache ─────────────────────────────────────
const profileCache = new Map();
async function resolveSellerProfile(firebaseUid) {
  if (profileCache.has(firebaseUid)) return profileCache.get(firebaseUid);
  const user = await prisma.user.findUnique({
    where: { firebaseUid },
    select: {
      id: true,
      sellerProfile: { select: { id: true, storeName: true } },
    },
  });
  const result = user?.sellerProfile?.id || null;
  profileCache.set(firebaseUid, result);
  return result;
}

// ── Category name → id resolution cache ──────────────────────────────────────
// Legacy Firestore products tag categories with their old display names
// ('Automotive', 'Home & Garden') that differ from the Postgres seed names
// ('Vehicles', 'Home'); aliases bridge the rename so categoryId links survive.
const CATEGORY_ALIASES = {
  'automotive': 'vehicles',
  'home & garden': 'home',
  'health & beauty': 'beauty',
  'sports & entertainment': 'other',
  'others': 'other',
};
const categoryCache = new Map();
async function resolveCategoryId(name) {
  if (!name) return null;
  const key = name.trim().toLowerCase();
  if (categoryCache.has(key)) return categoryCache.get(key);
  const target = CATEGORY_ALIASES[key] || name;
  const cat = await prisma.category.findFirst({
    where: { name: { equals: target, mode: 'insensitive' } },
    select: { id: true },
  });
  const result = cat?.id || null;
  categoryCache.set(key, result);
  return result;
}

async function main() {
  console.log(`[migrate-products] mode=${COMMIT ? 'COMMIT' : 'DRY-RUN'} limit=${LIMIT === Infinity ? 'none' : LIMIT}`);

  // Existing Postgres product titles (seller+title) — used for idempotent skip.
  const existing = await prisma.product.findMany({
    select: { sellerId: true, title: true },
  });
  const existingSet = new Set(existing.map(p => `${p.sellerId}|||${p.title}`));
  console.log(`[migrate-products] Postgres products already present: ${existingSet.size}`);

  // Read Firestore products
  let count = 0;
  let skipped = 0;
  let errored = 0;
  const batch = firestore.collection('products');

  // Firestore may not have compound indexes for filtered queries, so paginate
  // the whole collection and filter in-memory (active products only).
  const snapshot = await batch.limit(10000).get();
  console.log(`[migrate-products] Firestore docs fetched: ${snapshot.size}`);

  for (const doc of snapshot.docs) {
    if (count + skipped >= LIMIT) break;

    const data = doc.data();
    if (!data || !data.name) { skipped++; continue; }

    // Resolve SellerProfile (Firestore UID → Postgres profile id)
    const sellerProfileId = await resolveSellerProfile(data.sellerId);
    if (!sellerProfileId) { skipped++; continue; }

    // Skip if already present
    const pgTitle = String(data.name || '').trim();
    const dedupKey = `${sellerProfileId}|||${pgTitle}`;
    if (existingSet.has(dedupKey)) { skipped++; continue; }

    // Resolve Category
    const categoryId = await resolveCategoryId(data.category);

    try {
      const payload = mapFirestoreProductToPrisma(data, { sellerProfileId, categoryId });
      if (COMMIT) {
        const { categoryId: catId, ...rest } = payload;
        await prisma.product.create({
          data: {
            ...rest,
            price: Number(rest.price),
            snapshot: rest.snapshot,
            seller: { connect: { id: sellerProfileId } },
            category: catId ? { connect: { id: catId } } : undefined,
            media: { create: [] },
          },
        });
      }
      count++;
    } catch (e) {
      errored++;
      console.error(`[migrate-products] SKIP ${doc.id}: ${e.message}`);
    }
  }

  console.log(`[migrate-products] done. created=${count} skipped=${skipped} errors=${errored}`);

  // Phase 2: mirror legacy media URLs (Cloudinary) into ProductMedia so
  // Postgres-served catalogs keep displaying images. Idempotent — products with
  // any media row are skipped; R2 re-hosting stays a Phase F migration.
  const needMedia = await prisma.product.findMany({
    where: { deletedAt: null, media: { none: {} } },
    select: { id: true, snapshot: true },
    ...(Number.isFinite(LIMIT) ? { take: LIMIT } : {}),
  });
  let mediaRows = 0;
  let mediaSkipped = 0;
  for (const p of needMedia) {
    const rows = mapFirestoreMediaToProductRows(p.snapshot || {});
    if (!rows.length) {
      mediaSkipped++;
      continue;
    }
    if (COMMIT) {
      await prisma.productMedia.createMany({
        data: rows.map(r => ({ ...r, productId: p.id })),
      });
    }
    mediaRows += rows.length;
  }
  console.log(`[migrate-products] media done. rows=${mediaRows} productsWithoutMedia=${mediaSkipped}`);

  // Phase 3: enrich snapshots created before `category`/`subcategory` were part
  // of LEGACY_KEYS and link products whose categoryId was never resolved (legacy
  // names like 'Automotive' have no Postgres row). The server subcategory
  // filter, list-card category, and category page all read these. Idempotent:
  // only missing keys are merged.
  const enrichKeys = ['category', 'subcategory'];
  let enriched = 0;
  for (const doc of snapshot.docs) {
    if (enriched >= (Number.isFinite(LIMIT) ? LIMIT : Number.MAX_SAFE_INTEGER)) break;
    const data = doc.data();
    if (!data || !data.name) continue;
    const sellerProfileId = await resolveSellerProfile(data.sellerId);
    if (!sellerProfileId) continue;
    const product = await prisma.product.findFirst({
      where: { sellerId: sellerProfileId, title: String(data.name).trim(), deletedAt: null },
      select: { id: true, snapshot: true, categoryId: true },
    });
    if (!product) continue;
    const current = product.snapshot || {};
    const patch = {};
    for (const k of enrichKeys) {
      if (data[k] !== undefined && data[k] !== null && current[k] === undefined) patch[k] = data[k];
    }
    if (product.categoryId == null) {
      const linked = await resolveCategoryId(data.category);
      if (linked && linked !== product.categoryId) patch.categoryId_ = linked;
    }
    const hasMeta = Object.keys(patch).some((k) => k !== 'categoryId_');
    const updateId = patch.categoryId_ || undefined;
    if (hasMeta || updateId) {
      if (COMMIT) {
        const update = {};
        if (hasMeta) {
          const meta = { category: patch.category, subcategory: patch.subcategory };
          update.snapshot = { ...current, ...meta };
        }
        if (updateId) update.categoryId = updateId;
        await prisma.product.update({ where: { id: product.id }, data: update });
      }
      enriched++;
    }
  }
  console.log(`[migrate-products] snapshot enriched + category linked=${enriched}`);

  await prisma.$disconnect();
}

main().catch(async (e) => {
  console.error('[migrate-products] fatal:', e);
  await prisma.$disconnect();
  process.exit(1);
});
