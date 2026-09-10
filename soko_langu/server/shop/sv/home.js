/* Soko Vibe — Phase 1 home page (hero + categories + deals + feed + sellers).
   Renders into the global `view` element; the main product grid reuses
   feedRegion so the app's existing pagination (sentinel / load more) works. */
(function () {
  const C = window.SV.components;
  const { icon, svCard, skel, sectionHead } = C;

  function heroHtml() {
    return '<section class="sv-hero">'
      + '<div class="sv-hero-copy">'
      + '<span class="sv-kicker">' + esc(t('sv_kicker')) + '</span>'
      + '<h1>' + t('sv_hero_title') + '</h1>'
      + '<p>' + esc(t('sv_hero_sub')) + '</p>'
      + '<div class="sv-hero-cta">'
      + '<a class="sv-btn sv-btn-amber" href="#/">' + esc(t('sv_cta_buy')) + '</a>'
      + '<a class="sv-btn sv-btn-ghost" href="#/seller">' + esc(t('sv_cta_sell')) + '</a>'
      + '</div></div>'
      + '<div class="sv-hero-media" id="svHeroMedia">' + skel(4) + '</div>'
      + '</section>';
  }

  function catGridHtml() {
    const cats = browseCats();
    const tiles = cats.slice(0, 12).map((c) => {
      const count = Feed.list.filter((p) => catMatch(p, c)).length;
      return '<a class="sv-cat-tile" href="#/c/' + encodeURIComponent(c) + '">'
        + '<span class="sv-cat-ic">' + icon('box') + '</span>'
        + '<span class="sv-cat-name">' + esc(c) + '</span>'
        + (count ? '<span class="sv-cat-count">' + count + ' ' + esc(t('sv_items')) + '</span>' : '')
        + '</a>';
    }).join('');
    return '<section class="sv-section">' + sectionHead(t('sv_categories'), t('sv_categories_sub')) + '<div class="sv-cat-grid">' + tiles + '</div></section>';
  }

  function dealsHtml() {
    return '<section class="sv-section" id="svDealsSection">'
      + sectionHead(t('sv_deals'), t('sv_deals_sub'), '#/flash', t('sv_view_all'))
      + '<div class="sv-row sv-row-4" id="svDealsRow">' + skel(4) + '</div>'
      + '</section>';
  }

  function sellerStripHtml() {
    return '<section class="sv-section" id="svSellerSection">'
      + sectionHead(t('sv_sellers'), t('sv_sellers_sub'))
      + '<div class="sv-seller-strip" id="svSellerRow">' + skel(1) + '</div>'
      + '</section>';
  }

  function trustHtml() {
    const items = [
      ['shield', t('trust_escrow'), t('sv_trust_escrow_p')],
      ['check', t('trust_verified'), t('sv_trust_verified_p')],
      ['bolt', t('trust_clickpesa'), t('sv_trust_clickpesa_p')],
      ['truck', t('trust_delivery'), t('sv_trust_delivery_p')],
    ].map((it) => '<div class="sv-trust-item"><span class="sv-trust-ic">' + icon(it[0]) + '</span>'
      + '<div><b>' + esc(it[1]) + '</b><span>' + esc(it[2]) + '</span></div></div>').join('');
    return '<section class="sv-section"><div class="sv-trust-grid">' + items + '</div></section>';
  }

  function sellerCtaHtml() {
    return '<section class="sv-seller-cta">'
      + '<div><h3>' + esc(t('sv_seller_cta_t')) + '</h3><p>' + esc(t('sv_seller_cta_p')) + '</p></div>'
      + '<a class="sv-btn sv-btn-amber" href="#/seller">' + esc(t('sv_seller_cta_btn')) + '</a>'
      + '</section>';
  }

  function paintHeroMedia() {
    const host = document.getElementById('svHeroMedia');
    if (!host) return;
    const picks = sortFeed(Feed.list).slice(0, 4);
    if (!picks.length) { host.innerHTML = skel(4); return; }
    host.innerHTML = picks.map((p) => '<div class="sv-hero-tile">'
      + (p.images && p.images[0]
        ? '<img loading="lazy" src="' + esc(p.images[0]) + '" alt="' + esc(p.name) + '" onerror="this.parentElement.innerHTML=\'<div class=&quot;sv-ph&quot;>SOKO</div>\'">'
        : '<div class="sv-ph">SOKO</div>')
      + '<span>' + esc(p.name) + '</span></div>').join('');
  }

  function paintDeals() {
    const host = document.getElementById('svDealsRow');
    if (!host) return;
    let deals = Feed.list.filter((p) => discount(p) && p.stock > 0);
    if (deals.length < 4) deals = sortFeed(Feed.list).slice(0, 4);
    const picks = deals.slice(0, 4);
    host.innerHTML = picks.length ? picks.map(svCard).join('') : '';
    const sec = document.getElementById('svDealsSection');
    if (sec && !picks.length) sec.style.display = 'none';
  }

  function paintSellers() {
    const host = document.getElementById('svSellerRow');
    if (!host) return;
    const seen = {};
    const verified = Feed.list.filter((p) => p.sellerKycApproved && p.sellerName);
    const fill = verified.length >= 2 ? verified : Feed.list.filter((p) => p.sellerName);
    const picks = fill.filter((p) => { if (seen[p.sellerName]) return false; seen[p.sellerName] = 1; return true; }).slice(0, 8);
    const sec = document.getElementById('svSellerSection');
    if (!picks.length) { if (sec) sec.style.display = 'none'; return; }
    host.innerHTML = picks.map((p) => '<span class="sv-seller-pill">'
      + '<span class="sv-seller-av">' + esc((p.sellerName || '?').charAt(0).toUpperCase()) + '</span>'
      + '<span>' + esc(p.sellerName) + '</span>'
      + (p.sellerKycApproved ? C.verified(p) : '')
      + '</span>').join('');
    if (sec) sec.style.display = '';
  }

  function paintDynamic() {
    paintHeroMedia();
    paintDeals();
    paintSellers();
  }

  async function renderHome() {
    setLang();
    document.title = (lang === 'sw' ? 'Soko Vibe — Nunua Mtandaoni Tanzania' : 'Soko Vibe — Shop Online in Tanzania') + ' | Soko Vibe';
    document.body.dataset.route = 'home';
    Feed.idx = PAGE;
    Feed.mode = { kind: 'all' };
    setHero(true);
    paintActiveCat();

    const si = document.getElementById('searchInput');
    if (si) si.value = '';
    const sel = document.getElementById('catSelect');
    if (sel) sel.value = '';

    view.innerHTML = heroHtml()
      + catGridHtml()
      + dealsHtml()
      + feedRegion(t('feed_new'), t('home_hero_sub'), chipsFor(''))
      + trustHtml()
      + sellerCtaHtml();

    if (Feed.list.length) {
      paintDynamic();
      renderFeed();
      return;
    }
    await loadPageInto();
    if (document.body.dataset.route !== 'home') return;
    paintDynamic();
  }

  window.SV = window.SV || {};
  window.SV.home = { render: renderHome };
})();