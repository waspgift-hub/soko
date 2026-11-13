'use strict';

const { t, icon } = require('../core');
const { pageMeta, layout } = require('../components');
const seo = require('../seo');

function notFoundPage() {
  const title = 'Ukurasa Haupatikani | Page not found — Soko Vibe';
  const description = 'Ukurasa huu haupatikani. Rudi mwanzo au chunguza kurasa za Soko Vibe.';
  const meta = pageMeta({
    title,
    description,
    path: '/404',
    noindex: true,
    jsonLd: [],
  });

  const body = `<section class="sv-success">
  <div class="sv-container sv-success__inner">
    <span class="sv-success__mark sv-success__mark--muted">${icon('search')}</span>
    ${t('p', 'Hitilafu 404', 'Error 404', { class: 'sv-eyebrow' })}
    ${t('h1', 'Ukurasa huu haupatikani.', 'This page could not be found.', { class: 'sv-h1' })}
    ${t('p', 'Kiungo kinaweza kuwa cha zamani au kimeandikwa vibaya. Haya ni kurasa zinazoweza kukusaidia.', 'The link may be old or mistyped. These pages should help.', { class: 'sv-lead sv-lead--lg' })}
    <div class="sv-actions sv-actions--center">
      <a class="sv-btn sv-btn--primary" href="/" data-en="Back to home">Rudi mwanzo</a>
      <a class="sv-btn sv-btn--ghost" href="/features" data-en="Explore features">Chunguza vipengele</a>
      <a class="sv-btn sv-btn--ghost" href="/contact" data-en="Contact us">Wasiliana nasi</a>
    </div>
    <div class="sv-success__steps">
      <div><b>1</b><h2 data-en="Product">Bidhaa</h2><p><a href="/how-it-works" data-en="How it works">Jinsi inavyofanya kazi</a></p></div>
      <div><b>2</b><h2 data-en="Pricing">Bei</h2><p><a href="/pricing" data-en="See plans and pricing">Ona mipango na bei</a></p></div>
      <div><b>3</b><h2 data-en="Questions">Maswali</h2><p><a href="/faq" data-en="Read the FAQ">Soma maswali</a></p></div>
    </div>
    <p class="sv-muted">${t('span', 'Bado umekwama? Andika kwa support@sokovibe.co.tz.', 'Still stuck? Write to support@sokovibe.co.tz.')}</p>
  </div>
</section>`;

  return { file: '404.html', html: layout({ meta, active: '', body }) };
}

module.exports = { notFoundPage };
