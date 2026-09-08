'use strict';

const { getFirebaseFirestore } = require('../config/firebase');
const { SITE } = require('./meta');

const SITEMAP_TTL_MS = 6 * 60 * 60 * 1000;
const PRODUCTS_PER_FILE = 500;
const MAX_FILES = 50;

let cache = { ts: 0, files: [] };

function url(pathname) {
  return `${SITE.canonicalHost}${pathname}`;
}

function sitemapXml(urls) {
  const body = urls.map((u) => `<url><loc>${u}</loc></url>`).join('');
  return `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${body}\n</urlset>`;
}

async function collectSitemaps() {
  const db = getFirebaseFirestore();
  const files = [];
  const staticUrls = [
    '/',
    '/search',
    '/category',
    '/discovery',
    '/flash-sale',
    '/help',
    '/about',
    '/privacy-policy',
    '/terms-of-service',
  ].map(url);
  files.push({ name: 'home.xml', urls: staticUrls, xml: sitemapXml(staticUrls) });

  if (!db) return files;

  // Products: the same visibility rule the app feed uses (isActive == true).
  try {
    let cursor = null;
    let page = 1;
    for (;;) {
      let query = db
        .collection('products')
        .where('isActive', '==', true)
        .limit(PRODUCTS_PER_FILE);
      if (cursor) query = query.startAfter(cursor);
      const snap = await query.get();
      if (!snap.size) break;
      const urls = snap.docs.map((doc) => url(`/product/${doc.id}`));
      files.push({ name: `products-${page}.xml`, urls, xml: sitemapXml(urls) });
      cursor = snap.docs[snap.docs.length - 1];
      page += 1;
      if (snap.size < PRODUCTS_PER_FILE || page > MAX_FILES) break;
    }
  } catch (error) {
    console.error('[SEO] products sitemap failed:', error.message);
  }

  // Categories: display name is what the app routes on (/category-products/:name).
  try {
    const cats = await db.collection('categories').where('isActive', '==', true).get();
    const urls = cats.docs
      .map((doc) => {
        const name = (doc.data().name || '').trim();
        return name ? url(`/category-products/${encodeURIComponent(name)}`) : null;
      })
      .filter(Boolean);
    if (urls.length) files.push({ name: 'categories.xml', urls, xml: sitemapXml(urls) });
  } catch (error) {
    console.error('[SEO] categories sitemap failed:', error.message);
  }

  // Seller storefronts: users with an approved KYC and a public username.
  try {
    const users = await db.collection('users').where('kyc.approved', '==', true).get();
    const urls = users.docs
      .filter((doc) => (doc.data().username || '').trim())
      .map((doc) => url(`/public-profile/${doc.id}`));
    if (urls.length) files.push({ name: 'sellers.xml', urls, xml: sitemapXml(urls) });
  } catch (error) {
    // May require a composite index in Firestore (kyc.approved is a map field).
    console.warn('[SEO] sellers sitemap skipped:', error.message);
  }

  return files;
}

async function getSitemaps() {
  const now = Date.now();
  if (now - cache.ts > SITEMAP_TTL_MS) {
    cache = { ts: now, files: await collectSitemaps() };
  }
  return cache.files;
}

async function sitemapIndexXml() {
  const files = await getSitemaps();
  const body = files
    .map((f) => `<sitemap><loc>${SITE.canonicalHost}/sitemaps/${f.name}</loc></sitemap>`)
    .join('');
  return `<?xml version="1.0" encoding="UTF-8"?>\n<sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${body}\n</sitemapindex>`;
}

async function getSitemapFile(name) {
  const files = await getSitemaps();
  const found = files.find((f) => f.name === name);
  return found ? found.xml : null;
}

module.exports = {
  sitemapIndexXml,
  getSitemaps,
  getSitemapFile,
};