/* Soko Vibe Duka — browser app.
   Single hash-router SPA. Reads the products collection directly from
   Firestore (same project as the app), mirrors the app's flat one-product
   order flow against the legacy /api orders + ClickPesa endpoints. */

'use strict';

/* ---------- Boot ---------- */

const FB_CONFIG = {
  apiKey: 'AIzaSyBrh5W9VwbC3qTtSTm8LJbTQeYufRGil5s',
  authDomain: 'sokonimoko-8c171-a8d14.firebaseapp.com',
  projectId: 'sokonimoko-8c171-a8d14',
  appId: '1:344682929526:web:5d3732578d6f012ac26e57',
  messagingSenderId: '344682929526',
};
if (!window.firebase || !firebase.apps || firebase.apps.length === 0) firebase.initializeApp(FB_CONFIG);

const AUTH = firebase.auth();
const DB = firebase.firestore();

const PAGE = 24;
const view = document.getElementById('view');
const toastEl = document.getElementById('toast');
const NUMF = new Intl.NumberFormat('en-TZ');
const PAY_STATES = new Set(['paid', 'escrow_hold', 'escrow_held', 'paid_escrow_held', 'pending_escrow_release', 'dispatched', 'en_route', 'confirmed', 'delivered', 'completed']);
const BAD_STATES = new Set(['failed', 'cancelled']);

let lang = 'sw';
let theme = localStorage.getItem('sv_shop_theme') || 'light';
let cart = readCart();
let pollTimer = null;
let payCtx = null;

/* ---------- Small helpers ---------- */

const esc = (s) => String(s == null ? '' : s)
  .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
  .replace(/"/g, '&quot;').replace(/'/g, '&#39;');

const t = (k) => (SV_T[lang] && SV_T[lang][k] != null ? SV_T[lang][k] : SV_T.sw[k] != null ? SV_T.sw[k] : k);
const tf = (k) => String(t(k)).replace(/^./, (c) => c.toUpperCase());

function fmtTZS(n) {
  const v = Math.round(Number(n) || 0);
  return 'TSh ' + NUMF.format(v);
}

function ts2date(ts) {
  if (!ts) return '';
  const t = ts.toDate ? ts.toDate() : new Date(ts);
  if (isNaN(t)) return '';
  return t.toLocaleDateString(lang === 'sw' ? 'sw-TZ' : 'en-GB', { day: '2-digit', month: 'short', year: '2-digit' }) + ' ' +
    t.toLocaleTimeString(lang === 'sw' ? 'sw-TZ' : 'en-GB', { hour: '2-digit', minute: '2-digit' });
}

function e164(phone) {
  let p = String(phone || '').replace(/[^\d]/g, '');
  if (!p) return '';
  if (p.startsWith('0')) p = '255' + p.slice(1);
  if (p.length === 9) p = '255' + p;
  return p;
}

function waLink(phone, msg) {
  const n = e164(phone);
  return n ? 'https://wa.me/' + n + (msg ? '?text=' + encodeURIComponent(msg) : '') : '#';
}

function readCart() {
  try { return JSON.parse(localStorage.getItem('sv_shop_cart') || '[]'); } catch (_) { return []; }
}
function saveCart() { localStorage.setItem('sv_shop_cart', JSON.stringify(cart)); }
function cartQty() { return cart.reduce((s, i) => s + (i.q || 0), 0); }
function refreshBadge() {
  const b = document.getElementById('cartBadge');
  if (!b) return;
  const n = cartQty();
  b.textContent = String(n);
  b.classList.toggle('show', n > 0);
}

function toast(msg, ms) {
  toastEl.textContent = msg;
  toastEl.classList.add('show');
  clearTimeout(toast._ht);
  toast._ht = setTimeout(() => toastEl.classList.remove('show'), ms || 2600);
}

function setTheme() {
  document.documentElement.setAttribute('data-theme', theme);
  localStorage.setItem('sv_shop_theme', theme);
}

function setLang() {
  lang = localStorage.getItem('sv_shop_lang') || (navigator.language || 'sw').startsWith('en') ? 'en' : 'sw';
  if (SV_T[lang] == null) lang = 'sw';
  document.documentElement.lang = lang;
  localStorage.setItem('sv_shop_lang', lang);
}

function apiHeaders(token) {
  return { 'Content-Type': 'application/json', ...(token ? { Authorization: 'Bearer ' + token } : {}) };
}

async function apiGet(path) {
  const user = AUTH.currentUser;
  const token = user ? await user.getIdToken() : null;
  const res = await fetch(path, { headers: apiHeaders(token) });
  let data = {};
  try { data = await res.json(); } catch (_) {}
  if (!res.ok) throw new Error(data.error || 'HTTP ' + res.status);
  return data;
}

/* fetch with cold-start retries (Render free tier wakes ~15–60s) */
async function apiPost(path, body) {
  const user = AUTH.currentUser;
  const token = user ? await user.getIdToken() : null;
  let lastErr = null;
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      const ctrl = new AbortController();
      const to = setTimeout(() => ctrl.abort(), 15000);
      const res = await fetch(path, { method: 'POST', headers: apiHeaders(token), body: JSON.stringify(body), signal: ctrl.signal });
      clearTimeout(to);
      let data = {};
      try { data = await res.json(); } catch (_) {}
      if (!res.ok) throw new Error(data.error || 'HTTP ' + res.status);
      return data;
    } catch (e) {
      lastErr = e;
      if (e.name === 'AbortError' || (e.message && e.message.indexOf('Failed to fetch') === 0) || e.message === 'Failed to fetch') {
        await new Promise((r) => setTimeout(r, 2500));
        continue;
      }
      throw e;
    }
  }
  throw lastErr;
}

/* ---------- Product data ---------- */

function norm(doc) {
  const d = doc.data();
  return {
    id: doc.id,
    name: d.name || '',
    price: Number(d.price) || 0,
    currency: d.currency || 'TZS',
    images: Array.isArray(d.images) ? d.images : [],
    videoUrl: d.videoUrl || '',
    category: d.category || 'Vingine',
    subcategory: d.subcategory || '',
    description: d.description || '',
    sellerId: d.sellerId || '',
    sellerName: d.sellerName || 'Muuzaji',
    sellerPhone: d.sellerPhone || '',
    location: d.location || '',
    district: d.district || '',
    condition: d.condition || 'new',
    stock: Number(d.stock) || 0,
    unit: d.unit || 'kipande',
    minOrder: Number(d.minOrder) || 1,
    maxOrder: d.maxOrder != null ? Number(d.maxOrder) : null,
    brand: d.brand || '',
    isWholesale: !!d.isWholesale,
    wholesaleTiers: Array.isArray(d.wholesaleTiers) ? d.wholesaleTiers : [],
    variants: Array.isArray(d.variants) ? d.variants : [],
    attributes: d.attributes && typeof d.attributes === 'object' ? d.attributes : {},
    isActive: d.isActive !== false,
    isFeatured: !!d.isFeatured,
    featuredUntil: d.featuredUntil,
    isBoosted: !!d.isBoosted,
    boostedUntil: d.boostedUntil,
    boostTier: d.boostTier || '',
    rating: Number(d.rating) || 0,
    reviewCount: Number(d.reviewCount) || 0,
    soldCount: Number(d.soldCount) || 0,
    createdAt: d.createdAt,
  };
}

function boosted(p) {
  if (p.isBoosted) {
    const until = p.boostedUntil && p.boostedUntil.toDate ? p.boostedUntil.toDate() : (p.boostedUntil ? new Date(p.boostedUntil) : null);
    if (!until || until > new Date()) return p.boostTier || 'gold';
  }
  return null;
}
const TIER_RANK = { gold: 3, silver: 2, bronze: 1 };
function sortFeed(list) {
  return list.slice().sort((a, b) => {
    const ba = boosted(a) ? (TIER_RANK[boosted(a)] || 0) : 0;
    const bb = boosted(b) ? (TIER_RANK[boosted(b)] || 0) : 0;
    if (ba !== bb) return bb - ba;
    const ta = a.createdAt ? (a.createdAt.toDate ? a.createdAt.toDate().getTime() : new Date(a.createdAt).getTime()) : 0;
    const tb = b.createdAt ? (b.createdAt.toDate ? b.createdAt.toDate().getTime() : new Date(b.createdAt).getTime()) : 0;
    return tb - ta;
  });
}
function catSort(list) {
  return list.slice().sort((a, b) => {
    const ta = a.createdAt ? (a.createdAt.toDate ? a.createdAt.toDate().getTime() : new Date(a.createdAt).getTime()) : 0;
    const tb = b.createdAt ? (b.createdAt.toDate ? b.createdAt.toDate().getTime() : new Date(b.createdAt).getTime()) : 0;
    return tb - ta;
  });
}

const productCache = {};
async function getProduct(id) {
  if (productCache[id]) return productCache[id];
  const snap = await DB.collection('products').doc(id).get();
  if (!snap.exists) return null;
  productCache[id] = norm(snap);
  return productCache[id];
}

/* ---------- Card / markup builders ---------- */

function cardHtml(p) {
  const img = p.images[0];
  const bo = boosted(p);
  const soldout = p.stock <= 0;
  const flag = soldout
    ? '<span class="flag sold">' + esc(t('out_stock')) + '</span>'
    : (bo ? '<span class="flag boost">' + esc(bo) + '</span>' : '');
  return '<a class="card" href="#/p/' + encodeURIComponent(p.id) + '">'
    + '<div class="thumb">' + flag
    + (img ? '<img loading="lazy" src="' + esc(img) + '" alt="' + esc(p.name) + '" onerror="this.parentElement.classList.add(\'badimg\');this.remove()">' : '<div class="ph">SOKO</div>')
    + '<div class="ph" style="display:none"></div>'
    + '</div>'
    + '<div class="body">'
    + '<span class="cat">' + esc(p.category) + '</span>'
    + '<span class="nm">' + esc(p.name) + '</span>'
    + '<span class="pr">' + fmtTZS(p.price) + '</span>'
    + '<span class="meta"><span>' + esc(p.location || 'Tanzania') + '</span>'
    + (p.rating > 0 ? '<span>★ ' + p.rating.toFixed(1) + '</span>' : '')
    + (p.reviewCount ? '<span>(' + p.reviewCount + ')</span>' : '')
    + '</span>'
    + '</div></a>';
}

function skelGrid(n) {
  let s = '';
  for (let i = 0; i < n; i++) {
    s += '<div class="card"><div class="skel" style="height:0;padding-top:100%"></div>'
      + '<div class="skel" style="height:12px;width:60%;margin:10px 14px 0"></div>'
      + '<div class="skel" style="height:16px;width:40%;margin:10px 14px 14px"></div></div>';
  }
  return s;
}

const emptyHtml = (msg, sub, cta) => '<div class="empty-state"><div class="big">' + esc(msg) + '</div>'
  + (sub ? '<p>' + esc(sub) + '</p>' : '')
  + (cta ? '<a class="btn-dark" href="#/">' + esc(cta) + '</a>' : '')
  + '</div>';

/* ---------- Screens ---------- */

const Feed = { list: [], cursor: null, done: false, loading: false, mode: { kind: 'all' } };

async function loadPageInto() {
  if (Feed.loading || Feed.done) return;
  Feed.loading = true;
  try {
    let q = DB.collection('products').orderBy('createdAt', 'desc').limit(PAGE);
    if (Feed.cursor) q = DB.collection('products').orderBy('createdAt', 'desc').startAfter(Feed.cursor).limit(PAGE);
    const snap = await q.get();
    const fresh = snap.docs.map(norm).filter((p) => p.isActive && p.stock != null);
    Feed.cursor = snap.docs.length ? snap.docs[snap.docs.length - 1] : null;
    Feed.done = snap.docs.length < PAGE;
    if (Feed.idx) Feed.idx += PAGE;
    Feed.list = Feed.list.concat(fresh);
    renderFeed();
  } catch (e) {
    renderFeed(true);
  } finally {
    Feed.loading = false;
  }
}

function filterForMode() {
  const list = Feed.list;
  if (Feed.mode.kind === 'category') return catSort(list.filter((p) => p.category === Feed.mode.cat || p.subcategory === Feed.mode.cat));
  if (Feed.mode.kind === 'query') {
    const q = Feed.mode.q.toLowerCase();
    return catSort(list.filter((p) => (p.name || '').toLowerCase().indexOf(q) >= 0 || (p.brand || '').toLowerCase().indexOf(q) >= 0));
  }
  return sortFeed(list);
}

function renderFeed(errFlag) {
  const list = filterForMode();
  const host = document.getElementById('feedGrid');
  const sent = document.getElementById('sentinel');
  if (!host) return;
  if (errFlag && !Feed.list.length) {
    host.innerHTML = emptyHtml(t('err_generic'), t('empty'), t('home_browse'));
    if (sent) sent.style.display = 'none';
    return;
  }
  host.innerHTML = list.map(cardHtml).join('') + (Feed.loading && list.length === 0 ? skelGrid(8) : '');
  if (sent) sent.style.display = Feed.done ? 'none' : 'block';
  const moreBtn = document.getElementById('moreBtn');
  if (moreBtn) moreBtn.style.display = Feed.done || errFlag ? 'none' : 'inline-flex';
}

async function renderHome() {
  setLang();
  Feed.idx = PAGE;
  Feed.mode = { kind: 'all' };
  const hero = '<div class="hero"><div class="kicker">' + tf('home_hero_kicker') + '</div>'
    + '<h1>' + t('home_hero_title') + '</h1>'
    + '<p>' + t('home_hero_sub') + '</p></div>';
  const chips = '<div class="chips">'
    + '<a class="chip" href="#/">' + t('all') + '</a>'
    + SV_CATEGORIES.map((c) => '<a class="chip" href="#/c/' + encodeURIComponent(c) + '">' + esc(c) + '</a>').join('')
    + '</div>';
  view.innerHTML = '<div class="container">' + hero + chips
    + '<div class="section-title"><span>' + t('home_new') + '</span><small>' + t('home_browse') + '</small></div>'
    + '<div class="grid" id="feedGrid">' + skelGrid(8) + '</div>'
    + '<div class="center mt24"><button class="btn-outline" id="moreBtn" data-act="loadmore" style="display:none">' + t('load_more') + '</button></div>'
    + '</div>';
  if (Feed.list.length) { renderFeed(); return; }
  await loadPageInto();
}

function chipsFor(activeCat) {
  return '<div class="chips">'
    + '<a class="chip" href="#/">' + t('all') + '</a>'
    + SV_CATEGORIES.map((c) => '<a class="chip' + (c === activeCat ? ' active' : '') + '" href="#/c/' + encodeURIComponent(c) + '">' + esc(c) + '</a>').join('')
    + '</div>';
}

async function renderCategory(cat) {
  setLang();
  Feed.idx = PAGE;
  Feed.mode = { kind: 'category', cat: cat };
  view.innerHTML = '<div class="container">'
    + '<div class="headline-row"><a class="mini-link" href="#/">← ' + t('back') + '</a>'
    + '<span class="section-muted">' + esc(cat) + '</span></div>'
    + chipsFor(cat)
    + '<div class="grid" id="feedGrid">' + skelGrid(8) + '</div>'
    + '<div class="center mt24"><button class="btn-outline" id="moreBtn" data-act="loadmore" style="display:none">' + t('load_more') + '</button></div>'
    + '</div>';
  if (Feed.list.length) { renderFeed(); return; }
  await loadPageInto();
}

async function renderSearch(q) {
  setLang();
  Feed.mode = { kind: 'query', q: q };
  const ql = q.toLowerCase();
  view.innerHTML = '<div class="container">'
    + '<div class="headline-row"><a class="mini-link" href="#/">← ' + t('back') + '</a>'
    + '<span class="section-muted">"' + esc(q) + '"</span></div>'
    + '<div class="grid" id="feedGrid">' + skelGrid(8) + '</div>'
    + '<div class="center mt24"><button class="btn-outline" id="moreBtn" data-act="loadmore" style="display:none">' + t('load_more') + '</button></div>'
    + '</div>';
  const host = document.getElementById('feedGrid');
  if (!host) return;
  const inMem = Filter(Feed.list, ql);
  if (inMem.length) { renderFeed(); return; }
  try {
    const snap = await DB.collection('products')
      .where('searchName', '>=', ql).where('searchName', '<=', ql + '\uf8ff').limit(PAGE * 2).get();
    const hits = snap.docs.map(norm).filter((p) => p.isActive);
    host.innerHTML = hits.length
      ? hits.map(cardHtml).join('')
      : emptyHtml(t('empty_filter'), q, t('home_browse'));
    const sent = document.getElementById('sentinel');
    if (sent) sent.style.display = 'none';
  } catch (e) {
    host.innerHTML = emptyHtml(t('err_generic'), '', t('home_browse'));
  }
}

// local search fallback when loaded Feed has a match
function Filter(list, ql) {
  return list.filter((p) => (p.name || '').toLowerCase().indexOf(ql) >= 0);
}

async function renderProduct(id) {
  setLang();
  view.innerHTML = '<div class="container"><div class="skel" style="height:380px;margin-top:24px"></div></div>';
  let p;
  try { p = await getProduct(id); } catch (_) { p = null; }
  if (!p) {
    view.innerHTML = '<div class="container">' + emptyHtml(t('empty_filter'), '', t('home_browse')) + '</div>';
    return;
  }
  const bo = boosted(p);
  const soldout = p.stock <= 0;
  const mainImg = p.images[0] || '';
  const thumbs = p.images.slice(1, 6).map((u, i) =>
    '<button data-act="img" data-i="' + (i + 1) + '"><img src="' + esc(u) + '" alt="" onerror="this.remove()"></button>').join('');
  const attrs = Object.entries(p.attributes || {}).slice(0, 8).map(([k, v]) => '<tr><td>' + esc(k) + '</td><td>' + esc(v) + '</td></tr>').join('');
  const tiers = p.wholesaleTiers && p.wholesaleTiers.length
    ? '<div class="desc mt16"><h3>Jumla (wholesale)</h3><table class="attrs-table"><tr><td>Idadi</td><td>Bei kwa kipande</td></tr>'
      + p.wholesaleTiers.map((ti) => '<tr><td>' + esc(ti.minQuantity) + '+</td><td>' + fmtTZS(ti.pricePerUnit) + '</td></tr>').join('')
      + '</table></div>' : '';
  const variants = p.variants && p.variants.length
    ? '<div class="field mt16"><label>' + t('variants') + '</label><select id="variantSel">'
      + p.variants.map((v, i) => '<option value="' + esc(v.id) + '" data-adj="' + (Number(v.priceAdjustment) || 0) + '" data-stock="' + (Number(v.stock) != null ? Number(v.stock) : p.stock) + '">' + esc(v.name + (v.value ? ' — ' + v.value : '')) + ' (+' + fmtTZS(Number(v.priceAdjustment) || 0) + ')' + '</option>').join('')
      + '</select></div>' : '';
  const stockTxt = soldout
    ? '<span class="tag stock" style="color:var(--faint)">' + t('out_stock') + '</span>'
    : '<span class="tag stock">' + t('in_stock') + ': ' + p.stock + ' ' + esc(p.unit) + '</span>';

  view.innerHTML = '<div class="container"><div class="detail">'
    + '<div class="gallery">'
    + '<div class="main"><img id="mainImg" src="' + esc(mainImg) + '" alt="' + esc(p.name) + '" onerror="this.replaceWith(Object.assign(document.createElement(\'div\'),{className:\'ph\',textContent:\'SOKO\'}))"></div>'
    + (thumbs ? '<div class="thumbs">' + thumbs + '</div>' : '')
    + '</div>'
    + '<div class="info">'
    + '<span class="crumbs">' + esc(p.category) + (p.subcategory ? ' / ' + esc(p.subcategory) : '') + '</span>'
    + '<h1>' + esc(p.name) + '</h1>'
    + '<div class="price" id="priceNow">' + fmtTZS(p.price) + '</div>'
    + '<div class="tags">' + stockTxt
    + '<span class="tag">' + esc(p.condition) + '</span>'
    + (p.brand ? '<span class="tag">' + esc(p.brand) + '</span>' : '')
    + (bo ? '<span class="tag" style="border-color:var(--fg)">' + esc(bo) + '</span>' : '')
    + '</div>'
    + variants
    + '<div class="picker"><span class="section-muted">' + t('qty') + ':</span>'
    + '<div class="stepper"><button type="button" data-act="qminus" aria-label="-">−</button><span class="n" id="qtyN">1</span><button type="button" data-act="qplus" aria-label="+">+</button></div>'
    + '<span class="section-muted" id="stockNote">' + (soldout ? t('out_stock') : (p.maxOrder ? 'max ' + p.maxOrder : '')) + '</span></div>'
    + '<div class="rowbtns">'
    + '<button class="btn-dark btn-block" data-act="buynow"' + (soldout ? ' disabled' : '') + '>' + t('buy_now') + '</button>'
    + '</div>'
    + '<button class="btn-outline btn-block" data-act="addcart"' + (soldout ? ' disabled' : '') + '>' + t('add_cart') + '</button>'
    + '<div class="seller-card">'
    + '<div class="who"><div class="avatar">' + esc((p.sellerName || 'S').slice(0, 1).toUpperCase()) + '</div>'
    + '<div><div class="nm">' + esc(p.sellerName) + '</div>'
    + '<div class="loc">' + esc(p.location || 'Tanzania') + (p.district ? ' · ' + esc(p.district) : '') + '</div></div></div>'
    + (p.sellerPhone ? '<a class="btn-wa btn-block" href="' + waLink(p.sellerPhone, 'Habari ' + encodeURIComponent(p.name) + '?') + '" target="_blank" rel="noopener">' + t('wa_cta') + '</a>' : '')
    + '</div>'
    + '<div class="desc"><h3>' + t('description') + '</h3><p>' + esc(p.description) + '</p></div>'
    + tiers
    + (attrs ? '<div class="attrs mt16"><h3>' + t('attributes') + '</h3><table>' + attrs + '</table></div>' : '')
    + '</div></div></div>';

  let sel = { qty: 1, variantId: null, adj: 0, vstock: p.stock };
  window.__sel = sel;
  const variantSel = document.getElementById('variantSel');
  if (variantSel) {
    variantSel.addEventListener('change', () => {
      const o = variantSel.options[variantSel.selectedIndex];
      sel.variantId = o.value;
      sel.adj = Number(o.dataset.adj) || 0;
      sel.vstock = Number(o.dataset.stock) != null && Number(o.dataset.stock) >= 0 ? Number(o.dataset.stock) : p.stock;
      const max = Math.min(sel.vstock, p.maxOrder || sel.vstock || 1);
      if (sel.qty > max) sel.qty = max;
      document.getElementById('qtyN').textContent = sel.qty;
      document.getElementById('priceNow').textContent = fmtTZS(p.price + sel.adj);
      document.getElementById('stockNote').textContent = (sel.vstock <= 0 ? t('out_stock') : (p.maxOrder ? 'max ' + p.maxOrder : ''));
    });
  }
  const qtyN = document.getElementById('qtyN');
  const clampQ = () => {
    const max = Math.min(sel.vstock, p.maxOrder || sel.vstock || 1);
    sel.qty = Math.max(1, Math.min(sel.qty, max));
    qtyN.textContent = sel.qty;
  };
  document.addEventListener('click', function qh(e) {
    const el = e.target.closest('[data-act]');
    if (!el) return;
    if (el.dataset.act === 'qplus') { sel.qty++; clampQ(); }
    else if (el.dataset.act === 'qminus') { sel.qty--; clampQ(); }
    else if (el.dataset.act === 'addcart') { addToCart(p, sel); toast(t('add_to_cart_ok')); }
    else if (el.dataset.act === 'buynow') { location.hash = '#/checkout?p=' + encodeURIComponent(p.id) + '&q=' + sel.qty + (sel.variantId ? '&v=' + encodeURIComponent(sel.variantId) : ''); }
    else if (el.dataset.act === 'img') {
      const i = Number(el.dataset.i) || 0;
      const src = p.images[i];
      const m = document.getElementById('mainImg');
      if (m && src) m.src = src;
    }
  });
}

function addToCart(p, sel) {
  const q = sel.qty || 1;
  const ix = cart.findIndex((i) => i.p === p.id && (i.v || '') === (sel.variantId || ''));
  if (ix >= 0) {
    const max = Math.min(p.maxOrder || p.stock || 1, p.stock || 1);
    cart[ix].q = Math.min(Number(cart[ix].q || 0) + q, max);
  } else {
    cart.push({ p: p.id, v: sel.variantId || null, q: q, n: p.name, img: p.images[0] || '', u: p.price + (sel.adj || 0), s: p.sellerName || '', c: p.category || '' });
  }
  saveCart();
  refreshBadge();
}

async function renderCart() {
  setLang();
  if (!cart.length) {
    view.innerHTML = '<div class="container">' + emptyHtml(t('cart_empty'), '', t('cart_browse')) + '</div>';
    refreshBadge();
    return;
  }
  const items = await Promise.all(cart.map(async (i) => ({ line: i, prod: (await getProduct(i.p)) || null })));
  const groups = new Map();
  for (const it of items) {
    const seller = it.prod && it.prod.sellerName ? it.prod.sellerName : it.line.s;
    if (!groups.has(seller)) groups.set(seller, []);
    groups.get(seller).push(it);
  }
  const tot = items.reduce((s, it) => s + (Number(it.line.u) || 0) * Number(it.line.q || 0), 0);
  let html = '<div class="container"><div class="headline-row"><a class="mini-link" href="#/">← ' + t('back') + '</a>'
    + '<span class="section-title" style="margin:0">' + t('cart_title') + '</span></div>'
    + '<div class="cart-list">';
  for (const [seller, lines] of groups) {
    html += '<div class="cart-group"><div class="ghead"><span>' + t('cart_seller') + ': ' + esc(seller) + '</span></div>';
    for (const it of lines) {
      const p = it.prod;
      const img = it.line.img || (p && p.images[0]) || '';
      html += '<div class="cart-item">'
        + '<div class="thumb">' + (img ? '<img src="' + esc(img) + '" alt="" onerror="this.remove()">' : '') + '</div>'
        + '<div class="mid"><div class="nm">' + esc(it.line.n || (p && p.name) || '') + '</div>'
        + '<div class="pr">' + fmtTZS(Number(it.line.u) || 0) + ' × ' + it.line.q + ' = ' + fmtTZS((Number(it.line.u) || 0) * it.line.q) + '</div></div>'
        + '<div class="ctrls">'
        + '<div class="stepper"><button data-act="cqminus" data-p="' + esc(it.line.p) + '" data-v="' + esc(it.line.v || '') + '" aria-label="-">−</button><span class="n">' + it.line.q + '</span><button data-act="cqplus" data-p="' + esc(it.line.p) + '" data-v="' + esc(it.line.v || '') + '" aria-label="+">+</button></div>'
        + '<button class="rm" data-act="cartrm" data-p="' + esc(it.line.p) + '" data-v="' + esc(it.line.v || '') + '">' + t('remove') + '</button>'
        + '<button class="btn-dark" data-act="checkoutline" data-p="' + esc(it.line.p) + '" data-v="' + esc(it.line.v || '') + '">' + t('cart_checkout') + '</button>'
        + '</div></div>';
    }
    html += '</div>';
  }
  html += '</div>'
    + '<div class="cart-summary" style="border:1px solid var(--hairline);border-radius:var(--radius);background:var(--surface);margin-bottom:40px">'
    + '<span>' + t('cart_total') + '</span><span class="tot">' + fmtTZS(tot) + '</span></div>'
    + '</div>';
  view.innerHTML = html;
}

function renderOrders() {
  const user = AUTH.currentUser;
  if (!user) {
    view.innerHTML = '<div class="container">' + emptyHtml(t('need_auth'), '', t('nav_signin')).replace('#/', '#/account') + '</div>';
    return;
  }
  view.innerHTML = '<div class="container">'
    + '<div class="headline-row"><a class="mini-link" href="#/account">← ' + t('back') + '</a>'
    + '<span class="section-title" style="margin:0">' + t('orders_my') + '</span></div>'
    + '<div class="order-list"><div class="skel" style="height:74px"></div><div class="skel" style="height:74px"></div></div>'
    + '</div>';
  let q = DB.collection('orders').where('buyerId', '==', user.uid).limit(50);
  q.get().then((snap) => {
    const orders = snap.docs.map((d) => d.data());
    orders.sort((a, b) => tsMillis(b.createdAt) - tsMillis(a.createdAt));
    const host = document.querySelector('.order-list');
    if (!host) return;
    if (!orders.length) { host.innerHTML = emptyHtml(t('my_orders_empty'), '', t('home_browse')); return; }
    host.innerHTML = orders.map(orderHtml).join('');
  }).catch(() => {
    const host = document.querySelector('.order-list');
    if (host) host.innerHTML = emptyHtml(t('err_generic'), '', t('home_browse'));
  });
}
function tsMillis(ts) {
  if (!ts) return 0;
  return ts.toDate ? ts.toDate().getTime() : new Date(ts).getTime();
}
function orderHtml(o) {
  const st = o.status || 'pending';
  const pill = PAY_STATES.has(st) ? 'done' : (BAD_STATES.has(st) ? 'bad' : 'wait');
  return '<a class="order-item" href="#/orders">'
    + '<div class="thumb">' + (o.productImage ? '<img src="' + esc(o.productImage) + '" alt="" onerror="this.remove()">' : '') + '</div>'
    + '<div class="mid"><div class="nm">' + esc(o.productName || 'Agizo') + '</div>'
    + '<div class="meta">' + t('order_id') + ' ' + esc(String(o.orderId || o.id).slice(0, 8)) + ' · ' + ts2date(o.createdAt) + '</div></div>'
    + '<div class="rt"><span class="amt">' + fmtTZS(o.totalAmount) + '</span>'
    + '<span class="pill ' + pill + '">' + esc((SV_T[lang].order_statuses[st] || st)) + '</span>'
    + '</div></a>';
}

function renderAccount() {
  setLang();
  const user = AUTH.currentUser;
  const openTab = document.getElementById('acctab') ? 'profile' : 'orders-default';
  if (!user) {
    renderAuthForm(document.getElementById('acctab') ? 'orders' : 'signin');
    return;
  }
  view.innerHTML = '<div class="container"><div class="account-grid">'
    + '<div class="profile-card">'
    + '<div class="avatar-lg">' + esc((user.displayName || user.email || 'S').slice(0, 1).toUpperCase()) + '</div>'
    + '<div class="nm">' + esc(user.displayName || 'Soko Vibe') + '</div>'
    + '<div class="em">' + esc(user.email || '') + '</div>'
    + '<a class="btn-wa btn-block" href="https://wa.me/255700000000?text=' + encodeURIComponent('Nahitaji msaada kwenye Soko Vibe') + '" target="_blank" rel="noopener">WhatsApp Msaada</a>'
    + '<button class="btn-outline btn-block" data-act="signout">' + t('signout') + '</button>'
    + '</div>'
    + '<div><div class="tabs">'
    + '<button class="tab active" data-act="tab" data-tab="orders">' + t('orders_my') + '</button>'
    + '<button class="tab" data-act="tab" data-tab="profile">Akaunti</button>'
    + '</div><div id="tabBody"></div></div>'
    + '</div></div>';
  switchTab(openTab === 'orders-default' ? 'orders' : openTab);
}

function switchTab(tab) {
  const tabs = document.querySelectorAll('.tab');
  tabs.forEach((tb) => tb.classList.toggle('active', tb.dataset.tab === tab));
  const body = document.getElementById('tabBody');
  if (!body) return;
  if (tab === 'orders') { body.innerHTML = '<div class="order-list" id="ordHere"></div>'; loadOrdersInto(body); }
  else body.innerHTML = profileEditHtml();
}

async function loadOrdersInto(host) {
  const user = AUTH.currentUser;
  if (!user) return;
  const slot = document.getElementById('ordHere');
  if (!slot) return;
  slot.innerHTML = '<div class="skel" style="height:74px"></div><div class="skel" style="height:74px"></div>';
  try {
    const snap = await DB.collection('orders').where('buyerId', '==', user.uid).limit(50).get();
    const orders = snap.docs.map((d) => d.data()).sort((a, b) => tsMillis(b.createdAt) - tsMillis(a.createdAt));
    slot.innerHTML = orders.length ? orders.map(orderHtml).join('')
      : emptyHtml(t('my_orders_empty'), '', t('home_browse'));
  } catch (_) {
    slot.innerHTML = emptyHtml(t('err_generic'), '', t('home_browse'));
  }
}

function profileEditHtml() {
  const user = AUTH.currentUser;
  return '<div class="form-card"><h2>' + t('profile') + '</h2>'
    + '<div class="field"><label>' + t('name') + '</label><input id="pName" value="' + esc(user.displayName || '') + '"></div>'
    + '<div class="field"><label>' + t('phone') + '</label><input id="pPhone" value="' + esc(user.phoneNumber || '') + '" placeholder="+255 7xx xxx xxx"></div>'
    + '<button class="btn-dark" data-act="saveProfile">Hifadhi</button>'
    + '</div>';
}

function renderAuthForm(mode) {
  const authMode = mode || 'signin';
  view.innerHTML = '<div class="container" style="padding-top:30px">'
    + '<div class="form-card"><h2>' + (authMode === 'signin' ? t('signin_title') : t('signup_title')) + '</h2>'
    + '<div class="error-box" id="authErr"></div>'
    + (authMode === 'signup' ? '<div class="field"><label>' + t('name') + '</label><input id="aName"></div>' : '')
    + '<div class="field"><label>' + t('email') + '</label><input id="aEmail" type="email" autocomplete="email"></div>'
    + (authMode === 'signup' ? '<div class="field"><label>' + t('phone') + '</label><input id="aPhone" placeholder="+255 7xx xxx xxx"></div>' : '')
    + '<div class="field"><label>' + t('password') + '</label><input id="aPass" type="password" autocomplete="current-password"></div>'
    + '<button class="btn-dark" id="authBtn">' + (authMode === 'signin' ? t('submit_signin') : t('submit_signup')) + '</button>'
    + '<div class="auth-switch">' + (authMode === 'signin'
      ? t('no_account') + ' <a href="#/account?mode=signup">' + t('submit_signup') + '</a>'
      : t('have_account') + ' <a href="#/account?mode=signin">' + t('submit_signin') + '</a>') + '</div>'
    + '</div></div>';
  const btn = document.getElementById('authBtn');
  btn.addEventListener('click', async () => {
    const email = document.getElementById('aEmail').value.trim();
    const pass = document.getElementById('aPass').value;
    const errBox = document.getElementById('authErr');
    errBox.classList.remove('show');
    try {
      if (authMode === 'signin') {
        await AUTH.signInWithEmailAndPassword(email, pass);
      } else {
        const name = document.getElementById('aName').value.trim();
        const phone = e164(document.getElementById('aPhone').value);
        const cred = await AUTH.createUserWithEmailAndPassword(email, pass);
        if (name) await cred.user.updateProfile({ displayName: name });
        await DB.collection('users').doc(cred.user.uid).set({
          name: name || email.split('@')[0],
          email: email,
          phone: phone,
          isAdmin: false,
          isSuspended: false,
          sellerBalance: 0,
          createdAt: firebase.firestore.FieldValue.serverTimestamp(),
        });
      }
      toast('✔ ' + (authMode === 'signin' ? t('submit_signin') : t('submit_signup')));
      refreshChip();
      renderAccount();
    } catch (e) {
      errBox.textContent = errMsg(e);
      errBox.classList.add('show');
    }
  });
}

function errMsg(e) {
  const m = String(e && e.message ? e.message : e);
  if (m.indexOf('wrong-password') >= 0 || m.indexOf('invalid-credential') >= 0) return 'Nenosiri si sahihi.';
  if (m.indexOf('user-not-found') >= 0) return 'Akaunti haipo.';
  if (m.indexOf('email-already-in-use') >= 0) return 'Barua pepe hii tayari iko.';
  if (m.indexOf('invalid-email') >= 0) return 'Barua pepe si sahihi.';
  if (m.indexOf('weak-password') >= 0) return 'Nenosiri ni fupi (angalau herufi 6).';
  return t('err_generic');
}

/* ---------- Checkout + payment ---------- */

function checkoutMeta(p, qty, variantId) {
  const v = variantId ? (p.variants || []).find((x) => x.id === variantId) : null;
  const unit = p.price + (v && Number(v.priceAdjustment) ? Number(v.priceAdjustment) : 0);
  return { unit: unit, lineTotal: unit * qty };
}

async function renderCheckout(id, qty, variantId) {
  setLang();
  const user = AUTH.currentUser;
  if (!user) {
    renderAuthForm('signin');
    toast(t('need_auth'));
    return;
  }
  view.innerHTML = '<div class="container" style="padding-top:24px"><div class="skel" style="height:420px"></div></div>';
  const p = await getProduct(id);
  if (!p) { view.innerHTML = emptyHtml(t('empty_filter'), '', t('home_browse')); return; }
  const { unit, lineTotal } = checkoutMeta(p, qty, variantId);
  const regions = SV_REGIONS.map((r) => '<option value="' + esc(r) + '">' + esc(r) + '</option>').join('');
  view.innerHTML = '<div class="container" style="max-width:760px;padding-top:20px">'
    + '<div class="headline-row"><a class="mini-link" href="#/p/' + encodeURIComponent(p.id) + '">← ' + t('back') + '</a>'
    + '<span class="section-title" style="margin:0">' + t('checkout_title') + '</span></div>'
    + '<div class="form-card" style="max-width:none">'
    + '<div class="cart-item" style="padding:0;border:none">'
    + '<div class="thumb">' + (p.images[0] ? '<img src="' + esc(p.images[0]) + '" alt="">' : '') + '</div>'
    + '<div class="mid"><div class="nm">' + esc(p.name) + '</div>'
    + '<div class="pr">' + fmtTZS(unit) + ' × ' + qty + ' = ' + fmtTZS(lineTotal) + '</div></div></div>'
    + '<div class="field"><label>' + t('phone') + '</label><input id="ckPhone" value="' + esc(user.phoneNumber || '') + '" placeholder="+255 7xx xxx xxx"></div>'
    + '<div class="field"><label>' + t('region') + '</label><select id="ckRegion"><option value="">—</option>' + regions + '</select></div>'
    + '<div class="field"><label>' + t('district') + '</label><select id="ckDistrict"><option value="">—</option></select></div>'
    + '<div class="field"><label>' + t('ward') + '</label><input id="ckWard"></div>'
    + '<div class="field"><label>' + t('street') + '</label><input id="ckStreet"></div>'
    + '<div class="field"><label>' + t('landmarks') + '</label><input id="ckLandmarks"></div>'
    + '<div class="form-note">' + t('fee_note') + '</div>'
    + '<button class="btn-dark btn-block" id="ckBtn">' + t('place_order') + ' · ' + fmtTZS(lineTotal) + '</button>'
    + '</div></div>';
  const regionSel = document.getElementById('ckRegion');
  const distSel = document.getElementById('ckDistrict');
  regionSel.addEventListener('change', () => {
    const ds = SV_DISTRICTS[regionSel.value] || [];
    distSel.innerHTML = '<option value="">—</option>' + ds.map((d) => '<option value="' + esc(d) + '">' + esc(d) + '</option>').join('');
  });
  document.getElementById('ckBtn').addEventListener('click', () => placeOrder(p, qty, variantId, lineTotal, unit));
}

async function placeOrder(p, qty, variantId, lineTotal, unit) {
  const user = AUTH.currentUser;
  if (!user) return;
  const phone = e164(document.getElementById('ckPhone').value);
  const region = document.getElementById('ckRegion').value;
  const district = document.getElementById('ckDistrict').value;
  const ward = document.getElementById('ckWard').value.trim();
  const street = document.getElementById('ckStreet').value.trim();
  const landmarks = document.getElementById('ckLandmarks').value.trim();
  const btn = document.getElementById('ckBtn');
  if (!phone || !region || !district || !street) { toast('Jaza namba ya simu, mkoa, wilaya na mtaa.'); return; }
  btn.disabled = true;
  btn.textContent = t('processing');
  try {
    const created = await apiPost('/api/orders/create', {
      buyerId: user.uid,
      buyerName: user.displayName || '',
      buyerPhone: phone,
      sellerId: p.sellerId,
      sellerName: p.sellerName,
      productId: p.id,
      productName: p.name,
      productImage: p.images[0] || '',
      productPrice: lineTotal,
      quantity: qty,
      variantId: variantId || null,
      unitPrice: unit,
      region: region,
      district: district,
      ward: ward,
      street: street,
      landmarks: landmarks,
      latitude: null,
      longitude: null,
      deliveryType: 'local',
    });
    if (!created || !created.success || !created.order || !created.order.orderId) throw new Error('Order creation failed');
    const orderId = created.order.orderId;
    localStorage.removeItem('sv_shop_cart');
    cart = readCart();
    refreshBadge();
    renderPaymentScreen(p, qty, variantId, lineTotal, unit, orderId, phone, user);
  } catch (e) {
    btn.disabled = false;
    btn.textContent = t('place_order');
    toast(errMsg(e));
  }
}

function renderPaymentScreen(p, qty, variantId, lineTotal, unit, orderId, phone, user) {
  setLang();
  payCtx = { orderId: orderId, attempts: 0, done: false };
  view.innerHTML = '<div class="container" style="padding-top:30px"><div class="status-card">'
    + '<div class="phone-pulse"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><rect x="7" y="2" width="10" height="20" rx="2"/><path d="M11 18h2"/></svg></div>'
    + '<h2 style="font-family:var(--font-display);font-weight:700">' + t('pay_wait') + '</h2>'
    + '<div class="section-muted" id="payN">' + fmtTZS(lineTotal) + ' · ' + esc(p.name) + '</div>'
    + '<div class="spinner" id="paySpin"></div>'
    + '<div id="payState" class="section-muted">' + t('pay_status_pending') + '…</div>'
    + '<div class="status-timeline" id="payTimeline"></div>'
    + '<button class="btn-outline" id="payRetry" style="display:none">' + t('pay_new') + '</button>'
    + '<a class="mini-link" href="#/orders">' + t('orders_my') + '</a>'
    + '</div></div>';
  const retryBtn = document.getElementById('payRetry');
  retryBtn.addEventListener('click', () => initPay(p, qty, variantId, lineTotal, unit, orderId, phone, user));
  initPay(p, qty, variantId, lineTotal, unit, orderId, phone, user);
  clearInterval(pollTimer);
  pollTimer = setInterval(() => pollOrder(orderId), 3000);
}

async function initPay(p, qty, variantId, lineTotal, unit, orderId, phone, user) {
  const retryBtn = document.getElementById('payRetry');
  const spin = document.getElementById('paySpin');
  const state = document.getElementById('payState');
  if (spin) spin.style.display = 'block';
  if (retryBtn) retryBtn.style.display = 'none';
  if (state) state.textContent = t('pay_status_pending') + '…';
  try {
    const data = await apiPost('/api/create-marketplace-payment-link', {
      productPrice: lineTotal,
      productName: p.name,
      productId: p.id,
      sellerId: p.sellerId,
      sellerName: p.sellerName,
      email: (user && user.email) || '',
      phone: phone,
      buyerId: user.uid,
      buyerName: user.displayName || '',
      deliveryType: 'local',
      paymentMethod: 'ussd_push',
      shippingCost: 0,
      existingTransactionId: orderId,
    });
    if (data && data.message) toast(data.message, 4000);
  } catch (e) {
    const stateEl = document.getElementById('payState');
    if (stateEl) stateEl.textContent = errMsg(e);
    if (retryBtn) retryBtn.style.display = 'inline-flex';
    if (spin) spin.style.display = 'none';
  }
}

async function pollOrder(orderId) {
  if (!payCtx || payCtx.orderId !== orderId || payCtx.done) return;
  let st = null;
  try {
    const data = await apiGet('/api/orders/' + encodeURIComponent(orderId) + '/status');
    st = (data && (data.status || (data.order && data.order.status) || (data.data && data.data.status))) || null;
  } catch (_) { /* silent */ }
  if (!st) return;
  payCtx.attempts++;
  if (PAY_STATES.has(st)) return finishPay(st, true);
  if (BAD_STATES.has(st)) return finishPay(st, false);
  if (payCtx.attempts > 120) return finishPay(null, false);
}

function finishPay(st, ok) {
  if (!payCtx || payCtx.done) return;
  payCtx.done = true;
  clearInterval(pollTimer);
  const state = document.getElementById('payState');
  const spin = document.getElementById('paySpin');
  const retryBtn = document.getElementById('payRetry');
  const tl = document.getElementById('payTimeline');
  if (spin) spin.style.display = 'none';
  if (ok && state) {
    state.textContent = '✔ ' + t('pay_status_paid');
    tl.innerHTML = SV_STATUS_ORDER.map((s) =>
      '<div class="st' + (PAY_STATES.has(s) || PAY_STATES.has(st) ? ' done' : '') + '">'
      + '<span class="tick"></span>' + esc(SV_T[lang].order_statuses[s] || s) + '</div>').join('');
    if (retryBtn) retryBtn.style.display = 'none';
    localStorage.removeItem('sv_shop_cart');
    cart = readCart();
    refreshBadge();
  } else {
    if (state) state.textContent = '✕ ' + (st ? esc(SV_T[lang].order_statuses[st] || st) : t('pay_failed'));
    if (retryBtn) retryBtn.style.display = 'inline-flex';
  }
}

/* ---------- Router + actions ---------- */

const ACTIONS = {
  loadmore: () => loadPageInto(),
  img: () => {},
  qplus: () => {},
  qminus: () => {},
  addcart: () => {},
  buynow: () => {},
  cqplus: (el) => { cartBump(el, 1); },
  cqminus: (el) => { cartBump(el, -1); },
  cartrm: (el) => {
    cart = cart.filter((i) => !(i.p === el.dataset.p && (i.v || '') === el.dataset.v));
    saveCart(); refreshBadge(); renderCart();
  },
  checkoutline: (el) => {
    const line = cart.find((i) => i.p === el.dataset.p && (i.v || '') === el.dataset.v);
    if (line) location.hash = '#/checkout?p=' + encodeURIComponent(line.p) + '&q=' + line.q + (line.v ? '&v=' + encodeURIComponent(line.v) : '');
  },
  signout: () => { AUTH.signOut(); refreshChip(); renderHome(); },
  tab: (el) => switchTab(el.dataset.tab),
  saveProfile: async () => {
    const user = AUTH.currentUser;
    if (!user) return;
    const name = document.getElementById('pName').value.trim();
    const phone = e164(document.getElementById('pPhone').value);
    try {
      if (name && name !== user.displayName) await user.updateProfile({ displayName: name });
      await DB.collection('users').doc(user.uid).update({ name: name, phone: phone });
      toast('✔ Imesasishwa');
      refreshChip();
      renderAccount();
    } catch (e) { toast(errMsg(e)); }
  },
};

function cartBump(el, d) {
  const line = cart.find((i) => i.p === el.dataset.p && (i.v || '') === el.dataset.v);
  if (!line) return;
  line.q = Math.max(1, Number(line.q || 0) + d);
  saveCart(); refreshBadge(); renderCart();
}

function paramsOf() {
  const out = {};
  const i = location.hash.indexOf('?');
  if (i < 0) return out;
  new URLSearchParams(location.hash.slice(i + 1)).forEach((v, k) => {
    try { out[k] = decodeURIComponent(v); } catch (_) { out[k] = v; }
  });
  return out;
}

function route() {
  clearInterval(pollTimer); pollTimer = null;
  payCtx = null;
  closeMenu();
  const h = location.hash.replace(/^#\/?/, '');
  const path = h.split('?')[0];
  const seg = path.split('/').filter(Boolean);
  const q = paramsOf();
  if (seg.length === 0) return renderHome();
  if (seg[0] === 'p' && seg[1]) return renderProduct(seg[1]);
  if (seg[0] === 'c' && seg[1]) return renderCategory(decodeURIComponent(seg[1]));
  if (seg[0] === 'cart') return renderCart();
  if (seg[0] === 'checkout' && q.p) return renderCheckout(q.p, Number(q.q) || 1, q.v || null);
  if (seg[0] === 'search') return renderSearch(q.q || '');
  if (seg[0] === 'orders') return renderOrders();
  if (seg[0] === 'account') { if (q.mode) renderAuthForm(q.mode === 'signup' ? 'signup' : 'signin'); else renderAccount(); return; }
  return renderHome();
}

function closeMenu() {
  const mm = document.getElementById('mobileMenu');
  if (mm) mm.classList.remove('open');
}

function refreshChip() {
  const el = document.getElementById('navAccount');
  const mob = document.getElementById('mobAccount');
  const user = AUTH.currentUser;
  const label = user ? esc((user.displayName || user.email || 'Akaunti')) : (t('nav_signin'));
  if (el) { el.textContent = label; }
  if (mob) mob.textContent = user ? t('profile') : t('nav_signin');
}

/* ---------- Init wiring ---------- */

document.addEventListener('click', (e) => {
  const el = e.target.closest('[data-act]');
  if (!el) return;
  const fn = ACTIONS[el.dataset.act];
  if (fn) fn(el, e);
});

document.getElementById('searchForm').addEventListener('submit', (e) => {
  e.preventDefault();
  const q = document.getElementById('searchInput').value.trim();
  if (!q) return;
  location.hash = '#/search?q=' + encodeURIComponent(q);
});

document.getElementById('themeBtn').addEventListener('click', () => {
  theme = theme === 'dark' ? 'light' : 'dark';
  setTheme();
  updateThemeIcon();
});

function updateThemeIcon() {
  const svg = document.getElementById('themeIco');
  if (!svg) return;
  svg.innerHTML = theme === 'dark'
    ? '<circle cx="12" cy="12" r="4"/><path d="M12 2v2m0 16v2M4.9 4.9l1.4 1.4m11.4 11.4 1.4 1.4M2 12h2m16 0h2M4.9 19.1l1.4-1.4m11.4-11.4 1.4-1.4"/>'
    : '<path d="M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9Z"/>';
}

document.getElementById('menuBtn').addEventListener('click', () => {
  document.getElementById('mobileMenu').classList.toggle('open');
});

AUTH.onAuthStateChanged((user) => {
  refreshChip();
  if (user) {
    const now = firebase.firestore.Timestamp.now();
    DB.collection('user_sessions').doc(user.uid).set({
      uid: user.uid,
      lastActive: now,
      platform: 'web',
    }, { merge: true }).catch(() => {});
  }
});

window.addEventListener('hashchange', route);

(function init() {
  setTheme();
  setLang();
  updateThemeIcon();
  const si = document.getElementById('searchInput');
  si.placeholder = t('search_ph');
  document.title = 'Soko Vibe — Duka';
  refreshBadge();
  refreshChip();
  route();
})();