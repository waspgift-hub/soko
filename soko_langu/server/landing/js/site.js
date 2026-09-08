(function () {
  'use strict';

  var year = document.getElementById('year');
  if (year) year.textContent = new Date().getFullYear();

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

  if ('IntersectionObserver' in window && !window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
    var items = document.querySelectorAll('[data-reveal]');
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          entry.target.classList.add('in');
          io.unobserve(entry.target);
        }
      });
    }, { threshold: 0.12 });
    items.forEach(function (el) { io.observe(el); });
  } else {
    document.querySelectorAll('[data-reveal]').forEach(function (el) { el.classList.add('in'); });
  }
})();