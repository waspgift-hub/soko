'use strict';

const { SITE } = require('./meta');

// Public, indexable landing pages. Every path below exists and returns 200.
// Rules enforced here:
//   - canonical host only (https://www.sokovibe.co.tz)
//   - public 200 pages only: no /api, /admin, /health, login, checkout,
//     product deep links, deleted pages or 404s
//   - the /shop catalog is client-rendered (Firestore on load), so product
//     deep links are indexed by rendering engines but not listed here; the
//     sitemap carries the shop entry page only
const SITEMAP_PATHS = [
  '/',
  '/shop/',
  '/tanzania-marketplace',
  '/categories',
  '/how-soko-vibe-works',
  '/soko-vibe-fees',
  '/soko-vibe-escrow',
  '/about',
  '/about/founder',
  '/privacy-policy',
  '/terms-of-service',
  '/support',
];

function sitemapXml(paths) {
  const body = paths.map((p) => `<url><loc>${SITE.canonicalHost}${p === '/' ? '/' : p}</loc></url>`).join('');
  return `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${body}\n</urlset>`;
}

function buildSitemapXml() {
  return sitemapXml(SITEMAP_PATHS);
}

module.exports = { buildSitemapXml, SITEMAP_PATHS };