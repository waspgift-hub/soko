(function () {
  'use strict';
  var path = window.location.pathname;
  var home = path === '/' || path === '/index.html';
  var header = document.querySelector('.site-header, header.site, body > header');
  var shell = '<header class="site-header"><div class="container nav-bar" id="nav-bar"><a class="brand" href="/" aria-label="SokoVibe mwanzo"><img class="brand-mark" src="/assets/icon-192.png?v=2" alt="" width="34" height="34"><span class="brand-name">SokoVibe</span></a><nav class="nav-links" id="site-nav" aria-label="Menyu"><a href="/">Mwanzo</a><a href="/about">Kuhusu</a><a href="/categories">Kategoria</a><a href="/support">Msaada</a></nav><a class="nav-cta" href="/#launch-signup">Taarifa za uzinduzi</a><button class="menu-btn" type="button" aria-label="Fungua menyu" aria-expanded="false" aria-controls="site-nav"><span class="menu-line"></span><span class="menu-line"></span><span class="menu-line"></span></button></div></header>';
  if (header) header.outerHTML = shell; else document.body.insertAdjacentHTML('afterbegin', shell);

  var footer = '<footer class="site-footer"><div class="container footer-inner"><a class="footer-brand" href="/">SokoVibe</a><p>Soko la Tanzania. Tunajiandaa kuzindua.</p><div class="footer-links"><a href="/about">Kuhusu</a><a href="/categories">Kategoria</a><a href="/support">Msaada</a><a href="/privacy-policy">Faragha</a><a href="/terms-of-service">Masharti</a></div><div class="footer-bottom"><span>© ' + new Date().getFullYear() + ' SokoVibe</span><a href="mailto:support@sokovibe.co.tz">support@sokovibe.co.tz</a></div></div></footer>';
  var oldFooter = document.querySelector('footer');
  if (oldFooter) oldFooter.outerHTML = footer; else document.body.insertAdjacentHTML('beforeend', footer);

  if (!home && !document.querySelector('[data-waitlist-form]')) {
    var signup = '<section class="section launch-bottom shared-signup" id="launch-signup"><div class="container"><p class="section-eyebrow">TAARIFA ZA UZINDUZI</p><h2>Uwe wa kwanza kujua.</h2><p>Jiunge na orodha yetu ili upokee taarifa SokoVibe itakapozinduliwa.</p><form class="waitlist-form" data-waitlist-form><label class="sr-only" for="launch-email">Barua pepe</label><input id="launch-email" name="email" type="email" autocomplete="email" maxlength="254" placeholder="Barua pepe yako" required><label class="consent"><input type="checkbox" name="consent" required> Nakubali kupokea taarifa ya uzinduzi kupitia barua pepe.</label><button class="btn btn-green" type="submit">Jiunge na orodha</button><p class="form-status" role="status" aria-live="polite"></p></form><p class="privacy-note">Tutatumia barua pepe yako kwa taarifa za uzinduzi pekee. <a href="/privacy-policy">Sera ya faragha</a>.</p></div></section>';
    var f = document.querySelector('footer');
    if (f) f.insertAdjacentHTML('beforebegin', signup);
  }

  var bar = document.getElementById('nav-bar');
  var btn = document.querySelector('.menu-btn');
  if (btn && bar) {
    btn.addEventListener('click', function () {
      var open = bar.classList.toggle('open');
      btn.setAttribute('aria-expanded', open ? 'true' : 'false');
    });
    bar.querySelectorAll('a').forEach(function (link) {
      link.addEventListener('click', function () {
        bar.classList.remove('open');
        btn.setAttribute('aria-expanded', 'false');
      });
    });
  }

  document.querySelectorAll('[data-waitlist-form]').forEach(function (form) {
    form.addEventListener('submit', async function (event) {
      event.preventDefault();
      var email = form.elements.email.value.trim();
      var consent = form.elements.consent.checked;
      var button = form.querySelector('button[type="submit"]');
      var status = form.querySelector('.form-status');
      if (!consent) { status.textContent = 'Tafadhali kubali kupokea taarifa ya uzinduzi.'; return; }
      button.disabled = true;
      button.textContent = 'Inahifadhi...';
      status.textContent = '';
      try {
        var response = await fetch('/api/launch-waitlist', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ email: email, consent: true, source: window.location.pathname })
        });
        var data = await response.json();
        if (!response.ok) throw new Error(data.error || 'Imeshindikana kuhifadhi barua pepe.');
        status.textContent = data.alreadySubscribed ? 'Barua pepe hii tayari ipo kwenye orodha yetu.' : 'Asante! Utapokea taarifa SokoVibe itakapozinduliwa.';
        form.reset();
      } catch (error) {
        status.textContent = error.message || 'Hitilafu imetokea. Tafadhali jaribu tena.';
      } finally {
        button.disabled = false;
        button.textContent = 'Jiunge na orodha';
      }
    });
  });

  if ('IntersectionObserver' in window && !window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
    var items = document.querySelectorAll('[data-reveal]');
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) { entry.target.classList.add('in'); io.unobserve(entry.target); }
      });
    }, { threshold: 0.12 });
    items.forEach(function (el) { io.observe(el); });
  }
})();