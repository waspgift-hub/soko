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
  const res = await fetch(path, { headers: apiHeaders(token) });
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
  const n = Math.round(p.rating || 0);
  let s = '';
  for (let i = 1; i <= 5; i++) s += i <= n ? '★' : '☆';
  return '<span class="stars"' + (size ? ' style="font-size:' + size + '"' : '') + '>' + s
    + (p.reviewCount ? '<b>(' + p.reviewCount + ')</b>' : '') + '</span>';
}

const SELLER_SEAL = '<span class="vbadge"><svg width="9" height="9" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6L9 17l-5-5"/></svg>Verified</span>';

/* ---------- Card markup (div-based, quick actions) ---------- */

function cardHtml(p) {
  const img = p.images[0];
  const bo = boosted(p);
  const soldout = p.stock <= 0;
  const flag = soldout
    ? '<span class="flag sold">' + esc(t('out_stock')) + '</span>'
    : (bo ? '<span class="flag boost">' + esc(bo) + '</span>' : '');
  const price = '<span class="pr">' + fmtTZS(p.price)
    + (p.isWholesale && p.wholesaleTiers && p.wholesaleTiers.length ? '<span class="muted">' + fmtTZS(p.wholesaleTiers[0].pricePerUnit) + '</span>' : '')
    + '</span>';
  const foot = soldout
    ? '<span class="soldnote">' + esc(t('out_stock')) + '</span>'
    : '<button class="q-btn q-add" data-act="qaddcart" data-p="' + encodeURIComponent(p.id) + '">'
      + '<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><circle cx="8" cy="21" r="1"/><circle cx="19" cy="21" r="1"/><path d="M2.05 2.05h2l2.66 12.42a2 2 0 0 0 2 1.58h9.78a2 2 0 0 0 1.95-1.57l1.65-7.43H5.12"/></svg>'
      + esc(t('add_cart')) + '</button>'
      + '<button class="q-btn q-buy" data-act="qbuynow" data-p="' + encodeURIComponent(p.id) + '">' + esc(t('buy_now')) + '</button>';
  return '<div class="card" data-act="openprod" data-p="' + encodeURIComponent(p.id) + '" role="link" tabindex="0" aria-label="' + esc(p.name) + '">'
    + '<div class="thumb">' + flag
    + '<button class="fav" data-act="fav" data-p="' + encodeURIComponent(p.id) + '" aria-label="Penda" type="button">'
    + '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 14c1.49-1.46 3-3.21 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.76 0-3 .5-4.5 2-1.5-1.5-2.74-2-4.5-2A5.5 5.5 0 0 0 2 8.5c0 2.3 1.5 4.05 3 5.5l7 7Z"/></svg></button>'
    + (img
      ? '<img loading="lazy" src="' + esc(img) + '" alt="' + esc(p.name) + '" onerror="this.parentElement.classList.add(\'badimg\');this.remove()">'
      : '<div class="ph">SOKO</div>')
    + '</div>'
    + '<div class="body">'
    + '<span class="cat">' + esc(p.category) + '</span>'
    + '<span class="nm">' + esc(p.name) + '</span>'
    + price
    + '<div class="meta">'
    + '<span class="loc"><svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 10c0 6-8 12-8 12s-8-6-8-12a8 8 0 0 1 16 0Z"/><circle cx="12" cy="10" r="3"/></svg>' + esc(p.location || 'Tanzania') + '</span>'
    + (p.rating > 0 ? stars(p) : '<span>—</span>')
    + '</div>'
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

function buildCats() {
  const side = document.getElementById('sideCatList');
  const drawer = document.getElementById('catList');
  const sel = document.getElementById('catSelect');
  if (side) {
    side.innerHTML = '<div class="side-list">' + SV_CATEGORIES.map((c) => catSideItem(c)).join('') + '</div>';
  }
  if (drawer) {
    drawer.innerHTML = '<div class="side-list">' + SV_CATEGORIES.map((c) => catSideItem(c, true)).join('') + '</div>';
  }
  if (sel) {
    sel.innerHTML = '<option value="">Kategoria zote</option>'
      + SV_CATEGORIES.map((c) => '<option value="' + esc(c) + '">' + esc(c) + '</option>').join('');
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
    + SV_CATEGORIES.map((c) => '<a class="chip' + (c === active ? ' active' : '') + '" href="#/c/' + encodeURIComponent(c) + '">' + esc(c) + '</a>').join('')
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
    return catSort(list.filter((p) => p.category === Feed.mode.cat || (p.subcategory || '').toLowerCase() === String(Feed.mode.cat).toLowerCase()));
  }
  if (Feed.mode.kind === 'query') {
    const q = String(Feed.mode.q || '').toLowerCase();
    return catSort(list.filter((p) => {
      const hit = !q || (p.name || '').toLowerCase().indexOf(q) >= 0 || (p.brand || '').toLowerCase().indexOf(q) >= 0;
      if (!hit) return false;
      if (Feed.mode.c) {
        return p.category === Feed.mode.c || (p.subcategory || '').toLowerCase() === String(Feed.mode.c).toLowerCase();
      }
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
  host.innerHTML = list.map(cardHtml).join('') + (Feed.loading && list.length === 0 ? skelGrid(8) : '');
  if (sent) sent.style.display = Feed.done ? 'none' : 'block';
  const moreBtn = document.getElementById('moreBtn');
  if (moreBtn) moreBtn.style.display = Feed.done || errFlag ? 'none' : 'inline-flex';
  const sel = document.getElementById('sortSel');
  if (sel) sel.value = Feed.sort;
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
  const inMem = Feed.list.filter((p) => {
    const hit = !q || (p.name || '').toLowerCase().indexOf(q.toLowerCase()) >= 0 || (p.brand || '').toLowerCase().indexOf(q.toLowerCase()) >= 0;
    if (!hit) return false;
    if (cat) return p.category === cat || (p.subcategory || '').toLowerCase() === cat.toLowerCase();
    return true;
  });
  if (inMem.length) { renderFeed(); return; }
  try {
    const ql = q.toLowerCase();
    const snap = q
      ? await DB.collection('products').where('searchName', '>=', ql).where('searchName', '<=', ql + '\uf8ff').limit(PAGE * 2).get()
      : await DB.collection('products').orderBy('createdAt', 'desc').limit(PAGE * 2).get();
    const hits = snap.docs.map(norm).filter((p) => {
      if (!p.isActive) return false;
      if (q && (p.name || '').toLowerCase().indexOf(ql) < 0 && (p.brand || '').toLowerCase().indexOf(ql) < 0) return false;
      if (cat) return p.category === cat || (p.subcategory || '').toLowerCase() === cat.toLowerCase();
      return true;
    });
    host.innerHTML = hits.length ? hits.map(cardHtml).join('') : emptyHtml(t('empty_filter'), q || cat, t('home_browse'));
    const sent = document.getElementById('sentinel');
    if (sent) sent.style.display = 'none';
    const moreBtn = document.getElementById('moreBtn');
    if (moreBtn) moreBtn.style.display = 'none';
  } catch (e) {
    host.innerHTML = emptyHtml(t('err_generic'), '', t('home_browse'));
  }
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
  const thumbs = p.images.slice(1, 6).map((u, i) =>
    '<button data-act="img" data-i="' + (i + 1) + '"><img src="' + esc(u) + '" alt="" onerror="this.remove()"></button>').join('');
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
    + '<div class="main"><img id="mainImg" src="' + esc(mainImg) + '" alt="' + esc(p.name) + '" onerror="this.replaceWith(Object.assign(document.createElement(\'div\'),{className:\'ph\',textContent:\'SOKO\'}))"></div>'
    + (thumbs ? '<div class="thumbs">' + thumbs + '</div>' : '')
    + '</div>'
    + '<div class="dinfo">'
    + '<span class="crumb">' + esc(p.category) + (p.subcategory ? ' / ' + esc(p.subcategory) : '') + '</span>'
    + '<h1>' + esc(p.name) + '</h1>'
    + '<div class="rating-line">' + (p.rating > 0 ? stars(p, '14px') : '<span>Hakuna tathmini</span>')
    + '<span class="loc"><svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 10c0 6-8 12-8 12s-8-6-8-12a8 8 0 0 1 16 0Z"/><circle cx="12" cy="10" r="3"/></svg>' + esc(p.location || 'Tanzania') + (p.district ? ' · ' + esc(p.district) : '') + '</span></div>'
    + '<div class="price" id="priceNow">' + fmtTZS(p.price) + '</div>'
    + '<div class="tags">' + stockTxt
    + '<span class="tag">' + esc(p.condition) + '</span>'
    + (p.brand ? '<span class="tag">' + esc(p.brand) + '</span>' : '')
    + (bo ? '<span class="tag" style="border-color:var(--accent);color:var(--good)">★ ' + esc(bo) + '</span>' : '')
    + '</div>'
    + variants
    + '<div class="picker"><span class="section-muted">' + t('qty') + ':</span>'
    + '<div class="stepper"><button type="button" data-act="qminus" aria-label="-">−</button><span class="n" id="qtyN">1</span><button type="button" data-act="qplus" aria-label="+">+</button></div>'
    + '<span class="section-muted" id="stockNote">' + (soldout ? t('out_stock') : (p.maxOrder ? 'max ' + p.maxOrder : '')) + '</span></div>'
    + '<div class="rowbtns">'
    + '<button class="btn-dark" data-act="buynow"' + (soldout ? ' disabled' : '') + '>' + t('buy_now') + '</button>'
    + '<button class="icon-btn" data-act="addcart" title="' + esc(t('add_cart')) + '"' + (soldout ? ' disabled' : '') + ' aria-label="' + esc(t('add_cart')) + '">'
    + '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="8" cy="21" r="1"/><circle cx="19" cy="21" r="1"/><path d="M2.05 2.05h2l2.66 12.42a2 2 0 0 0 2 1.58h9.78a2 2 0 0 0 1.95-1.57l1.65-7.43H5.12"/></svg></button>'
    + '</div>'
    + '<div class="seller-card">'
    + '<div class="who"><div class="avatar">' + esc((p.sellerName || 'S').slice(0, 1).toUpperCase()) + '</div>'
    + '<div style="flex:1"><div class="nm">' + esc(p.sellerName) + ' ' + SELLER_SEAL + '</div>'
    + '<div class="loc">' + esc(p.location || 'Tanzania') + '</div></div></div>'
    + (p.sellerPhone ? '<a class="btn-wa btn-block" href="' + waLink(p.sellerPhone, 'Habari, ninauliza kuhusu ' + p.name + '.') + '" target="_blank" rel="noopener">'
      + '<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 11.5a8.38 8.38 0 0 1-.9 3.8 8.5 8.5 0 0 1-7.6 4.7 8.38 8.38 0 0 1-3.8-.9L3 21l1.9-5.7a8.38 8.38 0 0 1-.9-3.8 8.5 8.5 0 0 1 4.7-7.6 8.38 8.38 0 0 1 3.8-.9h.5a8.48 8.48 0 0 1 8 8v.5z"/></svg>'
      + esc(t('wa_cta')) + '</a>' : '')
    + '</div>'
    + '<div class="desc"><h3>' + t('description') + '</h3><p>' + esc(p.description) + '</p></div>'
    + tiers
    + (attrs ? '<div class="attrs mt24"><h3>' + t('attributes') + '</h3><table>' + attrs + '</table></div>' : '')
    + '</div></div></div>';

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
      const i = Number(el.dataset.i) || 0;
      const src = p.images[i];
      const m = document.getElementById('mainImg');
      if (m && src) m.src = src;
    }
  };
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

/* ---------- Orders ---------- */

function renderOrders() {
  setLang();
  setHero(false);
  const user = AUTH.currentUser;
  if (!user) {
    view.innerHTML = '<div class="container-wide">' + emptyHtml(t('need_auth'), '', t('nav_signin')).replace('#/', '#/account') + '</div>';
    return;
  }
  view.innerHTML = '<div class="container-wide"><div class="headline-row"><a class="mini-link" href="#/account">← ' + t('back') + '</a>'
    + '<span style="font-family:var(--font-display);font-weight:700;color:var(--ink);font-size:16px">' + t('orders_my') + '</span></div>'
    + '<div class="order-list"><div class="skel" style="height:74px"></div><div class="skel" style="height:74px"></div></div></div>';
  const host = $('.order-list');
  Promise.all([
    DB.collection('orders').where('buyerId', '==', user.uid).limit(50).get().catch(() => null),
  ]).then(([snap]) => {
    if (!host) return;
    if (!snap) { host.innerHTML = emptyHtml(t('err_generic'), '', t('home_browse')); return; }
    const orders = snap.docs.map((d) => d.data()).sort((a, b) => tsMillis(b.createdAt) - tsMillis(a.createdAt));
    if (!orders.length) { host.innerHTML = emptyHtml(t('my_orders_empty'), '', t('home_browse')); return; }
    host.innerHTML = orders.map(orderHtml).join('');
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
  if (!user) return;
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
    + '<div class="field"><label>' + t('password') + '</label><input id="aPass" type="password" autocomplete="current-password"></div>'
    + '<button class="btn-dark btn-block" id="authBtn">' + (authMode === 'signin' ? t('submit_signin') : t('submit_signup')) + '</button>'
    + '<div class="auth-switch">' + (authMode === 'signin'
      ? t('no_account') + ' <a href="#/account?mode=signup">' + t('submit_signup') + '</a>'
      : t('have_account') + ' <a href="#/account?mode=signin">' + t('submit_signin') + '</a>') + '</div>'
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
  if (!user) {
    renderAuthForm('signin');
    toast(t('need_auth'));
    return;
  }
  view.innerHTML = '<div class="container-wide"><div class="skel" style="height:480px;margin-top:18px"></div></div>';
  const p = await getProduct(id);
  if (!p) { view.innerHTML = '<div class="container-wide">' + emptyHtml(t('empty_filter'), '', t('home_browse')) + '</div>'; return; }
  const { unit, lineTotal } = checkoutMeta(p, qty, variantId);
  const regions = SV_REGIONS.map((r) => '<option value="' + esc(r) + '">' + esc(r) + '</option>').join('');
  view.innerHTML = '<div class="container-wide" style="max-width:940px;margin:0 auto;padding-top:18px">'
    + '<div class="headline-row"><a class="mini-link" href="#/p/' + encodeURIComponent(p.id) + '">← ' + t('back') + '</a>'
    + '<span style="font-family:var(--font-display);font-weight:700;color:var(--ink);font-size:16px">' + t('checkout_title') + '</span></div>'
    + stepsBar(1)
    + '<div class="ck-grid">'
    + '<div class="form-card"><h2>' + t('addr_heading') + '</h2>'
    + '<div class="field"><label>' + t('phone') + '</label><input id="ckPhone" value="' + esc(user.phoneNumber || '') + '" placeholder="+255 7xx xxx xxx"></div>'
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

/* ---------- Router + actions ---------- */

const ACTIONS = {
  opencats: () => openCats(),
  closecats: () => closeCats(),
  dsub: (el) => fillDrawerSub(decodeURIComponent(el.dataset.cat || '')),
  openprod: (el) => { location.hash = '#/p/' + encodeURIComponent(el.dataset.p); },
  qaddcart: (el, e) => { e.preventDefault(); e.stopPropagation(); quickAdd(decodeURIComponent(el.dataset.p)); },
  qbuynow: (el, e) => {
    e.preventDefault(); e.stopPropagation();
    const p = decodeURIComponent(el.dataset.p || '');
    location.hash = '#/checkout?p=' + encodeURIComponent(p) + '&q=1';
  },
  fav: (el, e) => { e.preventDefault(); e.stopPropagation(); el.classList.toggle('onfav'); el.style.color = el.classList.contains('onfav') ? '#c23434' : ''; },
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
  if (seg[0] === 'c' && seg[1]) return renderCategory(decodeURIComponent(seg[1]));
  if (seg[0] === 'cart') return renderCart();
  if (seg[0] === 'checkout' && q.p) return renderCheckout(q.p, Number(q.q) || 1, q.v || null);
  if (seg[0] === 'search') return renderSearch(q.q || '', q.c || '');
  if (seg[0] === 'orders') return renderOrders();
  if (seg[0] === 'o' && seg[1]) return renderOrderDetail(decodeURIComponent(seg[1]));
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

function highlightBottomNav() {
  const h = location.hash.replace(/^#\/?/, '');
  const seg = (h.split('?')[0]).split('/').filter(Boolean)[0] || '';
  const map = { '': 'home', cart: 'cart', orders: 'orders', o: 'orders', account: 'account' };
  const key = map[seg] || '';
  const targets = { home: 'a[href="#/"]', cart: 'a[href="#/cart"]', orders: 'a[href="#/orders"]', account: 'a[href="#/account"]' };
  const tgt = targets[key] ? document.querySelector(targets[key]) : null;
  $all('[data-bn]').forEach((b) => b.classList.toggle('on', b === tgt));
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

window.addEventListener('hashchange', () => { closeCats(); route(); highlightBottomNav(); });

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
  refreshChip();
  highlightBottomNav();
  route();
})();