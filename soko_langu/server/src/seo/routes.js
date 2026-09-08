'use strict';

const fs = require('fs');
const path = require('path');
const express = require('express');
const { buildMeta, injectMeta, SITE } = require('./meta');
const { sitemapIndexXml, getSitemapFile } = require('./sitemaps');

const router = express.Router();

const ROBOTS_TXT = `User-agent: *
Allow: /

Disallow: /api/
Disallow: /marketing/
Disallow: /admin/
Disallow: /login
Disallow: /register
Disallow: /forgot-password
Disallow: /verify-email
Disallow: /account-selection
Disallow: /chats
Disallow: /chat
Disallow: /cart
Disallow: /checkout
Disallow: /profile
Disallow: /settings
Disallow: /edit-profile
Disallow: /my-ads
Disallow: /wishlist
Disallow: /shop-customize
Disallow: /add-product
Disallow: /notifications
Disallow: /notification-preferences
Disallow: /seller
Disallow: /seller-earnings
Disallow: /seller-analytics
Disallow: /seller-dispatch
Disallow: /seller-orders
Disallow: /seller-quote
Disallow: /kyc
Disallow: /report
Disallow: /product-boost
Disallow: /boost-receipt
Disallow: /my-purchases
Disallow: /receipt
Disallow: /order-detail
Disallow: /order-flow
Disallow: /create-group
Disallow: /group-chat
Disallow: /create-flash-sale
Disallow: /product-reviews
Disallow: /buyer-requests
Disallow: /post-buyer-request
Disallow: /follow-list
Disallow: /ai-assistant

Sitemap: ${SITE.canonicalHost}/sitemap.xml
`;

router.get('/robots.txt', (req, res) => {
  res.type('text/plain').setHeader('Cache-Control', 'public, max-age=3600').send(ROBOTS_TXT);
});

router.get('/sitemap.xml', async (req, res) => {
  try {
    res
      .type('application/xml')
      .setHeader('Cache-Control', 'public, max-age=1800')
      .send(await sitemapIndexXml());
  } catch (error) {
    console.error('[SEO] sitemap index failed:', error.message);
    res.status(500).type('text/plain').send('Sitemap unavailable');
  }
});

router.get('/sitemaps/:file', async (req, res) => {
  const name = req.params.file;
  if (!/^[a-z0-9-]+\.xml$/.test(name)) {
    return res.status(404).type('text/plain').send('Not found');
  }
  try {
    const xml = await getSitemapFile(name);
    if (!xml) return res.status(404).type('text/plain').send('Not found');
    res.type('application/xml').setHeader('Cache-Control', 'public, max-age=1800').send(xml);
  } catch (error) {
    console.error('[SEO] sitemap file failed:', error.message);
    res.status(500).type('text/plain').send('Sitemap unavailable');
  }
});

const NOT_FOUND_HTML = `<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Page Not Found | ${SITE.name}</title>
<meta name="robots" content="noindex, nofollow">
<style>
  body{margin:0;font-family:Arial,Helvetica,sans-serif;background:#000;color:#fff;min-height:100vh;display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center;padding:24px}
  h1{font-size:2.4rem;letter-spacing:-.02em;margin:0 0 8px}
  p{color:#9b9b9b;margin:0 0 28px}
  a{color:#fff;border:1px solid #fff;padding:12px 28px;border-radius:10px;text-decoration:none;font-weight:600}
  a:hover{background:#fff;color:#000}
</style></head>
<body>
  <h1>404</h1>
  <p>Ukurasa huu haupo — the page you are looking for was not found.</p>
  <a href="${SITE.canonicalHost}/">Back to ${SITE.name}</a>
</body></html>`;

// Cached copy of the Flutter web app shell; SEO tags are injected per request.
let indexTemplate = null;
function getIndexTemplate() {
  if (indexTemplate !== null) return indexTemplate;
  try {
    indexTemplate = fs.readFileSync(
      path.join(__dirname, '..', '..', '..', 'build', 'web', 'index.html'),
      'utf8'
    );
  } catch (error) {
    console.error('[SEO] failed to read build/web/index.html:', error.message);
    indexTemplate = '';
  }
  return indexTemplate;
}

// Handles the SPA client routes: injects per-route SEO metadata and returns a
// real 404 when a product or path does not exist (no soft-404s for crawlers).
async function handleSpa(req, res, next) {
  const lastSeg = req.path.split('/').pop() || '';
  if (
    req.path.startsWith('/api') ||
    req.path.startsWith('/health') ||
    req.path.startsWith('/admin') ||
    req.path.startsWith('/marketing') ||
    req.path.startsWith('/.well-known') ||
    lastSeg.includes('.') ||
    !req.accepts('html')
  ) {
    return next();
  }

  const html = getIndexTemplate();
  if (!html) return next();

  // URL normalization: /product/abc/ -> /product/abc
  if (req.path.length > 1 && req.path.endsWith('/')) {
    const target = req.path.replace(/\/+$/, '') + (req.originalUrl.includes('?') ? '' : '');
    const qs = req.originalUrl.includes('?') ? req.originalUrl.slice(req.originalUrl.indexOf('?')) : '';
    return res.redirect(301, `${target}${qs}`);
  }

  let meta;
  try {
    meta = await buildMeta(req);
  } catch (error) {
    console.error('[SEO] meta build failed:', error.message);
    return next();
  }

  if (meta.status === 404) {
    return res
      .status(404)
      .type('html')
      .setHeader('Cache-Control', 'no-cache')
      .send(NOT_FOUND_HTML);
  }

  res
    .status(200)
    .type('html')
    .setHeader('Cache-Control', 'no-cache')
    .send(injectMeta(html, meta));
}

module.exports = { seoRouter: router, handleSpa };