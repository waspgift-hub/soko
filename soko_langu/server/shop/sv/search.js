/* Soko Vibe - Phase 1 search results + suggestions (filters, sort, view,
   did-you-mean). Replaces app renderSearch and enhanceSuggest. */
(function () {
  const C = window.SV.components;
  const { icon, svCard, skel, empty } = C;
  const HIST_KEY = 'sv_shop_search_hist';

  function norm(s) { return String(s || '').toLowerCase().replace(/[^\p{L}\p{N}\s]/gu, ' ').replace(/\s+/g, ' ').trim(); }
  function toks(s) { return norm(s).split(' ').filter(Boolean); }
  function uniq(arr) { return [...new Set(arr.filter(Boolean))]; }
  function toTime(v) { const n = Number(v); return n ? n : (v ? new Date(v).getTime() : 0); }
  function editDist(a, b) {
    const m = a.length, n = b.length;
    if (!m) return n; if (!n) return m;
    if (Math.abs(m - n) > 2) return 9;
    const dp = new Array(n + 1);
    for (let j = 0; j <= n; j++) dp[j] = j;
    for (let i = 1; i <= m; i++) {
      let prev = dp[0]; dp[0] = i;
      for (let j = 1; j <= n; j++) {
        const tmp = dp[j];
        dp[j] = Math.min(dp[j] + 1, dp[j - 1] + 1, prev + (a[i - 1] === b[j - 1] ? 0 : 1));
        prev = tmp;
      }
    }
    return dp[n];
  }

  function score(qt, p) {
    const t = toks(p.name), cs = toks(p.category || ''), bs = toks(p.brand || '');
    const full = norm(p.name).includes(qt.join(' '));
    let s = full ? 60 : 0;
    qt.forEach((tt) => {
      if (t.includes(tt)) s += 12;
      else if (t.some((x) => x.startsWith(tt))) s += 7;
      else if (t.some((x) => x.includes(tt))) s += 4;
      else if (t.some((x) => editDist(tt, x) <= 1)) s += 3;
      else if (cs.some((x) => x.startsWith(tt))) s += 3;
      else if (bs.some((x) => x.startsWith(tt))) s += 2;
    });
    return s;
  }

  function searchProducts(name, list) {
    const qt = toks(name);
    if (!qt.length) return list.slice();
    return list.map((p) => ({ p, s: score(qt, p) }))
      .filter((x) => x.s > 0)
      .sort((a, b) => (b.s - a.s) || ((Number(b.p.reviewCount) || 0) - (Number(a.p.reviewCount) || 0)))
      .map((x) => x.p);
  }

  function correctionFor(wn) {
    const w = toks(wn)[0];
    if (!w || w.length < 3) return null;
    const cand = new Set();
    Feed.list.forEach((p) => toks(p.name).forEach((x) => { if (x.startsWith(w) || editDist(w, x) <= 1) cand.add(x); }));
    let best = null, bd = 9;
    cand.forEach((x) => { if (x === w) return; const d = editDist(w, x); if (d < bd) { bd = d; best = x; } });
    return best;
  }

  function histList() { try { return JSON.parse(localStorage.getItem(HIST_KEY) || '[]'); } catch (e) { return []; } }
  function recordHist(q) {
    const qn = norm(q); if (!qn) return;
    let h = histList().filter((x) => norm(x) !== qn);
    h.unshift(q); h = h.slice(0, 8);
    try { localStorage.setItem(HIST_KEY, JSON.stringify(h)); } catch (e) {}
  }
  function clearHist() { try { localStorage.removeItem(HIST_KEY); } catch (e) {} }

  function curParams() { return Object.assign({}, paramsOf()); }
  function num(v) { const n = parseFloat(v); return isNaN(n) ? null : n; }

  async function ensureLoaded(cap) {
    let guard = 0;
    while (!Feed.done && Feed.list.length < (cap || 240) && guard < 14) { await loadPageInto(); guard++; }
  }

  function goHash(p) {
    const parts = [];
    ['q', 'c', 'sub', 'verified', 'ws', 'disc', 'cond', 'brand', 'minp', 'maxp', 'star', 'sort', 'view'].forEach((k) => {
      if (p[k] != null && p[k] !== '') parts.push(k + '=' + encodeURIComponent(p[k]));
    });
    location.hash = '#/search' + (parts.length ? '?' + parts.join('&') : '');
  }

  function matches(p, st, cat) {
    if (cat && !catMatch(p, cat)) return false;
    if (st.sub && (p.subcategory || '').toLowerCase() !== st.sub.toLowerCase()) return false;
    if (st.verified && !p.sellerKycApproved) return false;
    if (st.ws && !p.isWholesale) return false;
    if (st.disc && !(discount(p) > 0)) return false;
    if (st.cond && (p.condition || 'new') !== st.cond) return false;
    if (st.brand && (p.brand || '') !== st.brand) return false;
    if (st.minp != null && p.price < st.minp) return false;
    if (st.maxp != null && p.price > st.maxp) return false;
    if (st.star && (Number(p.rating) || 0) < st.star) return false;
    return true;
  }

  function applySort(arr, key) {
    switch (key) {
      case 'price_up': arr.sort((a, b) => a.price - b.price); break;
      case 'price_dn': arr.sort((a, b) => b.price - a.price); break;
      case 'newest': arr.sort((a, b) => toTime(b.createdAt) - toTime(a.createdAt)); break;
      case 'rating': arr.sort((a, b) => (Number(b.rating) || 0) - (Number(a.rating) || 0)); break;
      case 'sold': arr.sort((a, b) => (Number(b.soldCount) || 0) - (Number(a.soldCount) || 0)); break;
      case 'disc': arr.sort((a, b) => (discount(b) || 0) - (discount(a) || 0)); break;
      case 'name': arr.sort((a, b) => norm(a.name).localeCompare(norm(b.name))); break;
    }
  }

  function sortMarks() {
    return ['rel', 'newest', 'price_up', 'price_dn', 'rating', 'sold', 'disc', 'name'];
  }

  function sectionHeadHtml(title, total) {
    return '<div class="sv-section-head sv-search-head"><div>'
      + '<h1 class="sv-section-title">' + esc(title) + '</h1>'
      + '<div class="sv-section-sub">' + total + ' ' + esc(t('sv_items_found')) + '</div>'
      + '</div></div>';
  }

  function filterPanelHtml(list, st, cat) {
    const cats = browseCats();
    const catRows = cats.slice(0, 18).map((c) => {
      const n = list.filter((p) => catMatch(p, c)).length;
      const on = cat === c;
      return '<button type="button" class="sv-chip sq' + (on ? ' on' : '') + '" data-fil="c" data-val="' + esc(c) + '">'
        + '<span>' + esc(c) + '</span>' + (n ? '<i>' + n + '</i>' : '') + '</button>';
    }).join('');
    const brands = uniq(list.map((p) => p.brand));
    return '<aside class="sv-filterpanel" id="svFilterPanel">'
      + '<div class="sv-fhead"><h3>' + esc(t('sv_filter')) + '</h3>'
      + '<button type="button" class="sv-fclose" data-ftoggle="1" aria-label="' + esc(t('sv_f_remove')) + '">&times;</button></div>'
      + '<div class="sv-fgroup"><div class="sv-fh">' + esc(t('sv_f_cats')) + '</div><div class="sv-fcats">' + catRows + '</div></div>'
      + (brands.length ? '<div class="sv-fgroup"><div class="sv-fh">' + esc(t('sv_f_brand')) + '</div>'
        + '<select id="svBrandSel" class="sv-sort-sel"><option value="">' + esc(t('sv_all')) + '</option>'
        + brands.map((b) => '<option value="' + esc(b) + '"' + (st.brand === b ? ' selected' : '') + '>' + esc(b) + '</option>').join('')
        + '</select></div>' : '')
      + '<div class="sv-fgroup"><div class="sv-fh">' + esc(t('sv_f_price')) + '</div>'
      + '<div class="sv-price-row"><input id="svMinP" type="number" min="0" step="500" inputmode="numeric" placeholder="' + esc(t('sv_f_min')) + '" value="' + esc(st.minp != null ? st.minp : '') + '">'
      + '<span>&ndash;</span>'
      + '<input id="svMaxP" type="number" min="0" step="500" inputmode="numeric" placeholder="' + esc(t('sv_f_max')) + '" value="' + esc(st.maxp != null ? st.maxp : '') + '">'
      + '<button type="button" class="sv-btn sv-btn-amber sv-price-apply">' + esc(t('sv_f_go')) + '</button></div></div>'
      + '<div class="sv-fgroup"><div class="sv-fh">' + esc(t('sv_f_cond')) + '</div><div class="sv-fchips">'
      + [['new', t('sv_cond_new')], ['used', t('sv_cond_used')], ['refurbished', t('sv_cond_refurb')]]
        .map((c2) => '<button type="button" class="sv-chip' + (st.cond === c2[0] ? ' on' : '') + '" data-fil="cond" data-val="' + c2[0] + '">' + esc(c2[1]) + '</button>').join('')
      + '</div></div>'
      + '<div class="sv-fgroup"><div class="sv-fh">' + esc(t('sv_f_rating')) + '</div><div class="sv-fchips">'
      + [4, 3, 2].map((r) => '<button type="button" class="sv-chip' + (num(st.star) === r ? ' on' : '') + '" data-fil="star" data-val="' + r + '">' + r + '+</button>').join('')
      + '</div></div>'
      + '<div class="sv-fgroup sv-fchips">'
      + '<button type="button" class="sv-chip' + (st.verified ? ' on' : '') + '" data-fil="verified">' + esc(t('sv_f_ver')) + '</button>'
      + '<button type="button" class="sv-chip' + (st.ws ? ' on' : '') + '" data-fil="ws">' + esc(t('sv_f_ws')) + '</button>'
      + '<button type="button" class="sv-chip' + (st.disc ? ' on' : '') + '" data-fil="disc">' + esc(t('sv_f_disc')) + '</button>'
      + '</div>'
      + '<button type="button" class="sv-clear" data-clearall="1">' + esc(t('sv_f_clear')) + '</button>'
      + '</aside>';
  }

  function crumbHtml(cat, sub, query) {
    const H = '<span class="sv-crumb-node"><a href="#/">' + esc(t('nav_home')) + '</a></span>';
    if (cat) {
      const mid = sub
        ? '<a href="#/c/' + encodeURIComponent(cat) + '">' + esc(cat) + '</a>'
        : '<a href="#/search">' + esc(t('nav_categories')) + '</a>';
      return H + '<span class="sv-sep">/</span><span class="sv-crumb-node">' + mid + '</span>'
        + '<span class="sv-sep">/</span><span class="sv-crumb-node sv-crumb-cur">' + esc(sub || cat) + '</span>';
    }
    if (query) {
      return H + '<span class="sv-sep">/</span><span class="sv-crumb-node"><a href="#/search">' + esc(t('sv_crumb_search')) + '</a></span>'
        + '<span class="sv-sep">/</span><span class="sv-crumb-node sv-crumb-cur">' + esc(query) + '</span>';
    }
    return H + '<span class="sv-sep">/</span><span class="sv-crumb-node sv-crumb-cur">' + esc(t('sv_all_bidhaa')) + '</span>';
  }

  function refineRow(cat, sub) {
    const subs = (typeof SV_SUBCATS !== 'undefined' && SV_SUBCATS[cat]) || [];
    if (!subs.length) return '';
    const row = ['<a class="sv-chip' + (!sub ? ' on' : '') + '" href="#/c/' + encodeURIComponent(cat) + '">' + esc(t('sv_all')) + '</a>']
      .concat(subs.map((s) => '<a class="sv-chip' + (sub === s ? ' on' : '') + '" href="#/search?c=' + encodeURIComponent(cat) + '&sub=' + encodeURIComponent(s) + '">' + esc(s) + '</a>'));
    return '<div class="sv-refine-row" role="list">' + row.join('') + '</div>';
  }

  function renderShell(title, total, list, cat, st) {
    const sortSel = '<select id="svSortSel" class="sv-sort-sel" aria-label="' + esc(t('sv_sort')) + '">'
      + sortMarks().map((sk) => '<option value="' + sk + '"' + (st.sort === sk ? ' selected' : '') + '>' + esc(t('sv_sort_' + sk)) + '</option>').join('')
      + '</select>';
    const viewTog = '<div class="sv-viewtoggle" role="group">'
      + '<button type="button" class="sv-vbtn' + (st.view !== 'list' ? ' on' : '') + '" data-view="grid" title="' + esc(t('sv_view_grid')) + '" aria-label="' + esc(t('sv_view_grid')) + '">' + icon('grid') + '</button>'
      + '<button type="button" class="sv-vbtn' + (st.view === 'list' ? ' on' : '') + '" data-view="list" title="' + esc(t('sv_view_list')) + '" aria-label="' + esc(t('sv_view_list')) + '">' + icon('list') + '</button>'
      + '</div>';
    const tools = '<div class="sv-toolbar-right">' + sortSel + viewTog
      + '<button type="button" class="sv-btn sv-btn-outline sv-mfilterbtn" data-ftoggle="1">' + icon('filter') + esc(t('sv_filter')) + '</button></div>';

    view.innerHTML = '<section class="sv-search-page">'
      + '<nav class="sv-crumbs" aria-label="Breadcrumb">' + crumbHtml(cat, st.sub, st.bQuery) + '</nav>'
      + sectionHeadHtml(title, total)
      + refineRow(cat, st.sub)
      + '<div class="sv-toolbar"><p class="sv-sr-count"><b>' + total + '</b> ' + esc(t('sv_items_found')) + '</p>' + tools + '</div>'
      + '<div id="svDym"></div>'
      + '<div class="sv-active-chips" id="svActiveChips"></div>'
      + '<div class="sv-layout">' + filterPanelHtml(list, st, cat)
      + '<div class="sv-results"><div class="grid" id="svResultsHost">' + skel(9) + '</div></div>'
      + '</div></section>';
  }

  function dymHtml(qNorm, resultsLen) {
    if (!qNorm || resultsLen >= 12) return '';
    const corr = correctionFor(qNorm);
    if (!corr) return '';
    return '<div class="sv-dym">' + esc(t('sv_did_you_mean')) + ': '
      + '<a href="#/search?q=' + encodeURIComponent(corr) + '"><b>' + esc(corr) + '</b></a></div>';
  }

  function chipsHtml(st, cat) {
    const chips = [];
    if (cat) chips.push({ k: 'c', v: cat, label: esc(cat) });
    if (st.sub) chips.push({ k: 'sub', v: st.sub, label: esc(st.sub) });
    if (st.verified) chips.push({ k: 'verified', v: '1', label: t('sv_f_ver') });
    if (st.ws) chips.push({ k: 'ws', v: '1', label: t('sv_f_ws') });
    if (st.disc) chips.push({ k: 'disc', v: '1', label: t('sv_f_disc') });
    if (st.cond) chips.push({ k: 'cond', v: st.cond, label: t('sv_cond_' + st.cond) });
    if (st.brand) chips.push({ k: 'brand', v: st.brand, label: esc(st.brand) });
    if (st.minp != null) chips.push({ k: 'minp', v: String(st.minp), label: '&ge; ' + fmtTZS(st.minp) });
    if (st.maxp != null) chips.push({ k: 'maxp', v: String(st.maxp), label: '&le; ' + fmtTZS(st.maxp) });
    if (st.star) chips.push({ k: 'star', v: String(st.star), label: st.star + '+ ' + '&#9733;' });
    if (!chips.length) return '';
    return chips.map((ck) => '<span class="sv-active-chip"><span>' + ck.label + '</span>'
      + '<button type="button" aria-label="' + esc(t('sv_f_remove')) + '" data-fil="' + ck.k + '" data-val="' + ck.v + '">&times;</button></span>').join('');
  }

  function paintResults(results, st) {
    const host = document.getElementById('svResultsHost');
    if (!host) return;
    host.className = st.view === 'list' ? 'sv-list' : 'grid';
    if (!results.length) {
      host.innerHTML = empty(t('sv_no_results'), t('sv_try_diff'), t('sv_back_home'));
      return;
    }
    host.innerHTML = results.map(svCard).join('');
  }

  function handleClick(ev) {
    const ft = ev.target.closest('[data-ftoggle]');
    if (ft) { const fp = document.getElementById('svFilterPanel'); if (fp) fp.classList.toggle('sv-open'); return; }
    const vw = ev.target.closest('[data-view]');
    if (vw) { goHash(Object.assign(curParams(), { view: vw.getAttribute('data-view') })); return; }
    const pa = ev.target.closest('.sv-price-apply');
    if (pa) {
      const min = num(document.getElementById('svMinP').value);
      const max = num(document.getElementById('svMaxP').value);
      const p = curParams();
      if (min != null) p.minp = min; else delete p.minp;
      if (max != null) p.maxp = max; else delete p.maxp;
      goHash(p);
      return;
    }
    const ca = ev.target.closest('[data-clearall]');
    if (ca) { goHash({ q: curParams().q || '', c: curParams().c || '' }); return; }
    const fil = ev.target.closest('[data-fil]');
    if (fil) toggleParam(fil.getAttribute('data-fil'), fil.getAttribute('data-val'));
  }

  function toggleParam(k, v) {
    const p = curParams();
    if (k === 'c') { if (p.c && p.c === v) delete p.c; else p.c = v; }
    else if (k === 'verified' || k === 'ws' || k === 'disc') { if (p[k]) delete p[k]; else p[k] = '1'; }
    else if (k === 'star') { if (num(p[k]) === num(v)) delete p[k]; else p[k] = v; }
    else if (k === 'cond' || k === 'brand' || k === 'sub') { if (p[k] === v) delete p[k]; else p[k] = v; }
    else { delete p[k]; }
    goHash(p);
  }

  function handleChange(ev) {
    if (ev.target.id === 'svBrandSel') {
      const p = curParams();
      if (ev.target.value) p.brand = ev.target.value; else delete p.brand;
      goHash(p);
    } else if (ev.target.id === 'svSortSel') {
      goHash(Object.assign(curParams(), { sort: ev.target.value }));
    }
  }

  async function render(q, cat) {
    setLang();
    const prm = curParams();
    const query = q == null ? (prm.q || '') : q;
    const qNorm = norm(query);
    document.body.dataset.route = 'search';
    Feed.mode = { kind: 'query', q: query, c: cat };
    if (query) recordHist(query);

    await ensureLoaded(240);
    if (document.body.dataset.route !== 'search') return;

    let list = Feed.list.slice();
    if (qNorm) list = searchProducts(qNorm, list);
    if (cat) list = list.filter((p) => catMatch(p, cat));

    const st = {
      verified: prm.verified === '1' || prm.verified === 'true',
      ws: prm.ws === '1' || prm.ws === 'true',
      disc: prm.disc === '1' || prm.disc === 'true',
      cond: prm.cond || '',
      brand: prm.brand || '',
      sub: prm.sub || '',
      bQuery: query,
      minp: num(prm.minp),
      maxp: num(prm.maxp),
      star: num(prm.star) || 0,
      sort: prm.sort || 'rel',
      view: prm.view || (localStorage.getItem('sv_shop_view') || 'grid'),
    };

    const results = list.filter((p) => matches(p, st, cat));
    applySort(results, st.sort);

    const title = st.sub || query || (cat ? cat : t('sv_all_bidhaa'));
    const total = results.length;
    renderShell(title, total, list, cat, st);
    document.title = (!qNorm && !cat
      ? t('sv_all_bidhaa')
      : (query ? query + ' \u2014 ' : '') + title) + ' | Soko Vibe';

    document.getElementById('svActiveChips').innerHTML = chipsHtml(st, cat);
    document.getElementById('svDym').innerHTML = dymHtml(qNorm, total);
    paintResults(results, st);
  }

  /* ---- suggestions (overrides window.enhanceSuggest via init.js) ---- */
  function histChips() {
    const h = histList();
    if (!h.length) return '';
    return '<div class="sv-sgg-h">' + esc(t('sv_recent')) + '</div>'
      + h.map((x) => '<button type="button" data-act="sugg" data-q="' + esc(x) + '">' + icon('search') + ' ' + esc(x) + '</button>').join('');
  }

  function suggest(q) {
    const box = document.getElementById('suggestBox');
    if (!box) return;
    const v = (q || '').trim();
    if (!v) {
      box.innerHTML = histChips();
      box.setAttribute('data-empty', histChips() ? '0' : '1');
      box.hidden = false;
      return;
    }
    const vn = norm(v);
    const rows = [];
    const histHit = histList().filter((x) => norm(x).includes(vn)).slice(0, 3);
    if (histHit.length) rows.push('<div class="sv-sgg-h">' + esc(t('sv_recent')) + '</div>'
      + histHit.map((x) => '<button type="button" data-act="sugg" data-q="' + esc(x) + '">' + icon('search') + ' ' + esc(x) + '</button>').join(''));

    const hits = searchProducts(vn, Feed.list).slice(0, 5);
    if (hits.length) rows.push('<div class="sv-sgg-h">' + esc(t('sv_products')) + '</div>'
      + hits.map((p) => '<button type="button" data-act="sugg" data-q="' + esc(p.name.substring(0, 44)) + '">' + icon('box') + ' ' + esc(p.name.substring(0, 46)) + '</button>').join(''));

    const sellers = uniq(Feed.list.map((p) => p.sellerName)).filter((n) => n && norm(n).includes(vn)).slice(0, 3);
    if (sellers.length) rows.push('<div class="sv-sgg-h">' + esc(t('sv_sellers')) + '</div>'
      + sellers.map((n) => '<button type="button" data-act="sugg" data-q="' + esc(n) + '">' + icon('store') + ' ' + esc(n) + '</button>').join(''));

    const cats = browseCats().filter((c) => norm(c).includes(vn)).slice(0, 3);
    if (cats.length) rows.push('<div class="sv-sgg-h">' + esc(t('sv_categories')) + '</div>'
      + cats.map((c) => '<button type="button" data-act="sugg" data-q="' + esc(c) + '">' + icon('tag') + ' ' + esc(c) + '</button>').join(''));

    const corr = correctionFor(vn);
    if (corr && hits.length < 6) rows.push('<button type="button" data-act="sugg" data-q="' + esc(corr) + '">' + esc(t('sv_did_you_mean')) + ': <b>' + esc(corr) + '</b></button>');

    if (!rows.length) { box.hidden = true; return; }
    rows.push('<div class="sv-sgg-foot"><button type="button" data-svclear="1">' + esc(t('sv_clear')) + '</button></div>');
    box.innerHTML = rows.join('');
    box.setAttribute('data-empty', '0');
    box.hidden = false;
  }

  function wireClear(ev) {
    const cl = ev.target.closest('[data-svclear]');
    if (!cl) return;
    clearHist();
    const box = document.getElementById('suggestBox');
    if (box) { box.innerHTML = ''; box.hidden = true; }
  }

  function initListeners() {
    view.addEventListener('click', handleClick);
    view.addEventListener('change', handleChange);
    document.addEventListener('click', wireClear);
  }

  initListeners();

  window.SV = window.SV || {};
  window.SV.search = { render, suggest };
})();