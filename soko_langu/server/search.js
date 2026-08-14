const express = require('express');
const admin = require('firebase-admin');
const cache = require('./cache');

const router = express.Router();
const db = admin.firestore();
const FieldValue = admin.firestore.FieldValue;

const SEARCH_INDEX = {
  products: 'search_index_products',
  users: 'search_index_users',
  categories: 'search_index_categories',
  analytics: 'search_analytics',
  trending: 'search_trending',
};

const MAX_RESULTS_PER_SOURCE = 20;
const MAX_AUTOCOMPLETE = 10;
const MAX_TRENDING = 20;

function extractTrigrams(text) {
  const cleaned = (text || '').toLowerCase().replace(/[^a-z0-9\u0000-\u007F]/g, '');
  if (cleaned.length < 3) return [];
  const trigrams = new Set();
  for (let i = 0; i <= cleaned.length - 3; i++) {
    trigrams.add(cleaned.substring(i, i + 3));
  }
  return Array.from(trigrams);
}

function extractKeywords(text) {
  const cleaned = (text || '').toLowerCase().replace(/[^a-z0-9\s]/g, '');
  const words = cleaned.split(/\s+/).filter(w => w.length >= 2);
  return Array.from(new Set(words));
}

function calculateDistance(lat1, lng1, lat2, lng2) {
  const R = 6371;
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLng = ((lng2 - lng1) * Math.PI) / 180;
  const a = Math.sin(dLat / 2) ** 2 +
    Math.cos((lat1 * Math.PI) / 180) * Math.cos((lat2 * Math.PI) / 180) * Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function levenshtein(a, b) {
  const m = a.length, n = b.length;
  const dp = Array.from({ length: m + 1 }, () => Array(n + 1).fill(0));
  for (let i = 0; i <= m; i++) dp[i][0] = i;
  for (let j = 0; j <= n; j++) dp[0][j] = j;
  for (let i = 1; i <= m; i++) {
    for (let j = 1; j <= n; j++) {
      dp[i][j] = a[i - 1] === b[j - 1]
        ? dp[i - 1][j - 1]
        : 1 + Math.min(dp[i - 1][j], dp[i][j - 1], dp[i - 1][j - 1]);
    }
  }
  return dp[m][n];
}

function relevanceScore(doc, query, queryLower) {
  let score = 0;
  const name = (doc.name || '').toLowerCase();
  const description = (doc.description || '').toLowerCase();

  if (name === queryLower) score += 100;
  else if (name.startsWith(queryLower)) score += 80;
  else if (name.includes(queryLower)) score += 60;
  // Match against description too so results like "best gaming pc" can find
  // products whose description mentions the term without the title matching.
  if (description.includes(queryLower)) score += 50;

  // keywords is a per-word array, so match when ANY query keyword appears in it
  // (the old `includes(queryLower)` never hit for multi-word queries).
  if (doc.keywords && Array.isArray(doc.keywords)) {
    const queryWords = extractKeywords(queryLower);
    const hitCount = queryWords.filter((w) => doc.keywords.includes(w)).length;
    if (hitCount > 0) score += 40 + hitCount * 5;
  }
  if (doc.trigrams) {
    const queryTrigrams = extractTrigrams(query);
    const matchCount = queryTrigrams.filter(t => doc.trigrams.includes(t)).length;
    score += (matchCount / Math.max(queryTrigrams.length, 1)) * 30;
  }
  score += (doc.popularity || 0) * 0.1;
  if (doc.isBoosted) score += 50;
  if (doc.isActive === false) score -= 100;
  if (doc.kycApproved) score += 20;
  if (doc.type === 'product' && doc.stock <= 0) score -= 50;
  return Math.max(score, 0);
}

async function fuzzyCorrect(query) {
  const queryLower = query.toLowerCase().trim();
  if (queryLower.length < 3) return null;
  const queryTrigrams = extractTrigrams(queryLower);
  if (queryTrigrams.length === 0) return null;
  const productsSnap = await db
    .collection(SEARCH_INDEX.products)
    .where('trigrams', 'array-contains-any', queryTrigrams.slice(0, 10))
    .limit(20)
    .get();
  const corrections = [];
  for (const doc of productsSnap.docs) {
    const data = doc.data();
    const dist = levenshtein(queryLower, data.name || '');
    if (dist > 0 && dist <= Math.floor(queryLower.length / 3) + 1) {
      corrections.push({ word: data.displayName || data.name, distance: dist });
    }
  }
  corrections.sort((a, b) => a.distance - b.distance);
  return corrections.length > 0 ? corrections[0].word : null;
}

async function searchIndex(collection, query, options = {}) {
  const queryLower = query.toLowerCase().trim();
  const { limit = MAX_RESULTS_PER_SOURCE } = options;
  const keywords = extractKeywords(queryLower);
  if (queryLower.length === 0) return { results: [], total: 0 };
  const results = new Map();
  const prefixEnd = queryLower + '\uf8ff';
  const prefixSnap = await db
    .collection(collection)
    .where('name', '>=', queryLower)
    .where('name', '<=', prefixEnd)
    .orderBy('name')
    .limit(limit)
    .get();
  for (const doc of prefixSnap.docs) {
    const data = doc.data();
    results.set(doc.id, { ...data, id: doc.id, _score: relevanceScore(data, query, queryLower) + 50 });
  }
  const queryTrigrams = extractTrigrams(queryLower);
  if (queryTrigrams.length > 0 && results.size < limit * 2) {
    const trigramSnap = await db
      .collection(collection)
      .where('trigrams', 'array-contains-any', queryTrigrams.slice(0, 10))
      .limit(limit * 2)
      .get();
    for (const doc of trigramSnap.docs) {
      if (!results.has(doc.id)) {
        const data = doc.data();
        results.set(doc.id, { ...data, id: doc.id, _score: relevanceScore(data, query, queryLower) });
      }
    }
  }
  if (keywords.length > 0 && results.size < limit) {
    const keywordSnap = await db
      .collection(collection)
      .where('keywords', 'array-contains-any', keywords.slice(0, 10))
      .limit(limit)
      .get();
    for (const doc of keywordSnap.docs) {
      if (!results.has(doc.id)) {
        const data = doc.data();
        results.set(doc.id, { ...data, id: doc.id, _score: relevanceScore(data, query, queryLower) });
      }
    }
  }
  if (results.size === 0) {
    await fallbackSearchDirect(results, collection, queryLower, limit);
  }
  const sorted = Array.from(results.values())
    .sort((a, b) => b._score - a._score)
    .slice(0, limit);
  return { results: sorted, total: results.size };
}

async function fallbackSearchDirect(results, indexCollection, queryLower, limit) {
  const prefixEnd = queryLower + '\uf8ff';
  const sourceMap = {
    'search_index_products': { coll: 'products', type: 'product', nameField: 'name', extraFields: ['description', 'price', 'images', 'category', 'sellerName', 'sellerId', 'stock', 'rating', 'reviewCount', 'isActive', 'condition', 'sellerKycApproved'] },
    'search_index_users': { coll: 'users', type: 'seller', nameField: 'displayName', extraFields: ['username', 'bio', 'profileImage', 'location', 'latitude', 'longitude'] },
    'search_index_categories': { coll: 'categories', type: 'category', nameField: 'name', extraFields: ['nameSw', 'icon', 'image'] },
  };
  const source = sourceMap[indexCollection];
  if (!source) return;

  // First try case-insensitive searchKeywords array (products only)
  if (source.type === 'product') {
    const keywords = extractKeywords(queryLower);
    if (keywords.length > 0) {
      const keywordSnap = await db.collection(source.coll)
        .where('searchKeywords', 'array-contains-any', keywords.slice(0, 10))
        .where('isActive', '==', true)
        .limit(limit)
        .get();
      for (const doc of keywordSnap.docs) {
        const d = doc.data();
        const name = d[source.nameField] || '';
        const mapped = {
          id: doc.id, name, displayName: name, type: source.type,
          ...source.extraFields.reduce((acc, f) => { acc[f] = d[f]; return acc; }, {}),
          isBoosted: d.isBoosted === true || d.boostTier != null,
          kycApproved: d.kycApproved === true || d.sellerKycApproved === true,
          popularity: d.popularity || d.viewCount || 0,
          stock: d.stock ?? 0,
        };
        if (d.images && d.images.length > 0) mapped.image = d.images[0];
        mapped._score = relevanceScore(mapped, queryLower, queryLower) + 30;
        results.set(doc.id, mapped);
      }
      if (results.size >= limit) return;
    }
  }

  // Fallback: prefix match on name field
  const snap = await db.collection(source.coll)
    .where(source.nameField, '>=', queryLower)
    .where(source.nameField, '<=', prefixEnd)
    .limit(limit)
    .get();
  for (const doc of snap.docs) {
    if (results.has(doc.id)) continue;
    const d = doc.data();
    const name = d[source.nameField] || '';
    if (name.toLowerCase().includes(queryLower)) {
      const mapped = {
        id: doc.id, name, displayName: name, type: source.type,
        ...source.extraFields.reduce((acc, f) => { acc[f] = d[f]; return acc; }, {}),
        isBoosted: d.isBoosted === true || d.boostTier != null,
        kycApproved: d.kycApproved === true || d.sellerKycApproved === true,
        popularity: d.popularity || d.viewCount || 0,
        stock: d.stock ?? 0,
      };
      if (source.type === 'product' && d.images && d.images.length > 0) mapped.image = d.images[0];
      if (source.type === 'seller') mapped.profileImage = d.profileImage || d.photoURL || '';
      mapped._score = relevanceScore(mapped, queryLower, queryLower);
      results.set(doc.id, mapped);
    }
  }
}

async function authenticate(req) {
  const authHeader = req.headers.authorization || req.headers['Authorization'] || '';
  if (!authHeader.startsWith('Bearer ')) return null;
  try {
    return await admin.auth().verifyIdToken(authHeader.slice(7));
  } catch { return null; }
}

// ════════════════════════════════════════════════════════════
// GLOBAL SEARCH
// ════════════════════════════════════════════════════════════
router.post('/global-search', async (req, res) => {
  try {
    const decoded = await authenticate(req);
    if (!decoded) return res.status(401).json({ error: 'Unauthorized' });
    const { query, type = 'all', page = 0, pageSize = 20, filters = {} } = req.body;
    if (!query || query.trim().length === 0) {
      return res.json({ results: [], sources: {}, total: 0, correction: null, query: '' });
    }
    const queryLower = query.trim();
    let correction = null;
    if (queryLower.length >= 3) correction = await fuzzyCorrect(queryLower);
    const sourceTypes = type === 'all' ? ['products', 'users', 'categories'] : [type];
    const results = {};
    let allResults = [];
    let total = 0;
    for (const sourceType of sourceTypes) {
      let collection;
      switch (sourceType) {
        case 'products': collection = SEARCH_INDEX.products; break;
        case 'users': collection = SEARCH_INDEX.users; break;
        case 'categories': collection = SEARCH_INDEX.categories; break;
        default: continue;
      }
      const sourceResult = await searchIndex(collection, queryLower, { limit: MAX_RESULTS_PER_SOURCE });
      results[sourceType] = sourceResult.results;
      allResults = [...allResults, ...sourceResult.results.map(r => ({ ...r, sourceType }))];
      total += sourceResult.total;
    }
    let filtered = allResults;
    if (filters.minPrice != null) filtered = filtered.filter(r => r.type === 'product' && (r.price || 0) >= filters.minPrice);
    if (filters.maxPrice != null) filtered = filtered.filter(r => r.type === 'product' && (r.price || 0) <= filters.maxPrice);
    if (filters.category) filtered = filtered.filter(r => (r.category || '').toLowerCase() === filters.category.toLowerCase());
    if (filters.condition) filtered = filtered.filter(r => (r.condition || '').toLowerCase() === filters.condition.toLowerCase());
    if (filters.verifiedOnly) filtered = filtered.filter(r => r.kycApproved);
    if (filters.nearbyLat != null && filters.nearbyLng != null) {
      filtered.sort((a, b) => {
        const distA = a.latitude != null ? calculateDistance(filters.nearbyLat, filters.nearbyLng, a.latitude, a.longitude) : Infinity;
        const distB = b.latitude != null ? calculateDistance(filters.nearbyLat, filters.nearbyLng, b.latitude, b.longitude) : Infinity;
        return distA - distB;
      });
    }
    const start = page * pageSize;
    const paginated = filtered.slice(start, start + pageSize);
    // Record analytics asynchronously
    recordSearchQuery(decoded.uid, queryLower, total, type).catch(() => {});
    res.json({
      results: paginated, sources: results, total, page, pageSize,
      hasMore: start + pageSize < filtered.length, correction, query: queryLower,
    });
  } catch (e) {
    console.error('[SEARCH] global-search error:', e.message);
    res.status(400).json({ error: e.message });
  }
});

// ════════════════════════════════════════════════════════════
// AUTOCOMPLETE
// ════════════════════════════════════════════════════════════
router.post('/autocomplete', async (req, res) => {
  try {
    const decoded = await authenticate(req);
    if (!decoded) return res.status(401).json({ error: 'Unauthorized' });
    const { query } = req.body;
    if (!query || query.trim().length === 0) return res.json({ suggestions: [] });
    const queryLower = query.trim().toLowerCase();

    // Keystroke-by-keystroke calls hammer the index — 90s TTL on a per-query key.
    const cacheKey = `autocomplete:${queryLower}`;
    const cached = cache.get(cacheKey);
    if (cached) return res.json(cached);

    const prefixEnd = queryLower + '\uf8ff';
    const matchMap = new Map();
    const [productSnap, userSnap, categorySnap] = await Promise.all([
      db.collection(SEARCH_INDEX.products).where('name', '>=', queryLower).where('name', '<=', prefixEnd).orderBy('popularity', 'desc').limit(MAX_AUTOCOMPLETE).get(),
      db.collection(SEARCH_INDEX.users).where('name', '>=', queryLower).where('name', '<=', prefixEnd).orderBy('popularity', 'desc').limit(5).get(),
      db.collection(SEARCH_INDEX.categories).where('name', '>=', queryLower).where('name', '<=', prefixEnd).orderBy('popularity', 'desc').limit(5).get(),
    ]);
    for (const doc of productSnap.docs) {
      const d = doc.data();
      matchMap.set(d.displayName + '_product', { text: d.displayName, type: 'product', image: d.image || '', price: d.price, id: doc.id });
    }
    for (const doc of userSnap.docs) {
      const d = doc.data();
      matchMap.set(d.displayName + '_user', { text: d.displayName, type: 'seller', image: d.profileImage || '', id: doc.id });
    }
    for (const doc of categorySnap.docs) {
      const d = doc.data();
      matchMap.set(d.displayName + '_category', { text: d.displayName, type: 'category', image: d.image || d.icon || '', id: doc.id });
    }
    const suggestions = Array.from(matchMap.values()).slice(0, MAX_AUTOCOMPLETE);
    cache.set(cacheKey, { suggestions }, 90 * 1000);
    res.json({ suggestions });
  } catch (e) {
    console.error('[SEARCH] autocomplete error:', e.message);
    res.status(400).json({ error: e.message });
  }
});

// ════════════════════════════════════════════════════════════
// TRENDING SEARCHES
// ════════════════════════════════════════════════════════════
router.post('/trending', async (req, res) => {
  try {
    const CACHE_KEY = 'trending:all';
    const cached = cache.get(CACHE_KEY);
    if (cached) return res.json(cached);
    const snap = await db.collection(SEARCH_INDEX.trending).orderBy('count', 'desc').limit(MAX_TRENDING).get();
    const trending = snap.docs.map(doc => ({ text: doc.id, count: doc.data().count || 0 }));
    const payload = { trending };
    cache.set(CACHE_KEY, payload, 5 * 60 * 1000);
    res.json(payload);
  } catch (e) {
    console.error('[SEARCH] trending error:', e.message);
    res.status(400).json({ error: e.message });
  }
});

// ════════════════════════════════════════════════════════════
// RECORD CLICK
// ════════════════════════════════════════════════════════════
router.post('/record-click', async (req, res) => {
  try {
    const decoded = await authenticate(req);
    if (!decoded) return res.status(401).json({ error: 'Unauthorized' });
    const { resultId, resultType, query } = req.body;
    if (!resultId || !resultType) return res.status(400).json({ error: 'resultId and resultType required' });
    await db.collection(SEARCH_INDEX.analytics).add({
      userId: decoded.uid, type: 'click', resultId, resultType, query: query || '',
      timestamp: FieldValue.serverTimestamp(),
    });
    let ref;
    switch (resultType) {
      case 'product': ref = db.collection(SEARCH_INDEX.products).doc(resultId); break;
      case 'user': case 'seller': ref = db.collection(SEARCH_INDEX.users).doc(resultId); break;
    }
    if (ref) await ref.update({ viewCount: FieldValue.increment(1) });
    res.json({ success: true });
  } catch (e) {
    console.error('[SEARCH] record-click error:', e.message);
    res.status(400).json({ error: e.message });
  }
});

// ════════════════════════════════════════════════════════════
// MOST RATED — top-rated products & sellers for the initial view
// (open to guests; auth optional)
// ════════════════════════════════════════════════════════════
router.post('/most-rated', async (req, res) => {
  try {
    const limit = Math.min(Number(req.body.limit) || 10, 20);

    // Reads the whole `reviews` collection + per-seller user docs per request —
    // the single biggest read on the Spark free tier. Cache for 10 minutes.
    const cacheKey = `most-rated:${limit}`;
    const cached = cache.get(cacheKey);
    if (cached) return res.json(cached);

    // Top rated products — real reviewCount, active listings only
    const productsSnap = await db.collection('products')
      .where('isActive', '==', true)
      .orderBy('reviewCount', 'desc')
      .limit(limit * 2)
      .get();
    const products = [];
    for (const doc of productsSnap.docs) {
      const d = doc.data();
      if ((d.reviewCount || 0) <= 0) continue;
      const imgs = d.images || [];
      const boostedUntil = d.boostedUntil;
      const boosted = !!(d.isBoosted && boostedUntil &&
        new Date(boostedUntil.seconds ? boostedUntil.seconds * 1000 : boostedUntil) > new Date());
      products.push({
        id: doc.id,
        type: 'product',
        displayName: d.name || '',
        description: d.description || '',
        price: d.price || 0,
        image: imgs.length ? imgs[0] : null,
        sellerName: d.sellerName || '',
        category: d.category || '',
        rating: d.rating || 0,
        reviewCount: d.reviewCount || 0,
        location: d.location || '',
        isBoosted: boosted,
        kycApproved: !!d.sellerKycApproved,
      });
      if (products.length >= limit) break;
    }

    // Top rated sellers — aggregate real reviews by sellerId
    const reviewsSnap = await db.collection('reviews').get();
    const bySeller = {};
    for (const doc of reviewsSnap.docs) {
      const r = doc.data();
      if (!r.sellerId || r.sellerId.startsWith('seller_')) continue;
      if (!bySeller[r.sellerId]) bySeller[r.sellerId] = { total: 0, count: 0 };
      bySeller[r.sellerId].total += Number(r.rating) || 0;
      bySeller[r.sellerId].count += 1;
    }
    const ranked = Object.entries(bySeller)
      .map(([sellerId, s]) => ({ sellerId, avg: s.total / s.count, count: s.count }))
      .filter((r) => r.count > 0)
      .sort((a, b) => b.avg - a.avg || b.count - a.count)
      .slice(0, 8);

    const sellers = [];
    for (const r of ranked) {
      const userDoc = await db.collection('users').doc(r.sellerId).get();
      if (!userDoc.exists) continue;
      const u = userDoc.data();
      if (u.isSuspended) continue;
      sellers.push({
        id: r.sellerId,
        type: 'seller',
        displayName: u.displayName || u.name || '',
        image: u.photoURL || u.photoUrl || null,
        rating: r.avg,
        reviewCount: r.count,
        kycApproved: !!u.isKycApproved,
        location: u.location || '',
      });
    }

    const payload = { success: true, products, sellers };
    cache.set(cacheKey, payload, 10 * 60 * 1000);
    res.json(payload);
  } catch (e) {
    console.error('[SEARCH] most-rated error:', e.message);
    res.status(400).json({ error: e.message });
  }
});

// ════════════════════════════════════════════════════════════
// HELPERS
// ════════════════════════════════════════════════════════════
async function recordSearchQuery(userId, query, resultCount, type) {
  await db.collection(SEARCH_INDEX.analytics).add({ userId, query, resultCount, type, timestamp: FieldValue.serverTimestamp() });
  const trendingRef = db.collection(SEARCH_INDEX.trending).doc(query);
  await trendingRef.set({ count: FieldValue.increment(1), lastSearched: FieldValue.serverTimestamp() }, { merge: true });
}

module.exports = { router };
