'use strict';

const fs = require('fs');
const path = require('path');
const { SITE } = require('./meta');

const LANDING_DIR = path.join(__dirname, '..', '..', 'landing');

// Public, indexable landing pages. Every path below exists and returns 200.
// Rules enforced here:
//   - canonical host only (https://www.sokovibe.co.tz)
//   - public 200 pages only: no /api, /admin, /health, login, checkout,
//     product deep links, deleted pages or 404s
//   - the old /shop web-shop SPA is retired (redirects to /), so it is
//     intentionally absent here
const SITEMAP_PATHS = [
  '/',
  '/about',
  '/about/founder',
  '/how-it-works',
  '/features',
  '/buyers',
  '/sellers',
  '/pricing',
  '/faq',
  '/contact',
  '/privacy',
  '/terms',
  '/cookies',
  '/data-deletion',
];

// Route -> source document, so <lastmod> reflects when the page actually
// changed. A hardcoded date would go stale and teach crawlers to ignore it.
const PAGE_FILES = {
  '/': 'index.html',
  '/about': 'about.html',
  '/about/founder': 'about-founder.html',
  '/how-it-works': 'how-it-works.html',
  '/features': 'features.html',
  '/buyers': 'buyers.html',
  '/sellers': 'sellers.html',
  '/pricing': 'pricing.html',
  '/faq': 'faq.html',
  '/contact': 'contact.html',
  '/privacy': 'privacy.html',
  '/terms': 'terms.html',
  '/cookies': 'cookies.html',
  '/data-deletion': 'data-deletion.html',
};

function lastmodFor(p) {
  const file = PAGE_FILES[p];
  if (!file) return '';
  try {
    const mtime = fs.statSync(path.join(LANDING_DIR, file)).mtime;
    return `<lastmod>${mtime.toISOString().slice(0, 10)}</lastmod>`;
  } catch (_) {
    return '';
  }
}

function sitemapXml(paths) {
  const body = paths
    .map((p) => `<url><loc>${SITE.canonicalHost}${p === '/' ? '/' : p}</loc>${lastmodFor(p)}</url>`)
    .join('');
  return `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${body}\n</urlset>`;
}

function buildSitemapXml() {
  return sitemapXml(SITEMAP_PATHS);
}

function buildProductSitemapXml(productIds) {
  const paths = (productIds || [])
    .filter((id) => typeof id === 'string' && id && !id.includes('<'))
    .slice(0, 500)
    .map((id) => `/product/${encodeURIComponent(id)}`);
  return sitemapXml(paths);
}

module.exports = { buildSitemapXml, buildProductSitemapXml, SITEMAP_PATHS };
