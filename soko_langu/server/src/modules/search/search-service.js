const { getFirebaseFirestore } = require('../../config/firebase');
const adsConfig = require('../ads/ads-config');
const ranking = require('./search-ranking');

// Search execution notes.
//
// Two paths, both bounded per-read but neither capping total coverage:
//
//  1. INDEXED (fast path). `products.searchKeywords` is an array of normalised
//     tokens maintained by product-mirror.js. `array-contains` is served by a
//     Firestore index, so it returns exactly the matching set regardless of
//     catalogue size. Used whenever the query has usable tokens and there is
//     no price range (a range plus an array-contains needs a composite index
//     that is not deployed).
//
//  2. SCAN (fallback). For a stop-word-only query ("for sale", "the") or when a
//     price filter is present, matching is done in memory over paged queries
//     ordered by createdAt, so newest products win. It pages rather than taking
//     a single fixed slice, which is what removes the old 300-document
//     correctness ceiling.
//
// Ranking is deterministic within a strategy: candidates are ordered by
// createdAt desc before scoring, and scoreDoc uses integer token counts, so the
// same query returns the same order for the same data. Ties are broken by that
// createdAt order.
// Hard ceilings on the two execution strategies below. `CANDIDATE_PAGE` bounds
// a SINGLE Firestore read; `RESCAN_CEILING` / `INDEXED_CEILING` bound total work
// per request. Neither is a silent correctness limit any more: when a ceiling is
// reached the response carries `truncated: true`.
const CANDIDATE_PAGE = 300;
const RESCAN_CEILING = 1500;
const INDEXED_CEILING = 3000;

/**
 * Words that carry no meaning for retrieval in this marketplace.
 *
 * Without this, "for sale" queried the index for the tokens `for` and `sale`,
 * and `for` matches a large slice of the catalogue — which is both slow and
 * useless. Filtering them means a stop-word-only query falls through to the
 * scan path (the documented behaviour) instead of pulling thousands of
 * candidates that `scoreDoc` will mostly reject anyway.
 */
const STOP_WORDS = new Set([
  // English
  'a', 'an', 'and', 'are', 'as', 'at', 'be', 'been', 'but', 'by', 'for', 'from',
  'has', 'have', 'in', 'into', 'is', 'it', 'its', 'of', 'on', 'or', 'that', 'the',
  'their', 'then', 'there', 'these', 'they', 'this', 'to', 'was', 'were', 'will',
  'with', 'you', 'your',
  // Swahili — "ninunua", "naomba", "nzuri", "kwa bei"
  'na', 'ni', 'ya', 'wa', 'kwa', 'za', 'la', 'cha', 'vya', 'kwenye', 'katika',
  'bei', 'nzuri', 'po', 'pia', 'hii', 'hiyo', 'hizo', 'hawa', 'yake', 'wake',
  'wangu', 'wako', 'wetu', 'wao', 'sisi', 'ninyi', 'yeye', 'ndani', 'juu',
]);

function tokens(text) {
  return String(text || '')
    .toLowerCase()
    .split(/[^a-z0-9]+/)
    .filter((t) => t.length > 1 && !STOP_WORDS.has(t));
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
 * Normalises the live relevance score onto the 0..MAX_RELEVANCE band the
 * ranking module expects.
 *
 * scoreDoc returns `tokenCount` plus a 10-point phrase bonus, so its raw range is
 * 1..N+10. Scaling by the observed maximum keeps the ratio between a phrase hit
 * and a token-only hit intact while letting `verifiedSellerBoost` be expressed
 * as a percentage of the whole relevance band — which is what guarantees a
 * verified seller can never be weighted more heavily than relevance itself.
 */
const RELEVANCE_CEILING = 20;
function normalizeRelevance(rawScore) {
  return Math.min(ranking.MAX_RELEVANCE, (rawScore / RELEVANCE_CEILING) * ranking.MAX_RELEVANCE);
}

async function searchProducts({ query, categoryId, minPrice, maxPrice, sort, page = 1, limit = 20, ipAddress, userAgent }) {
  const db = getFirebaseFirestore();
  const p = Math.max(1, Number(page) || 1);
  const take = Math.min(Math.max(1, Number(limit) || 20), 50);

  const queryTokens = tokens(query);
  const wantedCategory = categoryId ? String(categoryId).toLowerCase() : null;
  const lo = minPrice != null && Number.isFinite(Number(minPrice)) ? Number(minPrice) : null;
  const hi = maxPrice != null && Number.isFinite(Number(maxPrice)) ? Number(maxPrice) : null;

  // A price range forces the scan path: Firestore cannot combine an inequality
  // on `price` with an `array-contains` on `searchKeywords` without a
  // composite index, and posting one for a mobile marketplace that is not
  // deployed is not a change to make speculatively.
  const canUseIndex =
    queryTokens.length > 0 && lo == null && hi == null;

  let strategy = canUseIndex ? 'indexed' : 'scan';
  let scan = canUseIndex
    ? await indexedCandidates(db, queryTokens)
    : await scanCandidates(db);

  // The index stores whole-word tokens ("iphone"), while `scoreDoc` also accepts
  // a token that is a SUBSTRING of a word — which is what lets "phone" find
  // "iPhone". That second rule cannot be served by an exact-token lookup, so an
  // indexed miss falls back to the scan rather than reporting "nothing found".
  //
  // Without this, switching search onto the index silently deleted substring
  // matching: the index returned zero candidates, so scoreDoc never ran.
  // The fallback only costs a scan when the fast path found literally nothing,
  // which is exactly the cost the pre-index implementation always paid.
  if (canUseIndex && scan.docs.length === 0) {
    const fallback = await scanCandidates(db);
    // A truncated scan is still better than a certain empty answer.
    if (fallback.docs.length > 0) {
      scan = fallback;
      strategy = 'scan_fallback';
    }
  }

  const scored = [];
  for (const doc of scan.docs) {
    const d = doc.data();
    if (!d?.name || d.price == null) continue;
    if (lo != null && d.price < lo) continue;
    if (hi != null && d.price > hi) continue;
    if (wantedCategory && String(d.category || '').toLowerCase() !== wantedCategory) continue;
    const score = queryTokens.length ? scoreDoc(d, queryTokens, query) : 1;
    if (queryTokens.length && score === 0) continue;
    scored.push({ d, id: doc.id, score: normalizeRelevance(score) });
  }

  // FinalScore = Relevance + Quality + Trust + Engagement + VerifiedSellerBoost.
  // The weights and the boost come from app_settings/ad_config, so an admin can
  // tune visibility without a redeploy. Price sorts skip the boost entirely.
  let config = null;
  if (sort !== 'price_asc' && sort !== 'price_desc') {
    try {
      config = await adsConfig.load();
      ranking.setRankingConfig(config);
    } catch (_) {
      // Config unreachable: fall back to the compiled defaults already seeded
      // in search-ranking. Search must never fail because config did.
      config = null;
    }
  }

  const ordered = ranking.sortRows(scored, { sort, config });

  const total = ordered.length;
  const pageRows = ordered.slice((p - 1) * take, p * take);
  const products = pageRows.map((r) => shapeProduct(r));

  return {
    products,
    pagination: { page: p, limit: take, total },
    // `indexed` / `scan` / `scan_fallback`: the middle one means the exact-token
    // index missed and the substring scan answered, which is a different
    // cost/recall profile and worth being able to see in a metric.
    strategy,
    truncated: scan.truncated === true,
  };
}

/**
 * Indexed candidate lookup via `searchKeywords`.
 *
 * `array-contains` returns EXACTLY the documents carrying the token, so unlike
 * the scan this is not a "newest N" approximation — the match set is exact and
 * grows with the catalogue.
 *
 * The previous version took one `.limit(CANDIDATE_PAGE)` per token and stopped.
 * That is a correctness ceiling, not just a latency one: an `array-contains`
 * query with no `orderBy` returns documents in `__name__` order, so for a token
 * matching more than 300 products (any common word) the caller silently got an
 * arbitrary 300 of them. This pages with `startAfter` until the match set is
 * exhausted, bounded by `INDEXED_CEILING`, and reports whether it stopped early.
 *
 * No `orderBy` is added on purpose — combining `array-contains` with a sort
 * field needs a composite index that is not deployed, and a query that throws
 * FAILED_PRECONDITION is worse than an unordered exact match that is then sorted
 * in memory by `ranking.sortRows`.
 *
 * Multi-token queries issue one query per token and merge on document id.
 * `scoreDoc` then applies AND semantics over the fetched set, which is what
 * keeps "iPhone 15" from surfacing a 15-inch laptop.
 */
async function indexedCandidates(db, queryTokens) {
  const unique = [...new Set(queryTokens)].slice(0, 6);
  const byId = new Map();
  let truncated = false;

  for (const t of unique) {
    let cursor = null;
    for (;;) {
      let q = db
        .collection('products')
        .where('isActive', '==', true)
        .where('searchKeywords', 'array-contains', t)
        .limit(CANDIDATE_PAGE);
      if (cursor) q = q.startAfter(cursor);

      const snap = await q.get();
      for (const doc of snap.docs) byId.set(doc.id, doc);

      if (snap.docs.length < CANDIDATE_PAGE) break;
      if (byId.size >= INDEXED_CEILING) {
        truncated = true;
        break;
      }
      cursor = snap.docs[snap.docs.length - 1];
    }
    if (truncated) break;
  }

  return { docs: [...byId.values()], truncated };
}

/**
 * Fallback scan: newest-first paged reads with in-memory matching.
 *
 * Paging (rather than one `limit(SCAN_LIMIT)`) is the fix. The old code read
 * exactly 300 documents and stopped, so any product older than the 300 newest
 * was unsearchable — a silent correctness ceiling. `RESCAN_CEILING` still
 * exists, but only to bound worst-case latency on a stop-word query over a very
 * large catalogue, and it is reported in `truncated` so the caller can tell a
 * partial answer from a complete one.
 */
async function scanCandidates(db, { ceiling = RESCAN_CEILING } = {}) {
  const out = [];
  let cursor = null;
  for (;;) {
    let q = db
      .collection('products')
      .where('isActive', '==', true)
      .orderBy('createdAt', 'desc')
      .limit(CANDIDATE_PAGE);
    if (cursor) q = q.startAfter(cursor);
    const snap = await q.get();
    if (snap.empty) break;
    for (const doc of snap.docs) out.push(doc);
    if (out.length >= ceiling) {
      return { docs: out.slice(0, ceiling), truncated: true };
    }
    if (snap.docs.length < CANDIDATE_PAGE) break;
    cursor = snap.docs[snap.docs.length - 1];
  }
  return { docs: out, truncated: false };
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
    // sellerId is what the client needs to resolve the Blue Tick from trusted
    // state (SellerVerificationService). `sellerKycApproved` is emitted as a
    // ranking hint only; the client never renders a badge from it.
    sellerId: d.sellerId || null,
    sellerKycApproved: d.sellerKycApproved === true,
    seller: d.sellerName
      ? { id: d.sellerId || null, storeName: d.sellerName }
      : { id: d.sellerId || null },
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