/**
 * Search Query Engine — performs global search across indexed data.
 * Supports full-text search, fuzzy matching (trigrams), autocomplete,
 * ranking, filtering, and analytics.
 */

const functions = require('firebase-functions');
const admin = require('firebase-admin');
const {
  SEARCH_INDEX,
  extractTrigrams,
  extractKeywords,
  extractPrefixes,
} = require('./indexer');

const db = admin.firestore();
const FieldValue = admin.firestore.FieldValue;

const MAX_RESULTS_PER_SOURCE = 20;
const MAX_AUTOCOMPLETE = 10;
const MAX_TRENDING = 20;

/**
 * Levenshtein distance for fuzzy matching.
 */
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

/**
 * Calculate relevance score for a search result.
 */
function relevanceScore(doc, query, queryLower) {
  let score = 0;
  const name = (doc.name || '').toLowerCase();
  const displayName = (doc.displayName || '').toLowerCase();

  if (name === queryLower) score += 100;
  else if (name.startsWith(queryLower)) score += 80;
  else if (name.includes(queryLower)) score += 60;

  if (doc.keywords && doc.keywords.includes(queryLower)) score += 40;
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

/**
 * Perform fuzzy correction on a query using trigram overlap.
 */
async function fuzzyCorrect(query) {
  const queryLower = query.toLowerCase().trim();
  if (queryLower.length < 3) return null;

  const queryTrigrams = extractTrigrams(queryLower);
  if (queryTrigrams.length === 0) return null;

  // Check products index for similar names
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

/**
 * Search a single index collection with keyword + fuzzy + prefix matching.
 */
async function searchIndex(collection, query, options = {}) {
  const queryLower = query.toLowerCase().trim();
  const { limit = MAX_RESULTS_PER_SOURCE, type } = options;
  const keywords = extractKeywords(queryLower);

  if (queryLower.length === 0) return { results: [], total: 0 };

  const results = new Map();

  // Phase 1: Prefix match on name (fast)
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
    results.set(doc.id, {
      ...data,
      id: doc.id,
      _score: relevanceScore(data, query, queryLower) + 50,
    });
  }

  // Phase 2: Keyword match via trigrams (for fuzzy)
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
        results.set(doc.id, {
          ...data,
          id: doc.id,
          _score: relevanceScore(data, query, queryLower),
        });
      }
    }
  }

  // Phase 3: Keyword array-contains-any (for partial matches)
  if (keywords.length > 0 && results.size < limit) {
    const keywordSnap = await db
      .collection(collection)
      .where('keywords', 'array-contains-any', keywords.slice(0, 10))
      .limit(limit)
      .get();

    for (const doc of keywordSnap.docs) {
      if (!results.has(doc.id)) {
        const data = doc.data();
        results.set(doc.id, {
          ...data,
          id: doc.id,
          _score: relevanceScore(data, query, queryLower),
        });
      }
    }
  }

  const sorted = Array.from(results.values())
    .sort((a, b) => b._score - a._score)
    .slice(0, limit);

  return { results: sorted, total: results.size };
}

/**
 * Global search across all indexes.
 */
async function globalSearch(data, context) {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Login required');
  }

  const {
    query,
    type = 'all',
    page = 0,
    pageSize = 20,
    filters = {},
  } = data;

  if (!query || query.trim().length === 0) {
    return { results: [], sources: {}, total: 0, correction: null };
  }

  const queryLower = query.trim();
  let correction = null;

  if (queryLower.length >= 3) {
    correction = await fuzzyCorrect(queryLower);
  }

  const sourceTypes = type === 'all'
    ? ['products', 'users', 'categories']
    : [type];

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

    const sourceResult = await searchIndex(collection, queryLower, {
      limit: MAX_RESULTS_PER_SOURCE,
      type: sourceType,
    });

    results[sourceType] = sourceResult.results;
    allResults = [...allResults, ...sourceResult.results.map(r => ({ ...r, sourceType }))];
    total += sourceResult.total;
  }

  // Apply filters
  let filtered = allResults;
  if (filters.minPrice != null) {
    filtered = filtered.filter(r => r.type === 'product' && (r.price || 0) >= filters.minPrice);
  }
  if (filters.maxPrice != null) {
    filtered = filtered.filter(r => r.type === 'product' && (r.price || 0) <= filters.maxPrice);
  }
  if (filters.category) {
    filtered = filtered.filter(r => (r.category || '').toLowerCase() === filters.category.toLowerCase());
  }
  if (filters.condition) {
    filtered = filtered.filter(r => (r.condition || '').toLowerCase() === filters.condition.toLowerCase());
  }
  if (filters.verifiedOnly) {
    filtered = filtered.filter(r => r.kycApproved);
  }
  if (filters.nearbyLat != null && filters.nearbyLng != null) {
    // Sort by distance if coordinates provided
    filtered.sort((a, b) => {
      const distA = a.latitude != null ? calculateDistance(
        filters.nearbyLat, filters.nearbyLng, a.latitude, a.longitude
      ) : Infinity;
      const distB = b.latitude != null ? calculateDistance(
        filters.nearbyLat, filters.nearbyLng, b.latitude, b.longitude
      ) : Infinity;
      return distA - distB;
    });
  }

  // Paginate combined results
  const start = page * pageSize;
  const paginated = filtered.slice(start, start + pageSize);

  // Track analytics asynchronously
  recordSearchQuery(context.auth.uid, queryLower, total, type).catch(() => {});

  return {
    results: paginated,
    sources: results,
    total,
    page,
    pageSize,
    hasMore: start + pageSize < filtered.length,
    correction,
    query: queryLower,
  };
}

/**
 * Autocomplete suggestions.
 */
async function searchAutocomplete(data, context) {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Login required');
  }

  const { query } = data;
  if (!query || query.trim().length === 0) {
    return { suggestions: [] };
  }

  const queryLower = query.trim().toLowerCase();
  const suggestions = new Map();

  // Get prefix matches from products
  const prefixEnd = queryLower + '\uf8ff';

  const [productSnap, userSnap, categorySnap] = await Promise.all([
    db.collection(SEARCH_INDEX.products)
      .where('name', '>=', queryLower)
      .where('name', '<=', prefixEnd)
      .orderBy('popularity', 'desc')
      .limit(MAX_AUTOCOMPLETE)
      .get(),
    db.collection(SEARCH_INDEX.users)
      .where('name', '>=', queryLower)
      .where('name', '<=', prefixEnd)
      .orderBy('popularity', 'desc')
      .limit(5)
      .get(),
    db.collection(SEARCH_INDEX.categories)
      .where('name', '>=', queryLower)
      .where('name', '<=', prefixEnd)
      .orderBy('popularity', 'desc')
      .limit(5)
      .get(),
  ]);

  for (const doc of productSnap.docs) {
    const d = doc.data();
    suggestions.set(d.displayName + '_product', {
      text: d.displayName,
      type: 'product',
      image: d.image || '',
      price: d.price,
      id: doc.id,
    });
  }

  for (const doc of userSnap.docs) {
    const d = doc.data();
    suggestions.set(d.displayName + '_user', {
      text: d.displayName,
      type: 'seller',
      image: d.profileImage || '',
      id: doc.id,
    });
  }

  for (const doc of categorySnap.docs) {
    const d = doc.data();
    suggestions.set(d.displayName + '_category', {
      text: d.displayName,
      type: 'category',
      image: d.image || d.icon || '',
      id: doc.id,
    });
  }

  return {
    suggestions: Array.from(suggestions.values()).slice(0, MAX_AUTOCOMPLETE),
  };
}

/**
 * Get trending searches.
 */
async function getTrendingSearches(data, context) {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Login required');
  }

  const snap = await db
    .collection(SEARCH_INDEX.trending)
    .orderBy('count', 'desc')
    .limit(MAX_TRENDING)
    .get();

  const trending = snap.docs.map(doc => ({
    text: doc.id,
    count: doc.data().count || 0,
  }));

  return { trending };
}

/**
 * Record search analytics.
 */
async function recordSearchQuery(userId, query, resultCount, type) {
  const today = new Date().toISOString().split('T')[0];

  // Increment global query counter
  await db.collection(SEARCH_INDEX.analytics).add({
    userId,
    query,
    resultCount,
    type,
    timestamp: FieldValue.serverTimestamp(),
  });

  // Update trending
  const trendingRef = db.collection(SEARCH_INDEX.trending).doc(query);
  await trendingRef.set({
    count: FieldValue.increment(1),
    lastSearched: FieldValue.serverTimestamp(),
  }, { merge: true });
}

/**
 * Record search click for ranking.
 */
async function recordSearchClick(data, context) {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Login required');
  }

  const { resultId, resultType, query } = data;
  if (!resultId || !resultType) {
    throw new functions.https.HttpsError('invalid-argument', 'resultId and resultType required');
  }

  await db.collection(SEARCH_INDEX.analytics).add({
    userId: context.auth.uid,
    type: 'click',
    resultId,
    resultType,
    query: query || '',
    timestamp: FieldValue.serverTimestamp(),
  });

  // Increment view count on the indexed document
  let ref;
  switch (resultType) {
    case 'product':
      ref = db.collection(SEARCH_INDEX.products).doc(resultId);
      break;
    case 'user':
    case 'seller':
      ref = db.collection(SEARCH_INDEX.users).doc(resultId);
      break;
  }
  if (ref) {
    await ref.update({ viewCount: FieldValue.increment(1) });
  }

  return { success: true };
}

function calculateDistance(lat1, lng1, lat2, lng2) {
  const R = 6371;
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLng = ((lng2 - lng1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos((lat1 * Math.PI) / 180) *
      Math.cos((lat2 * Math.PI) / 180) *
      Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

module.exports = {
  globalSearch,
  searchAutocomplete,
  getTrendingSearches,
  recordSearchClick,
};
