const { getFirebaseFirestore } = require('../../config/firebase');

// How many active docs to scan before giving up on in-memory text matching.
// A full collection scan is not viable at scale: see the note on searchProducts
// about replacing this with a real inverted index.
const SCAN_LIMIT = 300;

function tokens(text) {
  return String(text || '')
    .toLowerCase()
    .split(/[^a-z0-9]+/)
    .filter((t) => t.length > 1);
}

/**
 * Scores one product doc against the query tokens.
 *
 * Matching is AND, not OR: "iPhone 15" must not return a laptop that happens to
 * be a 15-inch model. A token counts as hit when it appears as a whole word or
 * as a substring of the haystack, so "phone" still finds "iPhone".
 *
 * An earlier version of this function issued `title: { contains, mode:
 * 'insensitive' }` through the store facade. That is Prisma syntax; the
 * Firestore-backed facade has no such operator, so the clause matched nothing
 * and search silently returned zero rows for every query. It also filtered on
 * `status: 'published'` and `slug`, none of which product-mirror.js writes —
 * the mirror emits `isActive`, `name` and `searchName`.
 */
function scoreDoc(doc, queryTokens, raw) {
  const haystack = [
    doc.name, doc.searchName, doc.brand, doc.category, doc.subcategory, doc.description,
  ].filter(Boolean).join(' ').toLowerCase();
  const hayTokens = new Set(tokens(haystack));

  for (const t of queryTokens) {
    if (!hayTokens.has(t) && !haystack.includes(t)) return 0;
  }

  // Phrase hits outrank bag-of-words hits once every token already matched.
  const phrase = String(raw || '').trim().toLowerCase();
  let score = queryTokens.length;
  if (phrase && haystack.includes(phrase)) score += 10;
  return score;
}

/**
 * Search published products, newest first, with optional price and category
 * bounds.
 *
 * Only `isActive == true` is expressed as a Firestore clause. Price bounds are
 * applied in memory: Firestore rejects a query that mixes an inequality on
 * `price` with an orderBy on `createdAt` unless a composite index exists for the
 * exact field combination, and search must not depend on an index nobody has
 * created. Text matching is in memory over a bounded window for the same reason
 * — once the catalogue outgrows SCAN_LIMIT, matching has to move to an inverted
 * index, and the mirror's `searchKeywords` array is already an
 * `array-contains` candidate.
 *
 * Returns the same { products, pagination } shape the routes and the AI tool
 * already consume.
 */
async function searchProducts({ query, categoryId, minPrice, maxPrice, sort, page = 1, limit = 20, ipAddress, userAgent }) {
  const db = getFirebaseFirestore();
  const p = Math.max(1, Number(page) || 1);
  const take = Math.min(Math.max(1, Number(limit) || 20), 50);

  const snap = await db
    .collection('products')
    .where('isActive', '==', true)
    .orderBy('createdAt', 'desc')
    .limit(SCAN_LIMIT)
    .get();

  const queryTokens = tokens(query);
  const wantedCategory = categoryId ? String(categoryId).toLowerCase() : null;
  const lo = minPrice != null && Number.isFinite(Number(minPrice)) ? Number(minPrice) : null;
  const hi = maxPrice != null && Number.isFinite(Number(maxPrice)) ? Number(maxPrice) : null;

  const scored = [];
  snap.forEach((doc) => {
    const d = doc.data();
    if (!d?.name || d.price == null) return;
    if (lo != null && d.price < lo) return;
    if (hi != null && d.price > hi) return;
    if (wantedCategory && String(d.category || '').toLowerCase() !== wantedCategory) return;
    const score = queryTokens.length ? scoreDoc(d, queryTokens, query) : 1;
    if (queryTokens.length && score === 0) return;
    scored.push({ d, id: doc.id, score });
  });

  const order = sort === 'price_asc' ? (a, b) => a.d.price - b.d.price
    : sort === 'price_desc' ? (a, b) => b.d.price - a.d.price
      : (a, b) => b.score - a.score || String(b.d.createdAt || '').localeCompare(String(a.d.createdAt || ''));

  scored.sort(order);

  const total = scored.length;
  const pageRows = scored.slice((p - 1) * take, p * take);
  const products = pageRows.map((r) => shapeProduct(r));

  return { products, pagination: { page: p, limit: take, total } };
}

// Presents a mirror doc in the shape callers already consume: `title` and a
// nested seller/category. The mirror stores these flattened.
function shapeProduct({ doc, d, id }) {
  const images = Array.isArray(d.images) ? d.images : [];
  return {
    id,
    title: d.name,
    description: d.description || null,
    price: d.price,
    currency: d.currency || 'TZS',
    location: d.location || d.district || null,
    stock: d.stock ?? null,
    rating: d.rating ?? null,
    reviewCount: d.reviewCount ?? 0,
    brand: d.brand || null,
    condition: d.condition || 'new',
    createdAt: d.createdAt || null,
    media: images.length ? [{ url: images[0] }] : [],
    seller: d.sellerName ? { storeName: d.sellerName } : null,
    category: d.category ? { name: d.category } : null,
  };
}

/**
 * Exact-title priority helper: returns true if a product title matches exactly.
 */
function exactTitleMatch(product, query) {
  return product.title.toLowerCase() === String(query).toLowerCase();
}

module.exports = { searchProducts, exactTitleMatch };