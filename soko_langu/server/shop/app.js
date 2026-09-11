/* Soko Vibe Duka — browser app.
   Single hash-router SPA. Reads the products collection directly from
   Firestore (same project as the app), mirrors the app's flat one-product
   order flow against the legacy /api orders + ClickPesa endpoints.
   Market-style UI: big search + category select, left mega category menu,
   hero slider, quick add-to-cart cards, app-like checkout wizard with
   escrow status timeline, bottom app-style navigation on mobile. */

'use strict';

/* ---------- Boot ---------- */

const FB_CONFIG = {
  apiKey: 'AIzaSyBrh5W9VwbC3qTtSTm8LJbTQeYufRGil5s',
  authDomain: 'sokonimoko-8c171-a8d14.firebaseapp.com',
  projectId: 'sokonimoko-8c171-a8d14',
  appId: '1:344682929526:web:5d3732578d6f012ac26e57',
  messagingSenderId: '344682929526',
};

if (window.firebase && firebase.apps && firebase.apps.length === 0) firebase.initializeApp(FB_CONFIG);

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
let heroIdx = 0;
let heroTimer = null;

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
  const d = ts.toDate ? ts.toDate() : new Date(ts);
  if (isNaN(d)) return '';
  return d.toLocaleDateString(lang === 'sw' ? 'sw-TZ' : 'en-GB', { day: '2-digit', month: 'short', year: '2-digit' }) + ' ' +
    d.toLocaleTimeString(lang === 'sw' ? 'sw-TZ' : 'en-GB', { hour: '2-digit', minute: '2-digit' });
}

function tsMillis(ts) {
  if (!ts) return 0;
  return ts.toDate ? ts.toDate().getTime() : new Date(ts).getTime();
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
  const n = cartQty();
  if (b) { b.textContent = String(n); b.classList.toggle('show', n > 0); }
  const dot = document.getElementById('bnBadge');
  if (dot) dot.hidden = n <= 0;
}

/* ---------- Wishlist (localStorage-backed) ---------- */

let wish = readWish();
function readWish() { try { return JSON.parse(localStorage.getItem('sv_shop_wish') || '[]'); } catch (_) { return []; } }
function saveWish() { localStorage.setItem('sv_shop_wish', JSON.stringify(wish)); }
function wishHas(id) { return wish.indexOf(id) >= 0; }
function refreshWishBadge() {
  const b = document.getElementById('wishBadge');
  if (b) { b.textContent = String(wish.length); b.hidden = wish.length === 0; }
}
function toggleWish(id) {
  const k = wish.indexOf(id);
  const added = k < 0;
  if (added) wish.push(id); else wish.splice(k, 1);
  saveWish();
  refreshWishBadge();
  toast(added ? '✔ ' + t('wish_saved') : '✕ ' + t('wish_removed'));
  return added;
}

function fallbackCopy(text, done) {
  const ta = document.createElement('textarea');
  ta.value = text;
  ta.style.position = 'fixed';
  ta.style.opacity = '0';
  document.body.appendChild(ta);
  ta.select();
  try { document.execCommand('copy'); done(); } catch (_) {}
  document.body.removeChild(ta);
}

/* ---------- Guest checkout context ---------- */

function guestCtx() {
  try { const g = JSON.parse(localStorage.getItem('sv_shop_guest') || 'null'); return (g && g.buyerId) ? g : null; } catch (_) { return null; }
}
function setGuest(g) {
  if (g && g.buyerId) localStorage.setItem('sv_shop_guest', JSON.stringify(g));
  else localStorage.removeItem('sv_shop_guest');
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
  lang = localStorage.getItem('sv_shop_lang') || ((navigator.language || 'sw').startsWith('en') ? 'en' : 'sw');
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
  const g = guestCtx();
  const qs = (!user && g)
    ? (path.indexOf('?') >= 0 ? '&' : '?') + 'buyerId=' + encodeURIComponent(g.buyerId) + '&phone=' + encodeURIComponent(g.phone || '')
    : '';
  const res = await fetch(path + qs, { headers: apiHeaders(token) });
  let data = {};
  try { data = await res.json(); } catch (_) {}
  if (!res.ok) throw new Error(data.error || 'HTTP ' + res.status);
  return data;
}

/* fetch with cold-start retries (Render free tier wakes ~15-60s) */
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
    sellerKycApproved: !!d.sellerKycApproved,
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

function featured(p) {
  if (!p.isFeatured) return false;
  const until = p.featuredUntil && p.featuredUntil.toDate ? p.featuredUntil.toDate() : (p.featuredUntil ? new Date(p.featuredUntil) : null);
  return !until || until > new Date();
}

function discount(p) {
  if (p.isWholesale && p.wholesaleTiers && p.wholesaleTiers.length) {
    const tier = Number(p.wholesaleTiers[0].pricePerUnit) || 0;
    if (tier > 0 && tier < p.price) return Math.round((1 - tier / p.price) * 100);
  }
  return null;
}

function sortFeed(list) {
  const RANK = { gold: 3, silver: 2, bronze: 1 };
  return list.slice().sort((a, b) => {
    const ba = boosted(a) ? (RANK[boosted(a)] || 0) : 0;
    const bb = boosted(b) ? (RANK[boosted(b)] || 0) : 0;
    if (ba !== bb) return bb - ba;
    return tsMillis(b.createdAt) - tsMillis(a.createdAt);
  });
}
function catSort(list) {
  return list.slice().sort((a, b) => tsMillis(b.createdAt) - tsMillis(a.createdAt));
}

const productCache = {};
async function getProduct(id) {
  if (!id) return null;
  if (productCache[id]) return productCache[id];
  try {
    const snap = await DB.collection('products').doc(id).get();
    if (!snap.exists) return null;
    productCache[id] = norm(snap);
  } catch (_) { return null; }
  return productCache[id];
}

/* ---------- Conservative selectors ---------- */

function $(sel, root) { return (root || document).querySelector(sel); }
function $all(sel, root) { return Array.prototype.slice.call((root || document).querySelectorAll(sel)); }

/* ---------- Brand / chrome builders ---------- */

function stars(p, size) {
  const r = Number(p.rating || 0).toFixed(1);
  return '<span class="stars"' + (size ? ' style="font-size:' + size + '"' : '') + '>★ <b>' + r + '</b>'
    + (p.reviewCount ? '<b class="sc">(' + (p.reviewCount || 0) + ')</b>' : '') + '</span>';
}

const SELLER_SEAL = '<span class="vbadge"><svg width="9" height="9" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6L9 17l-5-5"/></svg>Verified</span>';

/* ---------- Card markup (div-based, quick actions) ---------- */

function cardHtml(p) {
  const img = p.images[0];
  const bo = boosted(p);
  const ft = featured(p);
  const dc = discount(p);
  const soldout = p.stock <= 0;
  const flag = (ft ? '<span class="flag feat">' + esc(t('feat_until')) + '</span>' : '')
    + (bo ? '<span class="flag boost">' + esc(bo) + '</span>' : '');
  const dcHtml = dc ? '<span class="disc">−' + dc + '%</span>' : '';
  const soldov = soldout ? '<div class="sold-ov">' + esc(t('soldout_ov')) + '</div>' : '';
  const whstruck = p.isWholesale && p.wholesaleTiers && p.wholesaleTiers.length
    ? '<span class="muted">' + fmtTZS(p.wholesaleTiers[0].pricePerUnit) + '</span>' : '';
  const price = '<span class="pr">' + fmtTZS(p.price) + whstruck + '</span>';
  const verified = p.sellerKycApproved ? '<span class="verif" title="Muuzaji aliyethibitishwa (KYC)"><svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6L9 17l-5-5"/></svg></span>' : '';
  const gnew = (p.condition || 'new') === 'new' ? '<span class="tag-new">· ' + esc(t('cond_new')) + '</span>' : '';
  const starsHtml = p.rating > 0
    ? '<span class="stars" title="' + p.rating + ' / 5">★ <b>' + Number(p.rating).toFixed(1) + '</b><b class="sc">(' + (p.reviewCount || 0) + ')</b></span>'
    : '<span class="stars mut">★</span>';
  const foot = soldout
    ? '<span class="soldnote">' + esc(t('out_stock')) + '</span>'
    : '<button class="q-btn q-add" data-act="qaddcart" data-p="' + encodeURIComponent(p.id) + '">'
      + '<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><circle cx="8" cy="21" r="1"/><circle cx="19" cy="21" r="1"/><path d="M2.05 2.05h2l2.66 12.42a2 2 0 0 0 2 1.58h9.78a2 2 0 0 0 1.95-1.57l1.65-7.43H5.12"/></svg>'
      + esc(t('add_cart')) + '</button>'
      + '<button class="q-btn q-buy" data-act="qbuynow" data-p="' + encodeURIComponent(p.id) + '">' + esc(t('buy_now')) + '</button>';
  const favCls = wishHas(p.id) ? ' fav onfav' : ' fav';
  return '<div class="card" data-act="openprod" data-p="' + encodeURIComponent(p.id) + '" role="link" tabindex="0" aria-label="' + esc(p.name) + '">'
    + '<div class="thumb">' + flag + dcHtml
    + '<button class="' + favCls + '" data-act="fav" data-p="' + encodeURIComponent(p.id) + '" aria-label="' + esc(t('nav_wish')) + '" type="button">'
    + '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 14c1.49-1.46 3-3.21 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.76 0-3 .5-4.5 2-1.5-1.5-2.74-2-4.5-2A5.5 5.5 0 0 0 2 8.5c0 2.3 1.5 4.05 3 5.5l7 7Z"/></svg></button>'
    + (img
      ? '<img loading="lazy" src="' + esc(img) + '" alt="' + esc(p.name) + '" onerror="this.parentElement.classList.add(\'badimg\');this.remove()">'
      : '<div class="ph">SOKO</div>')
    + soldov
    + '</div>'
    + '<div class="body">'
    + '<span class="cat">' + esc(p.category) + '</span>'
    + '<span class="nm">' + esc(p.name) + verified + gnew + '</span>'
    + price
    + '<div class="meta">' + starsHtml + '<span class="soldct">' + (p.soldCount || 0) + ' ' + esc(t('sold')) + '</span></div>'
    + '<div class="foot">' + foot + '</div>'
    + '</div></div>';
}

function skelGrid(n) {
  let s = '';
  for (let i = 0; i < n; i++) {
    s += '<div class="card"><div class="skel" style="aspect-ratio:1/1"></div>'
      + '<div class="body"><div class="skel" style="height:10px;width:34%"></div>'
      + '<div class="skel" style="height:13px;width:86%;margin-top:6px"></div>'
      + '<div class="skel" style="height:16px;width:42%;margin-top:8px"></div>'
      + '<div class="skel cart-sk" style="margin-top:10px"></div></div></div>';
  }
  return s;
}

const emptyHtml = (msg, sub, cta) => '<div class="empty-state"><div class="big">' + esc(msg) + '</div>'
  + (sub ? '<p>' + esc(sub) + '</p>' : '')
  + (cta ? '<a class="btn-outline" href="#/">' + esc(cta) + '</a>' : '')
  + '</div>';

/* ---------- Sidebar mega menu + search select + drawer ---------- */

function activeCat() { return (Feed.mode && Feed.mode.cat) || ''; }

function browseCats() {
  const extra = [];
  for (const p of Feed.list) {
    const c = p.category;
    if (c && SV_CATEGORIES.indexOf(c) < 0 && extra.indexOf(c) < 0) extra.push(c);
  }
  return SV_CATEGORIES.concat(extra);
}

function catTokens(s) {
  return String(s || '').toLowerCase().replace(/&/g, ' ').split(/[^a-z0-9à-ž]+/).filter((w) => w.length >= 4);
}

function catMatch(p, cat) {
  if (!cat) return true;
  const pc = (p.category || '').trim();
  if (pc === cat) return true;
  if ((p.subcategory || '').toLowerCase() === cat.toLowerCase()) return true;
  const have = new Set(catTokens(pc));
  return catTokens(cat).some((w) => have.has(w));
}

function buildCats() {
  const side = document.getElementById('sideCatList');
  const drawer = document.getElementById('catList');
  const sel = document.getElementById('catSelect');
  if (side) {
    side.innerHTML = '<div class="side-list">' + browseCats().map((c) => catSideItem(c)).join('') + '</div>';
  }
  if (drawer) {
    drawer.innerHTML = '<div class="side-list">' + browseCats().map((c) => catSideItem(c, true)).join('') + '</div>';
  }
  if (sel) {
    const keep = sel.value;
    sel.innerHTML = '<option value="">Kategoria zote</option>'
      + browseCats().map((c) => '<option value="' + esc(c) + '">' + esc(c) + '</option>').join('');
    sel.value = keep;
  }
  paintActiveCat();
}

function catSideItem(c, drawerMode) {
  const subs = SV_SUBCATS[c] || [];
  const active = c === activeCat();
  const panel = subs.length && !drawerMode ? '<div class="cat-panel"><h4>' + esc(c) + '</h4>'
    + subs.map((s) => '<a href="#/c/' + encodeURIComponent(c) + '" data-navsub>' + esc(s) + '</a>').join('')
    + '<a class="view-all" href="#/c/' + encodeURIComponent(c) + '">' + t('view_detail') + ' →</a></div>' : '';
  return '<div class="side-item' + (subs.length ? ' has-subs' : '') + (active ? ' active' : '') + '" data-cat="' + esc(c) + '">'
    + '<a href="#/c/' + encodeURIComponent(c) + '"' + (drawerMode && subs.length ? ' data-act="dsub" data-cat="' + esc(c) + '"' : '') + '>'
    + '<span>' + esc(c) + '</span><span class="caret">›</span></a>' + panel + '</div>';
}

function paintActiveCat() {
  const c = activeCat();
  $all('.side-item').forEach((it) => it.classList.toggle('active', it.dataset.cat === c));
}

function openCats() {
  const d = document.getElementById('catDrawer');
  const s = document.getElementById('scrim');
  const t = document.getElementById('catToggle');
  if (d) { d.hidden = false; requestAnimationFrame(() => d.classList.add('open')); }
  if (s) s.hidden = false;
  if (t) t.setAttribute('aria-expanded', 'true');
  fillDrawerSub('');
}

function closeCats() {
  const d = document.getElementById('catDrawer');
  const s = document.getElementById('scrim');
  const t = document.getElementById('catToggle');
  if (d) d.classList.remove('open');
  if (s) s.hidden = true;
  if (t) t.setAttribute('aria-expanded', 'false');
}

function fillDrawerSub(cat) {
  const host = document.getElementById('catSub');
  if (!host) return;
  const subs = SV_SUBCATS[cat] || [];
  host.innerHTML = subs.length
    ? '<h4>' + esc(cat) + '</h4>' + subs.map((s) => '<a href="#/c/' + encodeURIComponent(cat) + '">' + esc(s) + '</a>').join('')
    + '<a href="#/c/' + encodeURIComponent(cat) + '" style="font-weight:700;color:var(--ink)">' + t('view_detail') + ' →</a>'
    : '';
}

/* ---------- Hero slider ---------- */

const SLIDES = [
  {
    k: 'Escrow Protected', title: 'Lipa salama kwa escrow kupitia ClickPesa',
    p: 'Fedha zako hushikiliwa hadi uthibitishe kupokea bidhaa yako. Hakuna hatari — unalipa unachokipata.',
    cta: 'Vinjari bidhaa', href: '#/', etch: 'SOKO', dark: true,
  },
  {
    k: 'Verified Sellers', title: 'Wauzaji waliothibitishwa Tanzania',
    p: 'Kila muuzaji hupitia uthibitisho (KYC). Mazungumzo moja kwa moja, usafirishaji nchi nzima.',
    cta: 'Mawasiliano ya muuzaji', href: '#/c/Services', etch: 'KYC', dark: false,
  },
  {
    k: 'Wholesale Deals', title: 'Bei za jumla kwa wafanyabiashara',
    p: 'Viwango vya bei kwa wingi, na malipo ya TZS. Boost bidhaa zako ili zionekane zaidi.',
    cta: 'Angalia jumla', href: '#/c/Agriculture', etch: 'TZS', dark: true,
  },
];

function buildHero() {
  const slides = document.getElementById('heroSlides');
  const dots = document.getElementById('slDots');
  if (!slides) return;
  slides.innerHTML = SLIDES.map((s, i) => '<div class="slide' + (s.dark ? ' dark' : '') + '" data-i="' + i + '" style="background:' + (s.dark ? 'var(--ink)' : 'var(--surface)') + '">'
    + '<div class="slide-copy"><span class="k">' + esc(s.k) + '</span>'
    + '<h3>' + esc(s.title) + '</h3>'
    + '<p class="p">' + esc(s.p) + '</p>'
    + '<a class="scap" href="' + s.href + '">' + esc(s.cta) + '</a></div>'
    + '<span class="slide-etch">' + esc(s.etch) + '</span>'
    + '</div>').join('');
  if (dots) {
    dots.innerHTML = SLIDES.map((s, i) => '<i data-i="' + i + '"' + (i === 0 ? ' class="on"' : '') + '></i>').join('');
  }
  setHeroIndex(0);
  if (SLIDES.length > 1) {
    clearInterval(heroTimer);
    heroTimer = setInterval(() => setHeroIndex(heroIdx + 1), 6500);
  }
}

function setHeroIndex(i) {
  const n = SLIDES.length;
  if (!n) return;
  heroIdx = ((i % n) + n) % n;
  const track = document.getElementById('heroSlides');
  if (track) track.style.transform = 'translateX(-' + heroIdx * 100 + '%)';
  $all('.sl-dots i').forEach((d, k) => d.classList.toggle('on', k === heroIdx));
}

function setHero(on) {
  const hero = document.getElementById('heroSlider');
  if (hero) hero.style.display = on ? '' : 'none';
}

/* ---------- Feed region (home / category / search) ---------- */

function feedRegion(title, sub, chipsHtml, extraHtml) {
  return '<div class="feed-head"><div class="f-title"><h2>' + esc(title) + '</h2>'
    + '<small>' + esc(sub || '') + '</small></div>'
    + '<div class="f-utils"><select class="sort-sel" id="sortSel" data-act="sort">'
    + '<option value="new">' + t('home_new') + '</option>'
    + '<option value="price-up">Bei ↑</option><option value="price-dn">Bei ↓</option></select></div></div>'
    + (chipsHtml || '')
    + (extraHtml || '')
    + '<div class="grid" id="feedGrid">' + skelGrid(8) + '</div>'
    + '<div id="sentinel" style="height:1px"></div>'
    + '<div class="center mt24"><button class="btn-outline" id="moreBtn" data-act="loadmore" style="display:none">' + t('load_more') + '</button></div>';
}

function chipsFor(active) {
  return '<div class="chips"><a class="chip' + (!active ? ' active' : '') + '" href="#/">' + t('all') + '</a>'
    + browseCats().map((c) => '<a class="chip' + (c === active ? ' active' : '') + '" href="#/c/' + encodeURIComponent(c) + '">' + esc(c) + '</a>').join('')
    + '</div>';
}

const Feed = { list: [], cursor: null, done: false, loading: false, mode: { kind: 'all' }, sort: 'new' };

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
  if (Feed.mode.kind === 'category') {
    return catSort(list.filter((p) => catMatch(p, Feed.mode.cat)));
  }
  if (Feed.mode.kind === 'query') {
    const q = String(Feed.mode.q || '').toLowerCase();
    return catSort(list.filter((p) => {
      const hit = !q || (p.name || '').toLowerCase().indexOf(q) >= 0 || (p.brand || '').toLowerCase().indexOf(q) >= 0;
      if (!hit) return false;
      if (Feed.mode.c) return catMatch(p, Feed.mode.c);
      return true;
    }));
  }
  return sortFeed(list);
}

function applySort(list) {
  if (Feed.sort === 'price-up') return list.slice().sort((a, b) => a.price - b.price);
  if (Feed.sort === 'price-dn') return list.slice().sort((a, b) => b.price - a.price);
  return list;
}

function renderFeed(errFlag) {
  const host = document.getElementById('feedGrid');
  const sent = document.getElementById('sentinel');
  if (!host) return;
  if (errFlag && !Feed.list.length) {
    host.innerHTML = emptyHtml(t('err_generic'), '', t('home_browse'));
    if (sent) sent.style.display = 'none';
    document.getElementById('moreBtn') && (document.getElementById('moreBtn').style.display = 'none');
    return;
  }
  const list = applySort(filterForMode());
  if (!list.length && !Feed.loading) {
    host.innerHTML = emptyHtml(t('empty_filter'), Feed.mode.kind === 'category' ? Feed.mode.cat : (Feed.mode.q || ''), t('home_browse'));
    if (sent) sent.style.display = 'none';
    const moreBtn = document.getElementById('moreBtn');
    if (moreBtn) moreBtn.style.display = 'none';
    return;
  }
  host.innerHTML = list.map(cardHtml).join('') + (Feed.loading && list.length === 0 ? skelGrid(8) : '');
  if (sent) sent.style.display = Feed.done ? 'none' : 'block';
  const moreBtn = document.getElementById('moreBtn');
  if (moreBtn) moreBtn.style.display = Feed.done || errFlag ? 'none' : 'inline-flex';
  const sel = document.getElementById('sortSel');
  if (sel) sel.value = Feed.sort;
  buildCats();
  const chipsHost = document.querySelector('.chips');
  if (chipsHost) {
    const activeChip = Feed.mode.kind === 'category' ? Feed.mode.cat : (Feed.mode.kind === 'query' ? (Feed.mode.c || '') : '');
    chipsHost.innerHTML = chipsFor(activeChip);
  }
}

function sortFeedView(v) {
  Feed.sort = v;
  renderFeed();
}

/* ---------- Browse screens ---------- */

async function renderHome() {
  setLang();
  Feed.idx = PAGE;
  Feed.mode = { kind: 'all' };
  setHero(true);
  view.innerHTML = feedRegion(t('feed_new'), t('home_hero_sub'), chipsFor(''));
  paintActiveCat();
  const si = document.getElementById('searchInput');
  if (si) si.value = '';
  const sel = document.getElementById('catSelect');
  if (sel) sel.value = '';
  if (Feed.list.length) { renderFeed(); return; }
  await loadPageInto();
}

async function renderCategory(cat) {
  setLang();
  Feed.idx = PAGE;
  Feed.mode = { kind: 'category', cat: cat };
  setHero(true);
  view.innerHTML = feedRegion(esc(cat), '', chipsFor(cat));
  paintActiveCat();
  const sel = document.getElementById('catSelect');
  if (sel) sel.value = cat;
  if (Feed.list.length) { renderFeed(); return; }
  await loadPageInto();
}

async function renderSearch(q, cat) {
  setLang();
  Feed.mode = { kind: 'query', q: q || '', c: cat || '' };
  setHero(true);
  const title = q ? '"' + q + '"' : (cat || t('feed_all'));
  view.innerHTML = feedRegion(title, '', chipsFor(cat || ''), '');
  const host = document.getElementById('feedGrid');
  if (!host) return;
  const sel = document.getElementById('catSelect');
  if (sel) sel.value = cat || '';
  if (!Feed.list.length) await loadPageInto();
  const ql = String(q || '').toLowerCase();
  const hits = Feed.list.filter((p) => {
    const hit = !ql || (p.name || '').toLowerCase().indexOf(ql) >= 0 || (p.brand || '').toLowerCase().indexOf(ql) >= 0;
    if (!hit) return false;
    if (cat) return catMatch(p, cat);
    return true;
  });
  host.innerHTML = hits.length ? hits.map(cardHtml).join('') : emptyHtml(t('empty_filter'), q || cat, t('home_browse'));
  const sent = document.getElementById('sentinel');
  if (sent) sent.style.display = 'none';
  const moreBtn = document.getElementById('moreBtn');
  if (moreBtn) moreBtn.style.display = 'none';
}

/* ---------- Product detail ---------- */

let __pQtyHandler = null;

async function renderProduct(id) {
  setLang();
  setHero(false);
  if (__pQtyHandler) { document.removeEventListener('click', __pQtyHandler); __pQtyHandler = null; }
  view.innerHTML = '<div class="container-wide"><div class="skel" style="height:420px;margin-top:22px"></div></div>';
  const p = await getProduct(id);
  if (!p) {
    view.innerHTML = '<div class="container-wide">' + emptyHtml(t('empty_filter'), '', t('home_browse')) + '</div>';
    return;
  }
  const bo = boosted(p);
  const soldout = p.stock <= 0;
const mainImg = p.images[0] || '';
    const mainImgHtml = (typeof window.SV !== 'undefined' && window.SV.image && window.SV.image.img)
      ? window.SV.image.img(mainImg, p.name, { size: 'large', ratio: '4 / 3', style: 'width:100%', class: 'ss-cover' })
      : '<div class="main"><img id="mainImg" src="' + esc(mainImg) + '" alt="' + esc(p.name) + '" onerror="this.replaceWith(Object.assign(document.createElement(\'div\'),{className:\'ph\',textContent:\'SOKO\'}))"></div>';
    const thumbs = p.images.slice(1, 6).map((u, i) =>
      '<button data-act="img" data-gi="' + i + '">'
      + (window.SV && window.SV.image ? window.SV.image.thumb(u, i, i === 0) : '<img src="' + esc(u) + '" alt="" onerror="this.remove()">')
      + '</button>').join('');
    const attrs = Object.entries(p.attributes || {}).slice(0, 8).map(([k, v]) => '<tr><td>' + esc(k) + '</td><td>' + esc(v) + '</td></tr>').join('');
  const tiers = p.wholesaleTiers && p.wholesaleTiers.length
    ? '<div class="desc mt24"><h3>Jumla (wholesale)</h3><table class="attrs-table"><tr><td>Idadi</td><td>Bei kwa kipande</td></tr>'
      + p.wholesaleTiers.map((ti) => '<tr><td>' + esc(ti.minQuantity) + '+</td><td>' + fmtTZS(ti.pricePerUnit) + '</td></tr>').join('')
      + '</table></div>' : '';
  const variants = p.variants && p.variants.length
    ? '<div class="field mt16"><label>' + t('variants') + '</label><select id="variantSel">'
      + p.variants.map((v, i) => '<option value="' + esc(v.id) + '" data-adj="' + (Number(v.priceAdjustment) || 0) + '" data-stock="' + (Number(v.stock) != null ? Number(v.stock) : p.stock) + '">' + esc(v.name + (v.value ? ' — ' + v.value : '')) + ' (+' + fmtTZS(Number(v.priceAdjustment) || 0) + ')' + '</option>').join('')
      + '</select></div>' : '';
  const stockTxt = soldout
    ? '<span class="tag stock" style="color:var(--bad)">' + t('out_stock') + '</span>'
    : '<span class="tag stock">' + t('in_stock') + ': ' + p.stock + ' ' + esc(p.unit) + '</span>';

  view.innerHTML = '<div class="container-wide"><div class="detail">'
    + '<div class="gallery">'
      + mainImgHtml
      + (thumbs ? '<div class="thumbs">' + thumbs + '</div>' : '')
      + '</div>'
    + '<div class="dinfo">'
    + '<span class="crumb">' + esc(p.category) + (p.subcategory ? ' / ' + esc(p.subcategory) : '') + '</span>'
    + '<h1>' + esc(p.name) + '</h1>'
    + '<div class="rating-line">' + (p.rating > 0 ? stars(p, '14px') : '<span>Hakuna tathmini</span>')
    + '<span class="section-muted">' + (p.soldCount || 0) + ' ' + esc(t('sold')) + '</span>'
    + (featured(p) ? '<span class="tag feat-tag">' + esc(t('feat_until')) + '</span>' : '')
    + '<span class="loc"><svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 10c0 6-8 12-8 12s-8-6-8-12a8 8 0 0 1 16 0Z"/><circle cx="12" cy="10" r="3"/></svg>' + esc(p.location || 'Tanzania') + (p.district ? ' · ' + esc(p.district) : '') + '</span></div>'
    + '<div class="price" id="priceNow">' + fmtTZS(p.price) + '</div>'
    + '<div class="tags">' + stockTxt
    + '<span class="tag">' + esc(p.condition) + '</span>'
    + (p.brand ? '<span class="tag">' + esc(p.brand) + '</span>' : '')
    + (bo ? '<span class="tag" style="border-color:var(--accent);color:var(--good)">' + esc(bo) + '</span>' : '')
    + '</div>'
    + variants
    + '<div class="picker"><span class="section-muted">' + t('qty') + ':</span>'
    + '<div class="stepper"><button type="button" data-act="qminus" aria-label="-">−</button><span class="n" id="qtyN">1</span><button type="button" data-act="qplus" aria-label="+">+</button></div>'
    + '<span class="section-muted" id="stockNote">' + (soldout ? t('out_stock') : (p.maxOrder ? 'max ' + p.maxOrder : '')) + '</span></div>'
    + '<div class="rowbtns">'
    + '<button class="icon-btn wish' + (wishHas(p.id) ? ' onfav' : '') + '" data-act="wish" data-p="' + encodeURIComponent(p.id) + '" title="' + esc(t('nav_wish')) + '" aria-label="' + esc(t('nav_wish')) + '">'
    + '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 14c1.49-1.46 3-3.21 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.76 0-3 .5-4.5 2-1.5-1.5-2.74-2-4.5-2A5.5 5.5 0 0 0 2 8.5c0 2.3 1.5 4.05 3 5.5l7 7Z"/></svg></button>'
    + '<button class="btn-dark" data-act="buynow"' + (soldout ? ' disabled' : '') + '>' + t('buy_now') + '</button>'
    + '<button class="icon-btn" data-act="addcart" title="' + esc(t('add_cart')) + '"' + (soldout ? ' disabled' : '') + ' aria-label="' + esc(t('add_cart')) + '">'
    + '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="8" cy="21" r="1"/><circle cx="19" cy="21" r="1"/><path d="M2.05 2.05h2l2.66 12.42a2 2 0 0 0 2 1.58h9.78a2 2 0 0 0 1.95-1.57l1.65-7.43H5.12"/></svg></button>'
    + '</div>'
    + '<div class="seller-card">'
    + '<div class="who"><div class="avatar">' + esc((p.sellerName || 'S').slice(0, 1).toUpperCase()) + '</div>'
    + '<div style="flex:1"><div class="nm">' + esc(p.sellerName) + (p.sellerKycApproved ? ' ' + SELLER_SEAL : '') + '</div>'
    + '<div class="loc">' + esc(p.location || 'Tanzania') + '</div></div></div>'
    + '<a class="sv-seller-link" href="#/store/' + encodeURIComponent(p.sellerId) + '">' + t('sv_store') + '</a>'
    + (p.sellerPhone ? '<a class="btn-wa btn-block" href="' + waLink(p.sellerPhone, 'Habari, ninauliza kuhusu ' + p.name + '.') + '" target="_blank" rel="noopener">'
      + '<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 11.5a8.38 8.38 0 0 1-.9 3.8 8.5 8.5 0 0 1-7.6 4.7 8.38 8.38 0 0 1-3.8-.9L3 21l1.9-5.7a8.38 8.38 0 0 1-.9-3.8 8.5 8.5 0 0 1 4.7-7.6 8.38 8.38 0 0 1 3.8-.9h.5a8.48 8.48 0 0 1 8 8v.5z"/></svg>'
      + esc(t('wa_cta')) + '</a>' : '')
    + '</div>'
    + '<div class="desc"><h3>' + t('description') + '</h3><p>' + esc(p.description) + '</p></div>'
    + tiers
    + (attrs ? '<div class="attrs mt24"><h3>' + t('attributes') + '</h3><table>' + attrs + '</table></div>' : '')
    + '<div class="share-row">'
    + '<a class="btn-outline" href="' + shareWa(p) + '" target="_blank" rel="noopener">'
    + '<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 11.5a8.38 8.38 0 0 1-.9 3.8 8.5 8.5 0 0 1-7.6 4.7 8.38 8.38 0 0 1-3.8-.9L3 21l1.9-5.7a8.38 8.38 0 0 1-.9-3.8 8.5 8.5 0 0 1 4.7-7.6 8.38 8.38 0 0 1 3.8-.9h.5a8.48 8.48 0 0 1 8 8v.5z"/></svg>'
    + esc(t('share')) + '</a>'
    + '<button class="btn-outline" data-act="copylink" data-p="' + encodeURIComponent(p.id) + '" type="button">' + esc(t('copy_link')) + '</button>'
    + '</div>'
    + '</div></div>'
    + '<div class="reviews" id="revHost" style="max-width:720px;margin:26px auto 0"><div class="skel" style="height:120px"></div></div>'
    + '</div>';

  let sel = { qty: 1, variantId: null, adj: 0, vstock: p.stock };
  window.__pCtx = { p: p, sel: sel };
  const variantSel = document.getElementById('variantSel');
  if (variantSel) {
    variantSel.addEventListener('change', () => {
      const o = variantSel.options[variantSel.selectedIndex];
      sel.variantId = o.value;
      sel.adj = Number(o.dataset.adj) || 0;
      sel.vstock = Number(o.dataset.stock) != null && Number(o.dataset.stock) >= 0 ? Number(o.dataset.stock) : p.stock;
      const max = Math.min(sel.vstock, p.maxOrder || sel.vstock || 1);
      if (sel.qty > max) sel.qty = max;
      const qEl = document.getElementById('qtyN');
      if (qEl) qEl.textContent = sel.qty;
      const pr = document.getElementById('priceNow');
      if (pr) pr.textContent = fmtTZS(p.price + sel.adj);
      const sn = document.getElementById('stockNote');
      if (sn) sn.textContent = (sel.vstock <= 0 ? t('out_stock') : (p.maxOrder ? 'max ' + p.maxOrder : ''));
    });
  }
  const qtyN = document.getElementById('qtyN');
  const clampQ = () => {
    const max = Math.min(sel.vstock, p.maxOrder || sel.vstock || 1);
    sel.qty = Math.max(1, Math.min(sel.qty, max));
    if (qtyN) qtyN.textContent = sel.qty;
  };
  __pQtyHandler = function qh(e) {
    const el = e.target.closest('[data-act]');
    if (!el) return;
    if (el.dataset.act === 'qplus') { sel.qty++; clampQ(); }
    else if (el.dataset.act === 'qminus') { sel.qty--; clampQ(); }
    else if (el.dataset.act === 'addcart') { addToCart(p, sel); toast('✔ ' + t('add_to_cart_ok')); }
    else if (el.dataset.act === 'buynow') {
      location.hash = '#/checkout?p=' + encodeURIComponent(p.id) + '&q=' + sel.qty + (sel.variantId ? '&v=' + encodeURIComponent(sel.variantId) : '');
    }
else if (el.dataset.act === 'img') {
       const gi = Number(el.dataset.gi) || 0;
       const i = gi + 1;
       const src = p.images[i];
       const m = document.getElementById('mainImg');
       if (m && src) m.src = src;
     }
  };
  /* ---------- SEO: Product structured data ---------- */
  injectJsonLd({
    '@context': 'https://schema.org',
    '@type': 'Product',
    'name': p.name,
    'image': (p.images && p.images[0]) ? p.images[0] : undefined,
    'description': (p.description || '').slice(0, 200),
    'sku': p.id,
    'offers': {
      '@type': 'Offer',
      'url': location.href,
      'priceCurrency': 'TZS',
      'price': Number(p.price) || 0,
      'availability': (p.stock > 0) ? 'https://schema.org/InStock' : 'https://schema.org/OutOfStock',
      'seller': { '@type': 'Organization', 'name': p.sellerName || 'Soko Vibe' }
    },
    'aggregateRating': (p.rating > 0 && p.reviewCount > 0)
      ? { '@type': 'AggregateRating', 'ratingValue': p.rating, 'reviewCount': p.reviewCount, 'bestRating': 5, 'worstRating': 1 }
      : undefined,
  });
  setPageMeta(p.name + ' — Soko Vibe', (p.description || '').slice(0, 160), location.href, (p.images && p.images[0]) ? p.images[0] : undefined);

  loadReviews(p.id, p.sellerId);
  if (typeof window.recordRecent === 'function') window.recordRecent(p.id);
  if (typeof window.parityProductExtras === 'function') window.parityProductExtras(p);
}

function shareWa(p) {
  const text = (p.name || '') + ' — ' + fmtTZS(p.price) + ' | Soko Vibe Duka: ' + location.href.split('#')[0] + '#/p/' + encodeURIComponent(p.id);
  return 'https://wa.me/?text=' + encodeURIComponent(text);
}

function starRow(n) {
  let s = '';
  for (let i = 1; i <= 5; i++) s += i <= n ? '★' : '☆';
  return s;
}

function revHtml(r) {
  const name = r.userName || 'Mteja';
  return '<div class="rev">'
    + '<div class="avatar">' + esc(String(name).slice(0, 1).toUpperCase()) + '</div>'
    + '<div class="rbody"><div class="rtop"><b>' + esc(name) + '</b>'
    + '<span class="stars">' + starRow(Math.round(Number(r.rating) || 0)) + '</span>'
    + '<time>' + ts2date(r.createdAt) + '</time></div>'
    + (r.comment ? '<p>' + esc(r.comment) + '</p>' : '')
    + (r.sellerReply ? '<div class="reply"><b>' + esc(t('seller')) + ':</b> ' + esc(r.sellerReply) + '</div>' : '')
    + '</div></div>';
}

function reviewFormHtml(productId, sellerId) {
  const opts = [5, 4, 3, 2, 1].map((v) => '<button type="button" class="rv-star' + (v === 5 ? ' on' : '') + '" data-act="rvstar" data-v="' + v + '" aria-label="' + v + ' ★">★</button>').join('');
  return '<div class="rev-form" id="revForm">'
    + '<h4>' + t('write_review') + '</h4>'
    + '<div class="rv-stars" id="rvStars">' + opts + '</div>'
    + '<textarea id="revComment" rows="2" maxlength="500" placeholder="' + esc(t('your_comment')) + '"></textarea>'
    + '<button class="btn-dark" data-act="postreview" data-p="' + encodeURIComponent(productId) + '" data-s="' + encodeURIComponent(sellerId) + '">' + t('submit_review') + '</button>'
    + '</div>';
}

async function loadReviews(productId, sellerId) {
  const host = document.getElementById('revHost');
  if (!host) return;
  let list = [];
  try {
    const snap = await DB.collection('reviews').where('productId', '==', productId).orderBy('createdAt', 'desc').limit(12).get();
    list = snap.docs.map((d) => d.data());
  } catch (_) { /* rules or transient — show empty block */ }
  const avg = list.length ? Math.round((list.reduce((s, r) => s + (Number(r.rating) || 0), 0) / list.length) * 10) / 10 : 0;
  const user = AUTH.currentUser;
  const canReview = user && user.uid !== sellerId;
  host.innerHTML = '<h3>' + t('reviews') + (list.length ? ' <small>(' + list.length + ')</small>' : '') + '</h3>'
    + (list.length ? '<div class="rev-avg"><b>' + avg.toFixed(1) + '</b><span class="stars">' + starRow(Math.round(avg)) + '</span>'
      + '<span class="muted">' + list.length + ' ' + esc(t('reviews')) + '</span></div>' : '')
    + (list.length ? '<div class="rev-list">' + list.map(revHtml).join('') + '</div>' : '<p class="muted">' + esc(t('no_reviews')) + '</p>')
    + (canReview ? reviewFormHtml(productId, sellerId) : '');
}

// Product aggregate rating is recomputed client-side after a review — the
// Firestore rules allow any signed-in user to touch only rating/reviewCount.
async function recomputeProductRating(productId) {
  try {
    const snap = await DB.collection('reviews').where('productId', '==', productId).get();
    const rs = snap.docs.map((d) => Number(d.data().rating) || 0);
    if (!rs.length) return;
    const avg = Math.round((rs.reduce((a, b) => a + b, 0) / rs.length) * 10) / 10;
    await DB.collection('products').doc(productId).update({ rating: avg, reviewCount: rs.length });
    const pc = productCache[productId];
    if (pc) { pc.rating = avg; pc.reviewCount = rs.length; }
  } catch (_) { /* non-critical */ }
}

function addToCart(p, sel) {
  const q = (sel && sel.qty) || 1;
  const vid = (sel && sel.variantId) || null;
  const ix = cart.findIndex((i) => i.p === p.id && (i.v || '') === (vid || ''));
  if (ix >= 0) {
    const max = Math.max(1, Math.min(p.maxOrder || p.stock || 1, p.stock || 1));
    cart[ix].q = Math.min(Number(cart[ix].q || 0) + q, max);
  } else {
    cart.push({ p: p.id, v: vid, q: q, n: p.name, img: p.images[0] || '', u: p.price + ((sel && sel.adj) || 0), s: p.sellerName || '', c: p.category || '' });
  }
  saveCart();
  refreshBadge();
}

/* quick add from card: if product has variants send buyer to the product page */
async function quickAdd(id) {
  const p = await getProduct(id);
  if (!p) return;
  if (p.variants && p.variants.length) {
    location.hash = '#/p/' + encodeURIComponent(id);
    return;
  }
  if (p.stock <= 0) { toast(t('out_stock')); return; }
  addToCart(p, { qty: 1, variantId: null, adj: 0 });
  toast('✔ ' + t('add_to_cart_ok'));
}

/* ---------- Cart ---------- */

async function renderCart() {
  setLang();
  setHero(false);
  if (!cart.length) {
    view.innerHTML = '<div class="container-wide">' + emptyHtml(t('cart_empty'), '', t('cart_browse')) + '</div>';
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
  let html = '<div class="container-wide"><div class="headline-row"><a class="mini-link" href="#/">← ' + t('back') + '</a>'
    + '<span class="section-title" style="font-family:var(--font-display);font-weight:700;color:var(--ink);margin:0">' + t('cart_title') + '</span></div>'
    + '<div class="cart-grid"><div class="cart-list">';
  for (const [seller, lines] of groups) {
    html += '<div class="cart-group"><div class="ghead">' + SELLER_SEAL + '<span>' + t('cart_seller') + ': ' + esc(seller) + '</span></div>';
    for (const it of lines) {
      const p = it.prod;
      const img = it.line.img || (p && p.images[0]) || '';
      html += '<div class="cart-item">'
        + '<div class="thumb">' + (img ? '<img src="' + esc(img) + '" alt="" onerror="this.remove()">' : '') + '</div>'
        + '<div class="mid"><div class="nm">' + esc(it.line.n || (p && p.name) || '') + '</div>'
        + '<div class="pr">' + fmtTZS(Number(it.line.u) || 0) + ' × ' + it.line.q + '</div></div>'
        + '<div class="ctrls"><div class="stepper">'
        + '<button data-act="cqminus" data-p="' + esc(it.line.p) + '" data-v="' + esc(it.line.v || '') + '" aria-label="-">−</button>'
        + '<span class="n">' + it.line.q + '</span>'
        + '<button data-act="cqplus" data-p="' + esc(it.line.p) + '" data-v="' + esc(it.line.v || '') + '" aria-label="+">+</button></div>'
        + '<button class="rm" data-act="cartrm" data-p="' + esc(it.line.p) + '" data-v="' + esc(it.line.v || '') + '">' + t('remove') + '</button>'
        + '</div></div>';
    }
    html += '</div>';
  }
  html += '</div>'
    + '<aside class="checkout-bar"><h3>' + t('cart_total') + '</h3>'
    + '<div class="sum-row"><span>Vitu</span><span>' + cartQty() + '</span></div>'
    + '<div class="sum-row"><span>Ada ya jukwaa</span><span>Escrow</span></div>'
    + '<div class="sum-row strong"><span>' + t('cart_total') + '</span><span>' + fmtTZS(tot) + '</span></div>'
    + '<div class="sec-note"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 2l8 3.5V11c0 5-3.4 8.8-8 11-4.6-2.2-8-6-8-11V5.5z"/><path d="M9 12l2 2 4-4"/></svg>'
    + '<span>' + t('escrow_note') + '</span></div>'
    + '<button class="btn-accent btn-block mt16" data-act="ckcart">' + t('cart_checkout') + ' · ' + fmtTZS(tot) + '</button></aside>'
    + '</div></div>';
  view.innerHTML = html;
}

function checkoutNextLine() {
  if (!cart.length) return;
  const outputs = [];
  for (const line of cart) {
    if (!outputs.some((o) => o.p === line.p && o.v === line.v)) outputs.push(line);
  }
  const first = outputs[0];
  location.hash = '#/checkout?p=' + encodeURIComponent(first.p) + '&q=' + first.q + (first.v ? '&v=' + encodeURIComponent(first.v) : '');
}

/* ---------- Wishlist page ---------- */

async function renderWishlist() {
  setLang();
  setHero(false);
  view.innerHTML = '<div class="container-wide"><div class="headline-row"><a class="mini-link" href="#/">← ' + t('back') + '</a>'
    + '<span style="font-family:var(--font-display);font-weight:700;color:var(--ink);font-size:16px">' + t('wish_title') + '</span></div>'
    + '<p class="muted" style="margin:4px 0 16px">' + esc(t('wish_hint')) + '</p>'
    + '<div class="grid" id="wishGrid"><div class="skel" style="height:220px"></div></div></div>';
  const host = document.getElementById('wishGrid');
  if (!host) return;
  const ids = wish.slice();
  if (!ids.length) { host.innerHTML = emptyHtml(t('wish_empty'), '', t('home_browse')); return; }
  const prods = (await Promise.all(ids.map(getProduct))).filter(Boolean);
  host.innerHTML = prods.length ? prods.map(cardHtml).join('') : emptyHtml(t('wish_empty'), '', t('home_browse'));
}

/* ---------- Orders ---------- */

const FILTER_STATES = { active: ['pending', 'quoted', 'paid', 'dispatched', 'confirmed'], completed: ['completed'], cancelled: ['cancelled', 'disputed', 'refunded'] };
function renderOrders() {
  setLang();
  setHero(false);
  const user = AUTH.currentUser;
  const g = guestCtx();
  if (!user && !g) {
    view.innerHTML = '<div class="container-wide">' + emptyHtml(t('need_auth'), '', t('nav_signin')).replace('#/', '#/account') + '</div>';
    return;
  }
  const fDefs = [{ v: 'all', l: t('sv_all_orders') }, { v: 'active', l: t('sv_active') }, { v: 'completed', l: t('sv_completed') }, { v: 'cancelled', l: t('sv_cancelled') }];
  const fRow = '<div class="order-filters" role="group">' + fDefs.map((f) => '<button type="button" class="sv-chip' + (orderFilter === f.v ? ' on' : '') + '" data-act="ofilter" data-v="' + f.v + '">' + f.l + '</button>').join('') + '</div>';
  view.innerHTML = '<div class="container-wide"><div class="headline-row"><a class="mini-link" href="#/account">← ' + t('back') + '</a>'
    + '<span style="font-family:var(--font-display);font-weight:700;color:var(--ink);font-size:16px">' + t('orders_my') + '</span></div>'
    + (g && !user ? '<div class="guest-box slim"><span>' + esc(t('guest_name')) + ': ' + esc(g.name || '') + ' · ' + esc(g.phone || '') + '</span></div>' : '')
    + fRow
    + '<div class="order-list"><div class="skel" style="height:74px"></div><div class="skel" style="height:74px"></div></div></div>';
  const host = $('.order-list');
  if (user) {
    Promise.all([
      DB.collection('orders').where('buyerId', '==', user.uid).limit(50).get().catch(() => null),
    ]).then(([snap]) => {
      if (!host) return;
      if (!snap) { host.innerHTML = emptyHtml(t('err_generic'), '', t('home_browse')); return; }
      let orders = snap.docs.map((d) => d.data()).sort((a, b) => tsMillis(b.createdAt) - tsMillis(a.createdAt));
      if (orderFilter && orderFilter !== 'all') orders = orders.filter((o) => (FILTER_STATES[orderFilter] || []).includes(o.status));
      if (!orders.length) { host.innerHTML = emptyHtml(t('my_orders_empty'), '', t('home_browse')); return; }
      host.innerHTML = orders.map(orderHtml).join('');
    });
    return;
  }
  apiGet('/api/orders/guest/list').then((data) => {
    if (!host) return;
    let orders = (data && data.data) || [];
    if (orderFilter && orderFilter !== 'all') orders = orders.filter((o) => (FILTER_STATES[orderFilter] || []).includes(o.status));
    if (!orders.length) { host.innerHTML = emptyHtml(t('my_orders_empty'), '', t('home_browse')); return; }
    host.innerHTML = orders.map(orderHtml).join('');
  }).catch(() => {
    if (host) host.innerHTML = emptyHtml(t('err_generic'), '', t('home_browse'));
  });
}

function orderHtml(o) {
  const st = o.status || 'pending';
  const pill = PAY_STATES.has(st) ? 'done' : (BAD_STATES.has(st) ? 'bad' : 'wait');
  const oid = o.orderId || o.id;
  const slug = orderSlug(oid);
  return '<a class="order-item" href="#/o/' + encodeURIComponent(slug) + '">'
    + '<div class="thumb">' + (o.productImage ? '<img src="' + esc(o.productImage) + '" alt="" onerror="this.remove()">' : '') + '</div>'
    + '<div class="mid"><div class="nm">' + esc(o.productName || 'Agizo') + '</div>'
    + '<div class="meta">' + t('order_id') + ' ' + esc(String(oid).slice(0, 10)) + ' · ' + ts2date(o.createdAt) + '</div></div>'
    + '<div class="rt"><span class="amt">' + fmtTZS(o.totalAmount) + '</span>'
    + '<span class="pill ' + pill + '">' + esc((SV_T[lang].order_statuses[st] || st)) + '</span></div></a>';
}

function orderSlug(id) {
  const s = String(id || '');
  return s.indexOf(':') >= 0 ? encodeURIComponent(s.replace(/^.*:/, '')) : s;
}

async function renderOrderDetail(id) {
  setLang();
  setHero(false);
  const user = AUTH.currentUser;
  view.innerHTML = '<div class="container-wide"><div class="headline-row"><a class="mini-link" href="#/orders">← ' + t('back') + '</a>'
    + '<span style="font-family:var(--font-display);font-weight:700;color:var(--ink);font-size:16px">Oda #' + esc(String(id).slice(0, 10)) + '</span></div>'
    + '<div class="skel" style="height:200px"></div></div>';
  if (!user) {
    if (!guestCtx()) return;
    try {
      const data = await apiGet('/api/orders/guest/list');
      const list = (data && data.data) || [];
      const found = list.find((o) => String(o.orderId) === String(id) || orderSlug(o.orderId) === orderSlug(id));
      if (found) { view.innerHTML = guestOrderHtml(found, id); return; }
    } catch (_) {}
    view.innerHTML = '<div class="container-wide">' + emptyHtml(t('empty_filter'), '', t('home_browse')) + '</div>';
    return;
  }
  let order = null;
  try {
    const ref = DB.collection('orders').doc(id);
    const snap = await ref.get();
    if (snap.exists) order = snap.data();
  } catch (_) { /* try query below */ }
  if (!order) {
    try {
      const q = await DB.collection('orders').where('orderId', '==', id).limit(2).get();
      if (q.docs.length) order = q.docs[0].data();
    } catch (_) {}
  }
  if (!order) {
    view.innerHTML = '<div class="container-wide">' + emptyHtml(t('empty_filter'), '', t('home_browse')) + '</div>';
    return;
  }
  const st = order.status || 'pending';
  const timelineIdx = SV_STATUS_ORDER.indexOf(st);
  const pill = PAY_STATES.has(st) ? 'done' : (BAD_STATES.has(st) ? 'bad' : 'wait');
  const tl = SV_STATUS_ORDER.map((s, i) => {
    const done = timelineIdx >= 0 && i < timelineIdx
      || (s === st)
      || (PAY_STATES.has(s) && PAY_STATES.has(st));
    return '<div class="st' + (done ? ' done' : '') + '"><span class="tick">✓</span>' + esc(SV_T[lang].order_statuses[s] || s) + '</div>';
  }).join('');
  view.innerHTML = '<div class="container-wide"><div class="order-detail">'
    + '<div class="od-head"><h2>' + t('orders_my') + '</h2>'
    + '<span class="pill ' + pill + '">' + esc(SV_T[lang].order_statuses[st] || st) + '</span></div>'
    + '<div class="card-block"><h3>' + t('cart_checkout') + '</h3>'
    + '<div class="line-item"><div class="thumb">' + (order.productImage ? '<img src="' + esc(order.productImage) + '" alt="" onerror="this.remove()">' : '') + '</div>'
    + '<div class="mid"><div class="nm">' + esc(order.productName || 'Agizo') + '</div>'
    + '<div class="pr">' + fmtTZS(order.unitPrice) + ' × ' + (order.quantity || 1) + '</div></div>'
    + '<div style="font-family:var(--font-mono);font-weight:700;color:var(--ink)">' + fmtTZS(order.totalAmount) + '</div></div>'
    + '<div class="sum-row"><span>Namba ya oda</span><span class="order-no">' + esc(String(order.orderId || id)) + '</span></div>'
    + '<div class="sum-row"><span>Tarehe</span><span>' + ts2date(order.createdAt) + '</span></div>'
    + '<div class="sum-row"><span>Anwani</span><span>' + esc([order.region, order.district, order.ward, order.street].filter(Boolean).join(', ')) + '</span></div>'
    + '<div class="sum-row"><span>Malipo</span><span style="color:var(--good)">' + t('trust_clickpesa') + ' · Escrow</span></div>'
    + '</div>'
    + '<div class="card-block"><h3>' + t('status_label') + '</h3><div class="status-timeline" style="max-width:none">' + tl + '</div>'
    + '<div class="sec-note" style="max-width:none"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 2l8 3.5V11c0 5-3.4 8.8-8 11-4.6-2.2-8-6-8-11V5.5z"/><path d="M9 12l2 2 4-4"/></svg>'
    + '<span>' + t('escrow_note') + '</span></div></div>'
    + '<div class="card-block"><h3>' + t('seller') + '</h3>'
    + '<div class="seller-card" style="margin:0"><div class="who"><div class="avatar">' + esc((order.sellerName || 'S').slice(0, 1).toUpperCase()) + '</div>'
    + '<div style="flex:1"><div class="nm">' + esc(order.sellerName || 'Muuzaji') + ' ' + SELLER_SEAL + '</div>'
    + '<div class="loc">' + esc([order.sellerLocation, order.sellerDistrict].filter(Boolean).join(', ') || 'Tanzania') + '</div></div></div>'
    + (order.sellerPhone
      ? '<a class="btn-wa btn-block" href="' + waLink(order.sellerPhone, 'Habari, nina ombi namba ' + String(order.orderId || id) + ' kuhusu ' + order.productName + '.') + '" target="_blank" rel="noopener">'
        + '<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 11.5a8.38 8.38 0 0 1-.9 3.8 8.5 8.5 0 0 1-7.6 4.7 8.38 8.38 0 0 1-3.8-.9L3 21l1.9-5.7a8.38 8.38 0 0 1-.9-3.8 8.5 8.5 0 0 1 4.7-7.6 8.38 8.38 0 0 1 3.8-.9h.5a8.48 8.48 0 0 1 8 8v.5z"/></svg>'
        + esc(t('wa_cta')) + '</a>' : '')
    + '</div></div>'
    + '</div></div>';
  if (typeof window.parityBuyerOrderArea === 'function') {
    try {
      const pg = await apiGet('/api/v1/orders/' + encodeURIComponent(order.orderId || id));
      window.parityBuyerOrderArea(order, (pg && pg.data) || pg || {});
    } catch (_) {}
  }
}

/* ---------- Account ---------- */

function guestOrderHtml(o, id) {
  const st = o.status || 'pending';
  const pill = PAY_STATES.has(st) ? 'done' : (BAD_STATES.has(st) ? 'bad' : 'wait');
  const tl = SV_STATUS_ORDER.map((s, i) => {
    const idx = SV_STATUS_ORDER.indexOf(st);
    const done = (idx >= 0 && i < idx) || (s === st) || (PAY_STATES.has(s) && PAY_STATES.has(st));
    return '<div class="st' + (done ? ' done' : '') + '"><span class="tick">✓</span>' + esc(SV_T[lang].order_statuses[s] || s) + '</div>';
  }).join('');
  const addr = [o.region, o.district, o.ward, o.street].filter(Boolean).join(', ');
  return '<div class="container-wide"><div class="order-detail">'
    + '<div class="od-head"><h2>' + t('orders_my') + '</h2>'
    + '<span class="pill ' + pill + '">' + esc(SV_T[lang].order_statuses[st] || st) + '</span></div>'
    + '<div class="card-block"><h3>' + t('cart_checkout') + '</h3>'
    + '<div class="line-item"><div class="thumb">' + (o.productImage ? '<img src="' + esc(o.productImage) + '" alt="" onerror="this.remove()">' : '') + '</div>'
    + '<div class="mid"><div class="nm">' + esc(o.productName || 'Agizo') + '</div>'
    + '<div class="pr">' + fmtTZS(o.unitPrice) + ' × ' + (o.quantity || 1) + '</div></div>'
    + '<div style="font-family:var(--font-mono);font-weight:700;color:var(--ink)">' + fmtTZS(o.totalAmount) + '</div></div>'
    + '<div class="sum-row"><span>Namba ya oda</span><span class="order-no">' + esc(String(o.orderId || id)) + '</span></div>'
    + '<div class="sum-row"><span>Tarehe</span><span>' + ts2date(o.createdAt) + '</span></div>'
    + (addr ? '<div class="sum-row"><span>Anwani</span><span>' + esc(addr) + '</span></div>' : '')
    + '<div class="sum-row"><span>Malipo</span><span style="color:var(--good)">' + t('trust_clickpesa') + ' · Escrow</span></div>'
    + '</div>'
    + '<div class="card-block"><h3>' + t('status_label') + '</h3><div class="status-timeline" style="max-width:none">' + tl + '</div>'
    + '<div class="sec-note" style="max-width:none"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 2l8 3.5V11c0 5-3.4 8.8-8 11-4.6-2.2-8-6-8-11V5.5z"/><path d="M9 12l2 2 4-4"/></svg>'
    + '<span>' + t('escrow_note') + '</span></div></div>'
    + (o.sellerName ? '<div class="card-block"><h3>' + t('seller') + '</h3>'
      + '<div class="seller-card" style="margin:0"><div class="who"><div class="avatar">' + esc((o.sellerName || 'S').slice(0, 1).toUpperCase()) + '</div>'
      + '<div style="flex:1"><div class="nm">' + esc(o.sellerName) + '</div>'
      + '<div class="loc">' + esc(o.region || 'Tanzania') + '</div></div></div></div></div>' : '')
    + '<a class="mini-link" style="display:inline-block;margin-top:8px" href="#/orders">← ' + t('back') + '</a>'
    + '</div></div></div>';
}

/* ---------- Account ---------- */

function renderAccount() {
  setLang();
  setHero(false);
  const user = AUTH.currentUser;
  const activeTab = $('.tab.active');
  const openTab = (activeTab && activeTab.dataset.tab) || 'orders';
  if (!user) {
    renderAuthForm('signin');
    return;
  }
  view.innerHTML = '<div class="container-wide"><div class="account-grid">'
    + '<div class="profile-card">'
    + '<div class="avatar-lg">' + esc((user.displayName || user.email || 'S').slice(0, 1).toUpperCase()) + '</div>'
    + '<div class="nm">' + esc(user.displayName || 'Soko Vibe') + '</div>'
    + '<div class="em">' + esc(user.email || '') + '</div>'
    + '<a class="btn-wa btn-block" href="https://wa.me/255693273241?text=' + encodeURIComponent('Nahitaji msaada kwenye Soko Vibe') + '" target="_blank" rel="noopener">WhatsApp Msaada</a>'
    + '<a class="btn-outline btn-block" href="#/notifications">' + esc(t('notifications')) + '</a>'
    + '<a class="btn-outline btn-block" href="#/chats">' + esc(t('chats')) + '</a>'
    + '<a class="btn-outline btn-block" href="#/flash">⚡ ' + esc(t('flash_sale')) + '</a>'
    + '<a class="btn-outline btn-block" href="#/seller">' + esc(t('nav_seller_page')) + '</a>'
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
  $all('.tab').forEach((tb) => tb.classList.toggle('active', tb.dataset.tab === tab));
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
    slot.innerHTML = orders.length ? orders.map(orderHtml).join('') : emptyHtml(t('my_orders_empty'), '', t('home_browse'));
  } catch (_) {
    slot.innerHTML = emptyHtml(t('err_generic'), '', t('home_browse'));
  }
}

function profileEditHtml() {
  const user = AUTH.currentUser;
  return '<div class="form-card" style="max-width:520px"><h2>' + t('profile') + '</h2>'
    + '<div class="field"><label>' + t('name') + '</label><input id="pName" value="' + esc(user.displayName || '') + '"></div>'
    + '<div class="field"><label>' + t('phone') + '</label><input id="pPhone" value="' + esc(user.phoneNumber || '') + '" placeholder="+255 7xx xxx xxx"></div>'
    + '<button class="btn-dark" data-act="saveProfile">Hifadhi</button>'
    + '</div>';
}

function renderAuthForm(mode) {
  const authMode = mode || 'signin';
  setHero(false);
  view.innerHTML = '<div class="container-wide"><div class="auth-wrap">'
    + '<div class="form-card"><h2>' + (authMode === 'signin' ? t('signin_title') : t('signup_title')) + '</h2>'
    + '<div class="error-box" id="authErr"></div>'
    + (authMode === 'signup' ? '<div class="field"><label>' + t('name') + '</label><input id="aName"></div>' : '')
    + '<div class="field"><label>' + t('email') + '</label><input id="aEmail" type="email" autocomplete="email"></div>'
    + (authMode === 'signup' ? '<div class="field"><label>' + t('phone') + '</label><input id="aPhone" placeholder="+255 7xx xxx xxx"></div>' : '')
    + (authMode === 'signup' ? '<label class="chk"><input type="checkbox" id="aIsSeller"> <span>' + esc(t('sell_signup')) + '</span></label>' : '')
    + '<div class="field"><label>' + t('password') + '</label><input id="aPass" type="password" autocomplete="current-password"></div>'
    + '<button class="btn-dark btn-block" id="authBtn">' + (authMode === 'signin' ? t('submit_signin') : t('submit_signup')) + '</button>'
    + '<div class="auth-switch">' + (authMode === 'signin'
      ? t('no_account') + ' <a href="#/account?mode=signup">' + t('submit_signup') + '</a>'
      : t('have_account') + ' <a href="#/account?mode=signin">' + t('submit_signin') + '</a>') + '</div>'
    + (typeof window.authAltButtons === 'function' ? window.authAltButtons() : '')
    + '</div></div></div>';
  const btn = document.getElementById('authBtn');
  btn.addEventListener('click', async () => {
    const email = document.getElementById('aEmail').value.trim();
    const pass = document.getElementById('aPass').value;
    const errBox = document.getElementById('authErr');
    if (errBox) errBox.classList.remove('show');
    try {
      if (authMode === 'signin') {
        await AUTH.signInWithEmailAndPassword(email, pass);
      } else {
        const name = document.getElementById('aName').value.trim();
        const phone = e164(document.getElementById('aPhone').value);
        const cred = await AUTH.createUserWithEmailAndPassword(email, pass);
        if (name) await cred.user.updateProfile({ displayName: name });
        const isSeller = !!(document.getElementById('aIsSeller') && document.getElementById('aIsSeller').checked);
        const uDoc = {
          name: name || email.split('@')[0],
          email: email,
          phone: phone,
          isAdmin: false,
          isSuspended: false,
          isSeller: isSeller,
          sellerBalance: 0,
          createdAt: firebase.firestore.FieldValue.serverTimestamp(),
        };
        if (isSeller) uDoc.sellerName = name || email.split('@')[0];
        await DB.collection('users').doc(cred.user.uid).set(uDoc);
      }
      toast('✔ ' + (authMode === 'signin' ? t('submit_signin') : t('submit_signup')));
      refreshChip();
      renderAccount();
    } catch (e) {
      if (errBox) { errBox.textContent = errMsg(e); errBox.classList.add('show'); }
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

/* ---------- Checkout wizard + payment ---------- */

function checkoutMeta(p, qty, variantId) {
  const v = variantId ? (p.variants || []).find((x) => x.id === variantId) : null;
  const unit = p.price + (v && Number(v.priceAdjustment) ? Number(v.priceAdjustment) : 0);
  return { unit: unit, lineTotal: unit * qty };
}

function stepsBar(active) {
  const names = [t('checkout_step_addr'), t('checkout_step_pay'), t('checkout_step_done')];
  let h = '<div class="steps">';
  names.forEach((n, i) => {
    const idx = i + 1;
    const cls = idx === active ? 'on' : (idx < active ? 'done' : '');
    h += '<div class="step ' + cls + '"><span class="n">' + (idx < active ? '✓' : idx) + '</span><span class="txt">' + esc(n) + '</span></div>';
    if (idx < names.length) h += '<div class="step-line ' + (idx < active ? 'done' : '') + '"></div>';
  });
  return h + '</div>';
}

async function renderCheckout(id, qty, variantId) {
  setLang();
  setHero(false);
  const user = AUTH.currentUser;
  view.innerHTML = '<div class="container-wide"><div class="skel" style="height:480px;margin-top:18px"></div></div>';
  const p = await getProduct(id);
  if (!p) { view.innerHTML = '<div class="container-wide">' + emptyHtml(t('empty_filter'), '', t('home_browse')) + '</div>'; return; }
  const { unit, lineTotal } = checkoutMeta(p, qty, variantId);
  const regions = SV_REGIONS.map((r) => '<option value="' + esc(r) + '">' + esc(r) + '</option>').join('');
  const g = guestCtx();
  const guestName = g ? esc(g.name || '') : '';
  const guestHtml = !user
    ? '<div class="guest-box"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>'
      + '<div><b>' + t('nav_signin') + ' au nunua bila akaunti</b><span>' + t('guest_note') + '</span></div></div>'
      + '<div class="field"><label>' + t('guest_name') + '</label><input id="ckName" value="' + guestName + '"></div>'
    : '';
  view.innerHTML = '<div class="container-wide" style="max-width:940px;margin:0 auto;padding-top:18px">'
    + '<div class="headline-row"><a class="mini-link" href="#/p/' + encodeURIComponent(p.id) + '">← ' + t('back') + '</a>'
    + '<span style="font-family:var(--font-display);font-weight:700;color:var(--ink);font-size:16px">' + t('checkout_title') + '</span></div>'
    + stepsBar(1)
    + '<div class="ck-grid">'
    + '<div class="form-card"><h2>' + t('addr_heading') + '</h2>'
    + guestHtml
    + '<div class="field"><label>' + t('phone') + '</label><input id="ckPhone" value="' + esc(user ? (user.phoneNumber || '') : (g ? g.phone : '')) + '" placeholder="+255 7xx xxx xxx"></div>'
    + '<div class="form-row">'
    + '<div class="field"><label>' + t('region') + '</label><select id="ckRegion"><option value="">—</option>' + regions + '</select></div>'
    + '<div class="field"><label>' + t('district') + '</label><select id="ckDistrict"><option value="">—</option></select></div>'
    + '</div>'
    + '<div class="form-row">'
    + '<div class="field"><label>' + t('ward') + '</label><input id="ckWard"></div>'
    + '<div class="field"><label>' + t('street') + '</label><input id="ckStreet"></div>'
    + '</div>'
    + '<div class="field"><label>' + t('landmarks') + '</label><input id="ckLandmarks"></div>'
    + '<div class="esc-msg"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 2l8 3.5V11c0 5-3.4 8.8-8 11-4.6-2.2-8-6-8-11V5.5z"/><path d="M9 12l2 2 4-4"/></svg>'
    + '<span>' + t('escrow_note') + '</span></div>'
    + '<button class="btn-accent btn-block" id="ckBtn">' + t('place_order') + ' · ' + fmtTZS(lineTotal) + '</button>'
    + '</div>'
    + '<aside class="checkout-bar"><h3>' + t('summary_heading') + '</h3>'
    + '<div class="line-item"><div class="thumb">' + (p.images[0] ? '<img src="' + esc(p.images[0]) + '" alt="">' : '') + '</div>'
    + '<div class="mid"><div class="nm">' + esc(p.name) + '</div><div class="pr">' + fmtTZS(unit) + ' × ' + qty + '</div></div>'
    + '<div style="font-family:var(--font-mono);font-weight:700;color:var(--ink)">' + fmtTZS(lineTotal) + '</div></div>'
    + '<div class="sum-row"><span>' + t('qty') + '</span><span>' + qty + '</span></div>'
    + '<div class="sum-row"><span>Ada ya jukwaa</span><span>Escrow</span></div>'
    + '<div class="sum-row strong"><span>' + t('cart_total') + '</span><span>' + fmtTZS(lineTotal) + '</span></div>'
    + '<div class="pay-promo"><div class="icon"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 2v20M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6"/></svg></div>'
    + '<div><b>' + t('trust_clickpesa') + '</b><span>TZS · USSD push · Mobile money</span></div></div>'
    + '</aside>'
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
  const phone = e164(document.getElementById('ckPhone').value);
  const region = document.getElementById('ckRegion').value;
  const district = document.getElementById('ckDistrict').value;
  const ward = document.getElementById('ckWard').value.trim();
  const street = document.getElementById('ckStreet').value.trim();
  const landmarks = document.getElementById('ckLandmarks').value.trim();
  const btn = document.getElementById('ckBtn');
  const nameEl = document.getElementById('ckName');
  const name = (nameEl ? nameEl.value.trim() : '') || (user && user.displayName) || '';
  if (!phone || !region || !district || !street) { toast('Jaza namba ya simu, mkoa, wilaya na mtaa.'); return; }
  if (!user && !name) { toast(t('need_name_phone')); return; }
  btn.disabled = true;
  btn.textContent = t('processing');
  try {
    const created = await apiPost('/api/orders/create', {
      buyerId: user ? user.uid : undefined,
      buyerName: name,
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
    if (!user && created.order.buyerId) setGuest({ buyerId: created.order.buyerId, phone: phone, name: name });
    localStorage.removeItem('sv_shop_cart');
    cart = readCart();
    refreshBadge();
    renderPaymentScreen(p, qty, variantId, lineTotal, unit, orderId, phone, user);
  } catch (e) {
    btn.disabled = false;
    btn.textContent = t('place_order') + ' · ' + fmtTZS(lineTotal);
    toast(errMsg(e));
  }
}

function renderPaymentScreen(p, qty, variantId, lineTotal, unit, orderId, phone, user) {
  setLang();
  payCtx = { orderId: orderId, attempts: 0, done: false };
  view.innerHTML = '<div class="container-wide"><div class="status-card">'
    + stepsBar(2)
    + '<div class="phone-pulse"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><rect x="7" y="2" width="10" height="20" rx="2"/><path d="M11 18h2"/></svg></div>'
    + '<h2>' + t('pay_wait') + '</h2>'
    + '<div class="order-no">' + t('order_id') + ' ' + esc(String(orderId).slice(0, 12)) + '</div>'
    + '<div class="sub">' + fmtTZS(lineTotal) + ' · ' + esc(p.name) + '</div>'
    + '<div class="spinner" id="paySpin"></div>'
    + '<div id="payState" class="section-muted">' + t('pay_status_pending') + '…</div>'
    + '<div class="status-timeline" id="payTimeline"></div>'
    + '<div class="cta-btns">'
    + '<button class="btn-outline" id="payRetry" style="display:none">' + t('pay_new') + '</button>'
    + '<a class="mini-link" href="#/orders" style="display:block;margin-top:14px">' + t('orders_my') + '</a>'
    + '</div></div></div>';
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
    const g = guestCtx();
    const data = await apiPost('/api/create-marketplace-payment-link', {
      productPrice: lineTotal,
      productName: p.name,
      productId: p.id,
      sellerId: p.sellerId,
      sellerName: p.sellerName,
      email: (user && user.email) || '',
      phone: phone,
      buyerId: (user ? user.uid : (g && g.buyerId)) || undefined,
      buyerName: (user ? (user.displayName || '') : (g && g.name)) || '',
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
  const orderId = payCtx.orderId;
  if (spin) spin.style.display = 'none';
  if (retryBtn) retryBtn.style.display = 'none';
  if (ok && state) {
    view.innerHTML = '<div class="container-wide"><div class="status-card">'
      + stepsBar(3)
      + '<div class="big-check"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6L9 17l-5-5"/></svg></div>'
      + '<h2>' + t('confirm_title') + '</h2>'
      + '<p class="sub">' + t('confirm_sub') + '</p>'
      + '<div class="order-no">' + t('order_id') + ' ' + esc(String(orderId)) + '</div>'
      + '<div class="status-timeline">' + SV_STATUS_ORDER.slice(0, 6).map((s) =>
          '<div class="st' + (PAY_STATES.has(s) ? ' done' : '') + '"><span class="tick">✓</span>' + esc(SV_T[lang].order_statuses[s] || s) + '</div>').join('') + '</div>'
      + '<div class="cta-btns">'
      + '<a class="btn-dark" href="#/orders">' + t('view_orders') + '</a>'
      + '<a class="btn-outline" href="#/">' + t('back_home') + '</a>'
      + '</div></div></div>';
    localStorage.removeItem('sv_shop_cart');
    cart = readCart();
    refreshBadge();
  } else {
    if (state) state.textContent = '✕ ' + (st ? esc(SV_T[lang].order_statuses[st] || st) : t('pay_failed'));
    if (retryBtn) retryBtn.style.display = 'inline-flex';
  }
}

/* ---------- Seller dashboard ---------- */

async function renderSellerPage(tab) {
  setLang();
  setHero(false);
  const user = AUTH.currentUser;
  if (!user) { renderAuthForm('signin'); toast(t('need_auth')); return; }
  view.innerHTML = '<div class="container-wide"><div class="skel" style="height:300px"></div></div>';
  let u = {};
  try {
    const snap = await DB.collection('users').doc(user.uid).get();
    if (snap.exists) u = snap.data();
  } catch (_) {}
  const isSeller = !!u.isSeller;
  const bal = Number(u.sellerBalance) || 0;
  const name = u.sellerName || u.name || user.displayName || 'Soko Vibe';
  const tabs = ['overview', 'products', 'orders', 'analytics', 'flash', 'kyc', 'boost', 'wallet'].map((k) =>
    '<button class="tab' + (k === tab ? ' active' : '') + '" data-act="sbtab" data-tab="' + k + '">' + esc(t('seller_' + k)) + '</button>').join('');
  view.innerHTML = '<div class="container-wide seller-page">'
    + '<div class="seller-head"><div class="avatar-lg">' + esc(String(name).slice(0, 1).toUpperCase()) + '</div>'
    + '<div class="who"><div class="nm">' + esc(name) + '</div>'
    + '<div class="loc">' + (isSeller ? t('seller_you') : t('not_seller')) + '</div></div>'
    + (isSeller ? '<div class="head-stat"><b>' + fmtTZS(bal) + '</b><span>' + esc(t('seller_balance_lbl')) + '</span></div>' : '')
    + '</div>'
    + '<div class="tabs">' + tabs + '</div>'
    + '<div id="sellerBody"></div></div>';
  const body = document.getElementById('sellerBody');
  if (!body) return;
  if (!isSeller) {
    body.innerHTML = '<div class="empty-state"><div class="big">🛍️</div>'
      + '<p>' + esc(t('not_seller')) + '</p>'
      + (u.kyc ? '' : '<p class="muted" style="max-width:520px">Muuzaji aliyethibitishwa (KYC) huonyeshwa vibao vya ' + esc(t('trust_verified')) + '.)</p>')
      + '<button class="btn-accent" data-act="becomeseller">' + esc(t('seller_become')) + '</button></div>';
    return;
  }
  if (tab === 'products') return sellerProductsBody(body, user, name);
  if (tab === 'orders') return sellerOrdersBody(body, user);
  if (tab === 'wallet') return sellerWalletBody(body, user, u, bal);
  if (tab === 'analytics' && typeof window.sellerAnalyticsBody === 'function') return window.sellerAnalyticsBody(body, user);
  if (tab === 'flash' && typeof window.sellerFlashBody === 'function') return window.sellerFlashBody(body, user);
  if (tab === 'kyc' && typeof window.sellerKycBody === 'function') return window.sellerKycBody(body, user);
  if (tab === 'boost' && typeof window.sellerBoostBody === 'function') return window.sellerBoostBody(body, user);
  sellerOverviewBody(body, user, u, bal);
}

async function sellerOverviewBody(body, user, u, bal) {
  body.innerHTML = '<div class="stat-grid">'
    + '<div class="stat"><b id="stProducts">…</b><span>' + esc(t('stats_products')) + '</span></div>'
    + '<div class="stat"><b id="stActive">…</b><span>' + esc(t('stats_active')) + '</span></div>'
    + '<div class="stat"><b id="stOrderPend">…</b><span>' + esc(t('stats_pending_orders')) + '</span></div>'
    + '<div class="stat"><b id="stOrders">…</b><span>' + esc(t('stats_orders')) + '</span></div>'
    + '</div>'
    + '<div class="rowbtns" style="margin-top:14px">'
    + '<a class="btn-dark" href="#/seller?t=products">' + esc(t('new_product')) + '</a>'
    + '<a class="btn-outline" href="#/seller?t=wallet">' + esc(t('seller_wallet')) + '</a>'
    + '</div>';
  try {
    const [psnap, osnap] = await Promise.all([
      DB.collection('products').where('sellerId', '==', user.uid).get(),
      DB.collection('orders').where('sellerId', '==', user.uid).limit(50).get().catch(() => null),
    ]);
    const plist = psnap.docs.map(norm);
    const ords = osnap ? osnap.docs.map((d) => d.data()) : [];
    const pending = ords.filter((o) => !PAY_STATES.has(o.status || '') && !BAD_STATES.has(o.status || '')).length;
    const st = (id, v) => { const el = document.getElementById(id); if (el) el.textContent = String(v); };
    st('stProducts', plist.length);
    st('stActive', plist.filter((p) => p.isActive).length);
    st('stOrderPend', pending);
    st('stOrders', ords.length);
  } catch (_) {}
}

async function sellerProductsBody(body, user, name) {
  body.innerHTML = '<div class="sd-toolbar"><h3>' + esc(t('seller_products')) + '</h3>'
    + '<button class="btn-accent" data-act="prodnew">+ ' + esc(t('new_product')) + '</button></div>'
    + '<div class="prod-list" id="prodList"><div class="skel" style="height:64px"></div></div>';
  const host = document.getElementById('prodList');
  if (!host) return;
  let list = [];
  try {
    const snap = await DB.collection('products').where('sellerId', '==', user.uid).get();
    list = snap.docs.map(norm).sort((a, b) => tsMillis(b.createdAt) - tsMillis(a.createdAt));
  } catch (_) {}
  if (!list.length) {
    host.innerHTML = emptyHtml(t('new_product'), '', t('home_browse'));
    return;
  }
  host.innerHTML = list.map((p) => '<div class="prod-row' + (p.isActive ? '' : ' off') + '">'
    + '<div class="thumb">' + (p.images[0] ? '<img src="' + esc(p.images[0]) + '" alt="" onerror="this.remove()">' : '') + '</div>'
    + '<div class="mid"><div class="nm">' + esc(p.name) + '</div>'
    + '<div class="pr">' + fmtTZS(p.price) + ' · ' + p.stock + ' · ' + esc(p.category) + '</div></div>'
    + '<div class="ctrls">'
    + '<button class="btn-sm" data-act="prodpub" data-p="' + encodeURIComponent(p.id) + '">' + esc(t(p.isActive ? 'unpublish' : 'publish')) + '</button>'
    + '<button class="btn-sm" data-act="prodedit" data-p="' + encodeURIComponent(p.id) + '">' + esc(t('edit_product')) + '</button>'
    + '<button class="btn-sm danger" data-act="proddel" data-p="' + encodeURIComponent(p.id) + '">' + esc(t('delete_product')) + '</button>'
    + '</div></div>').join('');
}

async function sellerOrdersBody(body, user) {
  body.innerHTML = '<h3>' + esc(t('seller_orders')) + '</h3>'
    + '<div class="order-list" id="soList"><div class="skel" style="height:64px"></div></div>';
  const host = document.getElementById('soList');
  if (!host) return;
  try {
    const snap = await DB.collection('orders').where('sellerId', '==', user.uid).limit(60).get();
    let pgByOrder = {};
    if (typeof window.sellerOrderActionsHtml === 'function') {
      try {
        const pg = await apiGet('/api/v1/orders?limit=200');
        const list = (pg && pg.data && (pg.data.orders || [])) || [];
        list.forEach((o) => {
          pgByOrder[String(o.id || '')] = o;
          if (o.orderNumber) pgByOrder[String(o.orderNumber)] = o;
          if (o.legacyFirestoreId) pgByOrder[String(o.legacyFirestoreId)] = o;
        });
      } catch (_) {}
    }
    const docs = snap.docs.map((d) => ({ d, o: d.data() }))
      .sort((a, b) => tsMillis(b.o.createdAt) - tsMillis(a.o.createdAt));
    host.innerHTML = docs.length ? docs.map(({ d, o }) => {
      const st = o.status || 'pending';
      const pill = PAY_STATES.has(st) ? 'done' : (BAD_STATES.has(st) ? 'bad' : 'wait');
      const pg = pgByOrder[String(o.orderId || '')] || pgByOrder[d.id] || null;
      const acts = (typeof window.sellerOrderActionsHtml === 'function')
        ? window.sellerOrderActionsHtml(o, user.uid, pg) : '';
      return '<div class="order-item">'
        + '<div class="thumb">' + (o.productImage ? '<img src="' + esc(o.productImage) + '" alt="" onerror="this.remove()">' : '') + '</div>'
        + '<div class="mid"><div class="nm">' + esc(o.buyerName || ('Oda #' + String(o.orderId || o.id).slice(0, 10))) + '</div>'
        + '<div class="meta">' + esc(o.productName || 'Agizo') + ' · ' + ts2date(o.createdAt) + '</div></div>'
        + '<div class="rt"><span class="amt">' + fmtTZS(o.totalAmount) + '</span>'
        + '<span class="pill ' + pill + '">' + esc(SV_T[lang].order_statuses[st] || st) + '</span>'
        + (o.buyerPhone ? '<a class="minilink" href="' + waLink(o.buyerPhone, 'Habari, kuhusu agizo #' + String(o.orderId || o.id) + ' (' + o.productName + ').') + '" target="_blank" rel="noopener">' + esc(t('wa_cta')) + '</a>' : '')
        + acts
        + '</div></div>';
    }).join('') : emptyHtml(t('my_orders_empty'), '', t('home_browse'));
  } catch (_) {
    host.innerHTML = emptyHtml(t('err_generic'), '', t('home_browse'));
  }
}

function sellerWalletBody(body, user, u, bal) {
  body.innerHTML = '<div class="wallet-card"><div class="bal"><span>' + esc(t('seller_balance_lbl')) + '</span>'
    + '<b id="wdBal">' + fmtTZS(bal) + '</b></div>'
    + '<form id="wdForm" class="wd-form"><div class="field"><label>' + esc(t('withdraw_amt')) + '</label>'
    + '<input id="wdAmt" type="number" min="1" step="1" inputmode="numeric"></div>'
    + '<div class="field"><label>' + esc(t('withdraw_phone')) + '</label>'
    + '<input id="wdPhone" value="' + esc(u.phone || '') + '" placeholder="+255 7xx xxx xxx"></div>'
    + '<button class="btn-accent" type="submit">' + esc(t('withdraw')) + '</button>'
    + '<p class="muted" style="font-size:12px;margin-top:10px">' + esc(t('min_withdraw')) + '</p>'
    + '</form></div>';
  const form = document.getElementById('wdForm');
  if (!form) return;
  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const amount = Math.round(Number(document.getElementById('wdAmt').value) || 0);
    const phone = e164(document.getElementById('wdPhone').value);
    if (amount < 1) { toast(t('min_withdraw')); return; }
    if (amount > bal) { toast('Kiasi kikubwa kuliko salio.'); return; }
    if (!phone) { toast('Andika namba ya simu ya ClickPesa.'); return; }
    try {
      const data = await apiPost('/api/payouts/seller/withdraw', { userId: user.uid, amount: amount, phone: phone });
      toast('✔ ' + t('withdraw_ok'));
      renderSellerPage('wallet');
    } catch (err) { toast(errMsg(err)); }
  });
}

function productFormHtml(p) {
  const cats = browseCats().map((c) => '<option value="' + esc(c) + '"' + (p && p.category === c ? ' selected' : '') + '>' + esc(c) + '</option>').join('');
  const conds = ['new', 'used', 'refurbished'].map((c) => '<option value="' + c + '"' + (p && p.condition === c ? ' selected' : '') + '>' + esc(t('cond_' + c)) + '</option>').join('');
  const ws = p && p.isWholesale && p.wholesaleTiers && p.wholesaleTiers.length ? p.wholesaleTiers : [{ minQuantity: 10, pricePerUnit: '' }];
  const wsRows = ws.map((ti, i) => '<div class="ws-row"><input class="ws-min" data-i="' + i + '" type="number" min="2" placeholder="' + esc(t('ws_min')) + '" value="' + esc(ti.minQuantity) + '">'
    + '<input class="ws-price" data-i="' + i + '" type="number" min="1" placeholder="' + esc(t('ws_price')) + '" value="' + esc(ti.pricePerUnit) + '"></div>').join('');
  return '<div class="container-wide" style="max-width:760px;margin:0 auto;padding-top:14px">'
    + '<div class="headline-row"><a class="mini-link" href="#/seller?t=products">← ' + t('back') + '</a>'
    + '<span style="font-family:var(--font-display);font-weight:700;color:var(--ink);font-size:16px">' + (p ? t('edit_product') : t('new_product')) + '</span></div>'
    + '<div class="form-card">'
    + '<input type="hidden" id="pfId" value="' + esc(p ? p.id : '') + '">'
    + '<div class="field"><label>' + t('product_name') + '</label><input id="pfName" value="' + esc(p ? p.name : '') + '"></div>'
    + '<div class="form-row"><div class="field"><label>' + t('product_price') + '</label><input id="pfPrice" type="number" min="1" value="' + (p ? p.price : '') + '"></div>'
    + '<div class="field"><label>' + t('product_stock') + '</label><input id="pfStock" type="number" min="0" value="' + (p ? p.stock : '') + '"></div></div>'
    + '<div class="form-row"><div class="field"><label>' + t('product_cat') + '</label><select id="pfCat">' + cats + '</select></div>'
    + '<div class="field"><label>' + t('product_cond') + '</label><select id="pfCond">' + conds + '</select></div></div>'
    + '<div class="field"><label>' + t('product_subcat') + '</label><input id="pfSub" value="' + esc(p ? p.subcategory : '') + '"></div>'
    + '<div class="field"><label>' + t('product_desc') + '</label><textarea id="pfDesc" rows="3">' + esc(p ? p.description : '') + '</textarea></div>'
    + '<div class="field"><label>' + t('product_imgs') + '</label><input id="pfImgs" value="' + esc(p ? (p.images || []).join(', ') : '') + '" placeholder="https://…, https://…"></div>'
    + '<div class="field"><label>' + t('product_loc') + '</label><input id="pfLoc" value="' + esc(p ? p.location : '') + '" placeholder="Mkoa, Wilaya"></div>'
    + '<label class="chk"><input type="checkbox" id="pfWs"' + (p && p.isWholesale ? ' checked' : '') + '> <span>' + esc(t('ws_toggle')) + '</span></label>'
    + '<div id="pfWsRows" class="ws-rows"' + (p && p.isWholesale ? '' : ' style="display:none"') + '>' + wsRows + '</div>'
    + '<button class="btn-accent btn-block mt16" data-act="prodsave">' + esc(t('save_product')) + '</button>'
    + '</div></div>';
}

async function sellerProdEditor(pid) {
  let p = null;
  if (pid) p = await getProduct(pid);
  view.innerHTML = productFormHtml(p);
  const wsChk = document.getElementById('pfWs');
  if (wsChk) wsChk.addEventListener('change', () => {
    const rows = document.getElementById('pfWsRows');
    if (rows) rows.style.display = wsChk.checked ? '' : 'none';
  });
}

async function saveSellerProduct() {
  const user = AUTH.currentUser;
  if (!user) return;
  const id = (document.getElementById('pfId') || {}).value || '';
  const name = (document.getElementById('pfName').value || '').trim();
  const price = Math.round(Number(document.getElementById('pfPrice').value) || 0);
  const stock = Math.max(0, Math.round(Number(document.getElementById('pfStock').value) || 0));
  const category = document.getElementById('pfCat').value;
  const condition = document.getElementById('pfCond').value;
  const subcategory = (document.getElementById('pfSub').value || '').trim();
  const description = (document.getElementById('pfDesc').value || '').trim();
  const images = (document.getElementById('pfImgs').value || '').split(',').map((x) => x.trim()).filter(Boolean).slice(0, 8);
  const locTxt = (document.getElementById('pfLoc').value || '').trim();
  const parts = locTxt.split(/[,]/).map((x) => x.trim()).filter(Boolean);
  const location = parts[0] || '';
  const district = parts[1] || '';
  const isWs = !!document.getElementById('pfWs').checked;
  const wholesaleTiers = isWs
    ? $all('.ws-row').map((r) => ({
        minQuantity: Math.max(2, Math.round(Number($('.ws-min', r).value) || 0)),
        pricePerUnit: Math.max(1, Math.round(Number($('.ws-price', r).value) || 0)),
      })).filter((t) => t.minQuantity >= 2 && t.pricePerUnit >= 1)
    : [];
  if (!name || price < 1) { toast('Andika jina na bei sahihi.'); return; }
  const keywords = (name + ' ' + (category || '') + ' ' + (subcategory || '')).toLowerCase().split(/[^a-z0-9]+/).filter((w) => w.length >= 3);
  const base = {
    name: name,
    searchName: name.toLowerCase(),
    description: description,
    price: price,
    currency: 'TZS',
    images: images,
    imageMetadata: [],
    videoUrl: '',
    category: category,
    subcategory: subcategory,
    location: location,
    district: district,
    stock: stock,
    brand: '',
    condition: condition,
    isWholesale: isWs,
    wholesaleTiers: wholesaleTiers,
    variants: [],
    attributes: {},
    searchKeywords: keywords,
  };
  try {
    if (id) {
      await DB.collection('products').doc(id).update(base);
    } else {
      let seller = {};
      try { const snap = await DB.collection('users').doc(user.uid).get(); if (snap.exists) seller = snap.data(); } catch (_) {}
      await DB.collection('products').add({
        ...base,
        sellerId: user.uid,
        sellerName: seller.sellerName || user.displayName || 'Duka',
        sellerPhone: seller.phone || '',
        rating: 0,
        reviewCount: 0,
        soldCount: 0,
        isActive: true,
        isFeatured: false,
        featuredUntil: null,
        sellerKycApproved: !!seller.kyc,
        barcode: null,
        createdAt: firebase.firestore.FieldValue.serverTimestamp(),
      });
    }
    toast('✔ ' + t('save_product'));
    renderSellerPage('products');
  } catch (e) { toast(errMsg(e)); }
}

/* ---------- Router + actions ---------- */

let orderFilter = 'all';

const ACTIONS = {
  dismissbar: () => {},
  opencats: () => openCats(),
  msgstore: (el) => {
    const u = decodeURIComponent(el.dataset.u || '');
    const n = decodeURIComponent(el.dataset.n || 'Muuzaji');
    location.hash = '#/chat/' + encodeURIComponent(u) + '?name=' + encodeURIComponent(n);
  },
  bnsearch: (el, e) => {
    e.preventDefault();
    if (window.innerWidth < 768) {
      const t = document.getElementById('svMobileSearchT');
      const form = document.getElementById('searchForm');
      if (t && form && !form.classList.contains('sv-expanded')) t.click();
    }
    setTimeout(() => { const i = document.getElementById('searchInput'); if (i) i.focus(); }, 140);
    setTimeout(() => { location.hash = '#/search'; }, 240);
  },
  closecats: () => closeCats(),
  ofilter: (el) => { orderFilter = el.dataset.v; renderOrders(); },
  dsub: (el) => fillDrawerSub(decodeURIComponent(el.dataset.cat || '')),
  openprod: (el) => { location.hash = '#/p/' + encodeURIComponent(el.dataset.p); },
  qaddcart: (el, e) => { e.preventDefault(); e.stopPropagation(); quickAdd(decodeURIComponent(el.dataset.p)); },
  qbuynow: (el, e) => {
    e.preventDefault(); e.stopPropagation();
    const p = decodeURIComponent(el.dataset.p || '');
    location.hash = '#/checkout?p=' + encodeURIComponent(p) + '&q=1';
  },
  fav: (el, e) => {
    e.preventDefault(); e.stopPropagation();
    const pid = decodeURIComponent(el.dataset.p || '');
    toggleWish(pid);
    const arr = document.querySelectorAll('.fav[data-p="' + el.dataset.p + '"]');
    arr.forEach((o) => o.classList.toggle('onfav', wishHas(pid)));
    if ((location.hash || '').indexOf('#/wishlist') === 0) renderWishlist();
  },
  wish: (el, e) => {
    if (e) { e.preventDefault(); e.stopPropagation(); }
    const pid = decodeURIComponent(el.dataset.p || '');
    const added = toggleWish(pid);
    el.classList.toggle('onfav', added);
  },
  copylink: (el) => {
    const pid = decodeURIComponent(el.dataset.p || '');
    const url = location.href.split('#')[0] + '#/p/' + encodeURIComponent(pid);
    const done = () => toast('✔ ' + t('copied'));
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(url).then(done).catch(() => fallbackCopy(url, done));
    } else fallbackCopy(url, done);
  },
  rvstar: (el) => {
    const host = el.closest('#revForm');
    const cur = Number(el.dataset.v) || 5;
    if (host) host._rv = cur;
    $all('.rv-star', host).forEach((x) => x.classList.toggle('on', Number(x.dataset.v) <= cur));
  },
  becomeseller: async () => {
    const user = AUTH.currentUser;
    if (!user) return;
    let seller = {};
    try { const snap = await DB.collection('users').doc(user.uid).get(); if (snap.exists) seller = snap.data(); } catch (_) {}
    try {
      await DB.collection('users').doc(user.uid).set({
        isSeller: true,
        sellerName: seller.name || user.displayName || 'Duka',
        phone: seller.phone || user.phoneNumber || '',
      }, { merge: true });
      toast('✔ ' + t('seller_you'));
      renderSellerPage('overview');
    } catch (e) { toast(errMsg(e)); }
  },
  sbtab: (el) => renderSellerPage(el.dataset.tab || 'overview'),
  prodnew: () => sellerProdEditor(null),
  prodedit: (el) => sellerProdEditor(decodeURIComponent(el.dataset.p)),
  prodsave: () => saveSellerProduct(),
  prodpub: async (el) => {
    const id = decodeURIComponent(el.dataset.p || '');
    try {
      const soon = await DB.collection('products').doc(id).get().catch(() => null);
      const isActive = soon ? soon.data().isActive !== false : true;
      await DB.collection('products').doc(id).update({ isActive: !isActive });
      toast('✔ ' + t(isActive ? 'unpublish' : 'publish'));
      renderSellerPage('products');
    } catch (err) { toast(errMsg(err)); }
  },
  proddel: async (el) => {
    const id = decodeURIComponent(el.dataset.p || '');
    if (!window.confirm(t('del_confirm'))) return;
    try {
      await DB.collection('products').doc(id).delete();
      toast('✔ ' + t('delete_product'));
      renderSellerPage('products');
    } catch (err) { toast(errMsg(err)); }
  },
  postreview: async (el) => {
    const pid = decodeURIComponent(el.dataset.p || '');
    const sellerId = decodeURIComponent(el.dataset.s || '');
    const user = AUTH.currentUser;
    if (!user) { renderAuthForm('signin'); return; }
    const form = el.closest('#revForm');
    const rating = (form && form._rv) || 5;
    const commentEl = document.getElementById('revComment');
    const comment = commentEl ? commentEl.value.trim() : '';
    if (!comment) { toast('Andika maoni.'); return; }
    try {
      await DB.collection('reviews').add({
        productId: pid,
        sellerId,
        userId: user.uid,
        userName: user.displayName || user.email || 'Mteja',
        userImage: '',
        rating: rating,
        comment: comment,
        images: [],
        helpfulCount: 0,
        isVerifiedPurchase: false,
        createdAt: firebase.firestore.FieldValue.serverTimestamp(),
      });
      await recomputeProductRating(pid);
      toast('✔ ' + t('review_ok'));
      loadReviews(pid, sellerId);
    } catch (err) { toast(errMsg(err)); }
  },
  loadmore: () => loadPageInto(),
  sort: (el) => sortFeedView(el.value),
  img: () => {},
  qplus: () => {},
  qminus: () => {},
  addcart: () => {},
  buynow: () => {},
  hprev: () => setHeroIndex(heroIdx - 1),
  hnext: () => setHeroIndex(heroIdx + 1),
  hdot: (el) => setHeroIndex(el.dataset.i),
  ckcart: () => checkoutNextLine(),
  cqplus: (el) => { cartBump(el, 1); },
  cqminus: (el) => { cartBump(el, -1); },
  cartrm: (el) => {
    cart = cart.filter((i) => !(i.p === el.dataset.p && (i.v || '') === el.dataset.v));
    saveCart(); refreshBadge(); renderCart();
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

Object.assign(ACTIONS, window.__PARITY_ACTIONS || {});
document.addEventListener('DOMContentLoaded', () => {
  Object.assign(ACTIONS, window.__PARITY_ACTIONS || {});
});

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
  closeCats();
  const h = location.hash.replace(/^#\/?/, '');
  const path = h.split('?')[0];
  const seg = path.split('/').filter(Boolean);
  const q = paramsOf();
  if (seg.length === 0) return renderHome();
  if (seg[0] === 'p' && seg[1]) return renderProduct(seg[1]);
  if (seg[0] === 'c' && seg[1]) {
    const cat = decodeURIComponent(seg[1]);
    if (window.SV && window.SV.search) return window.SV.search.render('', cat);
    return renderCategory(cat);
  }
  if (seg[0] === 'cart') return renderCart();
  if (seg[0] === 'checkout' && q.p) return renderCheckout(q.p, Number(q.q) || 1, q.v || null);
  if (seg[0] === 'search') return renderSearch(q.q || '', q.c || '');
  if (seg[0] === 'orders') return renderOrders();
  if (seg[0] === 'o' && seg[1]) return renderOrderDetail(decodeURIComponent(seg[1]));
  if (seg[0] === 'notifications' && typeof window.renderNotifications === 'function') return window.renderNotifications();
  if (seg[0] === 'notifprefs' && typeof window.renderNotifPrefs === 'function') return window.renderNotifPrefs();
  if (seg[0] === 'chats' && typeof window.renderChatInbox === 'function') return window.renderChatInbox();
  if (seg[0] === 'chat' && seg[1] && typeof window.renderChatRoom === 'function') {
    const prm = paramsOf();
    return window.renderChatRoom(seg[1], prm.name ? decodeURIComponent(prm.name) : 'Muuzaji');
  }
  if (seg[0] === 'flash' && typeof window.renderFlashSale === 'function') return window.renderFlashSale();
  if (seg[0] === 'wishlist') return renderWishlist();
  if (seg[0] === 'store' && seg[1] && window.SV.store) return window.SV.store.render(decodeURIComponent(seg[1]));
  if (seg[0] === 'seller') return renderSellerPage(q.t || 'overview');
  if (seg[0] === 'account') { if (q.mode) renderAuthForm(q.mode === 'signup' ? 'signup' : 'signin'); else renderAccount(); return; }
  return renderHome();
}

function refreshChip() {
  const user = AUTH.currentUser;
  const label = user ? (user.displayName || user.email || 'Akaunti') : t('nav_signin');
  const navAcct = document.getElementById('navAcctTxt');
  if (navAcct) navAcct.textContent = label;
  const bnAcct = document.getElementById('bnAcctTxt');
  if (bnAcct) bnAcct.textContent = user ? 'Akaunti' : t('nav_signin');
}

function highlightActiveNav() {
  const h = location.hash.replace(/^#\/?/, '');
  const seg = (h.split('?')[0]).split('/').filter(Boolean)[0] || '';
  const map = { '': 'home', p: 'home', c: 'cats', search: 'search', orders: 'orders', o: 'orders', wishlist: 'account', seller: 'account', account: 'account' };
  const key = map[seg] || '';
  const targets = { home: 'a[href="#/"]', cats: '[data-bn-cat]', search: 'a[href="#/search"]', orders: 'a[href="#/orders"]', account: 'a[href="#/account"]' };
  const tgt = targets[key] ? document.querySelector(targets[key]) : null;
  $all('[data-bn]').forEach((b) => b.classList.toggle('on', b === tgt));
  const curPath = location.hash.split('?')[0];
  $all('.top-links a[data-nav][href^="#"]').forEach((a) => {
    a.classList.toggle('on', (a.getAttribute('href') || '').split('?')[0] === curPath);
  });
  $all('.h-actions a.hl-act[href^="#"]').forEach((a) => {
    a.classList.toggle('on', (a.getAttribute('href') || '').split('?')[0] === curPath);
  });
}

/* ---------- Search + suggestions ---------- */

function searchSubmit(q, cat) {
  if (!q && !cat) return;
  if (q && cat) { location.hash = '#/search?q=' + encodeURIComponent(q) + '&c=' + encodeURIComponent(cat); return; }
  if (cat) { location.hash = '#/c/' + encodeURIComponent(cat); return; }
  location.hash = '#/search?q=' + encodeURIComponent(q);
}

function suggest(q) {
  const box = document.getElementById('suggestBox');
  if (!box) return;
  if (typeof window.enhanceSuggest === 'function') { window.enhanceSuggest(q); return; }
  const ql = (q || '').trim().toLowerCase();
  if (!ql || !Feed.list.length) { box.hidden = true; return; }
  const hits = Feed.list.filter((p) => (p.name || '').toLowerCase().indexOf(ql) >= 0).slice(0, 6).map((p) => p.name);
  if (!hits.length) { box.hidden = true; return; }
  box.innerHTML = hits.map((n) => '<button type="button" data-act="sugg">' + esc(n) + '</button>').join('');
  box.hidden = false;
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
  const cat = document.getElementById('catSelect').value;
  const box = document.getElementById('suggestBox');
  if (box) box.hidden = true;
  searchSubmit(q, cat);
});

const searchInput = document.getElementById('searchInput');
searchInput.addEventListener('input', () => suggest(searchInput.value));
searchInput.addEventListener('blur', () => setTimeout(() => { const b = document.getElementById('suggestBox'); if (b) b.hidden = true; }, 220));

const slPrev = document.getElementById('slPrev');
const slNext = document.getElementById('slNext');
if (slPrev) slPrev.addEventListener('click', () => setHeroIndex(heroIdx - 1));
if (slNext) slNext.addEventListener('click', () => setHeroIndex(heroIdx + 1));
const slDots = document.getElementById('slDots');
if (slDots) slDots.addEventListener('click', (e) => { const d = e.target.closest('i'); if (d) setHeroIndex(Number(d.dataset.i) || 0); });

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

document.getElementById('catToggle').addEventListener('click', () => openCats());

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

window.addEventListener('hashchange', () => { closeCats(); route(); highlightActiveNav(); });

(function init() {
  setTheme();
  setLang();
  updateThemeIcon();
  const si = document.getElementById('searchInput');
  si.placeholder = t('search_ph');
  document.title = 'Soko Vibe — Duka';
  buildCats();
  buildHero();
  refreshBadge();
  refreshWishBadge();
  refreshChip();
  highlightActiveNav();

  /* Slim offline bar — surfaces connectivity state without breaking flow. */
  (function offlineBar() {
    const bar = document.createElement('div');
    bar.id = 'offlineBar';
    bar.setAttribute('role', 'status');
    bar.innerHTML = '<span>' + esc(t('offline')) + '</span><button type="button" data-act="dismissbar" class="sv-btn sv-btn-ghost" style="padding:4px 10px;font-size:11.5px">' + esc(t('dismiss')) + '</button>';
    bar.style.cssText = 'position:fixed;top:0;left:0;right:0;z-index:9999;display:none;align-items:center;justify-content:space-between;background:var(--sv-warning);color:#fff;padding:6px 14px;font-size:12.5px;font-weight:600;';
    document.body.prepend(bar);
    function show() { bar.style.display = 'flex'; }
    function hide() { bar.style.display = 'none'; }
    window.addEventListener('offline', show);
    window.addEventListener('online', () => { hide(); location.reload(); });
    if (!navigator.onLine) show();
    bar.addEventListener('click', (e) => { if (e.target.closest('[data-act="dismissbar"]')) hide(); });
  })();

/* ---------- SEO / Structured Data (global) ---------- */
  window.injectJsonLd = function (obj) {
    try {
      var s = document.createElement('script');
      s.type = 'application/ld+json';
      s.textContent = JSON.stringify(obj);
      document.head.appendChild(s);
    } catch (e) { /* non-critical */ }
  };
  window.setPageMeta = function (title, desc, canonical, ogImg) {
    try {
      var t = document.querySelector('title'); if (t) t.textContent = title;
      var d = document.querySelector('meta[name="description"]'); if (d) d.setAttribute('content', desc);
      var c = document.querySelector('link[rel="canonical"]'); if (c) c.setAttribute('href', canonical);
      var ogT = document.querySelector('meta[property="og:title"]'); if (ogT) ogT.setAttribute('content', title);
      var ogD = document.querySelector('meta[property="og:description"]'); if (ogD) ogD.setAttribute('content', desc);
      var ogC = document.querySelector('meta[property="og:url"]'); if (ogC) ogC.setAttribute('content', canonical);
      if (ogImg) { var ogI = document.querySelector('meta[property="og:image"]'); if (ogI) ogI.setAttribute('content', ogImg); }
    } catch (e) { /* non-critical */ }
  };
  /* SEO route meta (lightweight) */
  (function seoForRoute() {
    var h = location.hash.replace(/^#\/?/, '');
    var seg = h.split('?')[0].split('/').filter(Boolean);
    var base = location.origin + '/shop';
    if (seg[0] === 'store' && seg[1]) {
      setPageMeta('Kibanda — Soko Vibe', 'Jadi kwa muuzaji huu kwenye Soko Vibe, soko la Tanzania.', base + '/store/' + encodeURIComponent(seg[1]));
    } else if (seg[0] === 'c' && seg[1]) {
      setPageMeta(decodeURIComponent(seg[1]) + ' — Soko Vibe', 'Pata ' + decodeURIComponent(seg[1]) + ' bora kwenye Soko Vibe.', base + '/category/' + encodeURIComponent(seg[1]));
    } else if (h.indexOf('search') === 0) {
      setPageMeta('Matokeo ya Utafutaji — Soko Vibe', 'Tafuta bidhaa, masoko, na wauzaji kwenye Soko Vibe.', base + '/search');
    } else {
      setPageMeta('Soko Vibe — Nunuza Bidhaa Mtandaoni Tanzania', 'Soko la Tanzania.', base + '/', 'https://www.sokovibe.co.tz/assets/icon-512.png');
    }
  })();
})();

window.addEventListener('DOMContentLoaded', () => route());