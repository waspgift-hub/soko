// Temp smoke harness for the shop API adapter (svProduct + api* helpers).
// Extracts the adapter block from app.js and exercises it against sample DTOs.
const fs = require('fs');
const path = require('path');

const src = fs.readFileSync(path.join(__dirname, '..', 'app.js'), 'utf8');
const lines = src.split('\n');
const start = lines.findIndex((l) => l.includes('API adapter (Postgres truth'));
if (start < 0) throw new Error('adapter banner not found');
let end = -1;
for (let i = start; i < lines.length; i++) {
  if (lines[i].startsWith('function featured(')) { end = i; break; }
}
if (end < 0) throw new Error('adapter end not found');
const block = lines.slice(start, end).join('\n');

const calls = [];
const TZ = () => new Date('2026-01-01T00:00:00.000Z');
const sample = {
  id: 'prod-abc-123',
  title: 'Simu Samsung A14',
  price: '450000',
  currency: 'TZS',
  status: 'published',
  description: 'Simu mpya',
  condition: 'new',
  stock: 5,
  rating: '4.5',
  reviewCount: 2,
  soldCount: 7,
  category: { id: 'cc1cb866-c44d-4c3d-9bbb-07d590fdc4c5', name: 'Magari' },
  createdAt: '2026-01-01T00:00:00.000Z',
  media: [{ r2Key: 'https://res.cloudinary.com/x/y.jpg', sortOrder: 0 }, { r2Key: 'products/abc/2.jpg', sortOrder: 1 }],
  seller: { id: 'aff84609-d7b4-48f4-a84e-c9441faaa78a', storeName: 'Duka Bora', storeSlug: 'duka-bora', sellerId: 'gKZgi2GSxsgHgW6hUhr0p5l17YT2', sellerPhone: '+255700123456' },
  snapshot: {
    legacyId: 'legacy-firestore-id-9Zf2',
    images: [],
    category: 'Vingine',
    subcategory: 'Simu',
    location: 'Dar es Salaam',
    unit: 'kipande',
    minOrder: 1,
    brand: 'Samsung',
    sellerKycApproved: true,
    boostedUntil: { _seconds: 1826216400, _nanoseconds: 0 },
    isBoosted: true,
    boostTier: 'gold',
  },
};

async function main() {
  const apiGet = async (p) => {
    calls.push(p);
    if (p.includes('/api/v1/products?page=')) return { data: { items: [sample], pagination: { page: 1, limit: 24, total: 1 } } };
    if (p.includes('/api/v1/products/')) return { data: sample };
    if (p.includes('/api/v1/products?sellerId=')) return { data: { items: [sample], pagination: { page: 1, limit: 100, total: 1 } } };
    if (p.includes('/api/v1/reviews/product/')) return { data: { reviews: [{ id: 'r1', userName: 'Juma', rating: 5, comment: 'Nzuri', sellerReply: null, createdAt: '2026-01-02T00:00:00.000Z' }], pagination: { total: 1 } } };
    throw new Error('unexpected path ' + p);
  };
  const fn = new Function('apiGet', 'PAGE', block + '\n;return { svProduct, apiGetProduct, apiFeedPage, apiStoreProducts, apiReviewsFor };')(
    apiGet, 24,
  );

  const p = fn.svProduct(sample);
  const assert = (cond, msg) => { if (!cond) throw new Error('FAIL: ' + msg); };
  assert(p.id === 'prod-abc-123', 'id');
  assert(p.name === 'Simu Samsung A14', 'name');
  assert(p.price === 450000, 'price number');
  assert(p.currency === 'TZS', 'currency');
  assert(p.images.length === 2, 'images length');
  assert(p.images[0] === 'https://res.cloudinary.com/x/y.jpg', 'absolute media passthrough');
  assert(p.images[1] === 'https://media.soko-vibe.co.tz/products/abc/2.jpg', 'r2 key prefixed');
  assert(p.category === 'Vingine', 'snapshot category wins');
  assert(p.subcategory === 'Simu', 'subcategory');
  assert(p.sellerId === 'gKZgi2GSxsgHgW6hUhr0p5l17YT2', 'sellerId = firebaseUid');
  assert(p.sellerProfileId === 'aff84609-d7b4-48f4-a84e-c9441faaa78a', 'sellerProfileId');
  assert(p.sellerName === 'Duka Bora', 'sellerName from seller.storeName');
  assert(p.sellerPhone === '+255700123456', 'sellerPhone');
  assert(p.stock === 5, 'stock');
  assert(p.isActive === true, 'isActive published');
  assert(p.isBoosted === true && p.boostTier === 'gold', 'boosted');
  assert(p.boostedUntil instanceof Date && p.boostedUntil.getTime() === 1826216400000, 'boostedUntil _seconds');
  assert(p._legacyId === 'legacy-firestore-id-9Zf2', 'legacyId');
  assert(p.rating === 4.5, 'rating');
  assert(p.reviewCount === 2, 'reviewCount');
  assert(p.sellerKycApproved === true, 'kyc');

  const inactive = fn.svProduct(Object.assign({}, sample, { status: 'draft' }));
  assert(inactive.isActive === false, 'draft inactive');

  const detail = await fn.apiGetProduct('prod-abc-123');
  assert(detail && detail.id === 'prod-abc-123', 'apiGetProduct ok');

  const feed = await fn.apiFeedPage(2);
  assert(feed.items.length === 1 && feed.done === true, 'apiFeedPage ok');

  const store = await fn.apiStoreProducts('gKZgi2GSxsgHgW6hUhr0p5l17YT2');
  assert(store.length === 1 && store[0].sellerId === 'gKZgi2GSxsgHgW6hUhr0p5l17YT2', 'apiStoreProducts ok');

  const reviews = await fn.apiReviewsFor({ id: 'prod-abc-123', _legacyId: 'legacy-firestore-id-9Zf2' }, 12);
  assert(Array.isArray(reviews) && reviews[0].userName === 'Juma', 'apiReviewsFor legacy key');
  assert(calls.some((c) => c.includes('/api/v1/reviews/product/legacy-firestore-id-9Zf2')), 'reviews read by legacyId');

  console.log('SMOKE OK — ' + calls.length + ' api calls, ' + JSON.stringify({ feed, store: store.length, reviews: reviews.length, boostedUntil: p.boostedUntil.toISOString() }));
}

main().catch((e) => { console.error(e.message); process.exit(1); });