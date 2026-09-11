/* Soko Vibe - public seller storefront (#/store/:uid).
   Trust section shows only real metrics: verified status, review-weighted
   rating from the seller's own products, total units sold, store age from
   the seller's profile (hidden when unavailable). No invented values. */
(function () {
  const C = window.SV.components;
  const { icon, svCard, skel, empty } = C;
  const CHAT_ICON = '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/></svg>';
  const PHONE_ICON = '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M22 16.9v3a2 2 0 0 1-2.2 2 19.8 19.8 0 0 1-8.6-3.1 19.5 19.5 0 0 1-6-6A19.8 19.8 0 0 1 2.1 4.2 2 2 0 0 1 4.1 2h3a2 2 0 0 1 2 1.7c.1 1 .4 2 .7 2.9a2 2 0 0 1-.5 2.1L8.1 10a16 16 0 0 0 6 6l1.3-1.2a2 2 0 0 1 2.1-.5c.9.3 1.9.6 2.9.7a2 2 0 0 1 1.6 2z"/></svg>';

  /* A Firestore read must never leave the page stuck on skeletons:
     race it against a timer, then fall back to already-loaded Feed data. */
  function reqTimeout(pr, ms) {
    try {
      return Promise.race([
        Promise.resolve(pr).catch(() => null),
        new Promise((res) => setTimeout(() => res(null), ms)),
      ]);
    } catch (_) { return Promise.resolve(null); }
  }

  async function render(uid) {
    setLang();
    document.body.dataset.route = 'store';
    Feed.mode = { kind: 'store', uid };
    view.innerHTML = '<section class="sv-store">' + skel(6) + '</section>';

    let list = [];
    const snap = await reqTimeout(DB.collection('products').where('sellerId', '==', uid).limit(100).get(), 12000);
    if (snap && snap.docs) {
      list = snap.docs.map((d) => { try { return norm(d); } catch (_) { return null; } }).filter(Boolean);
    }
    if (!list.length) list = Feed.list.filter((p) => p.sellerId === uid);
    list = list.slice().sort((a, b) => tsMillis(b.createdAt) - tsMillis(a.createdAt));
    if (document.body.dataset.route !== 'store') return;
    window.__storeList = list;

    const info = list.length
      ? { name: list[0].sellerName || 'Muuzaji', verified: !!list[0].sellerKycApproved, region: list[0].location || '', phone: list[0].sellerPhone || '' }
      : null;

    let rc = 0, rs = 0, sold = 0;
    list.forEach((p) => {
      const n = Number(p.reviewCount) || 0;
      rc += n; rs += (Number(p.rating) || 0) * n;
      sold += Number(p.soldCount) || 0;
    });
    const avg = rc ? rs / rc : 0;

    let since = '';
    const u = await reqTimeout(DB.collection('users').doc(uid).get(), 8000);
    if (document.body.dataset.route !== 'store') return;
    try {
      const c = u && u.exists && (u.data().createdAt || u.data().sellerSince);
      const d = c ? (c.toDate ? c.toDate() : new Date(c)) : null;
      if (d && !isNaN(d.getTime())) since = d.getFullYear();
    } catch (_) {}

    /* Server-authoritative trust passport (public endpoint). Uses the
       seller's own profile link when present; levels only — the numeric
       reliability score is intentionally not exposed. Falls back to
       product-derived metrics below when unavailable. */
    let dots = '';
    try {
      const ud = u && u.exists ? u.data() : null;
      const pid = ud && (ud.sellerProfileId || ud.sellerProfileID || ud.sellerId || ud.storeSlug);
      if (pid && typeof apiGet === 'function') {
        const r = await reqTimeout(apiGet('/api/v1/trust/sellers/' + encodeURIComponent(pid) + '/passport'), 8000);
        if (document.body.dataset.route !== 'store') return;
        const pp = r && (r.data || r.metrics ? (r.data || r) : null);
        if (pp && Array.isArray(pp.indicators) && pp.indicators.length) {
          dots = '<span class="sv-dots">' + pp.indicators.map((g) =>
            '<span class="sv-dot ' + (g.level === 'green' ? 'g' : g.level === 'amber' ? 'a' : 'x') + '" title="' + esc(g.key) + (g.value != null ? ': ' + g.value + '%' : '') + '"></span>'
          ).join('') + '</span>';
        }
      }
    } catch (_) {}

    const metrics = (avg > 0 ? '<span class="sv-store-metric">★ ' + avg.toFixed(1) + ' (' + rc + ')</span>' : '')
      + (sold > 0 ? '<span class="sv-store-metric">' + sold + ' ' + esc(t('sold')) + '</span>' : '')
      + (since ? '<span class="sv-store-metric">' + esc(t('sv_since')) + ' ' + since + '</span>' : '')
      + dots;

    const cats = [...new Set(list.map((p) => p.category).filter(Boolean))];
    const catRow = cats.length > 1
      ? '<div class="sv-refine-row" role="list"><button type="button" class="sv-chip on" data-act="scat" data-v="">' + esc(t('sv_all')) + '</button>'
        + cats.map((c) => '<button type="button" class="sv-chip" data-act="scat" data-v="' + esc(c) + '">' + esc(c) + '</button>').join('')
        + '</div>'
      : '';

    const head = '<div class="sv-store-head">'
      + '<div class="sv-store-av">' + icon('store') + '</div>'
      + '<div class="sv-store-meta"><h1>' + esc(info ? info.name : 'Kibanda') + '</h1>'
      + '<div class="sv-store-sub">'
      + (info && info.verified ? '<span class="sv-ver">' + icon('check') + esc(t('sv_ver_seller')) + '</span>' : '')
      + (info && info.region ? '<span>' + esc(info.region) + '</span>' : '')
      + '<span class="sv-store-count">' + list.length + ' ' + esc(t('sv_items')) + '</span>'
      + '</div>'
      + (metrics ? '<div class="sv-store-sub">' + metrics + '</div>' : '')
      + '</div>'
      + '<div class="sv-store-cta">'
      + '<button type="button" class="sv-btn sv-btn-outline sv-store-msg" data-act="msgstore" data-u="' + esc(uid) + '" data-n="' + esc(info ? info.name : '') + '">' + CHAT_ICON + esc(t('sv_msg_seller')) + '</button>'
      + ((typeof AUTH !== 'undefined' && AUTH.currentUser && AUTH.currentUser.uid !== uid)
        ? '<button type="button" class="sv-btn sv-btn-outline" data-act="follow" data-following="' + esc(uid) + '">' + esc(t('follow')) + '</button>'
        : '')
      + ((info && info.phone) ? '<a class="sv-btn sv-btn-outline" href="tel:' + esc(String(info.phone).replace(/\s+/g, '')) + '">' + PHONE_ICON + esc(t('call_seller')) + '</a>' : '')
      + '</div></div>';

    const body = list.length
      ? '<div class="sv-section-head"><h2 class="sv-section-title">' + esc(t('sv_store_products')) + '</h2></div>'
        + catRow
        + '<div class="grid" id="svStoreGrid">' + list.map(svCard).join('') + '</div>'
      : empty(t('sv_no_products'), t('sv_try_diff'), t('sv_back_home'));

    view.innerHTML = '<section class="sv-store">' + head + body + '</section>';
    document.title = (info ? info.name : 'Kibanda') + ' | Soko Vibe';
  }

  window.SV = window.SV || {};
  window.SV.store = { render };
})();
