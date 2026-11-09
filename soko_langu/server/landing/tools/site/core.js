'use strict';

// Shared helpers for the static site generator. Pages are authored as plain
// JavaScript so one header/footer/component definition is reused everywhere and
// the deployed output stays dependency-free static HTML.

const SITE = {
  name: 'Soko Vibe',
  host: 'https://www.sokovibe.co.tz',
  email: 'support@sokovibe.co.tz',
  privacyEmail: 'dpo@sokovibe.co.tz',
  phone: '+255693273241',
  phoneDisplay: '+255 693 273 241',
  locale: 'sw_TZ',
  ogImage: 'https://www.sokovibe.co.tz/assets/og-image.png',
};

function esc(value) {
  return String(value == null ? '' : value).replace(/[&<>"']/g, (c) => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#39;',
  }[c]));
}

function attrs(map = {}) {
  return Object.entries(map)
    .filter(([, v]) => v !== false && v !== null && v !== undefined)
    .map(([k, v]) => (v === true ? k : `${k}="${esc(v)}"`))
    .join(' ');
}

// Swahili is rendered in the HTML (crawlable default). `en` is the English
// string exposed through a data attribute and swapped by js/sv.js. `enHtml`
// allows a handful of inline links without duplicating whole documents.
function t(tag, swahili, english, extra = {}) {
  const { enHtml, ...rest } = extra;
  const a = attrs({ ...rest, ...(enHtml ? { 'data-en-html': english } : { 'data-en': english }) });
  return `<${tag}${a ? ` ${a}` : ''}>${swahili}</${tag}>`;
}

// Attribute-level translations: placeholder, aria-label, title.
function tr(english, kind = 'placeholder') {
  return `data-en-${kind}="${esc(english)}"`;
}

const ICONS = {
  arrow: '<path d="M5 12h14M13 6l6 6-6 6"/>',
  check: '<path d="M20 6 9 17l-5-5"/>',
  chevron: '<path d="m6 9 6 6 6-6"/>',
  search: '<circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/>',
  store: '<path d="M4 9h16l-1-5H5L4 9Z"/><path d="M5 9v10h14V9"/><path d="M9 19v-5h6v5"/>',
  video: '<rect x="3" y="6" width="13" height="12" rx="2"/><path d="m16 10 5-3v10l-5-3"/>',
  chat: '<path d="M21 12a8 8 0 0 1-8 8H7l-4 3v-7a8 8 0 1 1 18-4Z"/><path d="M8 11h8M8 15h5"/>',
  shield: '<path d="M12 3 5 6v5c0 5 3 8 7 10 4-2 7-5 7-10V6l-7-3Z"/><path d="m9 12 2 2 4-4"/>',
  sparkles: '<path d="m12 3 1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8L12 3Z"/><path d="M19 15l.9 2.1L22 18l-2.1.9L19 21l-.9-2.1L16 18l2.1-.9L19 15Z"/>',
  bell: '<path d="M18 9a6 6 0 1 0-12 0c0 5-2 6-2 6h16s-2-1-2-6Z"/><path d="M10 20a2 2 0 0 0 4 0"/>',
  wallet: '<path d="M4 7h15a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2h12"/><path d="M16 13h.01"/>',
  truck: '<path d="M3 7h11v9H3z"/><path d="M14 10h4l3 3v3h-7"/><circle cx="7" cy="18" r="2"/><circle cx="18" cy="18" r="2"/>',
  tag: '<path d="M20 13 13 20 3 10V3h7l10 10Z"/><circle cx="7.5" cy="7.5" r="1.2"/>',
  users: '<circle cx="9" cy="8" r="3.5"/><path d="M2.5 20a6.5 6.5 0 0 1 13 0"/><path d="M17 5a3 3 0 0 1 0 6M18 14a6 6 0 0 1 4 6"/>',
  lock: '<rect x="4" y="10" width="16" height="11" rx="2"/><path d="M8 10V7a4 4 0 0 1 8 0v3"/>',
  heart: '<path d="M12 20s-7-4.5-7-9.5A3.5 3.5 0 0 1 12 8a3.5 3.5 0 0 1 7 2.5C19 15.5 12 20 12 20Z"/>',
  mail: '<rect x="3" y="5" width="18" height="14" rx="2"/><path d="m3 7 9 6 9-6"/>',
  globe: '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a15 15 0 0 1 0 18a15 15 0 0 1 0-18Z"/>',
  menu: '<path d="M4 7h16M4 12h16M4 17h16"/>',
  close: '<path d="M6 6l12 12M18 6 6 18"/>',
  scale: '<path d="M12 4v16M7 20h10M5 7h14M5 7l-3 7h6L5 7ZM19 7l-3 7h6l-3-7Z"/>',
  document: '<path d="M6 3h8l4 4v14H6z"/><path d="M14 3v5h5M9 13h6M9 17h6"/>',
  pin: '<path d="M12 21s7-6 7-11a7 7 0 1 0-14 0c0 5 7 11 7 11Z"/><circle cx="12" cy="10" r="2.5"/>',
  refresh: '<path d="M20 11a8 8 0 1 0-2 6"/><path d="M20 5v6h-6"/>',
  message: '<path d="M21 11.5a8.5 8.5 0 0 1-12.4 7.6L3 21l1.9-5.6A8.5 8.5 0 1 1 21 11.5Z"/>',
  user: '<circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/>',
  bag: '<path d="M5 8h14l1 13H4L5 8Z"/><path d="M9 8V6a3 3 0 0 1 6 0v2"/>',
  star: '<path d="m12 3 2.8 5.7 6.2.9-4.5 4.4 1.1 6.2L12 17.3 6.4 20.2 7.5 14 3 9.6l6.2-.9L12 3Z"/>',
};

function icon(name, cls = '') {
  const body = ICONS[name] || ICONS.sparkles;
  return `<svg class="sv-icon${cls ? ` ${cls}` : ''}" viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false">${body}</svg>`;
}

function logo(href = '/', extraClass = '') {
  return `<a class="sv-logo${extraClass ? ` ${extraClass}` : ''}" href="${href}" aria-label="Soko Vibe — mwanzo" data-en-aria-label="Soko Vibe — home">
    <img src="/assets/icon-192.png" alt="" width="34" height="34" decoding="async">
    <span>Soko Vibe</span>
  </a>`;
}

// The navigation is one source of truth for desktop, mobile and the footer.
const NAV = [
  { href: '/', sw: 'Mwanzo', en: 'Home' },
  { href: '/about', sw: 'Kuhusu', en: 'About' },
  { href: '/how-it-works', sw: 'Jinsi Inavyofanya Kazi', en: 'How it works' },
  { href: '/features', sw: 'Vipengele', en: 'Features' },
  { href: '/buyers', sw: 'Wanunuzi', en: 'For buyers' },
  { href: '/sellers', sw: 'Wauzaji', en: 'For sellers' },
  { href: '/pricing', sw: 'Bei', en: 'Pricing' },
  { href: '/faq', sw: 'Maswali', en: 'FAQ' },
  { href: '/contact', sw: 'Mawasiliano', en: 'Contact' },
];

module.exports = { SITE, esc, attrs, t, tr, icon, logo, NAV };
