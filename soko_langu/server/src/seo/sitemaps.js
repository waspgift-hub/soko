'use strict';

const { SITE } = require('./meta');

// The web app is no longer served; only the public landing pages are
// indexed. Product pages live in the native apps only, so no /product/*
// or per-category URLs are listed here — every path below exists and
// returns 200.
const SITEMAP_PATHS = [
  '/',
  '/tanzania-marketplace',
  '/categories',
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