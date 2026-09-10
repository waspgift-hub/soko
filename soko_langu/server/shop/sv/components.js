/* Soko Vibe — Phase 1 reusable UI components (vanilla, no build step).
   Plain scripts loaded after app.js/parity.js; they reuse the global helpers
   (esc, t, fmtTZS, boosted, featured, discount, wishHas) and keep the exact
   data-act / data-p contracts the app's ACTIONS dispatcher expects. */
(function () {
  const svgNs = 'http://www.w3.org/2000/svg';

  function icon(name, cls) {
    const paths = {
      heart: 'M19 21l-7-4.5L5 21V6a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2z',
      cart: 'M3 3h2l2.5 12.5A2 2 0 0 0 9.5 17h8.9a2 2 0 0 0 1.95-1.55L22 7H6',
      check: 'M20 6L9 17l-5-5',
      search: 'm20 20-3.5-3.5M11 18a7 7 0 1 0 0-14 7 7 0 0 0 0 14z',
      pin: 'M12 21s-7-5.2-7-11a7 7 0 0 1 14 0c0 5.8-7 11-7 11zM12 12.5a2 2 0 1 0 0-4 2 2 0 0 0 0 4z',
      shield: 'M12 2l8 3.5V11c0 5-3.4 8.8-8 11-4.6-2.2-8-6-8-11V5.5zM9 12l2 2 4-4',
      truck: 'M2 7h11v10H2zM13 11h4l3 3v3h-7zM6 19a2 2 0 1 0 4 0 2 2 0 0 0-4 0zM16 19a2 2 0 1 0 4 0 2 2 0 0 0-4 0z',
      box: 'M21 8l-9-5-9 5v8l9 5 9-5V8zM3 8l9 5 9-5M12 13v8',
      store: 'M3 9l1-5h16l1 5M4 9v11h16V9M9 20v-6h6v6',
      star: 'M12 2l2.9 6.3 6.9.6-5.2 4.6 1.6 6.8L12 17.3l-6.2 3.6 1.6-6.8L2.2 9l6.9-.6z',
      filter: 'M22 3H2l8 9v7l4 2v-9z',
      grid: 'M3 3h8v8H3zM13 3h8v8h-8zM3 13h8v8H3zM13 13h8v8h-8z',
      list: 'M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01',
      bolt: 'M13 2L3 14h9l-1 8 10-12h-9l1-8z',
      user: 'M12 8a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM4 21c0-4 3.6-6 8-6s8 2 8 6',
      tag: 'M20 4H10L4 10l10 10 10-10V4zM7 8a1 1 0 1 0 0-2 1 1 0 0 0 0 2z',
    };
    const d = paths[icon] || paths.star;
    return '<svg' + (cls ? ' class="' + cls + '"' : '') + ' viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="' + d + '"/></svg>';
  }

  function ratingHtml(p) {
    const r = Number(p.rating) || 0;
    if (r <= 0) return '';
    const pct = Math.max(0, Math.min(100, (r / 5) * 100));
    const row = '<span class="sv-stars" aria-hidden="true"><span class="sv-stars-bg">★★★★★</span>'
      + '<span class="sv-stars-fill" style="width:' + pct + '%">★★★★★</span></span>';
    return '<span class="sv-rating" title="' + r + ' / 5">' + row + '<b>' + r.toFixed(1) + '</b>'
      + '<i>(' + (Number(p.reviewCount) || 0) + ')</i></span>';
  }

  function verified(p) {
    return p.sellerKycApproved
      ? '<span class="sv-ver" title="Muuzaji aliyethibitishwa (KYC)">' + icon('check') + '</span>'
      : '';
  }

  /* Conversion-focused product card. Keeps the .card class so legacy CSS and
     the app's event delegation keep working; new markup is styled by theme.css. */
  function svCard(p) {
    const id = encodeURIComponent(p.id);
    const img = p.images && p.images[0] ? p.images[0] : '';
    const dc = discount(p);
    const bo = boosted(p);
    const soldout = p.stock <= 0;
    const old = p.isWholesale && p.wholesaleTiers && p.wholesaleTiers.length
      ? '<del class="sv-old">' + fmtTZS(p.wholesaleTiers[0].pricePerUnit) + '</del>'
      : '';
    const favCls = 'sv-fav' + (wishHas(p.id) ? ' onfav' : '');
    const flag = bo ? '<span class="sv-flag">' + esc(bo) + '</span>' : '';
    const disc = dc ? '<span class="sv-badge-note">−' + dc + '%</span>' : '';
    const soldov = soldout ? '<span class="sv-soldov">' + esc(t('soldout_ov')) + '</span>' : '';
    const catTag = p.category ? '<span class="sv-cat-tag">' + esc(p.category) + '</span>' : '';
    const foot = soldout
      ? '<span class="sv-note-danger">' + esc(t('out_stock')) + '</span>'
      : '<button class="sv-qadd" data-act="qaddcart" data-p="' + id + '" type="button" title="' + esc(t('add_cart')) + '" aria-label="' + esc(t('add_cart')) + '">' + icon('cart') + '</button>'
        + '<button class="sv-qbuy" data-act="qbuynow" data-p="' + id + '" type="button">' + esc(t('sv_buy')) + '</button>';

    return '<div class="card sv-card" data-act="openprod" data-p="' + id + '" role="link" tabindex="0" aria-label="' + esc(p.name) + '">'
      + '<div class="sv-thumb">' + disc + flag + catTag
      + '<button class="' + favCls + '" data-act="fav" data-p="' + id + '" type="button" aria-label="' + esc(t('nav_wish')) + '">' + icon('heart') + '</button>'
      + (img
        ? '<img loading="lazy" src="' + esc(img) + '" alt="' + esc(p.name) + '" onerror="this.parentElement.classList.add(\'sv-badimg\');this.remove()">'
        : '<div class="sv-ph">SOKO</div>')
      + soldov + '</div>'
      + '<div class="sv-body">'
      + '<h3 class="sv-title">' + esc(p.name) + ' ' + verified(p) + '</h3>'
      + '<div class="sv-price"><b>' + fmtTZS(p.price) + '</b>' + old + '</div>'
      + '<div class="sv-meta">' + ratingHtml(p) + (Number(p.soldCount) ? '<span class="sv-sold">' + (Number(p.soldCount) || 0) + ' ' + esc(t('sold')) + '</span>' : '') + '</div>'
      + '<div class="sv-seller">' + icon('store') + '<span>' + esc(p.sellerName || 'Muuzaji') + '</span>' + verified(p) + '</div>'
      + '<div class="sv-foot">' + foot + '</div>'
      + '</div></div>';
  }

  function skel(n, pro) {
    let s = '';
    for (let i = 0; i < (n || 8); i++) {
      s += '<div class="card sv-card"><div class="sv-thumb"><div class="skel" style="position:absolute;inset:0;border-radius:0"></div></div>'
        + '<div class="sv-body">'
        + '<div class="skel" style="height:10px;width:38%"></div>'
        + '<div class="skel" style="height:14px;width:88%;margin-top:8px"></div>'
        + '<div class="skel" style="height:16px;width:46%;margin-top:10px"></div>'
        + '<div class="skel" style="height:12px;width:60%;margin-top:10px"></div>'
        + '<div class="skel" style="height:38px;width:100%;margin-top:12px"></div>'
        + '</div></div>';
    }
    return s;
  }

  function empty(msg, sub, ctaLabel) {
    return '<div class="sv-empty">'
      + '<div class="sv-empty-ic">' + icon('box') + '</div>'
      + (msg ? '<h3>' + esc(msg) + '</h3>' : '')
      + (sub ? '<p>' + esc(sub) + '</p>' : '')
      + (ctaLabel ? '<div class="sv-empty-reco" style="margin-top:16px"><a class="sv-btn sv-btn-outline" href="#/">' + esc(ctaLabel) + '</a></div>' : '')
      + '</div>';
  }

  function sectionHead(title, sub, moreHref, moreLabel) {
    return '<div class="sv-section-head">'
      + '<div><h2 class="sv-section-title">' + esc(title) + '</h2>' + (sub ? '<div class="sv-section-sub">' + esc(sub) + '</div>' : '') + '</div>'
      + (moreHref && moreLabel ? '<a class="sv-section-more" href="' + moreHref + '">' + esc(moreLabel) + '</a>' : '')
      + '</div>';
  }

  window.SV = window.SV || {};
  window.SV.components = { icon, svCard, skel, empty, sectionHead, ratingHtml, verified };
})();