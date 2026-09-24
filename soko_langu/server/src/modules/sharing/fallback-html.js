'use strict';

const { SITE } = require('../../seo/meta');
const { publicUrl, ogTags } = require('../media/cdn-service');

function escapeHtml(s) {
  return String(s ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function formatPrice(price) {
  try {
    return `TSh ${Number(price).toLocaleString('en-TZ')}`;
  } catch (_) {
    return `TSh ${price}`;
  }
}

function buildHtml({ title, description, imageUrl, canonical, ogType, body }) {
  const og = ogTags({ title, description, imageUrl, type: ogType });
  return `<!DOCTYPE html>
<html lang="sw">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>${escapeHtml(title)} | ${escapeHtml(SITE.name)}</title>
<meta name="description" content="${escapeHtml(description)}">
<link rel="canonical" href="${escapeHtml(canonical)}">
${og}
<meta property="og:url" content="${escapeHtml(canonical)}">
<meta property="og:site_name" content="${escapeHtml(SITE.name)}">
<meta name="twitter:card" content="summary_large_image">
<meta name="theme-color" content="#221c4a">
<link rel="icon" type="image/svg+xml" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 512 512'%3E%3Crect width='512' height='512' rx='120' fill='%23221c4a'/%3E%3Ctext x='256' y='330' font-family='Arial' font-size='220' font-weight='800' fill='%23fff' text-anchor='middle'%3ES%3C/text%3E%3C/svg%3E">
<style>
*{box-sizing:border-box}body{margin:0;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;background:#0f0c1f;color:#fff;min-height:100vh;display:flex;flex-direction:column}
.header{padding:16px 20px;display:flex;align-items:center;gap:12px;background:#1a1538;border-bottom:1px solid rgba(255,255,255,.08)}
.header .brand{font-weight:800;font-size:18px;letter-spacing:-.02em}
.header .brand span{color:#7c4dff}
.container{max-width:720px;margin:0 auto;padding:20px;width:100%;flex:1}
.card{background:#1e1a3a;border-radius:20px;overflow:hidden;border:1px solid rgba(255,255,255,.08);box-shadow:0 20px 60px rgba(0,0,0,.4)}
.card img{width:100%;height:360px;object-fit:cover;background:#2a2550;display:block}
.card .pad{padding:20px}
.h1{font-size:22px;font-weight:800;line-height:1.2;margin:0 0 8px}
.price{font-size:20px;font-weight:800;color:#7cffb2;margin:8px 0}
.meta{color:#b7b3d0;font-size:13px;margin:6px 0;display:flex;gap:12px;flex-wrap:wrap}
.meta span{display:inline-flex;align-items:center;gap:6px}
.desc{color:#d8d5f0;font-size:14px;line-height:1.6;margin:12px 0;white-space:pre-wrap}
.cta{display:flex;gap:12px;margin-top:18px;flex-wrap:wrap}
.btn{flex:1;min-width:140px;padding:14px 18px;border-radius:14px;font-weight:700;text-align:center;text-decoration:none;font-size:14px;cursor:pointer;border:none}
.btn-primary{background:linear-gradient(135deg,#7c4dff,#ff3e8f);color:#fff}
.btn-outline{background:rgba(255,255,255,.08);color:#fff;border:1px solid rgba(255,255,255,.15)}
.badge{display:inline-flex;align-items:center;gap:6px;background:rgba(124,77,255,.15);color:#b9a6ff;padding:6px 10px;border-radius:999px;font-size:12px;font-weight:600}
.notice{background:rgba(255,193,7,.1);border:1px solid rgba(255,193,7,.2);color:#ffd54f;padding:12px;border-radius:12px;font-size:13px;margin-top:12px}
.footer{text-align:center;padding:20px;color:#8a87a8;font-size:12px}
</style>
<script>
function openApp(url){
  // Try to open via intent, fallback to store
  window.location.href = url;
  setTimeout(function(){
    // If still here, show store CTA (browser didn't leave)
  }, 1500);
}
</script>
</head>
<body>
<header class="header">
  <div class="brand"><span>Soko</span> Vibe</div>
  <div style="margin-left:auto;font-size:12px;color:#9a97b8">Soko la Tanzania</div>
</header>
<div class="container">${body}</div>
<footer class="footer">© ${new Date().getFullYear()} Soko Vibe Limited · Dar es Salaam, Tanzania</footer>
</body></html>`;
}

async function productFallbackHtml(product) {
  if (!product) return null;
  const getStore = require('../../config/database').getStore;
  // product already loaded by caller, reuse
  const imageUrl = product.media && product.media[0]
    ? publicUrl({ kind: 'image', key: product.media[0].r2Key })
    : (product.snapshot && product.snapshot.images && product.snapshot.images[0]) || '';
  const title = product.title || product.snapshot?.name || 'Bidhaa';
  const price = formatPrice(product.price);
  const location = product.snapshot?.location || product.location || 'Tanzania';
  const condition = product.condition || product.snapshot?.condition || 'new';
  const sellerName = product.seller?.storeName || product.snapshot?.sellerName || 'Muuzaji';
  const rawDesc = product.description || product.snapshot?.description || '';
  const descSummary = rawDesc.length > 260 ? rawDesc.slice(0, 257) + '...' : rawDesc;
  const canonical = `${SITE.canonicalHost}/product/${product.id}`;
  const deepLink = canonical; // same — Android will intercept
  const ogDesc = `${title} — ${price} · ${sellerName} · ${location}`;

  const body = `
    <div class="card">
      ${imageUrl ? `<img src="${escapeHtml(imageUrl)}" alt="${escapeHtml(title)}" onerror="this.style.display='none'">` : `<div style="height:240px;display:flex;align-items:center;justify-content:center;background:#2a2550;color:#8a87a8">Hakuna picha</div>`}
      <div class="pad">
        <div class="badge">Soko Vibe · ${escapeHtml(condition)}</div>
        <h1 class="h1">${escapeHtml(title)}</h1>
        <div class="price">${escapeHtml(price)}</div>
        <div class="meta">
          <span>📍 ${escapeHtml(location)}</span>
          <span>👤 ${escapeHtml(sellerName)}</span>
          <span>✅ ${escapeHtml(condition)}</span>
        </div>
        ${descSummary ? `<div class="desc">${escapeHtml(descSummary)}</div>` : ''}
        <div class="cta">
          <a class="btn btn-primary" href="${escapeHtml(deepLink)}" onclick="openApp('${escapeHtml(deepLink)}'); return false;">Fungua kwenye Soko Vibe</a>
          <a class="btn btn-outline" href="https://play.google.com/store/apps/details?id=com.sokolangu.app">Pakua App</a>
        </div>
        <div class="notice">Unaona ukurasa wa wavuti kwa sababu Soko Vibe haijasakinishwa. Sakinisha app kwa uzoefu bora — pesa zako ziko salama kwenye escrow.</div>
      </div>
    </div>
  `;
  return buildHtml({
    title,
    description: ogDesc,
    imageUrl,
    canonical,
    ogType: 'product',
    body,
  });
}

async function sellerFallbackHtml(seller) {
  if (!seller) return null;
  const title = seller.storeName || 'Muuzaji';
  const desc = seller.storeDescription || `${title} kwenye Soko Vibe — angalia bidhaa zake.`;
  const imageUrl = seller.logoUrl || '';
  const canonical = `${SITE.canonicalHost}/seller/${seller.storeSlug}`;
  const body = `
    <div class="card">
      <div class="pad" style="text-align:center">
        ${imageUrl ? `<img src="${escapeHtml(imageUrl)}" alt="${escapeHtml(title)}" style="width:96px;height:96px;border-radius:999px;object-fit:cover;margin:0 auto 16px;display:block">` : `<div style="width:96px;height:96px;border-radius:999px;background:#2a2550;margin:0 auto 16px;display:flex;align-items:center;justify-content:center;font-size:36px">🏪</div>`}
        <h1 class="h1">${escapeHtml(title)}</h1>
        <div style="color:#b7b3d0;font-size:13px;margin:8px 0">${seller.isVerified ? '✅ Imehakikiwa' : ''} ${seller.location ? '· 📍 ' + escapeHtml(seller.location) : ''}</div>
        ${desc ? `<div class="desc" style="text-align:center">${escapeHtml(desc)}</div>` : ''}
        ${seller.rating ? `<div class="price" style="font-size:14px;color:#ffd54f">⭐ ${Number(seller.rating).toFixed(1)} / 5</div>` : ''}
        <div class="cta" style="justify-content:center">
          <a class="btn btn-primary" href="${escapeHtml(canonical)}">Fungua kwenye Soko Vibe</a>
          <a class="btn btn-outline" href="https://play.google.com/store/apps/details?id=com.sokolangu.app">Pakua App</a>
        </div>
      </div>
    </div>
  `;
  return buildHtml({
    title,
    description: desc.slice(0, 160),
    imageUrl,
    canonical,
    ogType: 'profile',
    body,
  });
}

module.exports = { productFallbackHtml, sellerFallbackHtml, buildHtml, escapeHtml, formatPrice };
