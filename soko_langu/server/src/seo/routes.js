'use strict';

const express = require('express');
const { SITE } = require('./meta');
const { buildSitemapXml } = require('./sitemaps');

const router = express.Router();

const ROBOTS_TXT = `User-agent: *
Allow: /

Disallow: /api/
Disallow: /admin/
Disallow: /marketing/

Sitemap: ${SITE.canonicalHost}/sitemap.xml
`;

router.get('/robots.txt', (req, res) => {
  res.type('text/plain').setHeader('Cache-Control', 'public, max-age=3600').send(ROBOTS_TXT);
});

const SITEMAP_XML = buildSitemapXml();

router.get('/sitemap.xml', (req, res) => {
  res
    .type('application/xml')
    .setHeader('Cache-Control', 'public, max-age=1800')
    .send(SITEMAP_XML);
});

// Legacy sitemap-file route kept so old crawler caches pointing at
// /sitemaps/home.xml keep resolving to the static landing sitemap.
router.get('/sitemaps/:file', (req, res) => {
  if (req.params.file !== 'home.xml') {
    return res.status(404).type('text/plain').send('Not found');
  }
  res.type('application/xml').setHeader('Cache-Control', 'public, max-age=1800').send(SITEMAP_XML);
});

const NOT_FOUND_HTML = (() => {
  const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const home = esc(`${SITE.canonicalHost}/`);
  return `<!DOCTYPE html>
<html lang="sw">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Ukurasa Haupo | ${esc(SITE.name)}</title>
<meta name="robots" content="noindex, nofollow">
<link rel="canonical" href="${home}">
<link rel="icon" type="image/png" sizes="32x32" href="/assets/favicon-32.png">
<style>
  body{margin:0;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,"Helvetica Neue",Arial,sans-serif;background:#000;color:#fff;min-height:100vh;display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center;padding:24px;-webkit-font-smoothing:antialiased}
  h1{font-size:2.4rem;letter-spacing:-.02em;margin:0 0 8px}
  p{color:#9b9b9b;margin:0 0 28px}
  a{color:#fff;border:1px solid #fff;padding:12px 28px;border-radius:10px;text-decoration:none;font-weight:600}
  a:hover{background:#fff;color:#000}
</style></head>
<body>
  <h1>404</h1>
  <p>Ukurasa huu haupo — the page you are looking for was not found.</p>
  <a href="${home}">Rudi kwenye ${esc(SITE.name)}</a>
</body></html>`;
})();

module.exports = { seoRouter: router, NOT_FOUND_HTML };