/* Soko Vibe Admin Panel
   Vanilla no-build SPA. The single login method is ADMIN_SECRET, sent as the
   x-admin-secret header on the same-origin v2 + legacy-compat API. No
   Firebase, no Google dependency. */
'use strict';

const API = '';
const SECRET_KEY = 'sv_admin_secret';
const THEME_KEY = 'sv_admin_theme';
// A request must never hang the UI forever: abort slow calls so every
// section either renders or shows its error instead of spinning endlessly.
const API_TIMEOUT_MS = 30000;

const S = {}; // tiny client cache for cross-section lookups

const $ = (id) => document.getElementById(id);
function esc(v) {
  return String(v == null ? '' : v).replace(/[&<>"']/g, (c) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  }[c]));
}
function fmtNum(v) { return (Math.round(Number(v) || 0)).toLocaleString('en-US'); }
function fmtTZS(v) { return 'TSh ' + fmtNum(v); }
function fmtTime(v) {
  if (!v) return '—';
  const d = new Date(v);
  if (isNaN(d)) return esc(String(v));
  return d.toLocaleString('en-GB', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' });
}
// Inasa Firestore Timestamp ({seconds,...}), ISO string, na Date bila kuteleza.
function tsToISO(v) {
  if (!v) return '';
  if (v instanceof Date) return v.toISOString();
  if (typeof v === 'string') return v;
  if (typeof v === 'object') {
    const sec = v.seconds != null ? v.seconds : v._seconds;
    if (sec != null) return new Date(Number(sec) * 1000).toISOString();
    return '';
  }
  return '';
}
function fmtDay(v) {
  const iso = tsToISO(v);
  if (!iso) return '—';
  const d = new Date(iso);
  if (isNaN(d)) return '—';
  return d.toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' });
}
function money(v) { return '<span class="num">' + fmtTZS(v) + '</span>'; }
function id12(v) { return v ? String(v).slice(0, 8) : '—'; }
function avatarOf(u) {
  const src = u && u.avatarUrl && /^https?:\/\//.test(u.avatarUrl) ? u.avatarUrl : null;
  const name = (u && (u.displayName || u.storeName || '')) || (u && u.email) || '?';
  return src
    ? '<img class="thumb" src="' + esc(src) + '" alt="' + esc(name) + '" loading="lazy">'
    : '<div class="thumb" style="display:grid;place-items:center;background:var(--okbg);color:var(--sv-accent-strong);font-weight:700;font-size:14px">' + esc(name.charAt(0).toUpperCase()) + '</div>';
}
function badge(status) {
  const s = String(status || '?').toLowerCase();
  const map = {
    completed: 'ok', delivered: 'ok', completedorder: 'ok', wallet_credited: 'ok', payout_complete: 'ok',
    active: 'ok', approved: 'ok', verified: 'ok', resolved: 'ok', done: 'ok', success: 'ok', processed: 'ok',
    published: 'ok', actioned: 'ok',
    pending: 'warn', awaiting_escrow_payment: 'warn', in_escrow: 'info', payment_pending: 'warn',
    processing: 'info', payout_pending: 'warn', under_review: 'warn', requested: 'warn', eligibility_check: 'warn',
    pending_payment: 'warn', shipping_fee_review: 'warn', review_required: 'warn', submitted: 'info',
    dispatched: 'info', in_transit: 'info', ready_to_dispatch: 'info', out_for_delivery: 'info',
    suspended: 'bad', rejected: 'bad', deleted: 'bad', cancelled: 'bad', canceled: 'bad', failed: 'bad',
    disputed: 'bad', refund_pending: 'warn', refunded: 'mut', dismissed: 'bad', expired: 'mut',
    draft: 'mut', blockchain_: 'mut', not_seller: 'mut', profile_required: 'warn', active_draft: 'mut',
  };
  const cls = map[s] || 'mut';
  return '<span class="bdg ' + (s.indexOf('_') > -1 && !map[s] ? 'info' : cls) + '"><span class="dot"></span>' + esc(status) + '</span>';
}
function fsFlagBadge(v) {
  if (v === null || v === undefined) return '<span class="dim">—</span>';
  return v
    ? '<span class="bdg bad"><span class="dot"></span>suspended</span>'
    : '<span class="bdg ok"><span class="dot"></span>active</span>';
}
let toastT; function toast(msg, ok) {
  const el = $('toast');
  el.textContent = LANG === 'en' ? trText(msg) : msg;
  el.className = 'toast show ' + (ok ? 'ok' : 'bad');
  clearTimeout(toastT);
  toastT = setTimeout(() => (el.className = 'toast'), 3400);
}
function icons() { if (window.lucide) lucide.createIcons(); }

// ---------------------------------------------------------------------------
// Language: Swahili (default) + English. The panel always renders Swahili
// first; when EN is active a MutationObserver translates inserted content
// with a longest-match phrase dictionary, so sections, drawers, modals and
// toasts all flip without touching every string call site. The nav and page
// titles use explicit maps so toggling English -> Swahili restores cleanly.
// ---------------------------------------------------------------------------
const LANG_KEY = 'sv_admin_lang';
let LANG = 'sw';
try { LANG = localStorage.getItem(LANG_KEY) || 'sw'; } catch (_) {}
const NAV_SW = {
  'nav-dashboard': 'Dashibodi', 'grp-manage': 'Usimamizi', 'nav-users': 'Watumiaji', 'nav-sellers': 'Wauzaji',
  'nav-products': 'Bidhaa', 'nav-orders': 'Maagizo', 'grp-protect': 'Ulinzi na Mahusiano',
  'nav-disputes': 'Migogoro', 'nav-refunds': 'Marejesho', 'nav-reports': 'Ripoti & Ulinzi',
  'nav-kyc': 'Wathibitisho (KYC)', 'grp-sales': 'Mauzo', 'nav-promos': 'Boost & Flash Sales',
  'grp-finance': 'Fedha', 'nav-revenue': 'Mapato ya Jukwaa', 'nav-finance': 'Fedha & Ledger',
  'nav-referrals': 'Rufaa', 'grp-comm': 'Mawasiliano', 'nav-broadcasts': 'Matangazo ya Broad',
  'nav-audit': 'Ukaguzi (Audit)', 'nav-settings': 'Mipangilio', 'grp-stats': 'Takwimu', 'nav-stats': 'Takwimu za Matumizi',
  'nav-landing': 'Landing / Orodha',
};
const NAV_EN = {
  'nav-dashboard': 'Dashboard', 'grp-manage': 'Management', 'nav-users': 'Users', 'nav-sellers': 'Sellers',
  'nav-products': 'Products', 'nav-orders': 'Orders', 'grp-protect': 'Protection & Relations',
  'nav-disputes': 'Disputes', 'nav-refunds': 'Refunds', 'nav-reports': 'Reports & Safety',
  'nav-kyc': 'Verifications (KYC)', 'grp-sales': 'Sales', 'nav-promos': 'Boost & Flash Sales',
  'grp-finance': 'Finance', 'nav-revenue': 'Platform Revenue', 'nav-finance': 'Finance & Ledger',
  'nav-referrals': 'Referrals', 'grp-comm': 'Communication', 'nav-broadcasts': 'Broadcasts',
  'nav-audit': 'Audit', 'nav-settings': 'Settings', 'grp-stats': 'Stats', 'nav-stats': 'Usage Statistics',
  'nav-landing': 'Landing / Waitlist',
};
const TITLES_EN = {
  dashboard: 'Dashboard', users: 'Users', sellers: 'Sellers', products: 'Products', orders: 'Orders',
  disputes: 'Disputes', refunds: 'Refunds', reports: 'Reports & Safety', kyc: 'Verifications (KYC)',
  promos: 'Boost & Flash Sales', revenue: 'Platform Revenue', finance: 'Finance & Ledger',
  referrals: 'Referrals', broadcasts: 'Broadcasts', audit: 'Audit', stats: 'Usage Statistics', settings: 'Settings',
  landing: 'Landing / Waitlist',
};
const SW2EN = {
  // Nav / titles
  'Dashibodi': 'Dashboard', 'Watumiaji': 'Users', 'Wauzaji': 'Sellers', 'Bidhaa': 'Products',
  'Migogoro': 'Disputes', 'Marejesho': 'Refunds', 'Maelezo ya jumla': 'Overview',
  // Dashboard
  'Inapakia dashibodi…': 'Loading dashboard…',
  'Hali ya soko kwa mtazamo mmoja': 'Market at a glance',
  'Wapya leo: ': 'New today: ', 'Kamili: ': 'Completed: ',
  'Watumiaji': 'Users', 'Maagizo': 'Orders', 'Mapato ya Tume': 'Commission Revenue',
  'Escrow Inashikiliwa': 'Escrow Held', 'Bidhaa': 'Products',
  'tume iliyokusanywa': 'collected commission', 'jumla dukani': 'total in stores',
  'thamani ya bidhaa zilizouzwa': 'value of goods sold', 'holdi': 'holds',
  'Mapato ya kila siku (siku 30)': 'Daily revenue (30 days)',
  'pesa / tume / watumiaji': 'money / commission / users',
  'Maagizo kwa hali': 'Orders by status', 'Angalia zote': 'View all',
  'Maagizo ya hivi punde': 'Recent orders', 'Agizo': 'Order', 'Mnunuzi': 'Buyer', 'Jumla': 'Total',
  'Hakuna maagizo bado': 'No orders yet',
  'Kazi zinazosubiri': 'Pending tasks', 'bonyeza kwenda': 'click to open',
  'Withdrawals zinazosubiri': 'Pending withdrawals', 'Migogoro wazi': 'Open disputes',
  'Wauzaji wanaosubiri uthibitisho': 'Sellers awaiting verification',
  'Marejesho yanayosubiri': 'Pending refunds',
  'Mtandaoni sasa hivi': 'Online right now', 'Dakika 1': '1 min', 'Dakika 5': '5 min',
  'Dakika 15': '15 min', 'Saa 1': '1 hour', 'Siku 1': '1 day',
  // Common UI
  'Inapakia…': 'Loading…', 'Inapakia': 'Loading', 'Hakuna watumiaji': 'No users',
  'Hakuna bidhaa': 'No products', 'Hakuna wauzaji': 'No sellers', 'Hakuna maagizo': 'No orders',
  'Hakuna rekodi': 'No records', 'ANGALIA': 'VIEW',
  'Angalia': 'View', 'Chuja': 'Filter', 'Futa': 'Cancel', 'Hifadhi': 'Save', 'Tuma': 'Send',
  'Tuma arifa': 'Send notification', 'Thibitisha': 'Verify', 'Kataa': 'Reject',
  'Sitisha': 'Suspend', 'Chapisha': 'Publish', 'Amilisha': 'Activate', 'Ondoa': 'Remove',
  'Onyesha upya': 'Refresh', 'Sasisha': 'Refresh',
  'Hali ya bidhaa': 'Product status', 'Hali ya mtumiaji': 'User status', 'Hali ya akaunti': 'Account status',
  'Hali mpya': 'New status', 'Hali: yote': 'Status: all', 'Sababu (hiari)': 'Reason (optional)',
  'Sababu': 'Reason', 'Hali imebadilishwa': 'Status updated', 'Imebadilishwa': 'Updated',
  'Vitendo': 'Actions', 'Firestore': 'Firestore', 'Hali': 'Status', 'Makosa': 'Errors',
  // Users
  'Tafuta: email, namba, jina, username…': 'Search: email, phone, name, username…',
  'Jukumu: yote': 'Role: all', 'Jukumu': 'Role', 'Anajiunga': 'Joined', 'Mtumiaji': 'User',
  'Simu': 'Phone', 'Email imethibitishwa': 'Email verified', 'Simu imethibitishwa': 'Phone verified',
  'Aliungana': 'Joined', 'Duka': 'Shop', 'Anwani': 'Addresses', 'Vifaa': 'Devices',
  'Maagizo (mnunuzi)': 'Orders (buyer)', 'Maagizo (muuzaji)': 'Orders (seller)',
  'Firebase UID': 'Firebase UID', 'hakuna': 'none', 'Ndiyo': 'Yes', 'La': 'No',
  'Badilisha hali ya akaunti. Chaguo <b>active</b> pia litaondoa alama isSuspended kwenye Firestore.':
    'Change account status. Choosing <b>active</b> also clears the isSuspended flag on Firestore.',
  'Sababu fupi kwa ukaguzi': 'Short reason for audit',
  'Hakuna akaunti iliyosimamishwa kwenye Firestore.': 'No accounts are suspended in Firestore.',
  'Watumiaji waliosimamishwa (Firestore)': 'Suspended users (Firestore)',
  'Bidhaa (Firestore)': 'Products (Firestore)',
  'Bidhaa (Firestore) — app hizi ndizo zinavyoonekana': 'Products (Firestore) — these are what the app shows',
  'Hakuna bidhaa kwenye Firestore.': 'No products in Firestore.',
  'Bidhaa haikuonekana': 'Product not found',
  // Sellers
  'Wauzaji': 'Sellers', 'Tafuta duka / anwani…': 'Search shop / address…',
  'Uthibitisho: yote': 'Verification: all', 'Uthibitisho': 'Verification',
  'Mmiliki': 'Owner', 'Rrating': 'Rating', 'Mauzo / Mapato': 'Sales / Revenue',
  'Salio': 'Balance', 'Mauzo': 'Sales', 'Muuzaji hakupatikana kwenye ukurasa wa kwanza': 'Seller not found on first page',
  'Uthibitisha uamuzi huu? Unatengenezwa kwenye rekodi ya ukaguzi.': 'Confirm this decision? It is written to the audit log.',
  'Rudi pending': 'Back to pending', 'Tafuta wauzaji…': 'Search sellers…',
  // Products
  'Tafuta bidhaa…': 'Search products…', 'Kategoria': 'Category', 'Dawa': 'Created',
  'stock': 'stock', 'Chagua hali mpya ya uchapishaji': 'Choose a new publish status',
  'Kwa nini hali hii?': 'Why this status?',
  // Orders
  'Namba ya agizo / simu / email / duka…': 'Order number / phone / email / shop…',
  'Hali: Yote': 'Status: all', 'Thibisha': 'Verify',
  // Drawers / details
  'Inafifia': 'Fading', 'Imeondolewa': 'Removed', 'Imeandaliwa': 'Prepared',
  // Pager
  'rekodi': 'records', 'ukurasa': 'page', 'Awali': 'Prev', 'Ijayo': 'Next',
  // Auth
  'Andika ADMIN_SECRET.': 'Enter ADMIN_SECRET.', 'Ingia': 'Sign in',
  'ADMIN_SECRET haikubaliki': 'ADMIN_SECRET rejected',
  'ADMIN_SECRET haikubaliki — ingia tena.': 'ADMIN_SECRET rejected — sign in again.',
  'Haijaidhinishwa': 'Unauthorized', 'Ingia kwanza': 'Sign in first',
  'Mtandao: ': 'Network: ', 'Ombi limechelewa (timeout). Jaribu tena.': 'Request timed out. Try again.',
  'Sasisha': 'Refresh', 'Badilisha lugha': 'Language',
  // Confirms / generic
  'Imefanyika': 'Done', 'imefanyika': 'done', 'Inaendeshwa…': 'Running…',
  'Mipangilio': 'Settings', 'Mipangilio ya Jumla': 'General Settings', 'Jina na Nembo': 'Name & Logo',
  'Muda na Eneo': 'Time & Region', 'Mawasiliano ya Msingi': 'Basic Contact',
  'Watumiaji na Ufikiaji': 'Users & Access', 'Usajili': 'Registration', 'Roles & Permissions': 'Roles & Permissions',
  'Usalama wa Watumiaji': 'User Security', 'Malipo na Sarafu': 'Payments & Currency',
  'Sarafu': 'Currency', 'Kodi': 'Tax', 'Njia za Malipo': 'Payment Gateways',
  'Barua pepe na Taarifa': 'Email & Notifications', 'SMTP': 'SMTP', 'SMS Gateway': 'SMS Gateway',
  'Violezo': 'Templates', 'Viunganishi na API Keys': 'Integrations & API Keys',
  'Analytics': 'Analytics', 'Kuingia kwa Mitandao': 'Social Login', 'Hifadhi ya Wingu': 'Cloud Storage',
  'Usalama na Matengenezo': 'Security & Maintenance', 'Hali ya Matengenezo': 'Maintenance Mode',
  'IP Whitelist / Blacklist': 'IP Whitelist / Blacklist', 'Nakala ya Akiba': 'Backup',
  'Utendaji na Uboreshaji': 'Performance & Optimization', 'Cache': 'Cache', 'Upakiaji': 'Upload',
  'Inapakia mipangilio…': 'Loading settings…', 'Hifadhi mipangilio': 'Save settings',
  'Mipangilio imehifadhiwa': 'Settings saved', 'Imeshindwa kuhifadhi mipangilio': 'Failed to save settings',
  'Futa cache': 'Clear cache', 'Imefutwa': 'Cleared',
  // Landing / Orodha
  'Waliopokea taarifa': 'Waitlist subscribers', 'Maoni ya vipengele': 'Feature suggestions',
  'Maoni ya jamii': 'Community comments',
  'Tuma barua pepe kwa waliopokea taarifa':
    'Email the waitlist subscribers',
  'Tumia hii ukamilishe app. Ujumbe unaenda kwa barua pepe zote zilizojisajili kwenye ukurasa wa "App ipo kwenye maendeleo".':
    'Use this when the app ships. The email goes to every address collected on the "App under development" page.',
  'Kichwa (subject)': 'Subject', 'Maandishi (body)': 'Message (body)',
  'Tuma kwa wote': 'Send to all',
  'Hakuna waliojisajili': 'No subscribers yet',
  'Hakuna maoni ya vipengele': 'No feature suggestions yet',
  'Hakuna maoni ya jamii': 'No community comments yet',
  'Maelezo': 'Details', 'Vipengele': 'Features', 'Jina': 'Name', 'Lugha': 'Language', 'Wakati': 'Time',
};
function escRe(s) { return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'); }
const SW2EN_PAIRS = Object.entries(SW2EN).sort((a, b) => b[0].length - a[0].length);
const EN_RE = new RegExp(
  SW2EN_PAIRS.map(([k]) => (/^[\p{L}\p{N}]+$/u.test(k) ? '\\b' + escRe(k) + '\\b' : escRe(k))).join('|'),
  'gu'
);
function trText(s) { return String(s).replace(EN_RE, (m) => (SW2EN[m] || m)); }
function applyLang(root) {
  if (LANG !== 'en') return;
  root = root || document.body;
  if (root.nodeType === 3) { root.nodeValue = trText(root.nodeValue); return; }
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, null);
  let n;
  const skipSel = 'script,style,textarea,select,option,input';
  while ((n = walker.nextNode())) {
    const p = n.parentNode;
    if (!p || (p.nodeType === 1 && p.matches && p.matches(skipSel))) continue;
    if (p && p.dataset && p.dataset.i18n) continue;
    const v = n.nodeValue;
    if (v) { const t = trText(v); if (t !== v) n.nodeValue = t; }
  }
  if (root.querySelectorAll) {
    root.querySelectorAll('input[placeholder],textarea[placeholder]').forEach((el) => {
      const pl = el.getAttribute('placeholder') || '';
      const t = trText(pl);
      if (t !== pl) el.setAttribute('placeholder', t);
    });
  }
}
function applyNav() {
  document.querySelectorAll('[data-i18n]').forEach((el) => {
    const k = el.dataset.i18n;
    el.textContent = (LANG === 'en' ? NAV_EN[k] : NAV_SW[k]) || el.textContent;
  });
}
function titleFor(sec) { return (LANG === 'en' ? TITLES_EN[sec] : '') || TITLES[sec] || sec; }
function langLabel() { return LANG === 'en' ? 'EN · SW' : 'SW · EN'; }
let langTimer = null;
new MutationObserver((muts) => {
  if (LANG !== 'en') return;
  let target = null;
  for (const mu of muts) {
    for (const node of mu.addedNodes) {
      if (node.nodeType === 1 || node.nodeType === 3) { if (!target) target = node; }
    }
  }
  if (!target) return;
  if (langTimer) clearTimeout(langTimer);
  langTimer = setTimeout(() => applyLang(target), 80);
}).observe(document.body, { childList: true, subtree: true });

// ---------------------------------------------------------------------------
// API
// ---------------------------------------------------------------------------
function secret() { try { return localStorage.getItem(SECRET_KEY) || ''; } catch (_) { return ''; } }
async function api(path, opts = {}) {
  const s = secret();
  if (!s) throw new Error('Ingia kwanza');
  const headers = { ...(opts.headers || {}), 'x-admin-secret': s };
  if (opts.body && typeof opts.body === 'object') {
    headers['Content-Type'] = 'application/json';
    opts.body = JSON.stringify(opts.body);
  }
  const ctrl = new AbortController();
  const to = setTimeout(() => ctrl.abort(), API_TIMEOUT_MS);
  let r;
  try {
    r = await fetch(API + path, { ...opts, headers, signal: ctrl.signal });
  } catch (e) {
    throw new Error(e && e.name === 'AbortError' ? 'Ombi limechelewa (timeout). Jaribu tena.' : ('Mtandao: ' + (e && e.message)));
  } finally {
    clearTimeout(to);
  }
  let j = null; try { j = await r.json(); } catch (_) {}
  if (r.status === 401) {
    try { localStorage.removeItem(SECRET_KEY); } catch (_) {}
    showLogin('ADMIN_SECRET haikubaliki — ingia tena.');
    throw new Error((j && j.error) || 'Haijaidhinishwa');
  }
  if (!r.ok) throw new Error((j && j.error) || ('HTTP ' + r.status));
  return j;
}
const getJSON = (p) => api(p);
const putJSON = (p, b) => api(p, { method: 'PUT', body: b });
const postJSON = (p, b) => api(p, { method: 'POST', body: b });

// ---------------------------------------------------------------------------
// UI shell: modal / drawer / confirm
// ---------------------------------------------------------------------------
function openModal(html) {
  $('modalOverlay').hidden = false;
  $('modalRoot').hidden = false;
  $('modalRoot').innerHTML = '<div class="modal">' + html + '</div>';
  icons();
}
function closeModal() { $('modalRoot').hidden = true; $('modalOverlay').hidden = true; $('modalRoot').innerHTML = ''; }
$('modalOverlay').addEventListener('click', closeModal);

function openDrawer(html) {
  $('drawerOverlay').hidden = false;
  $('drawer').hidden = false;
  $('drawerBody').innerHTML = html;
  icons();
}
function closeDrawer() { $('drawerOverlay').hidden = true; $('drawer').hidden = true; }
$('drawerOverlay').addEventListener('click', closeDrawer);
$('drawerClose').addEventListener('click', closeDrawer);
// Vitufe vya ndani ya drawer (data-fn): delegation moja inayofanya kazi
// kwa detail zote, kwani bindSection() inafunga section tu, si drawer.
$('drawerBody').addEventListener('click', (e) => {
  const b = e.target.closest('[data-fn]');
  if (!b || b.disabled) return;
  e.stopPropagation();
  const fn = ACTIONS[b.dataset.fn.replace(/^sv\./, '')];
  if (fn) { try { fn(JSON.parse(b.dataset.args || '{}'), b); } catch (err) { handleActionErr(err); } }
});

function confirmModal(title, msg, btnLabel, danger) {
  return new Promise((resolve) => {
    openModal(
      '<h3>' + esc(title) + '</h3>' +
      '<p class="msub">' + esc(msg) + '</p>' +
      '<div class="mfooter">' +
      '<button class="btn" id="cfNo">Futa</button>' +
      '<button class="btn ' + (danger ? 'danger' : 'accent') + '" id="cfYes">' + esc(btnLabel || 'Ndiyo') + '</button>' +
      '</div>'
    );
    $('cfNo').onclick = () => { closeModal(); resolve(false); };
    $('cfYes').onclick = () => { closeModal(); resolve(true); };
  });
}

function handleActionErr(e) {
  toast((e && e.message) || 'Imeshindikana', false);
  console.error(e);
}

function run(fn) {
  setBusy(true);
  fn().catch(handleActionErr).finally(() => setBusy(false));
}
function runQuiet(fn) {
  fn().catch(handleActionErr);
}

// ---------------------------------------------------------------------------
// Sections
// ---------------------------------------------------------------------------
const TITLES = {
  dashboard: 'Dashibodi', users: 'Watumiaji', sellers: 'Wauzaji', products: 'Bidhaa',
  orders: 'Maagizo', disputes: 'Migogoro', refunds: 'Marejesho', reports: 'Ripoti & Ulinzi',
  kyc: 'Wathibitisho (KYC)',
  promos: 'Boost & Flash Sales',
  revenue: 'Mapato ya Jukwaa',
  finance: 'Fedha & Ledger', referrals: 'Rufaa', broadcasts: 'Matangazo ya Broad', audit: 'Ukaguzi (Audit)',
  stats: 'Takwimu za Matumizi', settings: 'Mipangilio',
  landing: 'Landing / Waitlist',
};
const Pg = {};
function pgState(sec, field) {
  Pg[sec] = Pg[sec] || { page: 1, limit: 20 };
  return Pg[sec][field];
}
function setPg(sec, field, v) { Pg[sec] = (Pg[sec] || { page: 1, limit: 20 }); Pg[sec][field] = v; }

const secEl = (sec) => $('sec-' + sec);
function setBusy(b) { $('app').classList.toggle('busy', b); }
function touch() { $('lastUpd').textContent = 'Imejibiwa ' + new Date().toLocaleTimeString(); }
function pagerHTML(sec, pag) {
  const total = (pag && pag.total) || 0;
  const page = (pag && pag.page) || 1;
  const pages = Math.max(1, Math.ceil(total / ((pag && pag.limit) || 20)));
  return '<div class="pager"><span>' + fmtNum(total) + ' rekodi &middot; ukurasa ' + page + '/' + pages + '</span>' +
    '<button class="btn sm" data-act="page" data-dir="-1"' + (page <= 1 ? ' disabled' : '') + '>Awali</button>' +
    '<button class="btn sm" data-act="page" data-dir="1"' + (page >= pages ? ' disabled' : '') + '>Ijayo</button></div>';
}
// Wire pager/nav buttons inside a section using data-act + data-fn
function bindSection(sec) {
  const el = secEl(sec);
  el.querySelectorAll('[data-act="page"]').forEach((b) => {
    b.addEventListener('click', () => {
      setPg(sec, 'page', Math.max(1, (pgState(sec, 'page') || 1) + Number(b.dataset.dir)));
      LOADERS[sec]();
    });
  });
  el.querySelectorAll('[data-fn]').forEach((b) => {
    b.addEventListener('click', (e) => {
      e.stopPropagation();
      const fn = ACTIONS[b.dataset.fn.replace(/^sv\./, '')];
      if (fn) fn(JSON.parse(b.dataset.args || '{}'), b);
    });
  });
  icons();
}

// ---------------------------------------------------------------------------
// ACTION registry (buttons/menus delegate here)
// ---------------------------------------------------------------------------
const ACTIONS = {
  userStatus(args) { changeUserStatus(args.id, args.name); },
  userNotif(args) { sendUserNotif(args.uid, args.name); },
  viewUser(args) { viewUserDetail(args.id); },
  viewFsUser(args) { viewFsUserDetail(args.id); },
  sellerVerify(args) { sellerVerify(args.id, args.name, 'verify'); },
  sellerReject(args) { sellerVerify(args.id, args.name, 'reject'); },
  sellerPending(args) { sellerVerify(args.id, args.name, 'pending'); },
  viewSeller(args) { viewSellerDetail(args.id); },
  productModerate(args) { productModerate(args.id, args.title); },
  viewProduct(args) { viewProductDetail(args.id, args.title); },
  viewOrder(args) { viewOrderDetail(args.id, args.num, args.status); },
  viewFsOrder(args) { viewFsOrder(args.id, args.num); },
  disputeResolve(args) { disputeResolve(args.id, args.num, args.total); },
  viewDispute(args) { viewDisputeDetail(args.id); },
  refundProcess(args) { refundProcess(args.id, args.num); },
  withdrawalProcess(args) { withdrawalOp(args.id, 'process'); },
  withdrawalRetry(args) { withdrawalOp(args.id, 'retry'); },
  withdrawalConfirm(args) { withdrawalOp(args.id, 'confirm'); },
  reportReview(args) { reportReview(args.id, args.status); },
  referralComplete(args) { referralComplete(args.id); },
  reconciliationRun() { reconciliationRun(); },
  kycApprove(args) { kycReview(args.uid, args.name, 'approve'); },
  kycReject(args) { kycReview(args.uid, args.name, 'reject'); },
  kycRevoke(args) { kycReview(args.uid, args.name, 'revoke'); },
  revenueWithdraw() { revenueWithdraw(); },
  fsUnFlag(args) { fsUnFlagAcc(args.uid, args.name); },
  viewFsProduct(args) { viewFsProduct(args.id, args.name); },
  fpToggleActive(args) { fpToggleActive(args.id, args.name); },
  escrowRelease(args) { escrowReleaseAction(args); },
  escrowResolve(args) { escrowAdjudicate(args, 'release'); },
  escrowRefund(args) { escrowAdjudicate(args, 'refund'); },
  escrowTransfer(args) { escrowTransferAction(args); },
};

// ---------------------------------------------------------------------------
// Dashibodi
// ---------------------------------------------------------------------------
let charts = {};
function destroyCharts() { Object.keys(charts).forEach((k) => { try { charts[k].destroy(); } catch (_) {} }); charts = {}; }
function chartBase() {
  const dark = document.documentElement.getAttribute('data-theme') === 'dark';
  return {
    grid: { color: dark ? '#23352a' : '#eef1ef' },
    ticks: { color: dark ? '#93a69b' : '#5b6b63', font: { size: 11 } },
  };
}

// Overview ya dashibodi — muundo umeongozwa na template ya Adminator v4
// (puikinsh/Adminator-admin-dashboard, leseni ya MIT): safu ya KPI zenye
// trend, chati kuu + doughnut, jedwali la maagizo ya hivi punde, na foleni
// ya kazi zinazosubiri hatua (todo).
function trendChip(cur, prev) {
  cur = Number(cur) || 0; prev = Number(prev) || 0;
  if (!prev) return cur > 0 ? '<span class="trend info">mpya</span>' : '';
  const p = Math.round(((cur - prev) / prev) * 100);
  if (p === 0) return '<span class="trend">0%</span>';
  return '<span class="trend ' + (p > 0 ? 'ok' : 'bad') + '">' + (p > 0 ? '+' : '') + p + '%</span>';
}
function queueTotal(j) { return (j && j.data && j.data.pagination && j.data.pagination.total) || 0; }
async function loadDashboard() {
  const el = secEl('dashboard');
  el.innerHTML = '<div class="sectionempty"><div class="spinner" style="margin:0 auto 12px"></div>Inapakia dashibodi…</div>';
  try {
    const [dash, metrics, ts, online, recent, pendSellers, pendRefunds] = await Promise.all([
      getJSON('/api/v1/admin/dashboard'),
      getJSON('/api/v1/admin/metrics'),
      getJSON('/api/admin/timeseries?days=30').catch(() => null),
      getJSON('/api/admin/online').catch(() => null),
      getJSON('/api/v1/admin/orders?limit=6').catch(() => null),
      getJSON('/api/v1/admin/sellers?verificationStatus=pending&limit=1').catch(() => null),
      getJSON('/api/v1/admin/refunds?status=pending&limit=1').catch(() => null),
    ]);
    const k = (dash.data && dash.data.kpis) || {};
    const m = (metrics && metrics.data) || {};
    const onl = (online && (online.online || online)) || null;
    const series = (ts && ts.series) || [];
    const last = series[series.length - 1] || {};
    const prev = series[series.length - 2] || {};

    const gmv = Number(m.gmv || 0);
    const orderGroups = (m.ordersByStatus || []).slice().sort((a, b) => b.count - a.count).slice(0, 8);
    const orders = (recent && recent.data && recent.data.orders) || [];
    const fsOrders = (await getJSON('/api/admin/orders').catch(() => ({ orders: [] }))).orders || [];
    const recents = mergeRecent(orders, fsOrders);
    const queue = [
      { sec: 'finance', ic: 'banknote', lab: 'Withdrawals zinazosubiri', n: Number(m.withdrawalsPending || 0) },
      { sec: 'disputes', ic: 'scale', lab: 'Migogoro wazi', n: Number(m.disputesOpen || k.activeDisputes || 0) },
      { sec: 'sellers', ic: 'store', lab: 'Wauzaji wanaosubiri uthibitisho', n: queueTotal(pendSellers) },
      { sec: 'refunds', ic: 'rotate-ccw', lab: 'Marejesho yanayosubiri', n: queueTotal(pendRefunds) },
    ];

    el.innerHTML =
      '<div class="ov-head"><div><h2>Maelezo ya jumla</h2><p class="dim">Hali ya soko kwa mtazamo mmoja</p></div>' +
      '<button class="btn sm" data-ov="refresh"><i data-lucide="refresh-cw"></i>Sasisha</button></div>' +
      '<div class="grid kpis">' +
      kpi('Watumiaji', fmtNum(k.users), 'Wapya leo: ' + fmtNum(k.newUsersToday), 'users', trendChip(last.users, prev.users)) +
      kpi('Maagizo', fmtNum(k.orders), 'Kamili: ' + fmtNum(k.completedOrders), 'shopping-cart') +
      kpi('GMV', fmtTZS(gmv), 'thamani ya bidhaa zilizouzwa', 'coins', trendChip(last.money, prev.money)) +
      kpi('Mapato ya Tume', fmtTZS(k.commissionRevenue), 'tume iliyokusanywa', 'trending-up') +
      kpi('Escrow Inashikiliwa', fmtTZS(k.escrowHeld), fmtNum((m.escrowHolding || {}).count || 0) + ' holdi', 'lock') +
      kpi('Bidhaa', fmtNum(k.products), 'jumla dukani', 'package') +
      '</div>' +

      '<div class="grid cols2" style="margin-top:18px">' +
      '<div class="card"><div class="cardhead"><h3>Mapato ya kila siku (siku 30)</h3><div class="spacer"></div><span class="hint3">pesa / tume / watumiaji</span></div><div class="chartbox"><canvas id="chartTs"></canvas></div></div>' +
      '<div class="card"><div class="cardhead"><h3>Maagizo kwa hali</h3><div class="spacer"></div><button class="linklike" data-goto="orders" style="margin:0">Angalia zote</button></div><div class="chartbox"><canvas id="chartOrds"></canvas></div></div>' +
      '</div>' +

      '<div class="grid cols2" style="margin-top:18px">' +
      '<div class="card"><div class="cardhead"><h3>Maagizo ya hivi punde</h3><div class="spacer"></div><button class="linklike" data-goto="orders" style="margin:0">Angalia zote</button></div>' +
      '<div class="tablewrap"><table class="tbl"><thead><tr><th>Agizo</th><th>Mnunuzi</th><th style="text-align:right">Jumla</th><th>Hali</th><th></th></tr></thead><tbody>' +
      (recents.length ? recents.map((o) => '<tr>' +
        '<td class="mono"><b>' + esc(o.orderNumber || id12(o.id)) + '</b>' + (o.fs ? ' <span class="bdg mut">FS</span>' : '') + '<div class="dim">' + fmtTimeAny(o.createdAt) + '</div></td>' +
        '<td>' + esc((o.buyer && (o.buyer.displayName || o.buyer.email)) || '—') + '</td>' +
        '<td class="num">' + fmtTZS(o.totalAmount) + '</td>' +
        '<td>' + badge(o.status) + '</td>' +
        '<td class="rowactions"><button class="btn sm" data-fn="' + (o.fs ? 'viewFsOrder' : 'viewOrder') + '" data-args=\'' + JSON.stringify({ id: o.id, num: o.orderNumber || o.id, status: o.status }).replace(/'/g, '&#39;') + '\'>' + (o.fs ? 'Angalia' : 'Angalia') + '</button></td>' +
        '</tr>').join('') : '<tr><td colspan="5" class="empty">Hakuna maagizo bado</td></tr>') +
      '</tbody></table></div></div>' +

      '<div class="card"><div class="cardhead"><h3>Kazi zinazosubiri</h3><div class="spacer"></div><span class="hint3">bonyeza kwenda</span></div>' +
      '<div class="queue">' +
      queue.map((q) => '<button class="qrow' + (q.n ? '' : ' zero') + '" data-goto="' + q.sec + '">' +
        '<span class="qic"><i data-lucide="' + q.ic + '"></i></span>' +
        '<span class="qlab">' + esc(q.lab) + '</span>' +
        '<span class="qn">' + fmtNum(q.n) + '</span>' +
        '<i data-lucide="chevron-right" class="qgo"></i></button>').join('') +
      '</div>' +
      (onl ? '<div class="cardhead" style="margin:14px 0 8px"><h3>Mtandaoni sasa hivi</h3></div><div class="summRow">' +
        onlChip('Dakika 1', onl.lastMinute) + onlChip('Dakika 5', onl.last5Min) + onlChip('Dakika 15', onl.last15Min) +
        onlChip('Saa 1', onl.lastHour) + onlChip('Siku 1', onl.lastDay) + '</div>' : '') +
      '</div>' +
      '</div>';
    el.querySelectorAll('[data-goto]').forEach((b) => b.addEventListener('click', () => showSection(b.dataset.goto)));
    el.querySelector('[data-ov="refresh"]').addEventListener('click', () => loadDashboard());
    bindSection('dashboard');

    destroyCharts();
    if (window.Chart && series.length) {
      charts.ts = new Chart($('chartTs'), {
        type: 'line',
        data: {
          labels: series.map((s) => String(s.date || '').slice(5)),
          datasets: [
            { label: 'Money', data: series.map((s) => s.money), borderColor: '#2f9e5f', backgroundColor: 'rgba(47,158,95,.12)', fill: true, tension: .3, pointRadius: 0 },
            { label: 'Commission', data: series.map((s) => s.commission), borderColor: '#b7791f', backgroundColor: 'transparent', borderDash: [4, 3], tension: .3, pointRadius: 0 },
            { label: 'Users', data: series.map((s) => s.users), borderColor: '#2563eb', backgroundColor: 'transparent', tension: .3, pointRadius: 0, yAxisID: 'y1' },
          ],
        },
        options: {
          responsive: true, maintainAspectRatio: false, interaction: { mode: 'index', intersect: false },
          scales: { y: Object.assign({ beginAtZero: true }, { grid: chartBase().grid, ticks: chartBase().ticks }), y1: { position: 'right', grid: { display: false }, ticks: chartBase().ticks }, x: { grid: { display: false } } },
          plugins: { legend: { labels: { boxWidth: 12, color: chartBase().ticks.color } } },
        },
      });
    }
    if (window.Chart && orderGroups.length) {
      charts.ord = new Chart($('chartOrds'), {
        type: 'doughnut',
        data: {
          labels: orderGroups.map((g) => g.status),
          datasets: [{ data: orderGroups.map((g) => g.count), backgroundColor: ['#2f9e5f', '#7da8ff', '#e3a94d', '#f07070', '#2586e3', '#9b7dd8', '#49c3a0', '#d8a5e0'] }],
        },
        options: { responsive: true, maintainAspectRatio: false, cutout: '62%', plugins: { legend: { position: 'right', labels: { boxWidth: 12, font: { size: 11 }, color: chartBase().ticks.color } } } },
      });
    }
    el.querySelectorAll('canvas').forEach((c) => { if (c && !c.id) c.remove(); });
  } catch (e) {
    el.innerHTML = '<div class="card"><div class="cardhead"><h3>Dashibodi</h3></div><div class="err">' + esc(e.message) + '</div></div>';
  }
  touch(); icons();
}
function kpi(lab, val, sub, ic, trend) {
  return '<div class="kpi"><div class="lab">' + esc(lab) + '</div><div class="val">' + val + '</div><div class="sub">' + esc(sub) + (trend ? ' ' + trend : '') + '</div><div class="ic"><i data-lucide="' + esc(ic) + '"></i></div></div>';
}
function onlChip(lab, v) {
  return '<span class="bdg ' + (Number(v) > 0 ? 'ok' : 'mut') + '">' + esc(lab) + ': <b style="margin-left:4px">' + fmtNum(v) + '</b></span>';
}
function cardQuick(t, body) { return '<div class="card"><div class="cardhead"><h3>' + esc(t) + '</h3></div>' + body + '</div>'; }

// ---------------------------------------------------------------------------
// Watumiaji
// ---------------------------------------------------------------------------
function usersToolbar() {
  return '<div class="toolbar">' +
    '<input class="field q" id="uQ" placeholder="Tafuta: email, namba, jina, username…">' +
    '<select class="select-xs" id="uRole"><option value="">Jukumu: yote</option><option>buyer</option><option>seller</option><option>admin</option><option>super_admin</option></select>' +
    '<select class="select-xs" id="uStatus"><option value="">Hali: yote</option><option>active</option><option>pending</option><option>restricted</option><option>suspended</option><option>deletion_pending</option><option>deleted</option></select>' +
    '<button class="btn" id="uGo">Chuja</button><div class="spacer"></div><button class="btn sm" data-fn="nope" data-act="none" onclick="return false" hidden></button>' +
    '</div>';
}
async function loadUsers() {
  const el = secEl('users');
  const page = pgState('users', 'page') || 1;
  const q = pgState('users', 'q') || '';
  const role = pgState('users', 'role') || '';
  const status = pgState('users', 'status') || '';
  el.innerHTML = usersToolbar() + '<div class="card"><div class="tablewrap"><table class="tbl"><thead><tr>' +
    '<th>Mtumiaji</th><th>Email</th><th>Simu</th><th>Jukumu</th><th>Hali</th><th>Firestore</th><th>Anajiunga</th><th style="text-align:right">Vitendo</th></tr></thead>' +
    '<tbody id="uRows"><tr><td colspan="8" class="empty"><div class="spinner" style="width:22px;height:22px;margin:0 auto 8px"></div>Inapakia…</td></tr></tbody></table></div>' +
    '<div id="uPag"></div></div>' +
    '<div id="fsCard"></div>';
  const qs = new URLSearchParams({ page, limit: 20 });
  if (q) qs.set('q', q); if (role) qs.set('role', role); if (status) qs.set('accountStatus', status);
  try {
    const j = await getJSON('/api/v1/admin/users?' + qs.toString());
    const d = (j.data && j.data.users) || [];
    $('uRows').innerHTML = d.length
      ? d.map((u) => {
        const isFs = u.src === 'fs';
        const name = u.displayName || u.username || u.id;
        const args = JSON.stringify({ id: u.id, name }).replace(/'/g, '&#39;');
        return '<tr>' +
        '<td>' + avatarOf(u) + ' ' + esc(u.displayName || u.username || '—') + (isFs ? ' <span class="bdg mut">FS</span>' : ' <span class="bdg ok">PG</span>') + '</td>' +
        '<td>' + esc(u.email || '—') + '</td>' +
        '<td class="mono">' + esc(u.phone || '—') + '</td>' +
        '<td>' + badge(u.role) + '</td>' +
        '<td>' + badge(u.accountStatus) + '</td>' +
        '<td>' + fsFlagBadge(u.firestoreSuspended) + '</td>' +
        '<td class="dim">' + fmtTimeAny(u.createdAt) + '</td>' +
        '<td class="rowactions">' +
        (isFs
          ? '<button class="btn sm" data-fn="viewFsUser" data-args=\'' + args + '\'>Angalia</button>' +
            (u.firestoreSuspended ? '<button class="btn sm accent" data-fn="fsUnFlag" data-args=\'' + args + '\'>Amilisha</button>' : '')
          : '<button class="btn sm" data-fn="viewUser" data-args=\'' + args + '\'>Angalia</button>' +
            '<button class="btn sm" data-fn="userStatus" data-args=\'' + args + '\'>Hali</button>') +
        '</td></tr>';
      }).join('')
      : '<tr><td colspan="8" class="empty">Hakuna watumiaji</td></tr>';
    $('uPag').innerHTML = pagerHTML('users', j.data.pagination);
  } catch (e) { $('uRows').innerHTML = '<tr><td colspan="8" class="empty">' + esc(e.message) + '</td></tr>'; }
  bindSection('users');
  renderFsSuspended();
  touch();
}

async function changeUserStatus(id, name) {
  openModal(
    '<h3>Hali ya mtumiaji: ' + esc(name) + '</h3><p class="msub">Badilisha hali ya akaunti. Chaguo <b>active</b> pia litaondoa alama isSuspended kwenye Firestore.</p>' +
    '<label>Hali mpya</label><select class="field" id="usSel"><option value="active">active</option><option value="pending">pending</option><option value="suspended">suspended</option><option value="deleted">deleted</option></select>' +
    '<label>Sababu (hiari)</label><input class="field" id="usReason" placeholder="Sababu fupi kwa ukaguzi">' +
    '<div class="mfooter"><button class="btn" id="usNo">Futa</button><button class="btn accent" id="usYes">Hifadhi</button></div>'
  );
  $('usNo').onclick = closeModal;
  $('usYes').onclick = () => run(async () => {
    await putJSON('/api/v1/admin/users/' + id + '/status', { accountStatus: $('usSel').value, reason: $('usReason').value || undefined });
    closeModal(); toast('Hali imebadilishwa', true); loadUsers();
  });
}

async function viewUserDetail(id) {
  openDrawer('<div class="dsub">Tayari inapakia…</div>');
  try {
    const j = await getJSON('/api/v1/admin/users/' + id);
    const d = (j.data || {}).user || {};
    const sp = d.sellerProfile || {};
    const w = sp.wallet || {};
    const buyGroups = (j.data.buyerOrders || []);
    const sellGroups = (j.data.sellerOrders || []);
    const buyerTotal = buyGroups.reduce((a, g) => a + Number(g._sum.totalAmount || 0), 0);
    const sellerTotal = sellGroups.reduce((a, g) => a + Number(g._count.status || 0), 0);
    const ku = (g) => g.status + ' (' + (g._count._all || g._count.status || g._count) + ')';
    openDrawer(
      '<div class="dsub"></div><h3>' + esc(d.displayName || d.username || 'Mtumiaji') + '</h3>' +
      '<div class="dsub">' + esc(d.email || '') + (d.phone ? ' · ' + esc(d.phone) : '') + '</div>' +
      '<dl class="kv">' +
      '<dt>Firebase UID</dt><dd class="mono">' + esc(id12(d.firebaseUid || d.id)) + '</dd>' +
      '<dt>ID</dt><dd class="mono">' + esc(id12(d.id)) + '</dd>' +
      '<dt>Jukumu</dt><dd>' + badge(d.role) + '</dd>' +
      '<dt>Hali</dt><dd>' + badge(d.accountStatus) + '</dd>' +
      '<dt>Email imethibitishwa</dt><dd>' + (d.emailVerified ? 'Ndiyo' : 'La') + '</dd>' +
      '<dt>Simu imethibitishwa</dt><dd>' + (d.phoneVerified ? 'Ndiyo' : 'La') + '</dd>' +
      '<dt>Aliungana</dt><dd>' + fmtTime(d.createdAt) + '</dd>' +
      (sp.id ? '<dt>Duka</dt><dd>' + esc(sp.storeName || '—') + ' (' + badge(sp.verificationStatus) + ' · ' + badge(sp.sellerStatus) + ')</dd>' : '') +
      (sp.id ? '<dt>Rrating ya duka</dt><dd>' + Number(sp.reliabilityScore || 0).toFixed(1) + '/5</dd>' : '') +
      (w.availableBalance != null ? '<dt>Salio la duka</dt><dd>' + fmtTZS(w.availableBalance) + ' <span class="dim">pending ' + fmtTZS(w.pendingBalance) + '</span></dd>' : '') +
      (sp.id ? '<dt>Mauzo duka</dt><dd>' + fmtNum(sp.totalSales) + ' · ' + fmtTZS(sp.totalRevenue) + '</dd>' : '') +
      '<dt>Maagizo (mnunuzi)</dt><dd>' + (buyGroups.length ? buyGroups.map(ku).join(', ') : 'hakuna') + ' <b>' + fmtTZS(buyerTotal) + '</b></dd>' +
      '<dt>Maagizo (muuzaji)</dt><dd>' + (sellGroups.length ? sellGroups.map(ku).join(', ') : 'hakuna') + ' (' + fmtNum(sellerTotal) + ')</dd>' +
      '</dl>' +
      (d.addresses && d.addresses.length ? '<hr class="hr"><div class="dsub">Anwani (' + d.addresses.length + ')</div>' +
        d.addresses.slice(0, 5).map((a) => esc(a.addressLine1) + ' ' + esc(a.city || '')).join('<br>') : '') +
      (d.devices && d.devices.length ? '<hr class="hr"><div class="dsub">Vifaa (' + d.devices.length + ')</div>' +
        d.devices.map((dv) => esc(dv.platform || '?') + ' v' + esc(dv.appVersion || '?')).join('<br>') : '') +
      '<div class="drawer-actions">' +
      (d.firebaseUid ? '<button class="btn sm accent" data-fn="userNotif" data-args=\'' + JSON.stringify({ uid: d.firebaseUid, name: d.displayName || d.email || d.id }).replace(/'/g, '&#39;') + '\'>Tuma arifa</button>' : '') +
      '<button class="btn sm" data-fn="userStatus" data-args=\'' + JSON.stringify({ id: d.id, name: d.displayName || d.email || d.id }).replace(/'/g, '&#39;') + '\'>Hali ya akaunti</button>' +
      '</div>'
    );
    bindSection('users');
  } catch (e) { toast(e.message, false); }
}
async function viewFsUserDetail(id) {
  openDrawer('<div class="dsub">Inapakia…</div>');
  try {
    const j = await getJSON('/api/admin/users');
    const u = ((j && j.users) || []).find((x) => String(x.uid) === String(id) || String(x.id) === String(id));
    if (!u) { closeDrawer(); toast('Mtumiaji hakupatikana kwenye Firestore', false); return; }
    const args = JSON.stringify({ uid: u.uid || u.id, name: u.displayName || u.email || u.uid || u.id }).replace(/'/g, '&#39;');
    openDrawer(
      '<h3>' + esc(u.displayName || u.username || 'Mtumiaji') + '</h3>' +
      '<div class="dsub">' + esc(u.email || '') + (u.phone ? ' · ' + esc(u.phone) : '') + '</div>' +
      '<dl class="kv">' +
      '<dt>Firebase UID</dt><dd class="mono">' + esc(id12(u.uid || u.id)) + '</dd>' +
      '<dt>Hali (Firestore)</dt><dd>' + fsFlagBadge(u.isSuspended === true) + '</dd>' +
      '<dt>Username</dt><dd>' + esc(u.username || '—') + '</dd>' +
      '<dt>Imeundwa</dt><dd>' + fmtTimeAny(u.createdAt) + '</dd>' +
      '</dl>' +
      '<div class="drawer-actions">' +
      (u.isSuspended === true ? '<button class="btn sm accent" data-fn="fsUnFlag" data-args=\'' + args + '\'>Amilisha (Firestore)</button>' : '') +
      (u.uid || u.id ? '<button class="btn sm" data-fn="userNotif" data-args=\'' + args + '\'>Tuma arifa</button>' : '') +
      '</div>'
    );
    bindSection('users');
  } catch (e) { toast(e.message, false); }
}
async function sendUserNotif(uid, name) {
  openModal(
    '<h3>Arifa kwa ' + esc(name) + '</h3>' +
    '<label>Kichwa</label><input class="field" id="snTitle" placeholder="Kichwa cha arifa">' +
    '<label>Maandishi</label><textarea class="field" id="snBody" placeholder="Ujumbe…"></textarea>' +
    '<label>Aina</label><select class="field" id="snType"><option value="system">system</option><option value="order">order</option><option value="message">message</option><option value="promo">promo</option></select>' +
    '<div class="mfooter"><button class="btn" id="snNo">Futa</button><button class="btn accent" id="snYes">Tuma</button></div>'
  );
  $('snNo').onclick = closeModal;
  $('snYes').onclick = () => run(async () => {
    await postJSON('/api/admin/send-notification', { userId: uid, title: $('snTitle').value, body: $('snBody').value, type: $('snType').value });
    closeModal(); toast('Arifa imetumwa', true);
  });
}

// Firestore users/{uid}.isSuspended ni tofauti na accountStatus ya Postgres;
// hii ni orodha ya akaunti zilizosimamishwa FIRESTORE tu (ndiyo inaziba
// kuongeza bidhaa / kusoma BuyerRequests), na kitufe cha kuamisha moja kwa moja.
async function fsUnFlagAcc(uid, name) {
  if (!(await confirmModal('Amilisha (Firestore)', 'Ondoa isSuspended kwenye akaunti ya ' + esc(name) + '?', 'Ndiyo, amilisha'))) return;
  await run(async () => {
    await api('/api/admin/users/' + encodeURIComponent(uid), { method: 'PATCH', body: { updates: { isSuspended: false } } });
    toast('Akaunti imeamilishwa', true);
    renderFsSuspended(true);
    loadUsers();
  });
}
async function renderFsSuspended() {
  const wrap = $('fsCard');
  if (!wrap) return;
  wrap.innerHTML = '<div class="card"><div class="cardhead"><h3>Watumiaji waliosimamishwa (Firestore)</h3><button class="btn sm" id="fsRefresh">Onyesha upya</button></div><div class="dsub" style="padding:0 16px 16px"><div class="spinner" style="width:20px;height:20px"></div></div></div>';
  try {
    const j = await getJSON('/api/admin/users');
    const all = (j && j.users || []).filter((u) => u.isSuspended === true);
    if (!all.length) {
      wrap.innerHTML = '<div class="card"><div class="cardhead"><h3>Watumiaji waliosimamishwa (Firestore)</h3><button class="btn sm" id="fsRefresh">Onyesha upya</button></div><div class="dsub" style="padding:0 16px 16px">Hakuna akaunti iliyosimamishwa kwenye Firestore.</div></div>';
      $('fsRefresh').onclick = () => renderFsSuspended();
      return;
    }
    wrap.innerHTML = '<div class="card"><div class="cardhead"><h3>Watumiaji waliosimamishwa (Firestore)</h3><button class="btn sm" id="fsRefresh">Onyesha upya</button></div>' +
      '<div class="tablewrap" style="max-height:280px;overflow:auto"><table class="tbl"><thead><tr><th>Mtumiaji</th><th>Email / Simu</th><th>UID</th><th style="text-align:right">Vitendo</th></tr></thead><tbody>' +
      all.map((u) =>
        '<tr>' +
        '<td>' + avatarOf(u) + ' ' + esc(u.displayName || u.username || '—') + '</td>' +
        '<td>' + esc((u.email || '') + (u.phone ? ' · ' + u.phone : '')) + '</td>' +
        '<td class="mono">' + esc(id12(u.uid)) + '</td>' +
        '<td class="rowactions"><button class="btn sm accent" data-fn="fsUnFlag" data-args=\'' + JSON.stringify({ uid: u.uid, name: u.displayName || u.email || u.uid }).replace(/'/g, '&#39;') + '\'>Amilisha</button></td>' +
        '</tr>'
      ).join('') +
      '</tbody></table></div></div>';
    $('fsRefresh').onclick = () => renderFsSuspended();
    bindSection('users');
  } catch (e) {
    wrap.innerHTML = '<div class="card"><div class="cardhead"><h3>Watumiaji waliosimamishwa (Firestore)</h3></div><div class="err">' + esc(e.message) + '</div></div>';
  }
}
// fmtTime kwa Firestore Timestamp ({seconds}/{_seconds}) au Date/string.
function fmtTimeAny(v) {
  if (!v) return '—';
  if (typeof v === 'object' && v.seconds != null) return fmtTime(new Date(Number(v.seconds) * 1000));
  if (typeof v === 'object' && v._seconds != null) return fmtTime(new Date(Number(v._seconds) * 1000));
  return fmtTime(v);
}
// Bidhaa halisi za app zinaishi FIRESTORE (app inaandika moja kwa moja kwenye
// collection products), si Postgres. Kadi hii inazionyesha + inaruhusu
// Sitisha/Chapisha (isActive) moja kwa moja.
async function renderFsProducts() {
  const wrap = $('fpCard');
  if (!wrap) return;
  wrap.innerHTML = '<div class="card"><div class="cardhead"><h3>Bidhaa (Firestore) — app hizi ndizo zinavyoonekana</h3><button class="btn sm" id="fpRefresh">Onyesha upya</button></div><div class="dsub" style="padding:0 16px 16px"><div class="spinner" style="width:20px;height:20px"></div></div></div>';
  try {
    const j = await getJSON('/api/admin/products');
    const all = (j && j.products || []).slice(0, 50);
    if (!all.length) {
      wrap.innerHTML = '<div class="card"><div class="cardhead"><h3>Bidhaa (Firestore)</h3><button class="btn sm" id="fpRefresh">Onyesha upya</button></div><div class="dsub" style="padding:0 16px 16px">Hakuna bidhaa kwenye Firestore.</div></div>';
      $('fpRefresh').onclick = () => renderFsProducts();
      return;
    }
    wrap.innerHTML = '<div class="card"><div class="cardhead"><h3>Bidhaa (Firestore)</h3><button class="btn sm" id="fpRefresh">Onyesha upya</button></div>' +
      '<div class="tablewrap" style="max-height:360px;overflow:auto"><table class="tbl"><thead><tr><th>Bidhaa</th><th>Muuzaji</th><th>Kategoria</th><th>Bei</th><th>Hali</th><th>Dawa</th><th style="text-align:right">Vitendo</th></tr></thead><tbody>' +
      all.map((p) => {
        const img = (p.images && p.images[0]) || '';
        const thumb = img && /^https?:\/\//.test(img)
          ? '<img class="thumb" src="' + esc(img) + '" loading="lazy" onerror="this.style.display=\'none\'">'
          : '<div class="thumb" style="display:grid;place-items:center;color:var(--muted);font-size:11px">' + ((p.images && p.images.length) || 0) + '</div>';
        const active = p.isActive !== false;
        const args = JSON.stringify({ id: p.id, name: p.name || p.id }).replace(/'/g, '&#39;');
        return '<tr>' +
          '<td>' + thumb + ' <b>' + esc(p.name || '—') + '</b><div class="dim mono">' + esc(id12(p.id)) + '</div></td>' +
          '<td>' + esc(p.sellerName || '—') + '</td>' +
          '<td class="dim">' + esc(p.category || '—') + '</td>' +
          '<td class="num">' + fmtTZS(p.price) + (p.currency && p.currency !== 'TZS' ? ' ' + esc(p.currency) : '') + '<div class="dim">stock ' + fmtNum(p.stock) + '</div></td>' +
          '<td>' + (active ? '<span class="bdg ok"><span class="dot"></span>active</span>' : '<span class="bdg mut"><span class="dot"></span>inactive</span>') + '</td>' +
          '<td class="dim">' + fmtTimeAny(p.createdAt) + '</td>' +
          '<td class="rowactions">' +
          '<button class="btn sm" data-fn="viewFsProduct" data-args=\'' + args + '\'>Angalia</button>' +
          '<button class="btn sm ' + (active ? 'danger' : 'accent') + '" data-fn="fpToggleActive" data-args=\'' + args + '\'>' + (active ? 'Sitisha' : 'Chapisha') + '</button>' +
          '</td></tr>';
      }).join('') +
      '</tbody></table></div></div>';
    $('fpRefresh').onclick = () => renderFsProducts();
    bindSection('products');
  } catch (e) {
    wrap.innerHTML = '<div class="card"><div class="cardhead"><h3>Bidhaa (Firestore)</h3></div><div class="err">' + esc(e.message) + '</div></div>';
  }
}
async function viewFsProduct(id, name) {
  openDrawer('<div class="dsub">Inapakia…</div>');
  try {
    const j = await getJSON('/api/admin/products');
    const p = ((j && j.products) || []).find((x) => x.id === id);
    if (!p) { closeDrawer(); toast('Bidhaa haikuonekana', false); return; }
    const img = (p.images && p.images[0]) || '';
    openDrawer(
      '<h3>' + esc(p.name || '—') + '</h3>' +
      '<div class="dsub">' + esc(p.category || '') + (p.subcategory ? ' · ' + esc(p.subcategory) : '') + (p.location ? ' · ' + esc(p.location) : '') + '</div>' +
      (img ? '<div style="margin:10px 0"><img src="' + esc(img) + '" style="max-height:220px;border-radius:14px;width:100%;object-fit:cover" onerror="this.style.display=\'none\'"></div>' : '') +
      '<dl class="kv">' +
      '<dt>Bei</dt><dd>' + fmtTZS(p.price) + (p.currency && p.currency !== 'TZS' ? ' ' + esc(p.currency) : '') + '</dd>' +
      '<dt>Stock</dt><dd>' + fmtNum(p.stock) + (p.isWholesale ? ' · wholesale' : '') + '</dd>' +
      '<dt>Hali</dt><dd>' + (p.isActive === false ? '<span class="bdg mut">inactive</span>' : '<span class="bdg ok">active</span>') + (p.isFeatured ? ' · featured' : '') + (p.isBoosted ? ' · boosted' : '') + '</dd>' +
      '<dt>Muuzaji</dt><dd>' + esc(p.sellerName || '—') + (p.sellerPhone ? ' · ' + esc(p.sellerPhone) : '') + '</dd>' +
      '<dt>KYC ya muuzaji</dt><dd>' + (p.sellerKycApproved ? 'Ndiyo' : 'La') + '</dd>' +
      '<dt>Maelezo</dt><dd>' + esc((p.description || '—').slice(0, 400)) + '</dd>' +
      (p.barcode ? '<dt>Barcode</dt><dd class="mono">' + esc(p.barcode) + '</dd>' : '') +
      '<dt>Imeundwa</dt><dd>' + fmtTimeAny(p.createdAt) + '</dd>' +
      '</dl>' +
      '<div class="drawer-actions">' +
      '<button class="btn sm ' + (p.isActive === false ? 'accent' : 'danger') + '" data-fn="fpToggleActive" data-args=\'' + JSON.stringify({ id: p.id, name: p.name || p.id }).replace(/'/g, '&#39;') + '\'>' + (p.isActive === false ? 'Chapisha' : 'Sitisha') + '</button>' +
      '</div>'
    );
    bindSection('products');
  } catch (e) { toast(e.message, false); }
}
async function fpToggleActive(id, name) {
  const j = await getJSON('/api/admin/products');
  const cur = ((j && j.products) || []).find((x) => x.id === id);
  const to = !(cur && cur.isActive === false);
  const lab = to ? 'Chapisha' : 'Sitisha';
  if (!(await confirmModal(lab + ' (Firestore)', lab + ' bidhaa "' + esc(name) + '"?', 'Ndiyo, ' + lab.toLowerCase()))) return;
  await run(async () => {
    await api('/api/admin/products/' + encodeURIComponent(id), { method: 'PUT', body: { isActive: to } });
    toast('Imebadilishwa', true);
    renderFsProducts();
  });
}

// ---------------------------------------------------------------------------
// Wauzaji
// ---------------------------------------------------------------------------
function sellersToolbar() {
  return '<div class="toolbar">' +
    '<input class="field q" id="svQ" placeholder="Tafuta duka / anwani…">' +
    '<select class="select-xs" id="svV"><option value="">Uthibitisho: yote</option><option value="pending">pending</option><option value="verified">verified</option><option value="unverified">unverified</option><option value="rejected">rejected</option></select>' +
    '<button class="btn" id="svGo">Chuja</button>' +
    '</div>';
}
async function loadSellers() {
  const el = secEl('sellers');
  const page = pgState('sellers', 'page') || 1;
  const q = pgState('sellers', 'q') || '';
  const v = pgState('sellers', 'v') || '';
  el.innerHTML = sellersToolbar() + '<div class="card"><div class="tablewrap"><table class="tbl"><thead><tr>' +
    '<th>Duka</th><th>Mmiliki</th><th>Uthibitisho</th><th>Hali</th><th>Rrating</th><th>Mauzo / Mapato</th><th>Salio</th><th style="text-align:right">Vitendo</th></tr></thead>' +
    '<tbody id="svRows"><tr><td colspan="8" class="empty"><div class="spinner" style="width:22px;height:22px;margin:0 auto 8px"></div>Inapakia…</td></tr></tbody></table></div>' +
    '<div id="svPag"></div></div>';
  const qs = new URLSearchParams({ page, limit: 20 });
  if (q) qs.set('q', q); if (v) qs.set('verificationStatus', v);
  try {
    const j = await getJSON('/api/v1/admin/sellers?' + qs.toString());
    const d = (j.data && j.data.sellers) || [];
    $('svRows').innerHTML = d.length ? d.map((s) => {
      const w = s.wallet || {};
      const args = JSON.stringify({ id: s.id, name: s.storeName || s.id }).replace(/'/g, '&#39;');
      return '<tr>' +
        '<td><b>' + esc(s.storeName || '—') + '</b><div class="dim">' + esc(s.storeSlug || '') + '</div></td>' +
        '<td>' + esc((s.user && (s.user.displayName || s.user.email)) || '—') + '<div class="dim">' + (s.user && esc(s.user.phone || '')) + '</div></td>' +
        '<td>' + badge(s.verificationStatus) + '</td>' +
        '<td>' + badge(s.sellerStatus) + '</td>' +
        '<td>' + Number(s.reliabilityScore || 0).toFixed(1) + '<div class="dim">' + Math.round((s.onTimeDispatchRate || 1) * 100) + '%</div></td>' +
        '<td>' + fmtNum(s.totalSales) + '<div class="dim">' + fmtTZS(s.totalRevenue) + '</div></td>' +
        '<td>' + fmtTZS(w.availableBalance) + '<div class="dim">frozen ' + fmtTZS(w.frozenBalance) + '</div></td>' +
        '<td class="rowactions">' +
        '<button class="btn sm" data-fn="viewSeller" data-args=\'' + args + '\'>Angalia</button>' +
        (s.verificationStatus !== 'verified' ? '<button class="btn sm accent" data-fn="sellerVerify" data-args=\'' + args + '\'>Thibitisha</button>' : '') +
        (s.verificationStatus === 'pending' || s.verificationStatus === 'verified' ? '<button class="btn sm danger" data-fn="sellerReject" data-args=\'' + args + '\'>Kataa</button>' : '') +
        '</td></tr>';
    }).join('') : '<tr><td colspan="8" class="empty">Hakuna wauzaji</td></tr>';
    $('svPag').innerHTML = pagerHTML('sellers', j.data.pagination);
  } catch (e) { $('svRows').innerHTML = '<tr><td colspan="8" class="empty">' + esc(e.message) + '</td></tr>'; }
  bindSection('sellers'); touch();
}
async function sellerVerify(id, name, action) {
  const labels = { verify: 'Thibitisha', reject: 'Kataa', pending: 'Rudi pending' };
  const ok = await confirmModal(labels[action] + ': ' + name, 'Uthibitisha uamuzi huu? Unatengenezwa kwenye rekodi ya ukaguzi.', labels[action], action === 'reject');
  if (!ok) return;
  run(async () => {
    await putJSON('/api/v1/admin/sellers/' + id + '/verification', { action });
    toast(labels[action] + ' — imefanyika', true); loadSellers();
  });
}
async function viewSellerDetail(id) {
  openDrawer('<div class="dsub">Inapakia…</div>');
  try {
    const j = await getJSON('/api/v1/admin/sellers');
    // fetch single via list page 1 with slug/marker — use list with big limit then filter
    const all = (j.data && j.data.sellers) || [];
    const s = all.find((x) => x.id === id);
    if (!s) { closeDrawer(); toast('Muuzaji hakupatikana kwenye ukurasa wa kwanza', false); return; }
    const w = s.wallet || {};
    const u = s.user || {};
    openDrawer(
      '<h3>' + esc(s.storeName || 'Duka') + '</h3>' +
      '<div class="dsub">@' + esc(s.storeSlug || '') + '</div>' +
      '<dl class="kv">' +
      '<dt>Mmiliki</dt><dd>' + esc(u.displayName || u.email || '—') + '</dd>' +
      '<dt>Simu / email</dt><dd>' + esc(u.phone || '—') + ' · ' + esc(u.email || '—') + '</dd>' +
      '<dt>Uthibitisho</dt><dd>' + badge(s.verificationStatus) + ' · ' + badge(s.sellerStatus) + '</dd>' +
      '<dt>Maelezo</dt><dd>' + esc(s.storeDescription || '—') + '</dd>' +
      '<dt>Biashara</dt><dd>' + esc(s.businessType || '—') + '<div class="dim">' + esc(s.businessRegistrationNumber || s.taxId || '') + '</div></dd>' +
      '<dt>Rrating</dt><dd>' + Number(s.reliabilityScore || 0).toFixed(1) + '/5 · on-time ' + Math.round((s.onTimeDispatchRate || 1) * 100) + '% · dispute ' + Number(s.disputeRate || 0).toFixed(4) + '</dd>' +
      '<dt>Mauzo</dt><dd>' + fmtNum(s.totalSales) + ' · ' + fmtTZS(s.totalRevenue) + '</dd>' +
      '<dt>AI kitengo</dt><dd>' + Number(s.avgShippingResponseHours || 0).toFixed(1) + 'h</dd>' +
      '<dt>Salio</dt><dd>' + fmtTZS(w.availableBalance) + ' <span class="dim">+pending ' + fmtTZS(w.pendingBalance) + '</span></dd>' +
      '<dt>Imetolewa</dt><dd>' + fmtTZS(w.totalWithdrawn) + '</dd>' +
      '<dt>Bidhaa / maagizo / withdrawals</dt><dd>' + fmtNum(s._count && s._count.products) + ' / ' + fmtNum(s._count && s._count.orders) + ' / ' + fmtNum(s._count && s._count.withdrawals) + '</dd>' +
      '</dl>' +
      '<div class="drawer-actions">' +
      '<button class="btn sm accent" data-fn="sellerVerify" data-args=\'' + JSON.stringify({ id: s.id, name: s.storeName || s.id }).replace(/'/g, '&#39;') + '\'>Thibitisha</button>' +
      '<button class="btn sm danger" data-fn="sellerReject" data-args=\'' + JSON.stringify({ id: s.id, name: s.storeName || s.id }).replace(/'/g, '&#39;') + '\'>Kataa</button>' +
      '</div>'
    );
    bindSection('sellers');
  } catch (e) { toast(e.message, false); }
}

// ---------------------------------------------------------------------------
// Bidhaa
// ---------------------------------------------------------------------------
function productsToolbar() {
  return '<div class="toolbar">' +
    '<input class="field q" id="pQ" placeholder="Tafuta bidhaa…">' +
    '<select class="select-xs" id="pStatus"><option value="">Hali: yote</option><option>draft</option><option>published</option><option>suspended</option><option>rejected</option><option>deleted</option></select>' +
    '<button class="btn" id="pGo">Chuja</button>' +
    '</div>';
}
function thumbOf(media) {
  const m = (media && media[0]) || {};
  const url = m.thumbnailR2Key || m.r2Key;
  if (url && /^https?:\/\//.test(url)) return '<img class="thumb" src="' + esc(url) + '" loading="lazy" onerror="this.style.display=\'none\'">';
  return '<div class="thumb" style="display:grid;place-items:center;color:var(--muted);font-size:11px">' + (media ? media.length : 0) + '</div>';
}
async function loadProducts() {
  const el = secEl('products');
  const page = pgState('products', 'page') || 1;
  const q = pgState('products', 'q') || '';
  const st = pgState('products', 'st') || '';
  el.innerHTML = productsToolbar() + '<div class="card"><div class="tablewrap"><table class="tbl"><thead><tr>' +
    '<th>Bidhaa</th><th>Duka</th><th>Kategoria</th><th>Bei</th><th>Hali</th><th>Dawa</th><th style="text-align:right">Vitendo</th></tr></thead>' +
    '<tbody id="pRows"><tr><td colspan="7" class="empty"><div class="spinner" style="width:22px;height:22px;margin:0 auto 8px"></div>Inapakia…</td></tr></tbody></table></div>' +
    '<div id="pPag"></div></div>' +
    '<div id="fpCard"></div>';
  const qs = new URLSearchParams({ page, limit: 20 });
  if (q) qs.set('q', q); if (st) qs.set('status', st);
  try {
    const j = await getJSON('/api/v1/admin/products?' + qs.toString());
    const d = (j.data && j.data.products) || [];
    $('pRows').innerHTML = d.length ? d.map((p) => {
      const args = JSON.stringify({ id: p.id, title: p.title || p.id }).replace(/'/g, '&#39;');
      return '<tr>' +
        '<td>' + thumbOf(p.media) + ' <b>' + esc(p.title || '—') + '</b><div class="dim mono">' + esc(id12(p.id)) + '</div></td>' +
        '<td>' + esc((p.seller && p.seller.storeName) || '—') + '</td>' +
        '<td class="dim">' + esc((p.category && p.category.name) || '—') + '</td>' +
        '<td class="num">' + fmtTZS(p.price) + '<div class="dim">stock ' + fmtNum(p.stock) + '</div></td>' +
        '<td>' + badge(p.status) + '<div class="dim">' + esc(p.condition || '') + '</div></td>' +
        '<td class="dim">' + fmtTime(p.createdAt) + '</td>' +
        '<td class="rowactions">' +
        '<button class="btn sm" data-fn="viewProduct" data-args=\'' + args + '\'>Angalia</button>' +
        '<button class="btn sm" data-fn="productModerate" data-args=\'' + args + '\'>Hali</button>' +
        '</td></tr>';
    }).join('') : '<tr><td colspan="7" class="empty">Hakuna bidhaa</td></tr>';
    $('pPag').innerHTML = pagerHTML('products', j.data.pagination);
  } catch (e) { $('pRows').innerHTML = '<tr><td colspan="7" class="empty">' + esc(e.message) + '</td></tr>'; }
  bindSection('products'); touch();
  renderFsProducts();
}
async function productModerate(id, title) {
  openModal(
    '<h3>Hali ya bidhaa: ' + esc(title) + '</h3><p class="msub">Chagua hali mpya ya uchapishaji</p>' +
    '<div class="radio-row" id="pMoRow">' +
    ['published', 'suspended', 'rejected', 'draft'].map((s) => '<button class="radio-chip" data-v="' + s + '">' + s + '</button>').join('') +
    '</div>' +
    '<label>Sababu (hiari)</label><input class="field" id="pMoReason" placeholder="Kwa nini hali hii?">' +
    '<div class="mfooter"><button class="btn" id="pMoNo">Futa</button><button class="btn accent" id="pMoYes">Hifadhi</button></div>'
  );
  let pick = 'published';
  $('pMoRow').querySelectorAll('.radio-chip').forEach((c) => c.addEventListener('click', () => {
    $('pMoRow').querySelectorAll('.radio-chip').forEach((x) => x.classList.remove('on'));
    c.classList.add('on'); pick = c.dataset.v;
  }));
  $('pMoNo').onclick = closeModal;
  $('pMoYes').onclick = () => run(async () => {
    await putJSON('/api/v1/products/' + id + '/moderate', { status: pick, reason: $('pMoReason').value || undefined });
    closeModal(); toast('Hali imebadilishwa -> ' + pick, true); loadProducts();
  });
}
async function viewProductDetail(id, title) {
  openDrawer('<div class="dsub">Inapakia…</div>');
  try {
    const qs = new URLSearchParams({ page: 1, limit: 50 });
    const j = await getJSON('/api/v1/admin/products?' + qs.toString());
    const d = (j.data && j.data.products) || [];
    const p = d.find((x) => x.id === id);
    if (!p) { closeDrawer(); toast('Bidhaa haikuonekana', false); return; }
    const b = (p.boosts && p.boosts[0]) || {};
    openDrawer(
      '<h3>' + esc(p.title || '—') + '</h3>' +
      '<div class="dsub">' + esc(p.slug || '') + ' · ' + esc((p.category && p.category.name) || '') + '</div>' +
      '<dl class="kv">' +
      '<dt>Bei</dt><dd>' + fmtTZS(p.price) + (p.originalPrice ? ' <span class="dim">(was ' + fmtTZS(p.originalPrice) + ')</span>' : '') + '</dd>' +
      '<dt>Hali / stock</dt><dd>' + badge(p.status) + ' · ' + esc(p.condition || '') + ' · ' + fmtNum(p.stock) + '</dd>' +
      '<dt>Duka</dt><dd>' + esc((p.seller && p.seller.storeName) || '—') + '</dd>' +
      '<dt>Maelezo</dt><dd>' + esc((p.description || '—').slice(0, 400)) + '</dd>' +
      p.weightGrams ? '<dt>Uzito</dt><dd>' + fmtNum(p.weightGrams) + 'g</dd>' : '' +
      '<dt>Picha</dt><dd>' + fmtNum((p.media || []).length) + ' ' + (p.media || []).map((m) => (m.r2Key && /^https?:\/\//.test(m.r2Key)) ? '<a href="' + esc(m.r2Key) + '" target="_blank" rel="noopener">[picha]</a> ' : '').join('') + '</dd>' +
      (b.id ? '<dt>Boost</dt><dd>' + esc(b.plan || '—') + ' · ' + badge(b.status) + ' · hadi ' + fmtTime(b.expiresAt) + '</dd>' : '') +
      '<dt>Imeundwa</dt><dd>' + fmtTime(p.createdAt) + '</dd>' +
      '</dl>' +
      '<div class="drawer-actions">' +
      '<button class="btn sm accent" data-fn="productModerate" data-args=\'' + JSON.stringify({ id: p.id, title: p.title || p.id }).replace(/'/g, '&#39;') + '\'>Hali ya uchapishaji</button>' +
      '</div>'
    );
    bindSection('products');
  } catch (e) { toast(e.message, false); }
}

// ---------------------------------------------------------------------------
// Maagizo
// ---------------------------------------------------------------------------
function ordersToolbar() {
  return '<div class="toolbar">' +
    '<input class="field q" id="oQ" placeholder="Namba ya agizo / simu / email / duka…">' +
    '<select class="select-xs" id="oStatus"><option value="">Hali: yote</option>' +
    '<option>draft</option><option>awaiting_escrow_payment</option><option>in_escrow</option><option>ready_to_dispatch</option><option>dispatched</option><option>delivered</option><option>inspection_period</option><option>otp_pending</option><option>completed</option><option>wallet_credited</option><option>payout_pending</option><option>payout_complete</option><option>disputed</option><option>refund_pending</option><option>refunded</option><option>cancelled</option><option>expired</option><option>failed</option></select>' +
    '<button class="btn" id="oGo">Chuja</button>' +
    '</div>';
}
async function loadOrders() {
  const el = secEl('orders');
  const page = pgState('orders', 'page') || 1;
  const q = pgState('orders', 'q') || '';
  const st = pgState('orders', 'st') || '';
  el.innerHTML = ordersToolbar() + '<div class="card"><div class="tablewrap"><table class="tbl"><thead><tr>' +
    '<th>No.</th><th>Mnunuzi</th><th>Duka (muuzaji)</th><th>Jumla</th><th>Hali</th><th>Escrow</th><th>Iliundwa</th><th style="text-align:right">Vitendo</th></tr></thead>' +
    '<tbody id="oRows"><tr><td colspan="8" class="empty"><div class="spinner" style="width:22px;height:22px;margin:0 auto 8px"></div>Inapakia…</td></tr></tbody></table></div>' +
    '<div id="oPag"></div></div>' +
    '<div id="foCard"></div>';
  const qs = new URLSearchParams({ page, limit: 20 });
  if (q) qs.set('q', q); if (st) qs.set('status', st);
  try {
    const j = await getJSON('/api/v1/admin/orders?' + qs.toString());
    const d = (j.data && j.data.orders) || [];
    $('oRows').innerHTML = d.length ? d.map((o) => {
      const disp = o.dispute ? badge('disputed') : (o.escrowHold ? badge('in_escrow') : '');
      return '<tr>' +
        '<td class="mono"><b>' + esc(o.orderNumber || id12(o.id)) + '</b></td>' +
        '<td>' + esc((o.buyer && (o.buyer.displayName || o.buyer.email)) || '—') + '<div class="dim mono">' + esc((o.buyer && o.buyer.phone) || '') + '</div></td>' +
        '<td>' + esc((o.seller && o.seller.storeName) || '—') + '</td>' +
        '<td class="num">' + fmtTZS(o.totalAmount) + '</td>' +
        '<td>' + badge(o.status) + '</td>' +
        '<td>' + (disp || '—') + '</td>' +
        '<td class="dim">' + fmtTime(o.placedAt || o.createdAt) + '</td>' +
        '<td class="rowactions"><button class="btn sm" data-fn="viewOrder" data-args=\'' + JSON.stringify({ id: o.id, num: o.orderNumber || o.id, status: o.status }).replace(/'/g, '&#39;') + '\'>Angalia</button></td>' +
        '</tr>';
    }).join('') : '<tr><td colspan="8" class="empty">Hakuna maagizo</td></tr>';
    $('oPag').innerHTML = pagerHTML('orders', j.data.pagination);
  } catch (e) { $('oRows').innerHTML = '<tr><td colspan="8" class="empty">' + esc(e.message) + '</td></tr>'; }
  bindSection('orders'); touch();
  renderFsOrders();
}
// Maagizo halisi ya app yanaishi FIRESTORE; kadi hii inayapatia admin mwonekano
// na kufungua drawer moja kwa moja (oonloadOrders).
async function renderFsOrders() {
  const wrap = $('foCard');
  if (!wrap) return;
  wrap.innerHTML = '<div class="card"><div class="cardhead"><h3>Maagizo (Firestore) — app ndiyo yanayoandika hapa</h3><button class="btn sm" id="foRefresh">Onyesha upya</button></div><div class="dsub" style="padding:0 16px 16px"><div class="spinner" style="width:20px;height:20px"></div></div></div>';
  try {
    const [oj, uj] = await Promise.all([getJSON('/api/admin/orders'), getJSON('/api/admin/users').catch(() => null)]);
    const all = ((oj && oj.orders) || []).slice(0, 50);
    const umap = {};
    if (uj && uj.users) uj.users.forEach((u) => { umap[u.uid || u.id] = u; });
    if (!all.length) {
      wrap.innerHTML = '<div class="card"><div class="cardhead"><h3>Maagizo (Firestore)</h3><button class="btn sm" id="foRefresh">Onyesha upya</button></div><div class="dsub" style="padding:0 16px 16px">Hakuna maagizo kwenye Firestore.</div></div>';
      $('foRefresh').onclick = () => renderFsOrders();
      return;
    }
    wrap.innerHTML = '<div class="card"><div class="cardhead"><h3>Maagizo (Firestore)</h3><button class="btn sm" id="foRefresh">Onyesha upya</button></div>' +
      '<div class="tablewrap" style="max-height:360px;overflow:auto"><table class="tbl"><thead><tr><th>No.</th><th>Mnunuzi</th><th>Muuzaji</th><th>Jumla</th><th>Hali</th><th>Imeundwa</th><th style="text-align:right">Vitendo</th></tr></thead><tbody>' +
      all.map((o) => {
        const buyer = umap[o.buyerId] || {};
        const seller = umap[o.sellerId] || {};
        const args = JSON.stringify({ id: o.id, num: o.orderNumber || o.orderId || o.id }).replace(/'/g, '&#39;');
        return '<tr>' +
          '<td class="mono"><b>' + esc(o.orderNumber || o.orderId || id12(o.id)) + '</b>' + (o.orderNumber ? '<div class="dim mono">' + esc(id12(o.id)) + '</div>' : '') + '</td>' +
          '<td>' + esc(buyer.displayName || buyer.username || o.buyerId || '—') + '</td>' +
          '<td>' + esc(seller.displayName || o.sellerId || '—') + '</td>' +
          '<td class="num">' + fmtTZS(Number(o.totalAmount || o.amount || 0)) + '</td>' +
          '<td>' + badge(o.status) + '</td>' +
          '<td class="dim">' + fmtTimeAny(o.createdAt) + '</td>' +
          '<td class="rowactions"><button class="btn sm" data-fn="viewFsOrder" data-args=\'' + args + '\'>Angalia</button></td>' +
          '</tr>';
      }).join('') +
      '</tbody></table></div></div>';
    $('foRefresh').onclick = () => renderFsOrders();
    bindSection('orders');
  } catch (e) {
    wrap.innerHTML = '<div class="card"><div class="cardhead"><h3>Maagizo (Firestore)</h3></div><div class="err">' + esc(e.message) + '</div></div>';
  }
}
// Detail ya agizo inayoongozwa na HATUA ilipo (kazi/service inayofanyika
// muda huo): timeline ya hatua + kadi ya "sasa kinafanyika" yenye taarifa
// na vitendo vinavyohusiana na hatua hiyo, kisha wahusika/bidhaa/pesa.
const ORDER_PHASES = ['Agizo limewekwa', 'Malipo (escrow)', 'Usafirishaji', 'Imewasili', 'Imekamilika'];
function orderWork(o) {
  const s = String(o.status || '');
  const buyerName = (o.buyer && (o.buyer.displayName || o.buyer.email)) || 'mnunuzi';
  const buyerContact = (o.buyer && (o.buyer.phone || o.buyer.email)) || '—';
  const storeName = (o.seller && o.seller.storeName) || 'muuzaji';
  const pre = ['draft', 'published', 'address_required', 'pending_shipping_fee', 'shipping_fee_submitted', 'shipping_fee_review', 'awaiting_escrow_payment', 'payment_pending'];
  if (pre.includes(s)) return { phase: 1, tone: 'warn', title: 'Inasubiri malipo', desc: 'Agizo lipo lakini ' + buyerName + ' hajalipa bado.', extra: '<dt>Kiasi kinachosubiriwa</dt><dd>' + fmtTZS(o.totalAmount) + '</dd><dt>Mawasiliano ya mnunuzi</dt><dd>' + esc(buyerContact) + '</dd>' };
  if (s === 'in_escrow') return { phase: 2, tone: 'info', title: 'Pesa ziko escrow', desc: 'Malipo yamepokelewa na yanashikiliwa. Hatua inayofuata: ' + storeName + ' atume bidhaa.', extra: (o.escrowHold ? '<dt>Escrow</dt><dd>' + fmtTZS(o.escrowHold.amount) + ' · ' + badge(o.escrowHold.status) + '</dd>' : '<dt>Escrow</dt><dd>' + fmtTZS(o.totalAmount) + '</dd>') };
  if (s === 'ready_to_dispatch') return { phase: 2, tone: 'info', title: 'Tayari kusafirishwa', desc: storeName + ' anatakiwa kuandaa na kutuma bidhaa sasa.', extra: '<dt>Muuzaji</dt><dd>' + esc(storeName) + '</dd>' };
  if (['dispatched', 'in_transit', 'out_for_delivery', 'delivery_attempted'].includes(s)) return { phase: 2, tone: 'info', title: 'Inasafirishwa sasa', desc: 'Bidhaa iko njiani kuelekea kwa mnunuzi.', extra: '<dt>Msafirishaji</dt><dd>' + esc(o.courierName || '—') + (o.trackingNumber ? ' · <span class="mono">' + esc(o.trackingNumber) + '</span>' : '') + '<div class="dim">' + esc(o.shippingMethod || '') + '</div></dd>' };
  if (['delivered', 'inspection_period', 'otp_pending'].includes(s)) return { phase: 3, tone: 'info', title: 'Imewasili — inasubiri ukamilishaji', desc: 'Mnunuzi amepokea. Inasubiri uthibitisho wa kupokea ili pesa iachiwe.', extra: '<dt>Iliwasilishwa</dt><dd>' + fmtTime(o.deliveredAt) + '</dd>' };
  if (['completed', 'wallet_credited', 'payout_pending', 'payout_complete'].includes(s)) return { phase: 4, tone: 'ok', title: 'Imekamilika', desc: 'Agizo limefungwa salama. Tume ya jukwaa imerekodiwa.', extra: '<dt>Tume iliyopatikana</dt><dd>' + fmtTZS(o.platformCommission) + '</dd><dt>Ilikamilishwa</dt><dd>' + fmtTime(o.completedAt) + '</dd>' };
  if (s === 'disputed') {
    const d = o.dispute || {};
    const canResolve = d.id && d.status !== 'resolved';
    return { phase: -1, tone: 'bad', title: 'Mgogoro unaendelea', desc: 'Agizo limesimama kwenye utatuzi. ' + (d.reason ? 'Sababu: ' + d.reason + '.' : ''), extra: '<dt>Hali ya mgogoro</dt><dd>' + badge(d.status || 'disputed') + '</dd>', action: canResolve ? '<button class="btn sm accent" data-fn="disputeResolve" data-args=\'' + JSON.stringify({ id: d.id, num: o.orderNumber || o.id, total: o.totalAmount || 0 }).replace(/'/g, '&#39;') + '\'>Suluhisha mgogoro</button>' : '' };
  }
  if (s === 'refund_pending') return { phase: -1, tone: 'warn', title: 'Rejesho linasubiri kutekelezwa', desc: 'Pesa zinatarajiwa kurudishwa kwa mnunuzi.', extra: '<dt>Kiasi</dt><dd>' + fmtTZS(o.totalAmount) + '</dd>' };
  if (s === 'refunded') return { phase: -1, tone: 'mut', title: 'Pesa zimerejeshwa', desc: 'Agizo limefungwa kwa marejesho.', extra: '' };
  if (['cancelled', 'canceled', 'failed', 'expired'].includes(s)) return { phase: -1, tone: 'mut', title: 'Agizo limefungwa', desc: 'Hali ya mwisho: ' + s + '.', extra: '<dt>Imefungwa</dt><dd>' + fmtTime(o.cancelledAt || o.updatedAt) + '</dd>' };
  return { phase: -1, tone: 'info', title: 'Hali: ' + s, desc: '', extra: '' };
}
async function viewOrderDetail(id, num, status) {
  openDrawer('<div class="dsub">Inapakia…</div>');
  try {
    const j = await getJSON('/api/v1/admin/orders?q=' + encodeURIComponent(num));
    const d = (j.data && j.data.orders) || [];
    const o = d.find((x) => x.id === id) || d[0];
    if (!o) { closeDrawer(); toast('Agizo halikuonekana', false); return; }
    const work = orderWork(o);
    const stepTimes = [o.placedAt || o.createdAt, o.paidAt || (o.escrowHold ? o.escrowHold.createdAt : null), o.dispatchedAt, o.deliveredAt, o.completedAt];
    const steps = ORDER_PHASES.map((lab, i) => {
      const done = !!stepTimes[i] || (work.phase >= 0 && i < work.phase);
      const now = work.phase === i;
      return '<li class="step ' + (done ? 'done' : (now ? 'now' : 'todo')) + '"><span class="sdot"></span><div><b>' + lab + '</b><div class="dim">' + (stepTimes[i] ? fmtTime(stepTimes[i]) : (now ? 'inafanyika sasa' : '—')) + '</div></div></li>';
    }).join('');
    const items = (o.items || []).map((it) =>
      '<div style="display:flex;justify-content:space-between;gap:8px;padding:6px 0;border-bottom:1px solid var(--border)"><span>' + esc((it.snapshot && it.snapshot.title) || it.productId || 'Bidhaa') + ' × ' + fmtNum(it.quantity) + '</span><span class="num">' + fmtTZS(it.totalPrice) + '</span></div>').join('');
    openDrawer(
      '<h3>Agizo ' + esc(o.orderNumber || id12(o.id)) + '</h3>' +
      '<div class="dsub mono">' + esc(id12(o.id)) + ' · ' + fmtTime(o.placedAt || o.createdAt) + '</div>' +
      '<div class="worknow ' + work.tone + '"><div class="wrow"><span class="wtag">SASA</span>' + badge(o.status) + '</div>' +
      '<div class="wtitle">' + esc(work.title) + '</div><div class="wdesc">' + esc(work.desc) + '</div>' +
      (work.extra ? '<dl class="kv" style="margin:10px 0 0">' + work.extra + '</dl>' : '') +
      (work.action ? '<div class="drawer-actions" style="margin-top:10px">' + work.action + '</div>' : '') + '</div>' +
      '<div class="dsub" style="margin-top:14px">Hatua za agizo</div><ol class="steps">' + steps + '</ol>' +
      '<hr class="hr"><div class="dsub">Wahusika</div><dl class="kv">' +
      '<dt>Mnunuzi</dt><dd>' + esc((o.buyer && (o.buyer.displayName || o.buyer.email)) || '—') + '<div class="dim">' + esc((o.buyer && o.buyer.phone) || '') + '</div></dd>' +
      '<dt>Muuzaji</dt><dd>' + esc((o.seller && o.seller.storeName) || '—') + '</dd></dl>' +
      (items ? '<hr class="hr"><div class="dsub">Bidhaa</div>' + items : '') +
      '<hr class="hr"><div class="dsub">Pesa</div><dl class="kv">' +
      '<dt>Jumla</dt><dd>' + fmtTZS(o.totalAmount) + '</dd>' +
      '<dt>Bidhaa / usafiri</dt><dd>' + fmtTZS(o.productPrice) + ' / ' + fmtTZS(o.shippingFee) + '</dd>' +
      '<dt>Tume</dt><dd>' + fmtTZS(o.platformCommission) + '</dd></dl>' +
      adminEscrowCard(o)
    );
  } catch (e) { toast(e.message, false); }
}

// Drawer kwa agizo la FIRESTORE (legacy): id ni doc id ya orders collection,
// hali na pesa zinachukuliwa raw; v2 escrow huenda isijasawazishwa hapa.
async function viewFsOrder(id, num) {
  openDrawer('<div class="dsub">Inapakia…</div>');
  try {
    const [oj, uj] = await Promise.all([getJSON('/api/admin/orders'), getJSON('/api/admin/users').catch(() => null)]);
    const o = ((oj && oj.orders) || []).find((x) => x.id === id);
    if (!o) { closeDrawer(); toast('Agizo halikuonekana', false); return; }
    const umap = {};
    if (uj && uj.users) uj.users.forEach((u) => { umap[u.uid || u.id] = u; });
    const buyer = umap[o.buyerId] || {};
    const seller = umap[o.sellerId] || {};
    const items = Array.isArray(o.items) ? o.items : [];
    const total = Number(o.totalAmount || o.amount || 0);
    const ship = Number(o.shippingCost || o.shippingFee || 0);
    const actSec = document.querySelector('.section.active');
    openDrawer(
      '<h3>Agizo ' + esc(o.orderNumber || o.orderId || '#' + id12(o.id)) + '</h3>' +
      '<div class="dsub mono">' + esc(id12(o.id)) + ' · ' + fmtTimeAny(o.createdAt) + '</div>' +
      '<div class="worknow info"><div class="wrow"><span class="wtag">FIRESTORE</span>' + badge(o.status) + '</div>' +
      '<div class="wtitle">Hali: ' + esc(o.status || '—') + '</div>' +
      '<div class="wdesc">Agizo la Firestore (legacy) — huduma za v2 (escrow, malipo) zinaweza kuwa hazijasawazishwa hapa.</div></div>' +
      '<div class="dsub" style="margin-top:12px">Wahusika</div><dl class="kv">' +
      '<dt>Mnunuzi</dt><dd>' + esc(buyer.displayName || buyer.username || o.buyerId || '—') + '<div class="dim">' + esc((buyer.phone || '') + (buyer.email ? ' · ' + buyer.email : '')) + '</div></dd>' +
      '<dt>Muuzaji</dt><dd>' + esc(seller.displayName || o.sellerId || '—') + '</dd></dl>' +
      (items.length ? '<div class="dsub">Bidhaa</div>' + items.slice(0, 40).map((it) =>
        '<div style="display:flex;justify-content:space-between;gap:8px;padding:6px 0;border-bottom:1px solid var(--border)"><span>' + esc(it.title || it.productName || (it.snapshot && it.snapshot.title) || it.productId || 'Bidhaa') + ' × ' + fmtNum(it.qty || it.quantity || 1) + '</span><span class="num">' + fmtTZS(it.price || it.totalPrice || it.amount || 0) + '</span></div>').join('') : '') +
      '<hr class="hr"><div class="dsub">Pesa</div><dl class="kv">' +
      '<dt>Jumla</dt><dd>' + fmtTZS(total) + '</dd>' +
      (ship ? '<dt>Usafiri</dt><dd>' + fmtTZS(ship) + '</dd>' : '') +
      '</dl>'
    );
    if (actSec) bindSection(actSec.dataset.sec);
  } catch (e) { toast(e.message, false); }
}
function fsToDate(v) {
  if (!v) return null;
  if (v.seconds != null || v._seconds != null) return new Date(Number(v.seconds != null ? v.seconds : v._seconds) * 1000);
  return v;
}
function mergeRecent(pgRows, fsRows) {
  const seen = new Set([...pgRows.map((o) => o.id || ''), ...pgRows.map((o) => o.legacyFirestoreId || '').filter(Boolean)]);
  const fsNorm = (fsRows || []).filter((o) => !seen.has(o.id)).slice(0, 6).map((o) => {
    const buyer = (o.buyer && (o.buyer.displayName || o.buyer.name)) || o.buyerName || o.buyerId || '—';
    return {
      id: o.id,
      orderNumber: o.orderNumber || o.orderId,
      createdAt: fsToDate(o.createdAt),
      buyer: { displayName: buyer, email: '' },
      totalAmount: Number(o.totalAmount || o.amount || 0),
      status: o.status || 'unknown',
      fs: true,
    };
  });
  return [...pgRows.slice(0, 6).map((o) => ({ ...o, fs: false })), ...fsNorm]
    .sort((a, b) => new Date(b.createdAt || 0) - new Date(a.createdAt || 0))
    .slice(0, 6);
}

// Kadi ya Amana katika drawer la agizo: endapo agizo linashikilia escrow,
// admin ana vitendo vya kufungua kwa muuzaji, kutolea mnunuzi (refund), au
// kuhamisha fedha kwa namba anayochagua mwenyewe. orderId ni id ya Firestore
// kwa maagizo ya zamani, au id ya v2 kama haijasawazishwa (essc id inaonyeshwa).
function adminEscrowCard(o) {
  const s = String(o.status || '');
  // statuses asanézo la legacy Firestore pekee
  const legacyStatus = ['escrow_hold', 'paid_escrow_hold', 'paid_escrow_held'].includes(s);
  // v2 na legacy zote zinaweza kuwa in_escrow/diputed — hazionyeshwi bila legacyFirestoreId
  const mirrored = !!o.legacyFirestoreId && (s === 'disputed' || ['in_escrow', 'dispatched', 'awaiting_escrow_payment', 'payment_pending', 'ready_to_dispatch'].includes(s));
  if (!legacyStatus && !mirrored) return '';
  const escrowId = o.legacyFirestoreId || o.id;
  const holds = legacyStatus || (mirrored && s === 'in_escrow');
  const disputed = s === 'disputed';
  const mk = (fn, label, extra) => '<button class="btn sm ' + (extra || '') + '" data-fn="' + fn + '" data-args=\'' +
    JSON.stringify({ orderId: escrowId, num: o.orderNumber || o.id }).replace(/'/g, '&#39;') + '\'>' + label + '</button>';
  let buttons = '';
  if (holds) buttons += mk('escrowRelease', 'Fungua → Muuzaji', 'accent') + ' ';
  if (disputed) {
    buttons += mk('escrowResolve', 'Toa kwa Muuzaji', 'accent') + ' ';
    buttons += mk('escrowRefund', 'Rejesha kwa Mnunuzi', 'danger') + ' ';
  }
  buttons += mk('escrowTransfer', 'Hamisha kwa namba…', '');
  return '<hr class="hr"><div class="dsub">Amana (Escrow) — Vitendo vya Admin</div>' +
    '<div class="dim mono" style="margin:2px 0 8px">Id ya amana: ' + esc(escrowId) + '</div>' +
    '<div class="drawer-actions">' + buttons + '</div>' +
    '<p class="hint">Refund na hamisho hutumia ClickPesa payout kwenye namba halisi. Thibitisha id ya amana kabla ya kutuma.</p>';
}
async function escrowReleaseAction(args) {
  const ok = await confirmModal('Fungua Amana', 'Fungua escrow ya agizo ' + args.num + ' na kuweka pesa kwa salio la muuzaji?', 'Fungua', false);
  if (!ok) return;
  run(async () => {
    const j = await postJSON('/api/escrow/admin-release', { orderId: args.orderId });
    toast((j && j.message) || 'Amana imefunguliwa', true);
    loadOrders();
  });
}
async function escrowAdjudicate(args, mode) {
  const isRefund = mode === 'refund';
  const ok = await confirmModal(
    isRefund ? 'Rejesha kwa Mnunuzi' : 'Toa kwa Muuzaji',
    isRefund
      ? 'Tuma refund KAMILI ya agizo ' + args.num + ' kwa namba ya mnunuzi kupitia ClickPesa?'
      : 'Kamilisha mgogoro wa ' + args.num + ' na kutoa pesa zote kwa muuzaji?',
    isRefund ? 'Tuma Refund' : 'Toa kwa Muuzaji',
    isRefund
  );
  if (!ok) return;
  const notes = isRefund ? prompt('Sababu / Maelezo (kwa mnunuzi)') : prompt('Maelezo ya uamuzi');
  if (notes === null) return;
  run(async () => {
    const j = await postJSON('/api/escrow/admin-resolve-dispute', { orderId: args.orderId, resolution: isRefund ? 'refund' : 'release', note: notes });
    toast((j && j.message) || 'Mgogoro umesuluhishwa', true);
    loadOrders();
  });
}
async function escrowTransferAction(args) {
  openModal(
    '<h3>Hamisha Fedha (Admin Transfer)</h3>' +
    '<p class="msub">Agizo: ' + esc(args.num) + ' · Id ya amana: <span class="mono">' + esc(args.orderId) + '</span></p>' +
    '<label class="lab">Kiasi (TZS)</label><input id="trAmt" class="field" type="number" inputmode="numeric" min="1000" placeholder="e.g. 50000">' +
    '<label class="lab">Namba ya kupokea (ClickPesa)</label><input id="trPhone" class="field" type="tel" inputmode="tel" placeholder="e.g. 0712345678">' +
    '<label class="lab">Maelezo (si lazima)</label><input id="trNote" class="field" type="text" placeholder="Sababu ya hamisho">' +
    '<div class="err" id="trErr"></div>' +
    '<div class="mfooter"><button class="btn" id="trNo">Futa</button><button class="btn danger" id="trYes">Tuma Transfer</button></div>'
  );
  $('trNo').onclick = closeModal;
  $('trYes').onclick = () => {
    const amount = Math.round(Number($('trAmt').value) || 0);
    const phone = $('trPhone').value.trim();
    const note = $('trNote').value.trim();
    if (amount <= 0) { $('trErr').textContent = 'Andika kiasi halali.'; return; }
    if (!phone) { $('trErr').textContent = 'Andika namba ya kupokea.'; return; }
    run(async () => {
      const j = await postJSON('/api/escrow/admin-transfer', { orderId: args.orderId, amount, phone, note });
      closeModal();
      toast((j && j.message) || 'Transfer imetumwa', true);
      loadOrders();
    });
  };
}

// ---------------------------------------------------------------------------
// Migogoro
// ---------------------------------------------------------------------------
function disputesToolbar() {
  return '<div class="toolbar"><select class="select-xs" id="dStatus"><option value="">Hali: yote</option><option value="open">open</option><option value="under_review">under_review</option><option value="resolved">resolved</option></select>' +
    '<button class="btn" id="dGo">Chuja</button></div>';
}
function disputeReason(r) {
  const pretty = { WRONG_ITEM: 'Bidhaa yenye makosa', DAMAGED_ITEM: 'Imekwisha ama kuharibika', FAKE_ITEM: 'Bidhaa ghushi', NOT_RECEIVED: 'Haijafika', QUALITY_ISSUE: 'Ubora haufai', BUYER_FRAUD: 'Udanganyifu wa mnunuzi' };
  return pretty[r] || r;
}
async function loadDisputes() {
  const el = secEl('disputes');
  const page = pgState('disputes', 'page') || 1;
  const st = pgState('disputes', 'st') || '';
  el.innerHTML = disputesToolbar() + '<div class="card"><div class="tablewrap"><table class="tbl"><thead><tr>' +
    '<th>Agizo</th><th>Aliyependa</th><th>Sababu</th><th>Hali</th><th>Kiasi</th><th>Iliundwa</th><th style="text-align:right">Vitendo</th></tr></thead>' +
    '<tbody id="dRows"><tr><td colspan="7" class="empty"><div class="spinner" style="width:22px;height:22px;margin:0 auto 8px"></div>Inapakia…</td></tr></tbody></table></div>' +
    '<div id="dPag"></div></div>';
  const qs = new URLSearchParams({ page, limit: 20 });
  if (st) qs.set('status', st);
  try {
    const j = await getJSON('/api/v1/admin/disputes?' + qs.toString());
    const d = (j.data && j.data.disputes) || [];
    $('dRows').innerHTML = d.length ? d.map((dis) => {
      const args = JSON.stringify({ id: dis.id, num: (dis.order && dis.order.orderNumber) || dis.orderId, total: (dis.order && dis.order.totalAmount) || 0 }).replace(/'/g, '&#39;');
      return '<tr>' +
        '<td class="mono"><b>' + esc((dis.order && dis.order.orderNumber) || id12(dis.orderId)) + '</b></td>' +
        '<td>' + esc((dis.filer && (dis.filer.displayName || dis.filer.email)) || '—') + '</td>' +
        '<td>' + esc(disputeReason(dis.reason)) + '<div class="dim">' + esc((dis.description || '').slice(0, 60)) + '</div></td>' +
        '<td>' + badge(dis.status) + '</td>' +
        '<td class="num">' + fmtTZS((dis.order && dis.order.totalAmount) || 0) + '</td>' +
        '<td class="dim">' + fmtTime(dis.createdAt) + '</td>' +
        '<td class="rowactions">' +
        '<button class="btn sm" data-fn="viewDispute" data-args=\'' + JSON.stringify({ id: dis.id }).replace(/'/g, '&#39;') + '\'>Angalia</button>' +
        (dis.status !== 'resolved' ? '<button class="btn sm accent" data-fn="disputeResolve" data-args=\'' + args + '\'>Suluhisha</button>' : '') +
        '</td></tr>';
    }).join('') : '<tr><td colspan="7" class="empty">Hakuna migogoro</td></tr>';
    $('dPag').innerHTML = pagerHTML('disputes', j.data.pagination);
  } catch (e) { $('dRows').innerHTML = '<tr><td colspan="7" class="empty">' + esc(e.message) + '</td></tr>'; }
  bindSection('disputes'); touch();
}
async function viewDisputeDetail(id) {
  openDrawer('<div class="dsub">Inapakia…</div>');
  try {
    const qs = new URLSearchParams({ page: 1, limit: 50 });
    const j = await getJSON('/api/v1/admin/disputes?' + qs.toString());
    const all = (j.data && j.data.disputes) || [];
    const dis = all.find((x) => x.id === id);
    if (!dis) { closeDrawer(); toast('Mgogoro haukuonekana', false); return; }
    const evs = (dis.evidence || []);
    openDrawer(
      '<h3>Mgogoro kwenye ' + esc((dis.order && dis.order.orderNumber) || id12(dis.orderId)) + '</h3>' +
      '<div class="dsub">' + badge(dis.status) + ' · ' + esc(disputeReason(dis.reason)) + '</div>' +
      '<dl class="kv">' +
      '<dt>Aliiweka</dt><dd>' + esc((dis.filer && (dis.filer.displayName || dis.filer.email)) || '—') + '</dd>' +
      '<dt>Maelezo</dt><dd>' + esc(dis.description || '—') + '</dd>' +
      '<dt>Kiasi kwenye escrow</dt><dd>' + fmtTZS((dis.order && dis.order.totalAmount) || 0) + '</dd>' +
      '<dt>Uamuzi</dt><dd>' + esc(dis.resolution || '—') + ' ' + (dis.resolvedAt ? '(' + fmtTime(dis.resolvedAt) + ')' : '') + '</dd>' +
      '</dl>' +
      (evs.length ? '<hr class="hr"><div class="dsub">Ushahidi (' + evs.length + ')</div>' + evs.map((e) =>
        '<div style="padding:8px 0;border-bottom:1px solid var(--border)"><b>' + esc(e.type) + '</b> · ' + fmtTime(e.createdAt) +
        (e.description ? '<div class="dim">' + esc(e.description) + '</div>' : '') +
        (e.r2Key && /^https?:\/\//.test(e.r2Key) ? '<div><a href="' + esc(e.r2Key) + '" target="_blank" rel="noopener" class="btn sm">Ona ushahidi</a></div>' : '') + '</div>').join('') : '')
    );
  } catch (e) { toast(e.message, false); }
}
async function disputeResolve(id, num, total) {
  openModal(
    '<h3>Suluhisha mgogoro: ' + esc(num) + '</h3>' +
    '<p class="msub">Kiasi cha escrow: ' + fmtTZS(total) + '. Kwa PARTIAL Jumla ya mnunuzi+muuzaji inapaswa kuwa sawa na escrow.</p>' +
    '<div class="radio-row" id="drRow">' +
    '<button class="radio-chip" data-v="FULL_REFUND">FULL_REFUND (mnunuzi anapata zote)</button>' +
    '<button class="radio-chip" data-v="FULL_TO_SELLER">FULL_TO_SELLER (muuzaji anapata zote)</button>' +
    '<button class="radio-chip" data-v="PARTIAL">PARTIAL</button></div>' +
    '<div id="drPart" hidden>' +
    '<label>Kiasi cha mnunuzi (TSh)</label><input class="field" id="drBuyer" type="number" min="0" value="0">' +
    '<label>Kiasi cha muuzaji (TSh)</label><input class="field" id="drSeller" type="number" min="0" value="0">' +
    '</div>' +
    '<div class="mfooter"><button class="btn" id="drNo">Futa</button><button class="btn accent" id="drYes">Tengeneza Uamuzi</button></div>'
  );
  let pick = 'FULL_REFUND';
  $('drRow').querySelectorAll('.radio-chip').forEach((c) => c.addEventListener('click', () => {
    $('drRow').querySelectorAll('.radio-chip').forEach((x) => x.classList.remove('on'));
    c.classList.add('on'); pick = c.dataset.v; $('drPart').hidden = pick !== 'PARTIAL';
  }));
  $('drNo').onclick = closeModal;
  $('drYes').onclick = () => run(async () => {
    const body = { resolution: pick };
    if (pick === 'PARTIAL') { body.buyerAmount = Math.round(Number($('drBuyer').value)); body.sellerAmount = Math.round(Number($('drSeller').value)); }
    await putJSON('/api/v1/disputes/' + id + '/resolve', body);
    closeModal(); toast('Uamuzi umetengenezwa', true); loadDisputes();
  });
}

// ---------------------------------------------------------------------------
// Marejesho
// ---------------------------------------------------------------------------
function refundsToolbar() {
  return '<div class="toolbar"><select class="select-xs" id="rStatus"><option value="">Hali: yote</option><option value="pending">pending</option><option value="processing">processing</option><option value="completed">completed</option><option value="failed">failed</option></select>' +
    '<button class="btn" id="rGo">Chuja</button></div>';
}
async function loadRefunds() {
  const el = secEl('refunds');
  const page = pgState('refunds', 'page') || 1;
  const st = pgState('refunds', 'st') || '';
  el.innerHTML = refundsToolbar() + '<div class="card"><div class="tablewrap"><table class="tbl"><thead><tr>' +
    '<th>Agizo</th><th>Kiasi</th><th>Njia</th><th>Sababu</th><th>Hali</th><th>Iliundwa</th><th style="text-align:right">Vitendo</th></tr></thead>' +
    '<tbody id="rRows"><tr><td colspan="7" class="empty"><div class="spinner" style="width:22px;height:22px;margin:0 auto 8px"></div>Inapakia…</td></tr></tbody></table></div>' +
    '<div id="rPag"></div></div>';
  const qs = new URLSearchParams({ page, limit: 20 });
  if (st) qs.set('status', st);
  try {
    const j = await getJSON('/api/v1/admin/refunds?' + qs.toString());
    const d = (j.data && j.data.refunds) || [];
    $('rRows').innerHTML = d.length ? d.map((rf) => {
      const args = JSON.stringify({ id: rf.id, num: (rf.order && rf.order.orderNumber) || rf.orderId }).replace(/'/g, '&#39;');
      return '<tr>' +
        '<td class="mono"><b>' + esc((rf.order && rf.order.orderNumber) || id12(rf.orderId)) + '</b></td>' +
        '<td class="num">' + fmtTZS(rf.amount) + '</td>' +
        '<td>' + badge(rf.mode) + '</td>' +
        '<td class="dim">' + esc((rf.reason || '').slice(0, 50)) + '</td>' +
        '<td>' + badge(rf.status) + '</td>' +
        '<td class="dim">' + fmtTime(rf.createdAt) + '</td>' +
        '<td class="rowactions">' +
        (rf.status === 'pending' || rf.status === 'failed' ? '<button class="btn sm accent" data-fn="refundProcess" data-args=\'' + args + '\'>Tengeneza</button>' : '<span class="dim">—</span>') +
        '</td></tr>';
    }).join('') : '<tr><td colspan="7" class="empty">Hakuna marejesho</td></tr>';
    $('rPag').innerHTML = pagerHTML('refunds', j.data.pagination);
  } catch (e) { $('rRows').innerHTML = '<tr><td colspan="7" class="empty">' + esc(e.message) + '</td></tr>'; }
  bindSection('refunds'); touch();
}
async function refundProcess(id, num) {
  const ok = await confirmModal('Tengeneza marejesho kwenda ' + num, 'Hii hutoa escrow na kuwasilisha kwa mnunuzi. Hakika?', 'Tengeneza', false);
  if (!ok) return;
  run(async () => {
    await putJSON('/api/v1/refunds/' + id + '/process');
    toast('Marejesho yanatengenezwa', true); loadRefunds();
  });
}

// ---------------------------------------------------------------------------
// Ripoti & Ulinzi (moderation)
// ---------------------------------------------------------------------------
function reportsToolbar() {
  return '<div class="toolbar"><select class="select-xs" id="rpStatus"><option value="">Hali: yote</option><option value="pending">pending</option><option value="reviewed">reviewed</option><option value="actioned">actioned</option><option value="dismissed">dismissed</option></select>' +
    '<select class="select-xs" id="rpType"><option value="">Aina: yote</option><option value="product">product</option><option value="user">user</option></select>' +
    '<button class="btn" id="rpGo">Chuja</button></div>';
}
async function loadReports() {
  const el = secEl('reports');
  const page = pgState('reports', 'page') || 1;
  const st = pgState('reports', 'st') || '';
  const ty = pgState('reports', 'ty') || '';
  el.innerHTML = reportsToolbar() + '<div class="card"><div class="tablewrap"><table class="tbl"><thead><tr>' +
    '<th>Aliyeripoti</th><th>Aina</th><th>Sababu</th><th>Hali</th><th>Iliundwa</th><th style="text-align:right">Vitendo</th></tr></thead>' +
    '<tbody id="rpRows"><tr><td colspan="6" class="empty"><div class="spinner" style="width:22px;height:22px;margin:0 auto 8px"></div>Inapakia…</td></tr></tbody></table></div>' +
    '<div id="rpPag"></div></div>';
  const qs = new URLSearchParams({ page, limit: 20 });
  if (st) qs.set('status', st); if (ty) qs.set('targetType', ty);
  try {
    const j = await getJSON('/api/v1/moderation?' + qs.toString());
    const d = (j.data && j.data.items) || [];
    $('rpRows').innerHTML = d.length ? d.map((rp) => {
      const args = JSON.stringify({ id: rp.id, status: rp.status }).replace(/'/g, '&#39;');
      return '<tr>' +
        '<td>' + esc((rp.reporter && (rp.reporter.email || rp.reporter.phone)) || id12(rp.reporterId)) + '</td>' +
        '<td>' + badge(rp.targetType) + ' <div class="dim mono">' + esc(id12(rp.targetId)) + '</div></td>' +
        '<td>' + esc(rp.reason) + '<div class="dim">' + esc((rp.description || '').slice(0, 50)) + '</div></td>' +
        '<td>' + badge(rp.status) + '</td>' +
        '<td class="dim">' + fmtTime(rp.createdAt) + '</td>' +
        '<td class="rowactions">' +
        (rp.status === 'pending' ? ['reviewed', 'actioned', 'dismissed'].map((s) =>
          '<button class="btn sm ' + (s === 'dismissed' ? 'danger' : (s === 'actioned' ? 'accent' : '')) + '" data-fn="reportReview" data-args=\'' + JSON.stringify({ id: rp.id, status: s }).replace(/'/g, '&#39;') + '\'>' + s + '</button>'
        ).join('') : '<span class="dim">imehakikiwa</span>') +
        '</td></tr>';
    }).join('') : '<tr><td colspan="6" class="empty">Hakuna ripoti</td></tr>';
    $('rpPag').innerHTML = pagerHTML('reports', j.data.pagination);
  } catch (e) { $('rpRows').innerHTML = '<tr><td colspan="6" class="empty">' + esc(e.message) + '</td></tr>'; }
  bindSection('reports'); touch();
}
async function reportReview(id, status) {
  run(async () => {
    await putJSON('/api/v1/moderation/' + id + '/review', { status });
    toast('Ripoti -> ' + status, true); loadReports();
  });
}

// ---------------------------------------------------------------------------
// Fedha: KPI + Ledger + Withdrawals + Rekodi
// ---------------------------------------------------------------------------
function financeTabs(active) {
  const tabs = { main: 'Fedha', ledger: 'Ledger', withdrawals: 'Withdrawals', recon: 'Rekodi (Reconciliation)' };
  return '<div class="toolbar" style="margin-bottom:14px">' + Object.keys(tabs).map((k) =>
    '<button class="radio-chip ' + (active === k ? 'on' : '') + '" data-ftab="' + k + '">' + tabs[k] + '</button>').join('') + '</div>';
}
async function loadFinance(focus) {
  const el = secEl('finance');
  const f = focus || pgState('finance', 'f') || 'main';
  setPg('finance', 'f', f);
  el.innerHTML = financeTabs(f) + '<div class="finBody"></div>';
  if (f === 'main') loadFinanceMain();
  else if (f === 'ledger') loadLedger();
  else if (f === 'withdrawals') loadWithdrawals();
  else loadRecon();
  el.querySelectorAll('[data-ftab]').forEach((b) => b.addEventListener('click', () => loadFinance(b.dataset.ftab)));
}
async function loadFinanceMain() {
  const body = secEl('finance').querySelector('.finBody');
  body.innerHTML = '<div class="sectionempty"><div class="spinner" style="margin:0 auto 12px"></div>Inapakia…</div>';
  try {
    const [dash, met] = await Promise.all([getJSON('/api/v1/admin/dashboard'), getJSON('/api/v1/admin/metrics')]);
    const k = (dash.data && dash.data.kpis) || {};
    const m = (met.data && met.data) || {};
    body.innerHTML =
      '<div class="grid kpis">' +
      kpi('Mapato ya Tume', fmtTZS(k.commissionRevenue), 'jumla', 'trending-up') +
      kpi('Escrow inashikiliwa', fmtTZS(k.escrowHeld), fmtNum((m.escrowHolding || {}).count || 0) + ' includes', 'lock') +
      kpi('GMV', fmtTZS(m.gmv), 'jumla ya mauzo', 'coins') +
      kpi('Withdrawals zinazosubiri', fmtNum(m.withdrawalsPending || 0), 'pending + processing', 'banknote') +
      '</div>' +
      '<div class="grid cols2" style="margin-top:18px">' +
      '<div class="card"><div class="cardhead"><h3>Maagizo (fedha)</h3></div>' +
      '<table class="tbl"><thead><tr><th>Hali</th><th>Hesabu</th><th>Jumla</th></tr></thead><tbody>' +
      (m.ordersByStatus || []).map((g) => '<tr><td>' + badge(g.status) + '</td><td>' + fmtNum(g.count) + '</td><td class="num">' + fmtTZS(g.totalAmount) + '</td></tr>').join('') +
      '</tbody></table></div>' +
      '<div class="card"><div class="cardhead"><h3>Malipo</h3></div>' +
      '<table class="tbl"><thead><tr><th>Hali</th><th>Hesabu</th><th>Jumla</th></tr></thead><tbody>' +
      (m.paymentsByStatus || []).map((g) => '<tr><td>' + badge(g.status) + '</td><td>' + fmtNum(g.count) + '</td><td class="num">' + fmtTZS(g.totalAmount) + '</td></tr>').join('') +
      '</tbody></table></div></div>';
  } catch (e) { body.innerHTML = '<div class="card"><div class="err">' + esc(e.message) + '</div></div>'; }
  touch(); icons();
}
async function loadLedger() {
  const body = secEl('finance').querySelector('.finBody');
  const page = pgState('finance', 'page') || 1;
  body.innerHTML = '<div class="card"><div class="tablewrap"><table class="tbl"><thead><tr>' +
    '<th>Wakati</th><th>Duka</th><th>Aina</th><th>Kiasi</th><th>Salio baada</th><th>Rejea</th></tr></thead>' +
    '<tbody id="lgRows"><tr><td colspan="6" class="empty"><div class="spinner" style="width:22px;height:22px;margin:0 auto 8px"></div></td></tr></tbody></table></div><div id="lgPag"></div></div>';
  try {
    const j = await getJSON('/api/v1/admin/ledger?page=' + page + '&limit=30');
    const d = (j.data && j.data.entries) || [];
    $('lgRows').innerHTML = d.length ? d.map((e) => '<tr>' +
      '<td class="dim">' + fmtTime(e.createdAt) + '</td>' +
      '<td>' + esc((e.wallet && e.wallet.seller && e.wallet.seller.storeName) || '—') + '</td>' +
      '<td>' + badge(e.type) + '</td>' +
      '<td class="num">' + (Number(e.amount) < 0 ? '-' : '+') + fmtTZS(Math.abs(e.amount)) + '</td>' +
      '<td class="num">' + fmtTZS(e.balanceAfter) + '</td>' +
      '<td class="dim mono">' + esc(e.referenceType || '') + ' ' + esc(id12(e.referenceId)) + '</td></tr>').join('')
      : '<tr><td colspan="6" class="empty">Hakuna ledgers</td></tr>';
    $('lgPag').innerHTML = pagerHTML('finance', j.data.pagination);
  } catch (e) { $('lgRows').innerHTML = '<tr><td colspan="6" class="empty">' + esc(e.message) + '</td></tr>'; }
  bindSection('finance'); touch();
}
function withdrawalsToolbar() {
  return '<div class="toolbar">' +
    '<select class="select-xs" id="wStatus"><option value="">Hali: yote</option><option value="pending">pending</option><option value="processing">processing</option><option value="completed">completed</option><option value="failed">failed</option><option value="cancelled">cancelled</option></select>' +
    '<button class="btn" id="wGo">Chuja</button></div>';
}
async function loadWithdrawals() {
  const body = secEl('finance').querySelector('.finBody');
  const page = pgState('finance', 'page') || 1;
  const st = pgState('finance', 'wst') || '';
  body.innerHTML = '<div class="card">' + withdrawalsToolbar() + '<div class="tablewrap"><table class="tbl"><thead><tr>' +
    '<th>Duka</th><th>Kiasi</th><th>Hali</th><th>Payout ID</th><th>Iliundwa</th><th style="text-align:right">Vitendo</th></tr></thead>' +
    '<tbody id="wRows"><tr><td colspan="6" class="empty"><div class="spinner" style="width:22px;height:22px;margin:0 auto 8px"></div></td></tr></tbody></table></div><div id="wPag"></div></div>';
  const qs = new URLSearchParams({ page, limit: 20 });
  if (st) qs.set('status', st);
  try {
    const j = await getJSON('/api/v1/admin/withdrawals?' + qs.toString());
    const d = (j.data && j.data.withdrawals) || [];
    $('wRows').innerHTML = d.length ? d.map((w) => {
      const args = JSON.stringify({ id: w.id }).replace(/'/g, '&#39;');
      return '<tr>' +
        '<td>' + esc((w.seller && w.seller.storeName) || '—') + '</td>' +
        '<td class="num">' + fmtTZS(w.amount) + '</td>' +
        '<td>' + badge(w.status) + '</td>' +
        '<td class="dim mono">' + esc(id12(w.providerPayoutId)) + '</td>' +
        '<td class="dim">' + fmtTime(w.createdAt) + '</td>' +
        '<td class="rowactions">' +
        (w.status === 'pending' ? '<button class="btn sm accent" data-fn="withdrawalProcess" data-args=\'' + args + '\'>Tuma Payout</button>' : '') +
        ((w.status === 'failed') ? '<button class="btn sm" data-fn="withdrawalRetry" data-args=\'' + args + '\'>Jaribu tena</button>' : '') +
        (w.status === 'processing' ? '<button class="btn sm accent" data-fn="withdrawalConfirm" data-args=\'' + args + '\'>Thibitisha</button>' : '') +
        '</td></tr>';
    }).join('') : '<tr><td colspan="6" class="empty">Hakuna withdrawals</td></tr>';
    $('wPag').innerHTML = pagerHTML('finance', j.data.pagination);
  } catch (e) { $('wRows').innerHTML = '<tr><td colspan="6" class="empty">' + esc(e.message) + '</td></tr>'; }
  bindSection('finance'); touch();
}
async function withdrawalOp(id, op) {
  const map = { process: 'Tuma payout ya TSh kwenda ClickPesa?', retry: 'Jaribu tena payout iliyoshindikana?', confirm: 'Thibitisha payout imekamilika (inahitajika kama provider hairudishi callback)?' };
  const ok = await confirmModal('Withdrawal: ' + op, map[op] || 'Hakika?', op === 'retry' ? 'Jaribu tena' : 'Ndiyo', false);
  if (!ok) return;
  run(async () => {
    if (op === 'confirm') {
      const j = await postJSON('/api/v1/admin/withdrawals/' + id + '/confirm', {});
      toast('Imethibitishwa: ' + ((j.data && (j.data.status || j.data.providerPayoutId)) || 'ok'), true);
    } else {
      await postJSON('/api/v1/admin/withdrawals/' + id + '/' + op, {});
      toast('Operation imetumwa -> ' + op, true);
    }
    loadFinance('withdrawals');
  });
}
function fnReconList(runs) {
  return (runs || []).map((r) => '<tr>' +
    '<td>' + fmtTime(r.createdAt) + '</td><td>' + esc(r.provider || '—') + '</td>' +
    '<td class="num">' + fmtTZS(r.internalTotal) + '</td><td class="num">' + fmtTZS(r.providerTotal) + '</td>' +
    '<td class="num">' + fmtTZS(r.difference) + '</td><td>' + badge(r.status) + '</td></tr>').join('');
}
async function loadRecon() {
  const body = secEl('finance').querySelector('.finBody');
  body.innerHTML = '<div class="card"><div class="cardhead"><h3>Rekodi (Reconciliation)</h3><div class="spacer"></div>' +
    '<button class="btn sm accent" id="rcRun">Tengeneza Rekodi Mpya</button></div>' +
    '<div class="tablewrap"><table class="tbl"><thead><tr><th>Wakati</th><th>Provider</th><th>Ndani</th><th>Kwa upande wa provider</th><th>Tofauti</th><th>Hali</th></tr></thead>' +
    '<tbody id="rcRows"><tr><td colspan="6" class="empty">Inapakia…</td></tr></tbody></table></div><div id="rcPag"></div></div>';
  try {
    const j = await getJSON('/api/v1/reconciliation?page=1&limit=20');
    const runs = (j.data && (j.data.runs || j.data.items || j.data.rows || j.data)) || [];
    const list = Array.isArray(runs) ? runs : [];
    $('rcRows').innerHTML = list.length ? fnReconList(list) : '<tr><td colspan="6" class="empty">Hakuna rekodi</td></tr>';
  } catch (e) { $('rcRows').innerHTML = '<tr><td colspan="6" class="empty">' + esc(e.message) + '</td></tr>'; }
  $('rcRun').addEventListener('click', () => ACTIONS.reconciliationRun());
  touch();
}
async function reconciliationRun() {
  openModal(
    '<h3>Tengeneza Rekodi</h3><p class="msub">Linganisha malipo na provider kwa kipindi.</p>' +
    '<label>Provider</label><select class="field" id="rcProvider"><option value="clickpesa">clickpesa</option></select>' +
    '<div class="formgrid"><div><label>Kuanzia</label><input class="field" id="rcStart" type="datetime-local"></div>' +
    '<div><label>Hadi</label><input class="field" id="rcEnd" type="datetime-local"></div></div>' +
    '<div class="mfooter"><button class="btn" id="rcNo">Futa</button><button class="btn accent" id="rcYes">Run</button></div>'
  );
  $('rcNo').onclick = closeModal;
  $('rcYes').onclick = () => run(async () => {
    const start = new Date($('rcStart').value || Date.now() - 30 * 864e5);
    const end = new Date($('rcEnd').value || Date.now());
    await postJSON('/api/v1/reconciliation/run', { provider: $('rcProvider').value, periodStart: start.toISOString(), periodEnd: end.toISOString() });
    closeModal(); toast('Rekodi imeanzishwa', true); loadFinance('recon');
  });
}

// ---------------------------------------------------------------------------
// Rufaa
// ---------------------------------------------------------------------------
function referralsToolbar() {
  return '<div class="toolbar"><select class="select-xs" id="rfStatus"><option value="">Hali: yote</option><option value="pending">pending</option><option value="completed">completed</option></select>' +
    '<button class="btn" id="rfGo">Chuja</button></div>';
}
async function loadReferrals() {
  const el = secEl('referrals');
  const page = pgState('referrals', 'page') || 1;
  const st = pgState('referrals', 'st') || '';
  el.innerHTML = referralsToolbar() + '<div class="card"><div class="tablewrap"><table class="tbl"><thead><tr>' +
    '<th>Aliyerufuku</th><th>Aliyesajiliwa</th><th>Code</th><th>Hali</th><th>Reward</th><th>Iliundwa</th><th style="text-align:right">Vitendo</th></tr></thead>' +
    '<tbody id="rfRows"><tr><td colspan="7" class="empty"><div class="spinner" style="width:22px;height:22px;margin:0 auto 8px"></div>Inapakia…</td></tr></tbody></table></div>' +
    '<div id="rfPag"></div></div>';
  const qs = new URLSearchParams({ page, limit: 20 });
  if (st) qs.set('status', st);
  try {
    const j = await getJSON('/api/v1/admin/referrals?' + qs.toString());
    const d = (j.data && j.data.referrals) || [];
    $('rfRows').innerHTML = d.length ? d.map((rf) => {
      const args = JSON.stringify({ id: rf.id }).replace(/'/g, '&#39;');
      return '<tr>' +
        '<td>' + esc((rf.referrer && (rf.referrer.displayName || rf.referrer.email)) || '—') + '</td>' +
        '<td>' + esc((rf.referred && (rf.referred.displayName || rf.referred.email)) || '—') + '</td>' +
        '<td class="mono">' + esc(rf.code || '—') + '</td>' +
        '<td>' + badge(rf.status) + '</td>' +
        '<td>' + esc(rf.rewardType || '—') + ' <span class="num">' + fmtTZS(rf.rewardAmount) + '</span></td>' +
        '<td class="dim">' + fmtTime(rf.createdAt) + '</td>' +
        '<td class="rowactions">' +
        (rf.status !== 'completed' ? '<button class="btn sm accent" data-fn="referralComplete" data-args=\'' + args + '\'>Kamilisha</button>' : '<span class="dim">—</span>') +
        '</td></tr>';
    }).join('') : '<tr><td colspan="7" class="empty">Hakuna rufaa</td></tr>';
    $('rfPag').innerHTML = pagerHTML('referrals', j.data.pagination);
  } catch (e) { $('rfRows').innerHTML = '<tr><td colspan="7" class="empty">' + esc(e.message) + '</td></tr>'; }
  bindSection('referrals'); touch();
}
async function referralComplete(id) {
  openModal(
    '<h3>Kamilisha rufaa</h3><p class="msub">Toa zawadi kwa mwanzilishi</p>' +
    '<label>Aina ya zawadi</label><select class="field" id="rCType"><option value="voucher">voucher</option><option value="boost_credit">boost_credit</option><option value="visibility_credit">visibility_credit</option></select>' +
    '<label>Kiasi (TSh)</label><input class="field" id="rCAmt" type="number" min="0" value="0">' +
    '<label>Kitendo cha kuhitimu</label><input class="field" id="rCAct" placeholder="k.m. first_order">' +
    '<div class="mfooter"><button class="btn" id="rcN">Futa</button><button class="btn accent" id="rcY">Toa</button></div>'
  );
  $('rcN').onclick = closeModal;
  $('rcY').onclick = () => run(async () => {
    await postJSON('/api/v1/referrals/' + id + '/complete', {
      rewardType: $('rCType').value,
      rewardAmount: Math.round(Number($('rCAmt').value) || 0),
      qualifyingAction: $('rCAct').value || 'manual',
    });
    closeModal(); toast('Rufaa imekamilishwa', true); loadReferrals();
  });
}

// ---------------------------------------------------------------------------
// Matangazo ya Broad
// ---------------------------------------------------------------------------
async function loadBroadcasts() {
  const el = secEl('broadcasts');
  el.innerHTML =
    '<div class="card" style="max-width:720px">' +
    '<div class="cardhead"><h3>Tuma matangazo kwa watumiaji wote</h3></div>' +
    '<p class="intro">Ujumbe huu utapelekwa kwa watumiaji wote waliosajiliwa kwa push (OneSignal) na ndani ya app. Tumia kwa matangazo ya dharura au tangazo.</p>' +
    '<label>Kichwa</label><input class="field" id="bcTitle" placeholder="K.m. Tamasha la Soko Vibe">' +
    '<label>Maandishi</label><textarea class="field" id="bcBody" placeholder="Ujumbe mfupi…"></textarea>' +
    '<div style="display:flex;gap:10px;justify-content:flex-end;margin-top:10px">' +
    '<button class="btn accent" id="bcSend">Tuma kwa wote</button></div>' +
    '<div id="bcOut" style="margin-top:14px"></div></div>';
  $('bcSend').onclick = () => run(async () => {
    const title = $('bcTitle').value.trim();
    if (!title) { toast('Andika kichwa', false); return; }
    const j = await postJSON('/api/admin/broadcast-notification', { title, body: $('bcBody').value });
    $('bcOut').innerHTML = '<div class="bdg ok" style="margin-top:6px">Imetumwa kwa <b>&nbsp;' + fmtNum((j && j.totalUsers) || 0) + '&nbsp;</b> watumiaji · push ' + fmtNum((j && j.pushNotifications) || 0) + ' · in-app ' + fmtNum((j && j.inAppNotifications) || 0) + '</div>';
    toast('Matangazo yametumwa', true);
  });
  touch();
}

// ---------------------------------------------------------------------------
// Landing / Orodha (coming-soon submissions + waitlist email broadcast)
// ---------------------------------------------------------------------------
function landingRows(items, cols) {
  return items.map((it) => '<tr>' + cols.map((c) => c(it)).join('') + '</tr>').join('');
}
function landingLang(it) { return esc(String(it.lang || it.locale || '')); }
function landingWhen(it) { return '<td class="dim">' + fmtTime(tsToISO(it.createdAt)) + '</td>'; }
async function loadLanding() {
  const el = secEl('landing');
  el.innerHTML =
    '<div class="grid kpis" style="margin-bottom:14px">' +
    '<div class="kpi"><span class="lab">Waliopokea taarifa</span><span class="val" id="ldK1">…</span><span class="sub">barua pepe zilizokusanywa</span></div>' +
    '<div class="kpi"><span class="lab">Maoni ya vipengele</span><span class="val" id="ldK2">…</span><span class="sub">feature wishes</span></div>' +
    '<div class="kpi"><span class="lab">Maoni ya jamii</span><span class="val" id="ldK3">…</span><span class="sub">comments za wageni</span></div>' +
    '</div>' +
    '<div class="card" style="max-width:760px">' +
    '<div class="cardhead"><h3>Tuma barua pepe kwa waliopokea taarifa</h3></div>' +
    '<p class="intro">Tumia hii ukamilishe app. Ujumbe unaenda kwa barua pepe zote zilizojisajili kwenye ukurasa wa "App ipo kwenye maendeleo".</p>' +
    '<label>Kichwa (subject)</label><input class="field" id="ldSubject" placeholder="K.m. Soko Vibe ipo tayari!">' +
    '<label>Maandishi (body)</label><textarea class="field" id="ldBody" rows="3" placeholder="Hujambo…"></textarea>' +
    '<div style="display:flex;gap:10px;justify-content:flex-end;margin-top:10px">' +
    '<button class="btn accent" id="ldSend">Tuma kwa wote</button></div>' +
    '<div id="ldOut" style="margin-top:14px"></div></div>' +
    '<div class="card"><div class="cardhead"><h3>Waliopokea taarifa (barua pepe)</h3></div>' +
    '<div class="tablewrap"><table class="tbl"><thead><tr><th>Barua pepe</th><th>Jina</th><th>Lugha</th><th>Wakati</th></tr></thead>' +
    '<tbody id="ldWL"><tr><td colspan="4" class="empty"><div class="spinner" style="width:22px;height:22px;margin:0 auto 8px"></div>Inapakia…</td></tr></tbody></table></div></div>' +
    '<div class="card"><div class="cardhead"><h3>Maoni ya vipengele</h3></div>' +
    '<div class="tablewrap"><table class="tbl"><thead><tr><th>Vipengele</th><th>Maelezo</th><th>Jina</th><th>Wakati</th></tr></thead>' +
    '<tbody id="ldSUG"><tr><td colspan="4" class="empty">…</td></tr></tbody></table></div></div>' +
    '<div class="card"><div class="cardhead"><h3>Maoni ya jamii</h3></div>' +
    '<div class="tablewrap"><table class="tbl"><thead><tr><th>Jina</th><th>Maoni</th><th>Lugha</th><th>Wakati</th></tr></thead>' +
    '<tbody id="ldCM"><tr><td colspan="4" class="empty">…</td></tr></tbody></table></div></div>';
  $('ldSend').onclick = () => run(async () => {
    const subject = $('ldSubject').value.trim();
    if (!subject) { toast('Andika subject', false); return; }
    $('ldSend').disabled = true;
    try {
      const j = await postJSON('/api/v1/admin/landing/broadcast', { subject, body: $('ldBody').value });
      const d = (j && j.data) || {};
      const ok = Number(d.sent) > 0;
      $('ldOut').innerHTML = '<div class="bdg ' + (Number(d.failed) ? 'warn' : 'ok') + '">Imemalizika — jumla ' + fmtNum(d.total || 0) +
        ' · tuma ' + fmtNum(d.sent || 0) + ' · haikufaulu ' + fmtNum(d.failed || 0) + '</div>';
      toast((ok ? 'Barua pepe zimetumwa' : 'Hakuna barua zilizotumwa'), ok);
    } finally { $('ldSend').disabled = false; }
  });
  try {
    const j = await getJSON('/api/v1/admin/landing');
    const d = (j && j.data) || {};
    const wl = (d.waitlist && d.waitlist.items) || [];
    const sg = (d.suggestions && d.suggestions.items) || [];
    const cm = (d.comments && d.comments.items) || [];
    $('ldK1').textContent = fmtNum((d.waitlist && d.waitlist.total) || wl.length);
    $('ldK2').textContent = fmtNum((d.suggestions && d.suggestions.total) || sg.length);
    $('ldK3').textContent = fmtNum((d.comments && d.comments.total) || cm.length);
    $('ldWL').innerHTML = landingRows(wl, [
      (it) => '<td class="mono">' + esc(it.email) + '</td>',
      (it) => '<td>' + esc(it.name || '—') + '</td>',
      (it) => '<td>' + landingLang(it) + '</td>',
      landingWhen,
    ]) || '<tr><td colspan="4" class="empty">Hakuna waliojisajili</td></tr>';
    $('ldSUG').innerHTML = landingRows(sg, [
      (it) => '<td>' + ((it.features || []).map((f) => '<span class="bdg info"><span class="dot"></span>' + esc(f) + '</span>').join(' ') || '<span class="dim">—</span>') + '</td>',
      (it) => '<td>' + esc(it.details || it.suggestion || '') + '</td>',
      (it) => '<td>' + esc(it.name || '—') + '</td>',
      landingWhen,
    ]) || '<tr><td colspan="4" class="empty">Hakuna maoni ya vipengele</td></tr>';
    $('ldCM').innerHTML = landingRows(cm, [
      (it) => '<td>' + esc(it.name || it.email || '—') + '</td>',
      (it) => '<td>' + esc(it.text || it.comment || '') + '</td>',
      (it) => '<td>' + landingLang(it) + '</td>',
      landingWhen,
    ]) || '<tr><td colspan="4" class="empty">Hakuna maoni ya jamii</td></tr>';
  } catch (e) {
    $('ldWL').innerHTML = '<tr><td colspan="4" class="empty">' + esc(e.message) + '</td></tr>';
    $('ldSUG').innerHTML = '<tr><td colspan="4" class="empty">' + esc(e.message) + '</td></tr>';
    $('ldCM').innerHTML = '<tr><td colspan="4" class="empty">' + esc(e.message) + '</td></tr>';
  }
  bindSection('landing'); touch();
}

// ---------------------------------------------------------------------------
// Ukaguzi
// ---------------------------------------------------------------------------
function auditToolbar() {
  return '<div class="toolbar">' +
    '<input class="field q" id="aQ" placeholder="Tafuta action / entity…">' +
    '<button class="btn" id="aGo">Chuja</button></div>';
}
async function loadAudit() {
  const el = secEl('audit');
  const page = pgState('audit', 'page') || 1;
  const q = pgState('audit', 'q') || '';
  el.innerHTML = auditToolbar() + '<div class="card"><div class="tablewrap"><table class="tbl"><thead><tr>' +
    '<th>Wakati</th><th>Mtendaji</th><th>Kitendo</th><th>Kiunzi</th><th>Entity</th><th>IP</th></tr></thead>' +
    '<tbody id="aRows"><tr><td colspan="6" class="empty"><div class="spinner" style="width:22px;height:22px;margin:0 auto 8px"></div>Inapakia…</td></tr></tbody></table></div>' +
    '<div id="aPag"></div></div>';
  const qs = new URLSearchParams({ page, limit: 30 });
  if (q) qs.set('action', q);
  try {
    const j = await getJSON('/api/v1/admin/audit-logs?' + qs.toString());
    const d = (j.data && j.data.entries) || [];
    $('aRows').innerHTML = d.length ? d.map((a) => '<tr>' +
      '<td class="dim">' + fmtTime(a.createdAt) + '</td>' +
      '<td class="mono">' + esc(id12(a.actorId)) + ' <span class="dim">' + esc(a.actorType || '') + '</span></td>' +
      '<td><b>' + esc(a.action) + '</b>' + (a.newState ? '<div class="dim">' + esc(JSON.stringify(a.newState).slice(0, 60)) + '</div>' : '') + '</td>' +
      '<td>' + badge(a.entityType) + '</td>' +
      '<td class="mono dim">' + esc(id12(a.entityId)) + '</td>' +
      '<td class="dim mono">' + esc(String(a.ipAddress || '')) + '</td></tr>').join('')
      : '<tr><td colspan="6" class="empty">Hakuna ukaguzi</td></tr>';
    $('aPag').innerHTML = pagerHTML('audit', j.data.pagination);
  } catch (e) { $('aRows').innerHTML = '<tr><td colspan="6" class="empty">' + esc(e.message) + '</td></tr>'; }
  bindSection('audit'); touch();
}

// ---------------------------------------------------------------------------
// ---------------------------------------------------------------------------
// Takwimu za matumizi: watumiaji hai (siku/wiki/mwezi/mwaka), requests kwa
// kipindi, na orodha ya watumiaji wanaofanya requests nyingi zaidi.
// ---------------------------------------------------------------------------
const RG_LABEL = { min: 'Dakika', hour: 'Saa', day: 'Siku', month: 'Mwezi', year: 'Mwaka' };
const TD_LABEL = { 1: 'Leo', 7: 'Siku 7', 30: 'Siku 30' };
function pctOf(part, total) {
  part = Number(part) || 0; total = Number(total) || 0;
  if (!total) return '—';
  return (Math.round((part / total) * 1000) / 10) + '% ya jumla';
}
async function loadStats() {
  const el = secEl('stats');
  const rg = pgState('stats', 'rg') || 'day';
  const tdays = pgState('stats', 'tdays') || 7;
  el.innerHTML = '<div class="sectionempty"><div class="spinner" style="margin:0 auto 12px"></div>Inapakia takwimu…</div>';
  try {
    const [act, req, top] = await Promise.all([
      getJSON('/api/v1/admin/analytics/active'),
      getJSON('/api/v1/admin/analytics/requests?granularity=' + rg).catch(() => null),
      getJSON('/api/v1/admin/analytics/users/top?days=' + tdays + '&limit=20').catch(() => null),
    ]);
    const a = (act && act.data) || {};
    const r = (req && req.data) || {};
    const t = (top && top.data) || {};
    const users = t.users || [];
    const series14 = a.series14 || [];

    el.innerHTML =
      '<div class="ov-head"><div><h2>Watumiaji hai</h2><p class="dim">Kulingana na muda wa mwisho kuingia (rolling windows)</p></div></div>' +
      '<div class="grid kpis">' +
      kpi('Hai leo (24h)', fmtNum(a.day), pctOf(a.day, a.totalUsers), 'zap') +
      kpi('Hai wiki (7d)', fmtNum(a.week), pctOf(a.week, a.totalUsers), 'calendar') +
      kpi('Hai mwezi (30d)', fmtNum(a.month), pctOf(a.month, a.totalUsers), 'calendar-days') +
      kpi('Hai mwaka (365d)', fmtNum(a.year), pctOf(a.year, a.totalUsers), 'globe') +
      '</div>' +

      '<div class="grid cols2" style="margin-top:18px">' +
      '<div class="card"><div class="cardhead"><h3>Watumiaji hai kila siku (siku 14)</h3></div><div class="chartbox"><canvas id="stActChart"></canvas></div></div>' +
      '<div class="card"><div class="cardhead"><h3>Requests kwa ' + esc((RG_LABEL[rg] || rg).toLowerCase()) + '</h3><div class="spacer"></div><span class="hint3">jumla ' + fmtNum(r.spanTotal) + ' · wastani ' + esc(String(r.perUserAvg == null ? '—' : r.perUserAvg)) + ' / mtumiaji</span></div>' +
      '<div class="toolbar" style="margin-bottom:10px">' + Object.keys(RG_LABEL).map((g) =>
        '<button class="radio-chip' + (g === rg ? ' on' : '') + '" data-rg="' + g + '">' + RG_LABEL[g] + '</button>').join('') + '</div>' +
      '<div class="chartbox"><canvas id="stReqChart"></canvas></div>' +
      (r.tracked === false ? '<p class="hint">Bado hakuna data ya requests — inakusanywa kuanzia sasa, itaonekana baada ya muda mfupi.</p>' : '') +
      '</div></div>' +

      '<div class="card" style="margin-top:18px"><div class="cardhead"><h3>Watumiaji wanaofanya requests nyingi</h3><div class="spacer"></div><span class="hint3">kila mtumiaji anafanya requests ngapi</span></div>' +
      '<div class="toolbar" style="margin-bottom:10px">' + Object.keys(TD_LABEL).map((d) =>
        '<button class="radio-chip' + (Number(d) === Number(tdays) ? ' on' : '') + '" data-td="' + d + '">' + TD_LABEL[d] + '</button>').join('') + '</div>' +
      '<div class="tablewrap"><table class="tbl"><thead><tr><th>#</th><th>Mtumiaji</th><th>Jukumu</th><th style="text-align:right">Requests</th><th style="text-align:right">Wastani / siku</th><th>Alionekana</th></tr></thead><tbody>' +
      (users.length ? users.map((u) => '<tr>' +
        '<td class="dim">' + u.rank + '</td>' +
        '<td><b>' + esc(u.displayName || u.email || u.phone || id12(u.userId)) + '</b>' + (u.email ? '<div class="dim">' + esc(u.email) + '</div>' : '') + '</td>' +
        '<td>' + (u.role ? badge(u.role) : '—') + '</td>' +
        '<td class="num">' + fmtNum(u.requests) + '</td>' +
        '<td class="num">' + esc(String(u.avgPerDay)) + '</td>' +
        '<td class="dim">' + fmtTime(u.lastLoginAt) + '</td></tr>').join('')
        : '<tr><td colspan="6" class="empty">' + ((t.tracked === false) ? 'Bado hakuna data — inakusanywa kuanzia sasa.' : 'Hakuna data kwa kipindi hiki') + '</td></tr>') +
      '</tbody></table></div></div>';
    el.querySelectorAll('[data-rg]').forEach((b) => b.addEventListener('click', () => { setPg('stats', 'rg', b.dataset.rg); loadStats(); }));
    el.querySelectorAll('[data-td]').forEach((b) => b.addEventListener('click', () => { setPg('stats', 'tdays', Number(b.dataset.td)); loadStats(); }));

    destroyCharts();
    if (window.Chart && series14.length) {
      charts.stAct = new Chart($('stActChart'), {
        type: 'bar',
        data: {
          labels: series14.map((s) => String(s.date || '').slice(5)),
          datasets: [{ label: 'Watumiaji hai', data: series14.map((s) => s.users), backgroundColor: 'rgba(47,158,95,.55)', borderRadius: 4 }],
        },
        options: {
          responsive: true, maintainAspectRatio: false,
          scales: { y: Object.assign({ beginAtZero: true, ticks: Object.assign({ precision: 0 }, chartBase().ticks) }, { grid: chartBase().grid }), x: Object.assign({}, { grid: { display: false }, ticks: chartBase().ticks }) },
          plugins: { legend: { display: false } },
        },
      });
    }
    const pts = r.points || [];
    if (window.Chart && pts.length) {
      charts.stReq = new Chart($('stReqChart'), {
        type: 'line',
        data: {
          labels: pts.map((p) => p.t),
          datasets: [{ label: 'Requests', data: pts.map((p) => p.total), borderColor: '#2563eb', backgroundColor: 'rgba(37,99,235,.12)', fill: true, tension: .3, pointRadius: 0 }],
        },
        options: {
          responsive: true, maintainAspectRatio: false, interaction: { mode: 'index', intersect: false },
          scales: { y: Object.assign({ beginAtZero: true, ticks: Object.assign({ precision: 0 }, chartBase().ticks) }, { grid: chartBase().grid }), x: { grid: { display: false }, ticks: chartBase().ticks } },
          plugins: { legend: { display: false } },
        },
      });
    }
  } catch (e) {
    el.innerHTML = '<div class="card"><div class="cardhead"><h3>Takwimu</h3></div><div class="err">' + esc(e.message) + '</div></div>';
  }
  touch(); icons();
}

// ---------------------------------------------------------------------------
// Promos: Boost & Flash Sale analytics
// ---------------------------------------------------------------------------
function promoTabs(active) {
  const tabs = { boosts: 'Boosts (Mapandikizo)', flash: 'Flash Sales' };
  return '<div class="toolbar" style="margin-bottom:14px">' + Object.keys(tabs).map((k) =>
    '<button class="radio-chip ' + (active === k ? 'on' : '') + '" data-ptab="' + k + '">' + tabs[k] + '</button>').join('') + '</div>';
}
async function loadPromos(focus) {
  const el = secEl('promos');
  const f = focus || pgState('promos', 'f') || 'boosts';
  setPg('promos', 'f', f);
  el.innerHTML = promoTabs(f) + '<div class="finBody"></div>';
  loadPromoPane(f);
  el.querySelectorAll('[data-ptab]').forEach((b) => b.addEventListener('click', () => loadPromos(b.dataset.ptab)));
}
async function loadPromoPane(f) {
  const body = secEl('promos').querySelector('.finBody');
  body.innerHTML = '<div class="sectionempty"><div class="spinner" style="margin:0 auto 12px"></div>Inapakia…</div>';
  try {
    if (f === 'boosts') {
      const j = await getJSON('/api/admin/analytics/boosts');
      const act = j.active || [];
      const hist = j.history || [];
      const rev = hist.reduce((s, h) => s + (Number(h.commission) || 0), 0);
      body.innerHTML =
        '<div class="grid kpis">' +
        kpi('Boosts zinazoendesha', fmtNum(act.length), 'sasa hivi', 'megaphone') +
        kpi('Mapato ya Boost', fmtTZS(rev), 'tume zilizolipwa', 'coins') +
        kpi('Historia (manunuzi)', fmtNum(hist.length), 'miamala yote', 'history') +
        '</div>' +
        '<div class="card" style="margin-top:16px"><div class="cardhead"><h3>Boosts zinazoendesha sasa</h3></div>' +
        '<div class="tablewrap"><table class="tbl"><thead><tr><th>Bidhaa</th><th>Muuzaji</th><th>Daraja</th><th>Bei</th><th>Inaisha</th></tr></thead><tbody>' +
        (act.length ? act.map((a) => '<tr><td>' + (a.image ? '<img class="thumb" style="width:30px;height:30px" src="' + esc(a.image) + '" alt="">' : '') + ' ' + esc(a.title) + '</td>' +
          '<td>' + esc(a.sellerName || a.sellerId || '—') + '</td><td>' + badge(a.tier) + '</td><td class="num">' + fmtTZS(a.price) + '</td><td class="dim">' + fmtTime(a.boostedUntil) + '</td></tr>').join('')
          : '<tr><td colspan="5" class="empty">Hakuna boosts zinazoendesha</td></tr>') +
        '</tbody></table></div></div>' +
        '<div class="card" style="margin-top:12px"><div class="cardhead"><h3>Historia ya manunuzi ya Boost</h3></div>' +
        '<div class="tablewrap"><table class="tbl"><thead><tr><th>Wakati</th><th>Muuzaji</th><th>Daraja</th><th>Kiasi</th><th>Tume ya jukwaa</th></tr></thead><tbody>' +
        (hist.length ? hist.map((h) => '<tr><td class="dim">' + fmtTime(h.timestamp) + '</td><td>' + esc(h.sellerName || h.sellerId || '—') + '</td><td>' + badge(h.tier) + '</td><td class="num">' + fmtTZS(h.amount) + '</td><td class="num">' + fmtTZS(h.commission) + '</td></tr>').join('')
          : '<tr><td colspan="5" class="empty">Hakuna historia bado</td></tr>') +
        '</tbody></table></div></div>';
    } else {
      const j = await getJSON('/api/admin/analytics/flash-sales');
      const fs = j.flashSales || [];
      const c = j.counts || {};
      body.innerHTML =
        '<div class="grid kpis">' +
        kpi('Zinazoendesha', fmtNum(c.active || 0), 'flash sales sasa', 'zap') +
        kpi('Zimeratibiwa', fmtNum(c.scheduled || 0), 'hazijaanza', 'calendar-clock') +
        kpi('Zimekwisha', fmtNum((c.ended || 0) + (c.disabled || 0)), 'zamani/fungwa', 'check') +
        '</div>' +
        '<div class="card" style="margin-top:16px"><div class="tablewrap"><table class="tbl"><thead><tr>' +
        '<th>Bidhaa</th><th>Muuzaji</th><th>Punguzo</th><th>Bei (Asili → Sale)</th><th>Kuanza</th><th>Inaisha</th><th>Stock/Umauzo</th><th>Hali</th></tr></thead><tbody>' +
        (fs.length ? fs.map((x) => '<tr>' +
          '<td>' + (x.productImage ? '<img class="thumb" style="width:30px;height:30px" src="' + esc(x.productImage) + '" alt="">' : '') + ' ' + esc(x.productName || id12(x.productId)) + '</td>' +
          '<td>' + esc(x.sellerName || '—') + '<div class="dim">' + esc(x.location || '') + '</div></td>' +
          '<td class="num">' + (x.discountPercent || 0) + '%</td>' +
          '<td class="num">' + fmtTZS(x.originalPrice) + ' → ' + fmtTZS(x.salePrice) + '</td>' +
          '<td class="dim">' + fmtDay(x.startTime) + '</td><td class="dim">' + fmtDay(x.endTime) + '</td>' +
          '<td class="num">' + fmtNum(x.stock) + '/' + fmtNum(x.soldCount) + '</td>' +
          '<td>' + badge(x.status) + '</td></tr>').join('')
          : '<tr><td colspan="8" class="empty">Hakuna flash sales</td></tr>') +
        '</tbody></table></div></div>';
    }
  } catch (e) { body.innerHTML = '<div class="card"><div class="err">' + esc(e.message) + '</div></div>'; }
  touch(); icons();
}

// ---------------------------------------------------------------------------
// Mapato ya Jukwaa: fees (commission + boost) + admin withdrawal
// ---------------------------------------------------------------------------
async function loadRevenue() {
  const el = secEl('revenue');
  el.innerHTML = '<div class="sectionempty"><div class="spinner" style="margin:0 auto 12px"></div>Inapakia…</div>';
  try {
    const [fin, led, wd] = await Promise.all([
      getJSON('/api/admin/finance-summary'),
      getJSON('/api/admin/revenue-ledger?limit=60'),
      getJSON('/api/admin/revenue-withdrawals?limit=50'),
    ]);
    const e = fin.availableBalance != null ? fin : {};
    el.innerHTML =
      '<div class="grid kpis">' +
      kpi('Tume ya Mauzo', fmtTZS(fin.totalCommissions || 0), 'commission fee', 'percent') +
      kpi('Ada za Boost', fmtTZS(fin.totalBoostRevenue || 0), 'boost fee', 'megaphone') +
      kpi('Jumla ya Mapato', fmtTZS(fin.totalAdminBalance || 0), 'commission + boost', 'coins') +
      kpi('Inapatikana kuondolewa', fmtTZS(fin.availableBalance || 0), 'baada ya withdrawals', 'banknote') +
      '</div>' +
      '<div class="toolbar" style="margin:14px 0 8px"><button class="btn accent" id="revWithdrawBtn" data-fn="revenueWithdraw">Toa Mapato (Withdraw) → ClickPesa</button></div>' +
      '<div class="grid cols2" style="margin-top:6px">' +
      '<div class="card"><div class="cardhead"><h3>Ledger ya Mapato (commission/boost)</h3></div>' +
      '<div class="tablewrap"><table class="tbl"><thead><tr><th>Wakati</th><th>Mtumiaji</th><th>Aina</th><th>Kiasi</th><th>Tume</th></tr></thead><tbody>' +
      revRows(led.entries || []) +
      '</tbody></table></div></div>' +
      '<div class="card"><div class="cardhead"><h3>Withdrawals za Admin</h3></div>' +
      '<div class="tablewrap"><table class="tbl"><thead><tr><th>Wakati</th><th>Kiasi</th><th>Fee</th><th>Net</th><th>Simu</th><th>Hali</th></tr></thead><tbody>' +
      wdRows((wd.withdrawals || [])) +
      '</tbody></table></div></div>' +
      '</div>';
  } catch (e) { el.innerHTML = '<div class="card"><div class="err">' + esc(e.message) + '</div></div>'; }
  bindSection('revenue'); touch(); icons();
}
function revRows(entries) {
  if (!entries.length) return '<tr><td colspan="5" class="empty">Hakuna mapato bado</td></tr>';
  return entries.map((x) => '<tr><td class="dim">' + fmtTime(x.timestamp) + '</td>' +
    '<td>' + esc(x.userName || id12(x.userId)) + '<div class="dim mono">' + esc(id12(x.userId)) + '</div></td>' +
    '<td>' + badge(x.type) + '</td>' +
    '<td class="num">' + fmtTZS(x.amount) + '</td>' +
    '<td class="num">' + fmtTZS(x.commission) + '</td></tr>').join('');
}
function wdRows(rows) {
  if (!rows.length) return '<tr><td colspan="6" class="empty">Hakuna withdrawals za admin</td></tr>';
  return rows.map((x) => '<tr><td class="dim">' + fmtTime(x.createdAt) + '</td>' +
    '<td class="num">' + fmtTZS(x.amount) + '</td><td class="num">' + fmtTZS(x.fee) + '</td>' +
    '<td class="num">' + fmtTZS(x.netAmount) + '</td><td class="mono">' + esc(x.phone || '') + '</td>' +
    '<td>' + badge(x.status) + '</td></tr>').join('');
}
async function revenueWithdraw() {
  openModal(
    '<h3>Toa Mapato ya Jukwaa</h3>' +
    '<p class="msub">Fedha zitatumwa kwa namba yako kupitia ClickPesa payout.</p>' +
    '<label class="lab">Kiasi (TZS)</label><input id="rwAmt" class="field" type="number" inputmode="numeric" min="1000" placeholder="e.g. 100000">' +
    '<label class="lab">Namba yako (ClickPesa)</label><input id="rwPhone" class="field" type="tel" inputmode="tel" placeholder="e.g. 0712345678">' +
    '<div class="err" id="rwErr"></div>' +
    '<div class="mfooter"><button class="btn" id="rwNo">Futa</button><button class="btn accent" id="rwYes">Tuma Withdraw</button></div>'
  );
  $('rwNo').onclick = closeModal;
  $('rwYes').onclick = () => {
    const amount = Math.round(Number($('rwAmt').value) || 0);
    const phone = $('rwPhone').value.trim();
    if (amount <= 0) { $('rwErr').textContent = 'Andika kiasi halali.'; return; }
    if (!phone) { $('rwErr').textContent = 'Andika namba.'; return; }
    run(async () => {
      const j = await postJSON('/api/admin/withdraw', { amount, phone });
      closeModal();
      toast((j && j.message) || 'Withdraw imetumwa', true);
      loadRevenue();
    });
  };
}

// ---------------------------------------------------------------------------
// KYC admin approve/reject/revoke
// ---------------------------------------------------------------------------
function kycTabs(active) {
  const tabs = { pending: 'Zinazosubiri', all: 'Zote' };
  return '<div class="toolbar" style="margin-bottom:14px">' + Object.keys(tabs).map((k) =>
    '<button class="radio-chip ' + (active === k ? 'on' : '') + '" data-ktab="' + k + '">' + tabs[k] + '</button>').join('') + '</div>';
}
async function loadKyc(focus) {
  const el = secEl('kyc');
  const f = focus || pgState('kyc', 'f') || 'pending';
  setPg('kyc', 'f', f);
  el.innerHTML = kycTabs(f) + '<div class="finBody"></div>';
  loadKycList(f);
  el.querySelectorAll('[data-ktab]').forEach((b) => b.addEventListener('click', () => loadKyc(b.dataset.ktab)));
}
async function loadKycList(f) {
  const body = secEl('kyc').querySelector('.finBody');
  body.innerHTML = '<div class="card"><div class="sectionempty"><div class="spinner" style="margin:0 auto 12px"></div>Inapakia…</div></div>';
  try {
    const j = f === 'pending' ? await getJSON('/api/admin/kyc/pending') : await getJSON('/api/admin/kyc/all');
    const rows = f === 'pending' ? (j.pending || []) : (j.all || []);
    body.innerHTML = '<div class="card"><div class="tablewrap"><table class="tbl"><thead><tr>' +
      '<th>Mtumiaji</th><th>Aina ya Kitambulisho</th><th>Nambari</th><th>Iliwasilishwa</th><th>Hali</th><th style="text-align:right">Vitendo</th></tr></thead><tbody>' +
      (rows.length ? rows.map((u) => {
        const k = u.kyc || {};
        const st = k.status || 'none';
        const args = JSON.stringify({ uid: u.uid, name: u.displayName || u.email || u.uid }).replace(/'/g, '&#39;');
        let actions = '<span class="dim">—</span>';
        if (st === 'pending') {
          actions =
            '<button class="btn sm accent" data-fn="kycApprove" data-args=\'' + args + '\'>Kubali</button> ' +
            '<button class="btn sm danger" data-fn="kycReject" data-args=\'' + args + '\'>Kataa</button>';
        } else if (st === 'approved') {
          actions = '<button class="btn sm" data-fn="kycRevoke" data-args=\'' + args + '\'>Futa (Revoke)</button>';
        }
        return '<tr>' +
          '<td>' + avatarOf({ displayName: u.displayName, avatarUrl: '', email: u.email }) + ' <b>' + esc(u.displayName || '—') + '</b><div class="dim">' + esc(u.email || '') + ' · ' + esc(u.phone || '') + '</div></td>' +
          '<td>' + esc(k.idType || '—') + '</td>' +
          '<td class="mono">' + esc(k.idNumber || '—') + '</td>' +
          '<td class="dim">' + fmtDay(k.submittedAt) + '</td>' +
          '<td>' + badge(st) + '</td>' +
          '<td class="rowactions">' + actions + '</td></tr>';
      }).join('') : '<tr><td colspan="6" class="empty">Hakuna wasilisho la KYC</td></tr>') +
      '</tbody></table></div></div>';
  } catch (e) {
    body.innerHTML = '<div class="card"><div class="err">' + esc(e.message) + '</div></div>';
  }
  bindSection('kyc'); touch(); icons();
}
async function kycReview(uid, name, action) {
  if (action === 'reject') {
    const reason = prompt('Sababu ya kukataa KYC ya ' + name);
    if (reason === null) return;
    run(async () => {
      const j = await postJSON('/api/admin/kyc/review', { userId: uid, approve: false, notes: reason });
      toast((j && j.message) || 'KYC imekataliwa', true);
      loadKyc(pgState('kyc', 'f'));
    });
    return;
  }
  if (action === 'revoke') {
    const ok = await confirmModal('Futa KYC', 'Futa kibali cha KYC cha ' + name + '? Bidhaa zake zitaondolewa kibali cha kuuza.', 'Futa', true);
    if (!ok) return;
    const reason = prompt('Sababu ya kufuta');
    run(async () => {
      const j = await postJSON('/api/admin/kyc/revoke', { userId: uid, reason: reason || '' });
      toast((j && j.message) || 'KYC imefutwa', true);
      loadKyc(pgState('kyc', 'f'));
    });
    return;
  }
  const ok = await confirmModal('Kubali KYC', 'Kubali KYC ya ' + name + ' na amruhusu kuuza bidhaa?', 'Kubali', false);
  if (!ok) return;
  run(async () => {
    const j = await postJSON('/api/admin/kyc/review', { userId: uid, approve: true, notes: '' });
    toast((j && j.message) || 'KYC imekubaliwa', true);
    loadKyc(pgState('kyc', 'f'));
  });
}

// ---------------------------------------------------------------------------
// Settings (Mipangilio) — 7 groups, Firestore-backed, secrets masked as ******
// ---------------------------------------------------------------------------
async function loadSettings() {
  const el = secEl('settings');
  el.innerHTML = '<div class="card"><div class="sectionempty"><div class="spinner" style="margin:0 auto 12px"></div>Inapakia mipangilio…</div></div>';
  try {
    const j = await getJSON('/api/v1/admin/settings');
    const s = (j && j.data) || j || {};
    const g = s.general || {}, ra = s.registrationAndAuth || {}, pc = s.paymentsAndCurrency || {}, gw = (pc.gateways || {}),
      em = s.emailNotifications || {}, it = s.integrations || {}, oa = (it.oauth || {}), og = (oa.google || {}), of = (oa.facebook || {}),
      sm = s.securityMaintenance || {}, pf = s.performance || {};
    const chk = (v) => v ? 'checked' : '';
    const sel = (cur, val) => cur === val ? ' selected' : '';
    el.innerHTML =
      '<div class="settings-wrap">' +
      // 1 Jumla
      '<div class="card"><h3 data-i18n="grp-general">Mipangilio ya Jumla</h3>' +
      '<div class="settings-grid">' +
      '<div class="settings-group"><h4>Jina na Nembo</h4>' +
      '<label class="lab">Jina la jukwaa</label><input id="st-general-platformName" class="field" value="' + esc(g.platformName || '') + '">' +
      '<label class="lab">Tagline</label><input id="st-general-tagline" class="field" value="' + esc(g.tagline || '') + '">' +
      '<label class="lab">Logo URL</label><input id="st-general-logoUrl" class="field" value="' + esc(g.logoUrl || '') + '" placeholder="https://">' +
      '</div>' +
      '<div class="settings-group"><h4>Muda na Eneo</h4>' +
      '<label class="lab">Timezone</label><input id="st-general-timezone" class="field" value="' + esc(g.timezone || '') + '">' +
      '<label class="lab">Lugha</label><select id="st-general-language" class="field"><option value="sw"' + sel(g.language, 'sw') + '>sw</option><option value="en"' + sel(g.language, 'en') + '>en</option></select>' +
      '<label class="lab">Date format</label><select id="st-general-dateFormat" class="field"><option value="short"' + sel(g.dateFormat, 'short') + '>short</option><option value="long"' + sel(g.dateFormat, 'long') + '>long</option></select>' +
      '<label class="lab">Time format</label><select id="st-general-timeFormat" class="field"><option value="24h"' + sel(g.timeFormat, '24h') + '>24h</option><option value="12h"' + sel(g.timeFormat, '12h') + '>12h</option></select>' +
      '</div>' +
      '<div class="settings-group"><h4>Mawasiliano ya Msingi</h4>' +
      '<label class="lab">Admin email</label><input id="st-general-adminEmail" class="field" value="' + esc(g.adminEmail || '') + '">' +
      '<label class="lab">Support email</label><input id="st-general-supportEmail" class="field" value="' + esc(g.supportEmail || '') + '">' +
      '<label class="lab">Support phone</label><input id="st-general-supportPhone" class="field" value="' + esc(g.supportPhone || '') + '">' +
      '</div></div></div>' +
      // 2 Watumiaji na Ufikiaji
      '<div class="card"><h3>Watumiaji na Ufikiaji</h3><div class="settings-grid">' +
      '<div class="settings-group"><h4>Usajili</h4>' +
      '<label class="lab chk"><input type="checkbox" id="st-ra-allowRegistration" ' + chk(ra.allowRegistration) + '> Ruhusu usajili</label>' +
      '<label class="lab chk"><input type="checkbox" id="st-ra-allowSellerSignup" ' + chk(ra.allowSellerSignup) + '> Ruhusu wauzaji kujisajili</label>' +
      '<label class="lab">Default role</label><select id="st-ra-defaultUserRole" class="field"><option value="buyer"' + sel(ra.defaultUserRole, 'buyer') + '>buyer</option><option value="seller"' + sel(ra.defaultUserRole, 'seller') + '>seller</option></select>' +
      '</div>' +
      '<div class="settings-group"><h4>Roles & Permissions</h4><p class="dim">Roles: buyer / seller / admin (in-app)</p>' +
      '<label class="lab chk"><input type="checkbox" id="st-ra-requireEmailVerification" ' + chk(ra.requireEmailVerification) + '> Lazimisha uthibitisho wa email</label>' +
      '<label class="lab chk"><input type="checkbox" id="st-ra-requirePhoneVerification" ' + chk(ra.requirePhoneVerification) + '> Lazimisha uthibitisho wa simu</label>' +
      '</div>' +
      '<div class="settings-group"><h4>Usalama wa Watumiaji</h4>' +
      '<label class="lab chk"><input type="checkbox" id="st-ra-enable2FA" ' + chk(ra.enable2FA) + '> Washa 2FA</label>' +
      '<label class="lab">Muda wa session (dak)</label><input id="st-ra-sessionTimeoutMinutes" class="field" type="number" value="' + esc(ra.sessionTimeoutMinutes || 60) + '">' +
      '</div></div></div>' +
      // 3 Malipo na Sarafu
      '<div class="card"><h3>Malipo na Sarafu</h3><div class="settings-grid">' +
      '<div class="settings-group"><h4>Sarafu</h4>' +
      '<label class="lab">Sarafu</label><select id="st-pc-currency" class="field"><option value="TZS"' + sel(pc.currency, 'TZS') + '>TZS</option><option value="USD"' + sel(pc.currency, 'USD') + '>USD</option></select>' +
      '<label class="lab">Kodi (%)</label><input id="st-pc-taxRatePct" class="field" type="number" step="0.01" value="' + esc(pc.taxRatePct ?? 0) + '">' +
      '<label class="lab">Tume ya jukwaa (%)</label><input id="st-pc-platformCommissionPct" class="field" type="number" step="0.01" value="' + esc(pc.platformCommissionPct ?? 0) + '">' +
      '</div>' +
      '<div class="settings-group"><h4>Escrow</h4>' +
      '<label class="lab chk"><input type="checkbox" id="st-pc-enableEscrow" ' + chk(pc.enableEscrow) + '> Washa escrow</label>' +
      '<label class="lab">Siku kabla ya auto-release</label><input id="st-pc-escrowReleaseDays" class="field" type="number" value="' + esc(pc.escrowReleaseDays ?? 7) + '">' +
      '<label class="lab">Gateway kuu</label><select id="st-pc-primaryGateway" class="field"><option value="clickpesa"' + sel(pc.primaryGateway, 'clickpesa') + '>ClickPesa</option><option value="azamPay"' + sel(pc.primaryGateway, 'azamPay') + '>AzamPay</option><option value="selcom"' + sel(pc.primaryGateway, 'selcom') + '>Selcom</option><option value="stripe"' + sel(pc.primaryGateway, 'stripe') + '>Stripe</option><option value="paypal"' + sel(pc.primaryGateway, 'paypal') + '>PayPal</option></select>' +
      '</div>' +
      '<div class="settings-group"><h4>Njia za Malipo</h4>' +
      '<label class="lab">ClickPesa merchantId</label><input id="st-gw-clickpesa-merchantId" class="field" value="' + esc((gw.clickpesa || {}).merchantId || '') + '">' +
      '<label class="lab">ClickPesa apiKey</label><input id="st-gw-clickpesa-apiKey" class="field" value="' + esc((gw.clickpesa || {}).apiKey || '') + '" placeholder="****** ikiwa imewekwa">' +
      '<label class="lab">ClickPesa secret</label><input id="st-gw-clickpesa-secretKey" class="field" type="password" value="' + esc((gw.clickpesa || {}).secretKey || '') + '" placeholder="******">' +
      '<label class="lab">AzamPay secret</label><input id="st-gw-azamPay-secretKey" class="field" type="password" value="' + esc((gw.azamPay || {}).secretKey || '') + '" placeholder="******">' +
      '<label class="lab">Selcom secret</label><input id="st-gw-selcom-secretKey" class="field" type="password" value="' + esc((gw.selcom || {}).secretKey || '') + '" placeholder="******">' +
      '<label class="lab">Stripe secret</label><input id="st-gw-stripe-secretKey" class="field" type="password" value="' + esc((gw.stripe || {}).secretKey || '') + '" placeholder="******">' +
      '<label class="lab">PayPal secret</label><input id="st-gw-paypal-secretKey" class="field" type="password" value="' + esc((gw.paypal || {}).secretKey || '') + '" placeholder="******">' +
      '</div></div></div>' +
      // 4 Barua pepe na Taarifa
      '<div class="card"><h3>Barua pepe na Taarifa</h3><div class="settings-grid">' +
      '<div class="settings-group"><h4>SMTP</h4>' +
      '<label class="lab">Host</label><input id="st-em-smtpHost" class="field" value="' + esc(em.smtpHost || '') + '">' +
      '<label class="lab">Port</label><input id="st-em-smtpPort" class="field" type="number" value="' + esc(em.smtpPort || 587) + '">' +
      '<label class="lab chk"><input type="checkbox" id="st-em-smtpSecure" ' + chk(em.smtpSecure) + '> TLS/secure</label>' +
      '<label class="lab">SMTP user</label><input id="st-em-smtpUser" class="field" value="' + esc(em.smtpUser || '') + '" placeholder="******">' +
      '<label class="lab">SMTP pass</label><input id="st-em-smtpPass" class="field" type="password" value="' + esc(em.smtpPass || '') + '" placeholder="******">' +
      '<label class="lab">From email</label><input id="st-em-fromEmail" class="field" value="' + esc(em.fromEmail || '') + '">' +
      '<label class="lab">From name</label><input id="st-em-fromName" class="field" value="' + esc(em.fromName || '') + '">' +
      '</div>' +
      '<div class="settings-group"><h4>SMS Gateway</h4><p class="dim">Beem / Twilio — tumia apiKey/secret hapa</p>' +
      '<label class="lab">Provider</label><select id="st-em-smsProvider" class="field"><option value="beem"' + sel((s.sms && s.sms.provider) || 'beem', 'beem') + '>Beem</option><option value="twilio"' + sel((s.sms && s.sms.provider) || '', 'twilio') + '>Twilio</option></select>' +
      '</div>' +
      '<div class="settings-group"><h4>Violezo</h4>' +
      '<label class="lab">Buyer signature</label><textarea id="st-em-signatures-buyer" class="field" rows="2">' + esc((em.signatures || {}).buyer || '') + '</textarea>' +
      '<label class="lab">Seller signature</label><textarea id="st-em-signatures-seller" class="field" rows="2">' + esc((em.signatures || {}).seller || '') + '</textarea>' +
      '</div></div></div>' +
      // 5 Viunganishi
      '<div class="card"><h3>Viunganishi na API Keys</h3><div class="settings-grid">' +
      '<div class="settings-group"><h4>Analytics</h4>' +
      '<label class="lab">GA Measurement ID</label><input id="st-it-analyticsId" class="field" value="' + esc(it.analyticsId || '') + '">' +
      '<label class="lab">FB Pixel ID</label><input id="st-it-pixelId" class="field" value="' + esc(it.pixelId || '') + '">' +
      '</div>' +
      '<div class="settings-group"><h4>Kuingia kwa Mitandao</h4>' +
      '<label class="lab">Google clientId</label><input id="st-it-oauth-google-clientId" class="field" value="' + esc(og.clientId || '') + '">' +
      '<label class="lab">Google clientSecret</label><input id="st-it-oauth-google-clientSecret" class="field" type="password" value="' + esc(og.clientSecret || '') + '" placeholder="******">' +
      '<label class="lab">Facebook appId</label><input id="st-it-oauth-facebook-appId" class="field" value="' + esc(of.appId || '') + '">' +
      '<label class="lab">Facebook appSecret</label><input id="st-it-oauth-facebook-appSecret" class="field" type="password" value="' + esc(of.appSecret || '') + '" placeholder="******">' +
      '</div>' +
      '<div class="settings-group"><h4>Hifadhi ya Wingu</h4>' +
      '<label class="lab">S3 bucket</label><input id="st-it-s3Bucket" class="field" value="' + esc(it.s3Bucket || '') + '">' +
      '</div></div></div>' +
      // 6 Usalama na Matengenezo
      '<div class="card"><h3>Usalama na Matengenezo</h3><div class="settings-grid">' +
      '<div class="settings-group"><h4>Hali ya Matengenezo</h4>' +
      '<label class="lab chk"><input type="checkbox" id="st-sm-maintenanceMode" ' + chk(sm.maintenanceMode) + '> Washa maintenance mode</label>' +
      '<label class="lab">Sababu</label><textarea id="st-sm-maintenanceReason" class="field" rows="2">' + esc(sm.maintenanceReason || '') + '</textarea>' +
      '<label class="lab chk"><input type="checkbox" id="st-sm-allowSuspendedLogin" ' + chk(sm.allowSuspendedLogin) + '> Ruhusu suspended kuingia</label>' +
      '</div>' +
      '<div class="settings-group"><h4>IP Whitelist / Blacklist</h4>' +
      '<label class="lab">Whitelist (comma)</label><textarea id="st-sm-ipWhitelist" class="field" rows="2">' + esc(sm.ipWhitelist || '') + '</textarea>' +
      '<label class="lab">Blacklist (comma)</label><textarea id="st-sm-ipBlacklist" class="field" rows="2">' + esc(sm.ipBlacklist || '') + '</textarea>' +
      '</div>' +
      '<div class="settings-group"><h4>Nakala ya Akiba</h4>' +
      '<label class="lab">Ratiba</label><select id="st-sm-backupSchedule" class="field"><option value="daily"' + sel(sm.backupSchedule, 'daily') + '>daily</option><option value="weekly"' + sel(sm.backupSchedule, 'weekly') + '>weekly</option><option value="off"' + sel(sm.backupSchedule, 'off') + '>off</option></select>' +
      '</div></div></div>' +
      // 7 Utendaji
      '<div class="card"><h3>Utendaji na Uboreshaji</h3><div class="settings-grid">' +
      '<div class="settings-group"><h4>Cache</h4>' +
      '<label class="lab chk"><input type="checkbox" id="st-pf-enableCache" ' + chk(pf.enableCache) + '> Washa cache</label>' +
      '<label class="lab">TTL (sec)</label><input id="st-pf-cacheTtlSeconds" class="field" type="number" value="' + esc(pf.cacheTtlSeconds ?? 300) + '">' +
      '</div>' +
      '<div class="settings-group"><h4>Upakiaji</h4>' +
      '<label class="lab">Max upload MB</label><input id="st-pf-maxUploadMB" class="field" type="number" value="' + esc(pf.maxUploadMB ?? 5) + '">' +
      '<label class="lab">Image max MB</label><input id="st-pf-imageMaxMB" class="field" type="number" value="' + esc(pf.imageMaxMB ?? 5) + '">' +
      '<label class="lab chk"><input type="checkbox" id="st-pf-enableCompression" ' + chk(pf.enableCompression) + '> Washa compression</label>' +
      '<label class="lab">API rate limit /min</label><input id="st-pf-apiRateLimitPerMin" class="field" type="number" value="' + esc(pf.apiRateLimitPerMin ?? 300) + '">' +
      '</div></div></div>' +
      '<div class="card" style="display:flex;gap:10px;align-items:center"><button class="btn accent" id="st-save">Hifadhi mipangilio</button><span class="dim" id="st-msg"></span><button class="btn" id="st-clearCache" style="margin-left:auto">Futa cache</button></div>' +
      '</div>';
    $('st-save').addEventListener('click', saveSettings);
    $('st-clearCache').addEventListener('click', async () => {
      $('st-msg').textContent = 'Inaendeshwa…';
      try { await postJSON('/api/v1/admin/cache/clear', {}).catch(() => postJSON('/api/admin/cache/clear', {})); $('st-msg').textContent = 'Imefutwa'; toast('Cache imefutwa', true); } catch (e) { $('st-msg').textContent = esc(e.message); }
    });
    bindSection('settings'); touch(); icons();
    if (LANG === 'en') applyLang(el);
  } catch (e) { el.innerHTML = '<div class="card"><div class="err">' + esc(e.message) + '</div></div>'; }
}

async function saveSettings() {
  const v = (id) => { const el = $(id); return el ? el.value : ''; };
  const c = (id) => { const el = $(id); return el ? !!el.checked : false; };
  const n = (id, d) => { const x = Number(v(id)); return Number.isFinite(x) ? x : d; };
  const patch = {
    general: {
      platformName: v('st-general-platformName'), tagline: v('st-general-tagline'), logoUrl: v('st-general-logoUrl'),
      timezone: v('st-general-timezone'), language: v('st-general-language'), dateFormat: v('st-general-dateFormat'), timeFormat: v('st-general-timeFormat'),
      adminEmail: v('st-general-adminEmail'), supportEmail: v('st-general-supportEmail'), supportPhone: v('st-general-supportPhone'),
    },
    registrationAndAuth: {
      allowRegistration: c('st-ra-allowRegistration'), allowSellerSignup: c('st-ra-allowSellerSignup'), defaultUserRole: v('st-ra-defaultUserRole'),
      requireEmailVerification: c('st-ra-requireEmailVerification'), requirePhoneVerification: c('st-ra-requirePhoneVerification'),
      enable2FA: c('st-ra-enable2FA'), sessionTimeoutMinutes: n('st-ra-sessionTimeoutMinutes', 60),
    },
    paymentsAndCurrency: {
      currency: v('st-pc-currency'), taxRatePct: n('st-pc-taxRatePct', 0), platformCommissionPct: n('st-pc-platformCommissionPct', 0),
      enableEscrow: c('st-pc-enableEscrow'), escrowReleaseDays: n('st-pc-escrowReleaseDays', 7), primaryGateway: v('st-pc-primaryGateway'),
      gateways: {
        clickpesa: { merchantId: v('st-gw-clickpesa-merchantId'), apiKey: v('st-gw-clickpesa-apiKey'), secretKey: v('st-gw-clickpesa-secretKey') },
        azamPay: { secretKey: v('st-gw-azamPay-secretKey') },
        selcom: { secretKey: v('st-gw-selcom-secretKey') },
        stripe: { secretKey: v('st-gw-stripe-secretKey') },
        paypal: { secretKey: v('st-gw-paypal-secretKey') },
      },
    },
    emailNotifications: {
      smtpHost: v('st-em-smtpHost'), smtpPort: n('st-em-smtpPort', 587), smtpSecure: c('st-em-smtpSecure'),
      smtpUser: v('st-em-smtpUser'), smtpPass: v('st-em-smtpPass'),
      fromEmail: v('st-em-fromEmail'), fromName: v('st-em-fromName'),
      signatures: { buyer: v('st-em-signatures-buyer'), seller: v('st-em-signatures-seller') },
    },
    integrations: {
      analyticsId: v('st-it-analyticsId'), pixelId: v('st-it-pixelId'), s3Bucket: v('st-it-s3Bucket'),
      oauth: {
        google: { clientId: v('st-it-oauth-google-clientId'), clientSecret: v('st-it-oauth-google-clientSecret') },
        facebook: { appId: v('st-it-oauth-facebook-appId'), appSecret: v('st-it-oauth-facebook-appSecret') },
      },
    },
    securityMaintenance: {
      maintenanceMode: c('st-sm-maintenanceMode'), maintenanceReason: v('st-sm-maintenanceReason'),
      allowSuspendedLogin: c('st-sm-allowSuspendedLogin'), ipWhitelist: v('st-sm-ipWhitelist'), ipBlacklist: v('st-sm-ipBlacklist'),
      backupSchedule: v('st-sm-backupSchedule'),
    },
    performance: {
      enableCache: c('st-pf-enableCache'), cacheTtlSeconds: n('st-pf-cacheTtlSeconds', 300),
      maxUploadMB: n('st-pf-maxUploadMB', 5), imageMaxMB: n('st-pf-imageMaxMB', 5),
      enableCompression: c('st-pf-enableCompression'), apiRateLimitPerMin: n('st-pf-apiRateLimitPerMin', 300),
    },
  };
  $('st-msg').textContent = 'Inaendeshwa…';
  try {
    await putJSON('/api/v1/admin/settings', { patch });
    $('st-msg').textContent = 'Mipangilio imehifadhiwa';
    toast('Mipangilio imehifadhiwa', true);
    loadSettings();
  } catch (e) { $('st-msg').textContent = esc(e.message); toast(esc(e.message), false); }
}

// ---------------------------------------------------------------------------
// Loader registry + filter wiring
// ---------------------------------------------------------------------------
const LOADERS = {
  dashboard: loadDashboard, users: loadUsers, sellers: loadSellers, products: loadProducts,
  orders: loadOrders, disputes: loadDisputes, refunds: loadRefunds, reports: loadReports,
  kyc: loadKyc, promos: loadPromos, revenue: loadRevenue,
  finance: loadFinance, referrals: loadReferrals, broadcasts: loadBroadcasts, audit: loadAudit,
  landing: loadLanding,
  stats: loadStats, settings: loadSettings,
};
function bindToolbar(sec, qId, goId, qKey) {
  const el = secEl(sec);
  const q = el.querySelector('#' + qId);
  const go = el.querySelector('#' + goId);
  if (!go) return;
  go.addEventListener('click', () => {
    if (q) setPg(sec, qKey, q.value.trim());
    setPg(sec, 'page', 1);
    LOADERS[sec]();
  });
  if (q) q.addEventListener('keydown', (e) => { if (e.key === 'Enter') go.click(); });
}
function bindSelect(sec, selId, key) {
  const el = secEl(sec);
  const s = el.querySelector('#' + selId);
  if (s) s.addEventListener('change', () => { setPg(sec, key, s.value); setPg(sec, 'page', 1); LOADERS[sec](); });
}

// Nav + shell
function showSection(sec) {
  document.querySelectorAll('.nav-item').forEach((b) => b.classList.remove('active'));
  document.querySelector('.nav-item[data-sec="' + sec + '"]').classList.add('active');
  document.querySelectorAll('.section').forEach((s) => s.classList.remove('active'));
  $('sec-' + sec).classList.add('active');
  $('pageTitle').textContent = titleFor(sec);
  $('lastUpd').textContent = 'Inapakia…';
  LOADERS[sec] && LOADERS[sec]();
  $('sidebar').classList.remove('open');
  window.scrollTo(0, 0);
}
$('nav').addEventListener('click', (e) => {
  const b = e.target.closest('.nav-item');
  if (b) showSection(b.dataset.sec);
});
$('refreshBtn').addEventListener('click', () => {
  const sec = document.querySelector('.section.active').dataset.sec;
  setPg(sec, 'page', 1);
  LOADERS[sec]();
});
$('menuBtn').addEventListener('click', () => $('sidebar').classList.toggle('open'));
$('themeBtn').addEventListener('click', () => {
  const on = document.documentElement.getAttribute('data-theme') !== 'dark';
  document.documentElement.setAttribute('data-theme', on ? 'dark' : 'light');
  try { localStorage.setItem(THEME_KEY, on ? 'dark' : 'light'); } catch (_) {}
  $('themeBtn').innerHTML = '<i data-lucide="' + (on ? 'sun' : 'moon') + '"></i>';
  icons();
});
$('langBtn').addEventListener('click', () => {
  LANG = LANG === 'en' ? 'sw' : 'en';
  try { localStorage.setItem(LANG_KEY, LANG); } catch (_) {}
  applyNav();
  const sec = document.querySelector('.section.active') ? document.querySelector('.section.active').dataset.sec : null;
  if (sec && LOADERS[sec]) LOADERS[sec]();
  if (LANG === 'en' && !(sec && LOADERS[sec])) applyLang(document.body);
  $('langBtn').textContent = langLabel();
});

// ---------------------------------------------------------------------------
// Auth
// ---------------------------------------------------------------------------
function showLogin(err) {
  $('screen').hidden = true;
  $('loginCard').hidden = false;
  $('authErr').textContent = err || '';
}
function showApp() {
  $('screen').hidden = true;
  $('loginCard').hidden = true;
  $('app').hidden = false;
  document.title = 'Soko Vibe Admin';
  applyTheme();
  applyNav();
  $('langBtn').textContent = langLabel();
  if (LANG === 'en') applyLang(document.body);
  showSection('dashboard');
}
function applyTheme() {
  let t = 'light';
  try { t = localStorage.getItem(THEME_KEY) || 'light'; } catch (_) {}
  document.documentElement.setAttribute('data-theme', t);
  $('themeBtn').innerHTML = '<i data-lucide="' + (t === 'dark' ? 'sun' : 'moon') + '"></i>';
  icons();
}

// The single login: verify the secret against the dashboard, then enter.
async function trySecretLogin() {
  const v = $('secVal').value.trim();
  if (!v) { $('authErr').textContent = 'Andika ADMIN_SECRET.'; return; }
  $('authErr').textContent = '';
  $('secSave').disabled = true;
  try { localStorage.setItem(SECRET_KEY, v); } catch (_) {}
  try {
    await getJSON('/api/v1/admin/dashboard');
    $('meName').textContent = 'ADMIN_SECRET';
    $('meRole').textContent = 'secret mode';
    showApp();
  } catch (e) {
    try { localStorage.removeItem(SECRET_KEY); } catch (_) {}
    showLogin('ADMIN_SECRET haikubaliki: ' + (e && e.message));
  } finally {
    $('secSave').disabled = false;
  }
}
$('secSave').onclick = () => { trySecretLogin().catch(handleActionErr); };
$('secVal').addEventListener('keydown', (e) => { if (e.key === 'Enter') $('secSave').click(); });
$('logoutBtn').onclick = () => {
  try { localStorage.removeItem(SECRET_KEY); } catch (_) {}
  location.reload();
};

// ---------------------------------------------------------------------------
// Boot
// ---------------------------------------------------------------------------
window.addEventListener('error', (ev) => {
  const err = (ev && ev.message) || 'unknown';
  if ($('app') && !$('app').hidden) { toast(err, false); return; }
  showLogin('Runtime: ' + err);
});

// Boot: a stored secret is verified silently, otherwise show the login.
// Every path settles — no Firebase, no hanging callbacks, no eternal splash.
(async () => {
  try {
    if (secret()) {
      await getJSON('/api/v1/admin/dashboard');
      $('meName').textContent = 'ADMIN_SECRET';
      $('meRole').textContent = 'secret mode';
      showApp();
    } else {
      showLogin('');
    }
  } catch (e) {
    try { localStorage.removeItem(SECRET_KEY); } catch (_) {}
    showLogin('ADMIN_SECRET haikubaliki: ' + (e && e.message));
  }
})();

// Apply stored theme on first paint
applyTheme();