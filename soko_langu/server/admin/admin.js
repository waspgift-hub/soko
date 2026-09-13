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
let toastT; function toast(msg, ok) {
  const el = $('toast');
  el.textContent = msg;
  el.className = 'toast show ' + (ok ? 'ok' : 'bad');
  clearTimeout(toastT);
  toastT = setTimeout(() => (el.className = 'toast'), 3400);
}
function icons() { if (window.lucide) lucide.createIcons(); }

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
  stats: 'Takwimu za Matumizi',
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
  sellerVerify(args) { sellerVerify(args.id, args.name, 'verify'); },
  sellerReject(args) { sellerVerify(args.id, args.name, 'reject'); },
  sellerPending(args) { sellerVerify(args.id, args.name, 'pending'); },
  viewSeller(args) { viewSellerDetail(args.id); },
  productModerate(args) { productModerate(args.id, args.title); },
  viewProduct(args) { viewProductDetail(args.id, args.title); },
  viewOrder(args) { viewOrderDetail(args.id, args.num, args.status); },
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
      (orders.length ? orders.map((o) => '<tr>' +
        '<td class="mono"><b>' + esc(o.orderNumber || id12(o.id)) + '</b><div class="dim">' + fmtTime(o.createdAt) + '</div></td>' +
        '<td>' + esc((o.buyer && (o.buyer.displayName || o.buyer.email)) || '—') + '</td>' +
        '<td class="num">' + fmtTZS(o.totalAmount) + '</td>' +
        '<td>' + badge(o.status) + '</td>' +
        '<td class="rowactions"><button class="btn sm" data-fn="viewOrder" data-args=\'' + JSON.stringify({ id: o.id, num: o.orderNumber || o.id, status: o.status }).replace(/'/g, '&#39;') + '\'>Angalia</button></td>' +
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
    '<th>Mtumiaji</th><th>Email</th><th>Simu</th><th>Jukumu</th><th>Hali</th><th>Anajiunga</th><th style="text-align:right">Vitendo</th></tr></thead>' +
    '<tbody id="uRows"><tr><td colspan="7" class="empty"><div class="spinner" style="width:22px;height:22px;margin:0 auto 8px"></div>Inapakia…</td></tr></tbody></table></div>' +
    '<div id="uPag"></div></div>';
  const qs = new URLSearchParams({ page, limit: 20 });
  if (q) qs.set('q', q); if (role) qs.set('role', role); if (status) qs.set('accountStatus', status);
  try {
    const j = await getJSON('/api/v1/admin/users?' + qs.toString());
    const d = (j.data && j.data.users) || [];
    $('uRows').innerHTML = d.length
      ? d.map((u) =>
        '<tr>' +
        '<td>' + avatarOf(u) + ' ' + esc(u.displayName || u.username || '—') + '</td>' +
        '<td>' + esc(u.email || '—') + '</td>' +
        '<td class="mono">' + esc(u.phone || '—') + '</td>' +
        '<td>' + badge(u.role) + '</td>' +
        '<td>' + badge(u.accountStatus) + '</td>' +
        '<td class="dim">' + fmtTime(u.createdAt) + '</td>' +
        '<td class="rowactions">' +
        '<button class="btn sm" data-fn="viewUser" data-args=\'' + JSON.stringify({ id: u.id, name: u.displayName || u.email || u.id }).replace(/'/g, '&#39;') + '\'>Angalia</button>' +
        '<button class="btn sm" data-fn="userStatus" data-args=\'' + JSON.stringify({ id: u.id, name: u.displayName || u.email || u.id }).replace(/'/g, '&#39;') + '\'>Hali</button>' +
        '</td></tr>'
      ).join('')
      : '<tr><td colspan="7" class="empty">Hakuna watumiaji</td></tr>';
    $('uPag').innerHTML = pagerHTML('users', j.data.pagination);
  } catch (e) { $('uRows').innerHTML = '<tr><td colspan="7" class="empty">' + esc(e.message) + '</td></tr>'; }
  bindSection('users');
  touch();
}

async function changeUserStatus(id, name) {
  openModal(
    '<h3>Hali ya mtumiaji: ' + esc(name) + '</h3><p class="msub">Badilisha hali ya akaunti</p>' +
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
    '<div id="pPag"></div></div>';
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
    '<div id="oPag"></div></div>';
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
// Loader registry + filter wiring
// ---------------------------------------------------------------------------
const LOADERS = {
  dashboard: loadDashboard, users: loadUsers, sellers: loadSellers, products: loadProducts,
  orders: loadOrders, disputes: loadDisputes, refunds: loadRefunds, reports: loadReports,
  kyc: loadKyc, promos: loadPromos, revenue: loadRevenue,
  finance: loadFinance, referrals: loadReferrals, broadcasts: loadBroadcasts, audit: loadAudit,
  stats: loadStats,
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
  $('pageTitle').textContent = TITLES[sec] || sec;
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