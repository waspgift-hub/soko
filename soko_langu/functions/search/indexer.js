/**
 * Search Indexer — maintains search indexes for products, users, and categories.
 * Uses trigram indexing for fuzzy matching, keyword arrays, and prefix fields.
 */

const admin = require('firebase-admin');
const functions = require('firebase-functions');

const db = admin.firestore();
const FieldValue = admin.firestore.FieldValue;

const SEARCH_INDEX = {
  products: 'search_index_products',
  users: 'search_index_users',
  categories: 'search_index_categories',
  analytics: 'search_analytics',
  trending: 'search_trending',
};

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

function extractPrefixes(text, minLen = 1, maxLen = 5) {
  const cleaned = (text || '').toLowerCase().replace(/[^a-z0-9]/g, '');
  const prefixes = new Set();
  for (let i = minLen; i <= Math.min(maxLen, cleaned.length); i++) {
    prefixes.add(cleaned.substring(0, i));
  }
  return Array.from(prefixes);
}

function computePopularityScore(product) {
  let score = 0;
  score += (product.soldCount || 0) * 10;
  score += (product.viewCount || 0);
  score += (product.rating || 0) * 5;
  score += (product.reviewCount || 0) * 3;
  if (product.isBoosted) score += 50;
  if (product.isActive) score += 20;
  if (product.kycApproved) score += 30;
  return score;
}

/**
 * Index a product for search.
 */
async function indexProduct(productId, productData) {
  const text = [
    productData.name,
    productData.description,
    productData.brand,
    productData.category,
    productData.subcategory,
    productData.sellerName,
    productData.location,
    ...(productData.tags || []),
  ].filter(Boolean).join(' ');

  const indexDoc = {
    type: 'product',
    id: productId,
    name: (productData.name || '').toLowerCase(),
    displayName: productData.name || '',
    description: (productData.description || '').substring(0, 200),
    price: productData.price || 0,
    currency: productData.currency || 'TZS',
    image: Array.isArray(productData.images) && productData.images.length > 0
      ? productData.images[0] : '',
    sellerId: productData.sellerId || '',
    sellerName: productData.sellerName || '',
    category: productData.category || '',
    subcategory: productData.subcategory || '',
    brand: productData.brand || '',
    condition: productData.condition || '',
    location: productData.location || '',
    rating: productData.rating || 0,
    reviewCount: productData.reviewCount || productData.reviewCount || 0,
    soldCount: productData.soldCount || 0,
    viewCount: productData.viewCount || 0,
    stock: productData.stock || 0,
    isActive: productData.isActive ?? true,
    isBoosted: productData.isBoosted ?? false,
    isWholesale: productData.isWholesale ?? false,
    kycApproved: productData.kycApproved ?? false,
    discount: productData.discount || 0,
    flashSalePrice: productData.flashSalePrice || null,
    keywords: extractKeywords(text),
    trigrams: extractTrigrams(text),
    prefixes: extractPrefixes(productData.name || ''),
    popularity: computePopularityScore(productData),
    tags: productData.tags || [],
    createdAt: productData.createdAt || FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };

  // Store seller name as searchable keywords as well
  if (productData.sellerName) {
    const sellerKeywords = extractKeywords(productData.sellerName);
    indexDoc.keywords = [...new Set([...indexDoc.keywords, ...sellerKeywords])];
  }

  await db.collection(SEARCH_INDEX.products).doc(productId).set(indexDoc);
  return indexDoc;
}

/**
 * Index a user/seller for search.
 */
async function indexUser(uid, userData) {
  const text = [
    userData.displayName,
    userData.username,
    userData.bio,
    userData.location,
    userData.shopName,
    userData.businessName,
  ].filter(Boolean).join(' ');

  const indexDoc = {
    type: 'user',
    id: uid,
    name: (userData.displayName || userData.username || '').toLowerCase(),
    displayName: userData.displayName || userData.username || '',
    username: userData.username || '',
    bio: (userData.bio || '').substring(0, 200),
    location: userData.location || '',
    latitude: userData.latitude || null,
    longitude: userData.longitude || null,
    profileImage: userData.profileImage || '',
    shopName: userData.shopName || '',
    businessName: userData.businessName || '',
    kycApproved: userData.kycApproved ?? false,
    isPremium: userData.isPremium ?? false,
    productCount: userData.productCount || 0,
    rating: userData.rating || 0,
    reviewCount: userData.reviewCount || 0,
    keywords: extractKeywords(text),
    trigrams: extractTrigrams(text),
    prefixes: extractPrefixes(userData.displayName || userData.username || ''),
    popularity: (userData.rating || 0) * 10 + (userData.productCount || 0) * 5 + (userData.reviewCount || 0) * 2,
    createdAt: userData.createdAt || FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };

  await db.collection(SEARCH_INDEX.users).doc(uid).set(indexDoc);
  return indexDoc;
}

/**
 * Index a category for search.
 */
async function indexCategory(categoryId, categoryData) {
  const text = [categoryData.name, categoryData.description, categoryData.parentName]
    .filter(Boolean).join(' ');

  const indexDoc = {
    type: 'category',
    id: categoryId,
    name: (categoryData.name || '').toLowerCase(),
    displayName: categoryData.name || '',
    description: (categoryData.description || '').substring(0, 200),
    parentId: categoryData.parentId || '',
    parentName: categoryData.parentName || '',
    icon: categoryData.icon || '',
    image: categoryData.image || '',
    productCount: categoryData.productCount || 0,
    keywords: extractKeywords(text),
    trigrams: extractTrigrams(text),
    prefixes: extractPrefixes(categoryData.name || ''),
    popularity: categoryData.productCount || 0,
    updatedAt: FieldValue.serverTimestamp(),
  };

  await db.collection(SEARCH_INDEX.categories).doc(categoryId).set(indexDoc);
  return indexDoc;
}

/**
 * Delete a product from search index.
 */
async function deleteProductIndex(productId) {
  await db.collection(SEARCH_INDEX.products).doc(productId).delete();
}

/**
 * Delete a user from search index.
 */
async function deleteUserIndex(uid) {
  await db.collection(SEARCH_INDEX.users).doc(uid).delete();
}

// ─── FIRESTORE TRIGGERS ───

exports.onProductCreated = functions.firestore
  .document('products/{productId}')
  .onCreate(async (snap) => {
    await indexProduct(snap.id, snap.data());
  });

exports.onProductUpdated = functions.firestore
  .document('products/{productId}')
  .onUpdate(async (change) => {
    await indexProduct(change.after.id, change.after.data());
  });

exports.onProductDeleted = functions.firestore
  .document('products/{productId}')
  .onDelete(async (snap) => {
    await deleteProductIndex(snap.id);
  });

exports.onUserCreated = functions.firestore
  .document('users/{userId}')
  .onCreate(async (snap) => {
    await indexUser(snap.id, snap.data());
  });

exports.onUserUpdated = functions.firestore
  .document('users/{userId}')
  .onUpdate(async (change) => {
    await indexUser(change.after.id, change.after.data());
  });

exports.onUserDeleted = functions.firestore
  .document('users/{userId}')
  .onDelete(async (snap) => {
    await deleteUserIndex(snap.id);
  });

module.exports = {
  indexProduct,
  indexUser,
  indexCategory,
  deleteProductIndex,
  deleteUserIndex,
  extractKeywords,
  extractTrigrams,
  extractPrefixes,
  computePopularityScore,
  SEARCH_INDEX,
};
