/* Soko Vibe - public seller storefront (#/store/:uid). Browse a single
   seller's products; reuses the already-loaded Feed so no extra query. */
(function () {
  const C = window.SV.components;
  const { icon, svCard, skel, empty } = C;
  const CHAT_ICON = '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/></svg>';

  async function render(uid) {
    setLang();
    document.body.dataset.route = 'store';
    Feed.mode = { kind: 'store', uid };
    view.innerHTML = '<section class="sv-store">' + skel(6) + '</section>';

    let guard = 0;
    while (!Feed.done && Feed.list.length < 240 && guard < 14) { await loadPageInto(); guard++; }
    document.body.dataset.route = 'store';

    const list = Feed.list.filter((p) => p.sellerId === uid);
    const info = list.length
      ? { name: list[0].sellerName || 'Muuzaji', verified: !!list[0].sellerKycApproved, region: list[0].location || '' }
      : null;

    const head = '<div class="sv-store-head">'
      + '<div class="sv-store-av">' + icon('store') + '</div>'
      + '<div class="sv-store-meta"><h1>' + esc(info ? info.name : 'Kibanda') + '</h1>'
      + '<div class="sv-store-sub">'
      + (info && info.verified ? '<span class="sv-ver">' + icon('check') + esc(t('sv_ver_seller')) + '</span>' : '')
      + (info && info.region ? '<span>' + esc(info.region) + '</span>' : '')
      + '<span class="sv-store-count">' + list.length + ' ' + esc(t('sv_items')) + '</span>'
      + '</div></div>'
      + '<div class="sv-store-cta">'
      + '<button type="button" class="sv-btn sv-btn-outline sv-store-msg" data-act="msgstore" data-u="' + esc(uid) + '" data-n="' + esc(info ? info.name : '') + '">' + CHAT_ICON + esc(t('sv_msg_seller')) + '</button>'
      + '</div></div>';

    const body = list.length
      ? '<div class="sv-section-head"><h2 class="sv-section-title">' + esc(t('sv_store_products')) + '</h2></div>'
        + '<div class="grid">' + list.map(svCard).join('') + '</div>'
      : empty(t('sv_no_products'), t('sv_try_diff'), t('sv_back_home'));

    view.innerHTML = '<section class="sv-store">' + head + body + '</section>';
    document.title = (info ? info.name : 'Kibanda') + ' | Soko Vibe';
  }

  window.SV = window.SV || {};
  window.SV.store = { render };
})();