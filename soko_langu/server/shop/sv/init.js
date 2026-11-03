/* Soko Vibe - Phase 1 wiring. Loaded last: installs the new renders over the
   app's function declarations (lookup stays dynamic in route()), seeds the
   mobile category scroller, and wires the mobile search/lang toggles. */
(function () {
  function install() {
    window.renderHome = window.SV.home.render;
    window.renderSearch = window.SV.search.render;
    window.enhanceSuggest = window.SV.search.suggest;
    window.cardHtml = (p) => window.SV.components.svCard(p);

    const mc = document.getElementById('svMobileCats');
    if (mc) {
      const links = ['<a class="sv-mcat on" href="#/">' + esc(t('all')) + '</a>']
        .concat(browseCats().map((c) => '<a class="sv-mcat" href="#/c/' + encodeURIComponent(c) + '">' + esc(c) + '</a>'));
      mc.innerHTML = links.join('');
    }

    const langBtn = document.getElementById('svLangBtn');
    if (langBtn) {
      langBtn.textContent = lang === 'sw' ? 'EN' : 'SW';
      langBtn.addEventListener('click', () => {
        lang = lang === 'sw' ? 'en' : 'sw';
        localStorage.setItem('sv_shop_lang', lang);
        document.documentElement.lang = lang;
        const si = document.getElementById('searchInput');
        if (si) si.placeholder = t('search_ph');
        langBtn.textContent = lang === 'sw' ? 'EN' : 'SW';
        mc.innerHTML = ['<a class="sv-mcat on" href="#/">' + esc(t('all')) + '</a>']
          .concat(browseCats().map((c) => '<a class="sv-mcat" href="#/c/' + encodeURIComponent(c) + '">' + esc(c) + '</a>')).join('');
        route();
      });
    }

    const msearch = document.getElementById('svMobileSearchT');
    if (msearch) {
      msearch.addEventListener('click', () => {
        const form = document.getElementById('searchForm');
        if (!form) return;
        form.classList.toggle('sv-expanded');
        msearch.setAttribute('aria-expanded', form.classList.contains('sv-expanded') ? 'true' : 'false');
        if (form.classList.contains('sv-expanded')) setTimeout(() => {
          const i = document.getElementById('searchInput');
          if (i) i.focus();
        }, 60);
      });
    }
  }

  document.addEventListener('change', (e) => {
    if (e.target && e.target.id === 'sortSel') {
      Feed.sort = e.target.value;
      if (typeof renderFeed === 'function') renderFeed();
    }
  });

  install();

  window.SV.init = install;
})();