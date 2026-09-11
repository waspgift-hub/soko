/* Soko Vibe — marketplace home (compact promo + category rail + rails +
   all-products feed). Renders into the global `view` element; the feed
   reuses feedRegion so the app's existing pagination keeps working. */
(function () {
  const C = window.SV.components;
  const { icon, svCard, skel, sectionHead } = C;

  function promoHtml() {
    return '<section class="sv-promo" aria-label="Matangazo">'
      + '<div class="sv-promo-copy">'
      + '<b>' + esc(t('sv_promo_t')) + '</b>'
      + '<p>' + esc(t('sv_promo_p')) + '</p>'
      + '</div>'
      + '<div class="sv-promo-cta">'
      + '<a class="sv-btn sv-btn-promo" href="#/flash">' + esc(t('sv_cta_deals')) + '</a>'
      + '<a class="sv-btn sv-btn-link" href="#/seller">' + esc(t('sv_cta_sell')) + '</a>'
      + '</div>'
      + '</section>';
  }

  function catRailHtml() {
    const cats = browseCats();
    const tiles = cats.slice(0, 10).map((c) => {
      const count = Feed.list.filter((p) => catMatch(p, c)).length;
      return '<a class="sv-cat-tile" href="#/c/' + encodeURIComponent(c) + '">'
        + '<span class="sv-cat-ic">' + icon('box') + '</span>'
        + '<span class="sv-cat-name">' + esc(c) + '</span>'
        + (count ? '<span class="sv-cat-count">' + count + ' ' + esc(t('sv_items')) + '</span>' : '')
        + '</a>';
    }).join('');
    return '<section class="sv-section">' + sectionHead(t('sv_categories'), '') + '<div class="sv-cat-grid" role="list">' + tiles + '</div></section>';
  }

  function railHtml(id, title, moreHref) {
    return '<section class="sv-section" id="' + id + 'Sec">'
      + sectionHead(title, '', moreHref, t('sv_view_all'))
      + '<div class="sv-rail-wrap">'
      + '<button class="sv-rail-arrow prev" type="button" data-rail-prev data-rail="' + id + '" aria-label="Zote zilizopita">'
      + '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><path d="m15 18-6-6 6-6"/></svg></button>'
      + '<div class="sv-rail" data-rail id="' + id + '">' + skel(6) + '</div>'
      + '<button class="sv-rail-arrow next" type="button" data-rail-next data-rail="' + id + '" aria-label="Inayofuata">'
      + '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><path d="m9 18 6-6-6-6"/></svg></button>'
      + '</div></section>';
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

  function paintRail(id, picks) {
    const host = document.getElementById(id);
    if (!host) return;
    const sec = document.getElementById(id + 'Sec');
    if (!picks.length) { if (sec) sec.style.display = 'none'; return; }
    host.innerHTML = picks.map(svCard).join('');
    if (sec) sec.style.display = '';
  }

  function paintRails() {
    const list = Feed.list;

    let deals = list.filter((p) => discount(p) && p.stock > 0);
    if (deals.length < 4) deals = sortFeed(list);
    paintRail('svDealsRow', deals.slice(0, 10));

    const best = list.slice().filter((p) => p.stock > 0).sort((a, b) => (b.soldCount || 0) - (a.soldCount || 0));
    paintRail('svBestRow', (best[0] && best[0].soldCount ? best : sortFeed(list)).slice(0, 10));

    paintRail('svNewRow', list.slice(0, 10));
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
    host.innerHTML = picks.map((p) => '<a class="sv-seller-pill" href="#/store/' + encodeURIComponent(p.sellerId) + '" title="' + esc(t('sv_store_products')) + '">'
      + '<span class="sv-seller-av">' + esc((p.sellerName || '?').charAt(0).toUpperCase()) + '</span>'
      + '<span>' + esc(p.sellerName) + '</span>'
      + (p.sellerKycApproved ? C.verified(p) : '')
      + '</a>').join('');
    if (sec) sec.style.display = '';
  }

  function wireRails() {
    document.querySelectorAll('[data-rail-prev], [data-rail-next]').forEach((btn) => {
      btn.addEventListener('click', () => {
        const rail = document.querySelector('[data-rail="' + btn.dataset.rail + '"]');
        if (!rail) return;
        rail.scrollBy({ left: btn.dataset.railPrev ? -rail.clientWidth * 0.8 : rail.clientWidth * 0.8, behavior: 'smooth' });
      });
    });
  }

  function paintDynamic() {
    paintRails();
    paintSellers();
    wireRails();
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

    view.innerHTML = promoHtml()
      + trustHtml()
      + catRailHtml()
      + railHtml('svDealsRow', t('sv_deals'), '#/flash')
      + railHtml('svBestRow', t('sv_best'))
      + sellerCtaHtml()
      + feedRegion(t('feed_all'), t('home_hero_sub'), chipsFor(''));

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