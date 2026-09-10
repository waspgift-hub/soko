/* Soko Vibe — cart page (dense, spec-style). Overrides renderCart with a
   two-panel layout. Action contracts (cqplus/cqminus/cartrm/ckcart) and the
   money path are untouched. */
(function () {
  async function renderCart() {
    setLang();
    setHero(false);
    if (!cart.length) {
      view.innerHTML = '<div class="container-wide">' + emptyHtml(t('cart_empty'), '', t('cart_browse'))
        + '<div class="sv-empty-cats">' + chipsFor('') + '</div>'
        + '<div class="sv-cart-foot"><a class="sv-btn sv-btn-dark" href="#/">' + esc(t('sv_continue')) + '</a></div>'
        + '</div>';
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
      + '<span class="section-title">' + esc(t('cart_title')) + ' <span class="sv-sr-count">(' + cartQty() + ')</span></span></div>'
      + '<div class="cart-grid"><div class="cart-list">';

    for (const [seller, lines] of groups) {
      const sub = lines.reduce((s, it) => s + (Number(it.line.u) || 0) * Number(it.line.q || 0), 0);
      html += '<div class="cart-group"><div class="ghead">' + SELLER_SEAL + '<span>' + t('cart_seller') + ': ' + esc(seller) + '</span>'
        + '<b class="gsub">' + esc(t('sv_group_subtotal')) + ': ' + fmtTZS(sub) + '</b></div>';
      for (const it of lines) {
        const p = it.prod;
        const img = it.line.img || (p && p.images[0]) || '';
        const unit = Number(it.line.u) || 0;
        const oldP = p && discount(p) && p.price > unit ? p.price : 0;
        html += '<div class="cart-item">'
          + '<div class="thumb">' + (img ? '<img src="' + esc(img) + '" alt="" loading="lazy" onerror="this.remove()">' : '') + '</div>'
          + '<div class="mid">'
          + '<div class="nm">' + esc(it.line.n || (p && p.name) || '') + '</div>'
          + (p && p.sellerKycApproved
            ? '<div class="sv-seller">' + C.verified(p) + '<span>Muuzaji aliyethibitishwa</span></div>' : '')
          + '<div class="pr">' + fmtTZS(unit) + (oldP ? ' <del class="sv-old">' + fmtTZS(oldP) + '</del>' : '') + '</div>'
          + '</div>'
          + '<div class="ctrls">'
          + '<div class="stepper">'
          + '<button data-act="cqminus" data-p="' + esc(it.line.p) + '" data-v="' + esc(it.line.v || '') + '" aria-label="Punguza">−</button>'
          + '<span class="n">' + it.line.q + '</span>'
          + '<button data-act="cqplus" data-p="' + esc(it.line.p) + '" data-v="' + esc(it.line.v || '') + '" aria-label="Ongeza">+</button>'
          + '</div>'
          + '<button class="rm" data-act="cartrm" data-p="' + esc(it.line.p) + '" data-v="' + esc(it.line.v || '') + '">' + t('remove') + '</button>'
          + '</div></div>';
      }
      html += '</div>';
    }
    html += '</div>'
      + '<aside class="checkout-bar"><h3>' + t('cart_total') + '</h3>'
      + '<div class="sum-row"><span>' + t('cart_items') + '</span><span>' + cartQty() + '</span></div>'
      + '<div class="sum-row"><span>' + t('cart_fee') + '</span><span>Escrow</span></div>'
      + '<div class="sum-row strong"><span>' + t('cart_total') + '</span><span>' + fmtTZS(tot) + '</span></div>'
      + '<div class="sec-note">' + window.SV.components.icon('shield')
      + '<span>' + t('escrow_note') + '</span></div>'
      + '<button class="btn-accent btn-block mt16" data-act="ckcart" type="button">' + t('cart_checkout') + ' · ' + fmtTZS(tot) + '</button>'
      + '</aside></div>'
      + '<div class="sv-cart-foot"><a class="mini-link" href="#/">← ' + esc(t('sv_continue')) + '</a></div>'
      + '</div>';
    view.innerHTML = html;
  }

  const C = window.SV.components;
  window.renderCart = renderCart;
})();