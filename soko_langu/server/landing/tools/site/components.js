'use strict';

const { SITE, esc, attrs, t, tr, icon, logo, NAV } = require('./core');

function langSwitch(id, compact = false) {
  return `<div class="sv-lang" role="group" aria-label="Lugha" data-en-aria-label="Language"${compact ? ' data-lang-compact' : ''}>
    <button type="button" class="sv-lang__btn is-active" data-lang-switch="sw" aria-pressed="true" lang="sw">SW</button>
    <span class="sv-lang__sep" aria-hidden="true">/</span>
    <button type="button" class="sv-lang__btn" data-lang-switch="en" aria-pressed="false" lang="en">EN</button>
  </div>`;
}

function header(active) {
  const links = NAV.map((item) => {
    const current = item.href === active ? ' aria-current="page"' : '';
    return `<a class="sv-nav__link" href="${item.href}"${current} data-en="${esc(item.en)}">${esc(item.sw)}</a>`;
  }).join('\n        ');

  return `<a class="sv-skip" href="#main" data-en="Skip to content">Nenda kwenye maudhui</a>
<header class="sv-header" data-header>
  <div class="sv-container sv-header__inner">
    ${logo()}
    <nav class="sv-nav" aria-label="Urambazaji mkuu" data-en-aria-label="Main navigation">
        ${links}
    </nav>
    <div class="sv-header__actions">
      ${langSwitch('header')}
      <a class="sv-btn sv-btn--primary sv-btn--sm sv-header__cta" href="/#waitlist" data-en="Join the waitlist">Jiunge na orodha</a>
      <button type="button" class="sv-burger" aria-expanded="false" aria-controls="sv-mobile" aria-label="Fungua menyu" data-en-aria-label="Open menu" data-burger>
        ${icon('menu')}
        ${icon('close', 'sv-burger__close')}
      </button>
    </div>
  </div>
  <div class="sv-mobile" id="sv-mobile" hidden>
    <nav class="sv-mobile__nav" aria-label="Urambazaji wa simu" data-en-aria-label="Mobile navigation">
      ${NAV.map((item) => `<a href="${item.href}"${item.href === active ? ' aria-current="page"' : ''} data-en="${esc(item.en)}">${esc(item.sw)}</a>`).join('\n      ')}
    </nav>
    <div class="sv-mobile__foot">
      ${langSwitch('mobile')}
      <a class="sv-btn sv-btn--primary" href="/#waitlist" data-en="Join the waitlist">Jiunge na orodha</a>
    </div>
  </div>
</header>`;
}

function footer() {
  return `<footer class="sv-footer">
  <div class="sv-container">
    <div class="sv-footer__grid">
      <div class="sv-footer__brand">
        ${logo()}
        <p data-en="A marketplace being built for Tanzania — simpler, safer and more social.">Soko linalojengwa kwa ajili ya Tanzania — rahisi, salama na la kijamii zaidi.</p>
        <p class="sv-footer__status">
          <span class="sv-dot" aria-hidden="true"></span>
          <span data-en="The app is in development. Join the launch list.">App iko kwenye maendeleo. Jiunge na orodha ya uzinduzi.</span>
        </p>
      </div>
      <div class="sv-footer__col">
        <h2 class="sv-footer__title" data-en="Product">Bidhaa</h2>
        <ul>
          <li><a href="/features" data-en="Features">Vipengele</a></li>
          <li><a href="/how-it-works" data-en="How it works">Jinsi inavyofanya kazi</a></li>
          <li><a href="/pricing" data-en="Pricing">Bei</a></li>
          <li><a href="/buyers" data-en="For buyers">Kwa wanunuzi</a></li>
          <li><a href="/sellers" data-en="For sellers">Kwa wauzaji</a></li>
        </ul>
      </div>
      <div class="sv-footer__col">
        <h2 class="sv-footer__title" data-en="Company">Kampuni</h2>
        <ul>
          <li><a href="/about" data-en="About us">Kuhusu sisi</a></li>
          <li><a href="/about/founder" data-en="Founder">Mwanzilishi</a></li>
          <li><a href="/contact" data-en="Contact">Mawasiliano</a></li>
          <li><a href="/faq" data-en="FAQ">Maswali</a></li>
          <li><a href="/data-deletion" data-en="Data deletion">Kufuta data</a></li>
        </ul>
      </div>
      <div class="sv-footer__col">
        <h2 class="sv-footer__title" data-en="Support">Msaada</h2>
        <ul>
          <li><a href="mailto:${SITE.email}">${SITE.email}</a></li>
          <li><a href="https://wa.me/${SITE.phone.replace('+', '')}" rel="noopener" data-en="WhatsApp support">Msaada wa WhatsApp</a></li>
          <li><a href="/privacy" data-en="Privacy policy">Sera ya faragha</a></li>
          <li><a href="/terms" data-en="Terms of use">Masharti ya matumizi</a></li>
          <li><a href="/cookies" data-en="Cookie policy">Sera ya vidakuzi</a></li>
        </ul>
      </div>
    </div>
    <div class="sv-footer__bottom">
      <p>&copy; <span data-year>${new Date().getUTCFullYear()}</span> ${SITE.name}. <span data-en="All rights reserved.">Haki zote zimehifadhiwa.</span></p>
      <p data-en="Built in Tanzania for Tanzania.">Imejengwa Tanzania kwa ajili ya Tanzania.</p>
    </div>
  </div>
</footer>`;
}

function pageMeta({
  title,
  description,
  path,
  ogType = 'website',
  noindex = false,
  jsonLd = [],
  lang = 'sw',
}) {
  const canonical = `${SITE.host}${path === '/' ? '/' : path}`;
  const enUrl = `${canonical}${path.includes('?') ? '&' : '?'}lang=en`;
  const robots = noindex ? 'noindex, nofollow' : 'index, follow, max-image-preview:large';
  const ld = jsonLd.map((obj) => `<script type="application/ld+json">${JSON.stringify(obj)}</script>`).join('\n');

  return `<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>${esc(title)}</title>
<meta name="description" content="${esc(description)}">
<meta name="robots" content="${robots}">
<meta name="theme-color" content="#0A0A0A">
<meta name="color-scheme" content="light">
<link rel="canonical" href="${canonical}">
<link rel="alternate" hreflang="sw-TZ" href="${canonical}">
<link rel="alternate" hreflang="en" href="${enUrl}">
<link rel="alternate" hreflang="x-default" href="${canonical}">
<meta property="og:type" content="${ogType}">
<meta property="og:site_name" content="${SITE.name}">
<meta property="og:locale" content="${lang === 'en' ? 'en_TZ' : 'sw_TZ'}">
<meta property="og:locale:alternate" content="${lang === 'en' ? 'sw_TZ' : 'en_TZ'}">
<meta property="og:url" content="${canonical}">
<meta property="og:title" content="${esc(title)}">
<meta property="og:description" content="${esc(description)}">
<meta property="og:image" content="${SITE.ogImage}">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta property="og:image:alt" content="Soko Vibe — soko la mtandaoni la Tanzania">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="${esc(title)}">
<meta name="twitter:description" content="${esc(description)}">
<meta name="twitter:image" content="${SITE.ogImage}">
<link rel="icon" href="/assets/favicon.ico" sizes="any">
<link rel="icon" type="image/png" sizes="32x32" href="/assets/favicon-32.png">
<link rel="icon" type="image/png" sizes="16x16" href="/assets/favicon-16.png">
<link rel="apple-touch-icon" href="/assets/apple-touch-icon.png">
<link rel="manifest" href="/manifest.json">
<link rel="preload" href="/css/sv.css" as="style">
<link rel="stylesheet" href="/css/sv.css">
${ld}`;
}

function layout({ meta, active, body, scripts = '' }) {
  return `<!DOCTYPE html>
<html lang="sw" data-theme="light">
<head>
${meta}
</head>
<body>
${header(active)}
<main id="main">
${body}
</main>
${footer()}
<div class="sv-toast" role="status" aria-live="polite" aria-atomic="true" data-toast hidden></div>
<script src="/js/sv.js" defer></script>
${scripts}
</body>
</html>
`;
}

function sectionHead({ eyebrow, title, lead, center = false, id }) {
  return `<div class="sv-section__head${center ? ' is-center' : ''}"${id ? ` id="${id}"` : ''}>
    ${eyebrow ? t('p', eyebrow.sw, eyebrow.en, { class: 'sv-eyebrow' }) : ''}
    ${t('h2', title.sw, title.en, { class: 'sv-h2' })}
    ${lead ? t('p', lead.sw, lead.en, { class: 'sv-lead' }) : ''}
  </div>`;
}

function pageHero({ eyebrow, title, lead, actions = '', breadcrumb }) {
  return `<section class="sv-pagehero">
  <div class="sv-container">
    ${breadcrumb ? `<nav class="sv-breadcrumb" aria-label="Breadcrumb"><a href="/" data-en="Home">Mwanzo</a><span aria-hidden="true">/</span><span aria-current="page">${breadcrumb}</span></nav>` : ''}
    ${eyebrow ? t('p', eyebrow.sw, eyebrow.en, { class: 'sv-eyebrow' }) : ''}
    ${t('h1', title.sw, title.en, { class: 'sv-h1' })}
    ${lead ? t('p', lead.sw, lead.en, { class: 'sv-lead sv-lead--lg' }) : ''}
    ${actions ? `<div class="sv-actions">${actions}</div>` : ''}
  </div>
</section>`;
}

function statusBadge(kind) {
  const map = {
    live: { sw: 'Inapatikana', en: 'Available', cls: 'is-live' },
    dev: { sw: 'Inaendelezwa', en: 'In development', cls: 'is-dev' },
    planned: { sw: 'Imepangwa', en: 'Planned', cls: 'is-planned' },
  };
  const item = map[kind] || map.dev;
  return `<span class="sv-badge ${item.cls}" data-en="${item.en}">${item.sw}</span>`;
}

function featureCard({ iconName, title, text, status, href, linkLabel }) {
  return `<article class="sv-card sv-feature">
    <span class="sv-feature__icon">${icon(iconName)}</span>
    <div class="sv-feature__body">
      <div class="sv-feature__top">
        ${t('h3', title.sw, title.en)}
        ${status ? statusBadge(status) : ''}
      </div>
      ${t('p', text.sw, text.en)}
      ${href ? `<a class="sv-link" href="${href}">${t('span', linkLabel.sw, linkLabel.en)} ${icon('arrow', 'sv-icon--sm')}</a>` : ''}
    </div>
  </article>`;
}

function step({ number, iconName, title, text }) {
  return `<li class="sv-step">
    <div class="sv-step__top">
      <span class="sv-step__num" aria-hidden="true">${number}</span>
      <span class="sv-step__icon">${icon(iconName)}</span>
    </div>
    ${t('h3', title.sw, title.en)}
    ${t('p', text.sw, text.en)}
  </li>`;
}

function accordion(items, idPrefix) {
  return `<div class="sv-accordion" data-accordion>
    ${items.map((item, i) => {
      const id = `${idPrefix}-${i + 1}`;
      return `<div class="sv-acc">
      <h3 class="sv-acc__heading">
        <button type="button" class="sv-acc__trigger" aria-expanded="false" aria-controls="${id}" id="${id}-btn">
          <span data-en="${esc(item.en.q)}">${esc(item.sw.q)}</span>
          <span class="sv-acc__chev" aria-hidden="true">${icon('chevron')}</span>
        </button>
      </h3>
      <div class="sv-acc__panel" id="${id}" role="region" aria-labelledby="${id}-btn" hidden>
        <div class="sv-acc__inner">
          ${item.sw.a.startsWith('<') ? item.sw.a : `<p data-en-html="${esc(item.en.a)}">${item.sw.a}</p>`}
        </div>
      </div>
    </div>`;
    }).join('\n')}
  </div>`;
}

function waitlistForm({ id, source, compact = false, title, lead, defaultType = 'buyer' }) {
  return `<form class="sv-waitlist${compact ? ' sv-waitlist--compact' : ''}" data-waitlist novalidate>
  ${title ? t('h3', title.sw, title.en, { class: 'sv-h3' }) : ''}
  ${lead ? t('p', lead.sw, lead.en, { class: 'sv-form__lead' }) : ''}
  <div class="sv-field">
    <label for="${id}-email" data-en="Email address">Barua pepe</label>
    <div class="sv-field__row">
      <input id="${id}-email" name="email" type="email" inputmode="email" autocomplete="email" required
        placeholder="jina@mfano.com" ${tr('you@example.com')} aria-describedby="${id}-help ${id}-status">
      <button class="sv-btn sv-btn--primary" type="submit">
        <span data-en="Notify me when we launch">Nijulishe tutakapozindua</span>
        <span class="sv-btn__spinner" aria-hidden="true"></span>
      </button>
    </div>
    <p class="sv-help" id="${id}-help" data-en="One email at launch. No spam, unsubscribe anytime.">Barua pepe moja wakati wa uzinduzi. Hakuna barua taka, unaweza kujiondoa wakati wowote.</p>
  </div>
  ${compact ? `<input type="hidden" name="userType" value="${esc(defaultType)}">` : `<fieldset class="sv-field sv-choice">
    <legend data-en="I want to use Soko Vibe as">Nataka kutumia Soko Vibe kama</legend>
    <div class="sv-choice__opts">
      <label><input type="radio" name="userType" value="buyer"${defaultType === 'buyer' ? ' checked' : ''}><span data-en="Buyer">Mnunuzi</span></label>
      <label><input type="radio" name="userType" value="seller"${defaultType === 'seller' ? ' checked' : ''}><span data-en="Seller">Muuza</span></label>
      <label><input type="radio" name="userType" value="both"${defaultType === 'both' ? ' checked' : ''}><span data-en="Both">Wote wawili</span></label>
    </div>
  </fieldset>`}
  <div class="sv-consent">
    <input id="${id}-consent" name="consent" type="checkbox" required>
    <label for="${id}-consent">
      <span data-en-html="I agree to receive launch updates from Soko Vibe and I have read the <a href=&quot;/privacy&quot;>privacy policy</a>.">Nakubali kupokea taarifa za uzinduzi kutoka Soko Vibe na nimesoma <a href="/privacy">sera ya faragha</a>.</span>
    </label>
  </div>
  <div class="sv-hp" aria-hidden="true">
    <label for="${id}-website">Website</label>
    <input id="${id}-website" name="website" type="text" tabindex="-1" autocomplete="off">
  </div>
  <input type="hidden" name="source" value="${esc(source)}">
  <input type="hidden" name="formStartedAt" value="" data-started>
  <p class="sv-status" id="${id}-status" role="status" aria-live="polite" data-form-status></p>
</form>`;
}

function contactForm() {
  return `<form class="sv-form sv-contact-form" data-contact novalidate>
  <div class="sv-form__grid">
    <div class="sv-field">
      <label for="contact-name" data-en="Your name">Jina lako</label>
      <input id="contact-name" name="name" type="text" autocomplete="name" required maxlength="120"
        aria-describedby="contact-status" ${tr('Your name')}>
    </div>
    <div class="sv-field">
      <label for="contact-email" data-en="Email address">Barua pepe</label>
      <input id="contact-email" name="email" type="email" inputmode="email" autocomplete="email" required maxlength="254"
        placeholder="jina@mfano.com" ${tr('you@example.com')} aria-describedby="contact-status">
    </div>
  </div>
  <div class="sv-field">
    <label for="contact-subject" data-en="Subject">Mada</label>
    <select id="contact-subject" name="subject" required>
      <option value="general" data-en="General question">Swali la jumla</option>
      <option value="buyer" data-en="Buyer support">Msaada kwa mnunuzi</option>
      <option value="seller" data-en="Seller support">Msaada kwa muuza</option>
      <option value="waitlist" data-en="Waitlist or launch updates">Orodha ya uzinduzi</option>
      <option value="privacy" data-en="Privacy or data request">Faragha au data</option>
      <option value="press" data-en="Press and partnerships">Vyombo vya habari na ushirikiano</option>
    </select>
  </div>
  <div class="sv-field">
    <label for="contact-message" data-en="Message">Ujumbe</label>
    <textarea id="contact-message" name="message" rows="6" required minlength="20" maxlength="4000"
      aria-describedby="contact-status contact-count" ${tr('Tell us how we can help…')}></textarea>
    <p class="sv-help" id="contact-count"><span data-message-count>0</span> / 4000</p>
  </div>
  <div class="sv-consent">
    <input id="contact-consent" name="consent" type="checkbox" required>
    <label for="contact-consent">
      <span data-en-html="I agree that Soko Vibe may use these details to reply to my message, as described in the <a href=&quot;/privacy&quot;>privacy policy</a>.">Nakubali kwamba Soko Vibe inaweza kutumia taarifa hizi kujibu ujumbe wangu, kama ilivyoelezwa kwenye <a href="/privacy">sera ya faragha</a>.</span>
    </label>
  </div>
  <div class="sv-hp" aria-hidden="true">
    <label for="contact-website">Website</label>
    <input id="contact-website" name="website" type="text" tabindex="-1" autocomplete="off">
  </div>
  <input type="hidden" name="formStartedAt" value="" data-started>
  <div class="sv-form__actions">
    <button class="sv-btn sv-btn--primary" type="submit">
      <span data-en="Send message">Tuma ujumbe</span>
      <span class="sv-btn__spinner" aria-hidden="true"></span>
    </button>
    <p class="sv-help" data-en="We usually reply within two working days.">Kwa kawaida tunajibu ndani ya siku mbili za kazi.</p>
  </div>
  <p class="sv-status" id="contact-status" role="status" aria-live="polite" data-form-status></p>
</form>`;
}

function ctaSection({ id = 'waitlist', title, lead }) {
  return `<section class="sv-cta" id="${id}">
  <div class="sv-container sv-cta__inner">
    <div class="sv-cta__copy">
      ${t('p', 'Orodha ya uzinduzi', 'Launch list', { class: 'sv-eyebrow sv-eyebrow--dark' })}
      ${t('h2', title.sw, title.en, { class: 'sv-h2' })}
      ${t('p', lead.sw, lead.en, { class: 'sv-cta__lead' })}
      <ul class="sv-cta__list">
        <li>${icon('check', 'sv-icon--sm')} ${t('span', 'Taarifa moja tutakapozindua', 'One update when we launch')}</li>
        <li>${icon('check', 'sv-icon--sm')} ${t('span', 'Hakuna barua taka', 'No spam')}</li>
        <li>${icon('check', 'sv-icon--sm')} ${t('span', 'Unaweza kujiondoa wakati wowote', 'Unsubscribe anytime')}</li>
      </ul>
    </div>
    <div class="sv-cta__form">
      ${waitlistForm({ id: `${id}-form`, source: id, compact: true })}
    </div>
  </div>
</section>`;
}

module.exports = {
  langSwitch,
  header,
  footer,
  pageMeta,
  layout,
  sectionHead,
  pageHero,
  statusBadge,
  featureCard,
  step,
  accordion,
  waitlistForm,
  contactForm,
  ctaSection,
};
