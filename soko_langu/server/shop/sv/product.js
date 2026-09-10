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
  }

  async function wrapped(id) {
    if (ORIG) await ORIG(id);
    const p = (window.__pCtx && window.__pCtx.p) || null;
    const dinfo = document.querySelector('.detail .dinfo');
    if (dinfo && !dinfo.querySelector('.sv-trust-mini')) {
      dinfo.insertAdjacentHTML('beforeend', trustRow(p || {}));
      if (p) dinfo.insertAdjacentHTML('beforeend', delRow(p));
    }
    await related(p, id);
  }

  window.renderProduct = wrapped;
})();