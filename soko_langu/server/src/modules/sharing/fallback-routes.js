'use strict';

const { Router } = require('express');
const { getStore } = require('../../config/database');
const { publicUrl } = require('../media/cdn-service');
const { productFallbackHtml, sellerFallbackHtml, buildHtml, escapeHtml } = require('./fallback-html');
const { SITE } = require('../../seo/meta');

const router = Router();

// Helper to check if request is bot / crawler — always serve OG HTML
function isBot(req) {
  const ua = (req.get('user-agent') || '').toLowerCase();
  return /bot|crawler|spider|facebook|whatsapp|telegram|twitter|slack|linkedin|embed/.test(ua);
}

// Product web fallback — works when app not installed.
// Serves full HTML with OG + product card, install CTA, and "Open in Soko Vibe" button.
router.get('/product/:slugOrId', async (req, res) => {
  try {
    const store = getStore();
    const product = await store.product.findFirst({
      where: { OR: [{ slug: req.params.slugOrId }, { id: req.params.slugOrId }], status: 'published' },
      include: {
        media: { orderBy: { sortOrder: 'asc' }, take: 1 },
        seller: { select: { storeName: true, storeSlug: true } },
        category: { select: { name: true } },
      },
    });
    if (!product) {
      return res.status(404).type('html').send(
        buildHtml({
          title: 'Bidhaa haipo',
          description: 'Bidhaa uliyoitafuta haipo kwenye Soko Vibe.',
          canonical: `${SITE.canonicalHost}/product/${escapeHtml(req.params.slugOrId)}`,
          ogType: 'website',
          body: `<div class="card"><div class="pad" style="text-align:center"><h1 class="h1">Bidhaa haipo</h1><p class="desc">Bidhaa hii haipo au imefutwa.</p><a class="btn btn-primary" href="/">Rudi Sokoni</a></div></div>`,
        }),
      );
    }
    // For bots or browsers without app, serve rich fallback
    // For app interstitial, same HTML — Android autoVerify will open app instead when installed.
    const html = await productFallbackHtml(product);
    res.type('html').setHeader('Cache-Control', 'public, max-age=60').send(html);
  } catch (e) {
    console.error('product fallback error', e);
    res.status(500).json({ success: false, error: 'INTERNAL' });
  }
});

// Seller / profile fallback
router.get(['/seller/:username', '/profile/:username'], async (req, res) => {
  try {
    const store = getStore();
    const seller = await store.sellerProfile.findFirst({
      where: { OR: [{ storeSlug: req.params.username }, { id: req.params.username }] },
      include: { user: true },
    });
    if (!seller) {
      return res.status(404).type('html').send(
        buildHtml({
          title: 'Muuzaji haipo',
          description: 'Muuzaji uliyemtafuta haipo.',
          canonical: `${SITE.canonicalHost}/seller/${escapeHtml(req.params.username)}`,
          ogType: 'profile',
          body: `<div class="card"><div class="pad" style="text-align:center"><h1 class="h1">Muuzaji haipo</h1><p class="desc">Profile hii haipo au imefutwa.</p><a class="btn btn-primary" href="/">Rudi Sokoni</a></div></div>`,
        }),
      );
    }
    const html = await sellerFallbackHtml(seller);
    res.type('html').setHeader('Cache-Control', 'public, max-age=120').send(html);
  } catch (e) {
    console.error('seller fallback error', e);
    res.status(500).json({ success: false, error: 'INTERNAL' });
  }
});

// Order — auth required. Never expose private data. Show login CTA.
router.get('/order/:orderId', (req, res) => {
  const canonical = `${SITE.canonicalHost}/order/${escapeHtml(req.params.orderId)}`;
  const body = `
    <div class="card">
      <div class="pad" style="text-align:center">
        <h1 class="h1">Oda yako</h1>
        <p class="desc">Ingia kwenye Soko Vibe kuona maelezo ya oda. Taarifa za siri (anwani, malipo, OTP) zinaonekana tu ukiwa umeingia.</p>
        <div class="cta" style="justify-content:center">
          <a class="btn btn-primary" href="${canonical}">Ingia na Fungua Oda</a>
          <a class="btn btn-outline" href="https://play.google.com/store/apps/details?id=com.sokolangu.app">Pakua App</a>
        </div>
      </div>
    </div>
  `;
  res.type('html').setHeader('Cache-Control', 'no-store').send(
    buildHtml({
      title: 'Oda — Soko Vibe',
      description: 'Ingia kuona maelezo ya oda yako kwenye Soko Vibe.',
      canonical,
      ogType: 'website',
      body,
    }),
  );
});

// OTP — same as order, never place OTP in URL
router.get('/otp/:orderId', (req, res) => {
  const canonical = `${SITE.canonicalHost}/otp/${escapeHtml(req.params.orderId)}`;
  const body = `
    <div class="card">
      <div class="pad" style="text-align:center">
        <h1 class="h1">Thibitisha Upokeaji</h1>
        <p class="desc">Link hii inahusu uthibitisho wa oda. OTP halisi haipo kwenye link — ingia ndani ya app kuthibitisha.</p>
        <div class="cta" style="justify-content:center">
          <a class="btn btn-primary" href="${SITE.canonicalHost}/order/${escapeHtml(req.params.orderId)}">Fungua Oda</a>
        </div>
      </div>
    </div>
  `;
  res.type('html').setHeader('Cache-Control', 'no-store').send(
    buildHtml({
      title: 'OTP — Soko Vibe',
      description: 'Thibitisha upokeaji salama kwenye Soko Vibe.',
      canonical,
      ogType: 'website',
      body,
    }),
  );
});

// Category fallback — redirect to category products SPA or show landing
router.get('/category/:name', (req, res) => {
  const name = req.params.name;
  const canonical = `${SITE.canonicalHost}/category/${encodeURIComponent(name)}`;
  const body = `
    <div class="card">
      <div class="pad" style="text-align:center">
        <h1 class="h1">${escapeHtml(name)}</h1>
        <p class="desc">Gundua bidhaa za ${escapeHtml(name)} kwenye Soko Vibe.</p>
        <div class="cta" style="justify-content:center">
          <a class="btn btn-primary" href="${canonical}">Fungua kwenye App</a>
          <a class="btn btn-outline" href="/">Vinjari Sokoni</a>
        </div>
      </div>
    </div>
  `;
  res.type('html').setHeader('Cache-Control', 'public, max-age=120').send(
    buildHtml({
      title: `${name} — Soko Vibe`,
      description: `Gundua bidhaa za ${name} kwenye Soko Vibe.`,
      canonical,
      ogType: 'website',
      body,
    }),
  );
});

// Search fallback
router.get('/search', (req, res) => {
  const q = (req.query.q || req.query.search || '').toString().slice(0, 80);
  const canonical = `${SITE.canonicalHost}/search${q ? `?q=${encodeURIComponent(q)}` : ''}`;
  const body = `
    <div class="card">
      <div class="pad" style="text-align:center">
        <h1 class="h1">${q ? `Tafuta: ${escapeHtml(q)}` : 'Tafuta Soko Vibe'}</h1>
        <p class="desc">Tafuta bidhaa, wauzaji na kategoria kwenye Soko Vibe.</p>
        <div class="cta" style="justify-content:center">
          <a class="btn btn-primary" href="${canonical}">Fungua kwenye App</a>
        </div>
      </div>
    </div>
  `;
  res.type('html').send(
    buildHtml({
      title: q ? `Tafuta ${q}` : 'Tafuta — Soko Vibe',
      description: 'Tafuta bidhaa kwenye Soko Vibe.',
      canonical,
      ogType: 'website',
      body,
    }),
  );
});

module.exports = router;
