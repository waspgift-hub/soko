/* Soko Vibe — product page upgrades. Wraps the original renderProduct
   (app.js) and appends a trust mini-row, a delivery estimate and a related
   products rail. The original gallery / variants / qty / add-to-cart /
   buy-now / reviews wiring is untouched. */
(function () {
  const C = window.SV.components;
  const ORIG = window.renderProduct;

  function trustRow(p) {
    const items = [
      ['shield', t('trust_escrow')],
      ['check', p.sellerKycApproved ? t('trust_verified') : t('trust_payments')],
      ['bolt', t('trust_clickpesa')],
      ['truck', t('trust_delivery')],
    ];
    return '<div class="sv-trust-mini">' + items.map((it) => '<span>' + C.icon(it[0]) + esc(it[1]) + '</span>').join('') + '</div>';
  }

  function delRow(p) {
    return '<div class="sv-delrow">' + C.icon('pin')
      + '<span>' + esc(p.location || 'Tanzania') + (p.district ? ' · ' + esc(p.district) : '') + '</span>'
      + '<b>·</b>'
      + '<b>' + esc(t('sv_del_ests')) + '</b>'
      + '</div>';
  }

  function stickyBar(p) {
    const soldout = p.stock <= 0;
    return '<div class="sv-buysticky" aria-label="Nunua">'
      + '<div class="sv-buyp"><span class="sv-buyp-lab">' + esc(t('qty')) + '</span>'
      + '<div class="stepper sv-stepper"><button type="button" data-act="qminus" aria-label="-">−</button>'
      + '<span class="n" id="qtyN2">1</span><button type="button" data-act="qplus" aria-label="+">+</button></div></div>'
      + '<button class="sv-btn sv-btn-amber" data-act="addcart"' + (soldout ? ' disabled' : '') + '>'
      + '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="8" cy="21" r="1"/><circle cx="19" cy="21" r="1"/><path d="M2.05 2.05h2l2.66 12.42a2 2 0 0 0 2 1.58h9.78a2 2 0 0 0 1.95-1.57l1.65-7.43H5.12"/></svg>'
      + esc(t('add_cart')) + '</button>'
      + '<button class="sv-btn sv-btn-dark" data-act="buynow"' + (soldout ? ' disabled' : '') + '>'
      + esc(t('buy_now')) + '</button>'
      + '</div>';
  }

  function wireStickyQty() {
    const qEl = document.getElementById('qtyN');
    const q2 = document.getElementById('qtyN2');
    if (!qEl || !q2 || !window.MutationObserver) return;
    const sync = () => { const n = document.getElementById('qtyN2'); if (n) n.textContent = qEl.textContent; };
    new MutationObserver(sync).observe(qEl, { childList: true, subtree: true });
  }

  async function related(p, id) {
    const anchor = document.getElementById('revHost');
    if (!anchor || !p) return;
    if (!Feed.list.length) await loadPageInto();
    const picks = Feed.list.filter((x) => x.id !== id && x.category === p.category && x.stock > 0);
    const src = picks.length >= 4 ? picks : Feed.list.filter((x) => x.id !== id && x.stock > 0).sort((a, b) => (b.soldCount || 0) - (a.soldCount || 0)).slice(0, 10);
    const list = (picks.length >= 4 ? picks : src).slice(0, 10);
    if (!list.length) return;
    const viewAll = '#/search?c=' + encodeURIComponent(p.category || '');
    anchor.insertAdjacentHTML('afterend',
      '<section class="sv-related sv-section">'
      + C.sectionHead(t('sv_related'), '', viewAll, t('sv_view_all'))
      + '<div class="sv-rail" data-rail>'
      + list.map(C.svCard).join('')
      + '</div></section>');
    const mine = Feed.list.filter((x) => x.id !== id && x.sellerId && x.sellerId === p.sellerId && x.stock > 0).slice(0, 10);
    if (mine.length >= 2) {
      const storeHref = '#/store/' + encodeURIComponent(p.sellerId);
      anchor.insertAdjacentHTML('afterend',
        '<section class="sv-related sv-section">'
        + C.sectionHead(t('sv_more_seller'), '', storeHref, t('sv_view_all'))
        + '<div class="sv-rail" data-rail>'
        + mine.map(C.svCard).join('')
        + '</div></section>');
    }
  }

  async function wrapped(id) {
    if (ORIG) await ORIG(id);
    const p = (window.__pCtx && window.__pCtx.p) || null;
    const dinfo = document.querySelector('.detail .dinfo');
    if (dinfo && dinfo.querySelector('.price') && !dinfo.querySelector('.sv-trust-mini')) {
      dinfo.querySelector('.price').insertAdjacentHTML('afterend', trustRow(p || {}) + (p ? delRow(p) : ''));
    }
    const detail = document.querySelector('.detail');
    if (detail && p && !detail.querySelector('.sv-buysticky')) {
      detail.insertAdjacentHTML('beforeend', stickyBar(p));
      wireStickyQty();
      document.body.classList.add('sv-has-buysticky');
    }
    await related(p, id);
  }

  window.renderProduct = wrapped;
})();