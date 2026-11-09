'use strict';

const { SITE } = require('./core');

const ORG_ID = `${SITE.host}/#organization`;
const SITE_ID = `${SITE.host}/#website`;

function organization() {
  return {
    '@context': 'https://schema.org',
    '@type': 'Organization',
    '@id': ORG_ID,
    name: SITE.name,
    alternateName: 'Soko Vibe Tanzania',
    url: `${SITE.host}/`,
    logo: {
      '@type': 'ImageObject',
      url: `${SITE.host}/assets/icon-512.png`,
      width: 512,
      height: 512,
    },
    description: 'Soko Vibe is a Tanzania-based online marketplace connecting buyers and sellers across Tanzania.',
    email: SITE.email,
    telephone: SITE.phone,
    address: {
      '@type': 'PostalAddress',
      addressLocality: 'Dar es Salaam',
      addressCountry: 'TZ',
    },
    areaServed: { '@type': 'Country', name: 'Tanzania' },
  };
}

function website() {
  return {
    '@context': 'https://schema.org',
    '@type': 'WebSite',
    '@id': SITE_ID,
    name: SITE.name,
    url: `${SITE.host}/`,
    inLanguage: 'sw-TZ',
    publisher: { '@id': ORG_ID },
  };
}

function webpage({ path, title, description, lang = 'sw-TZ' }) {
  const url = `${SITE.host}${path === '/' ? '/' : path}`;
  return {
    '@context': 'https://schema.org',
    '@type': 'WebPage',
    '@id': `${url}#webpage`,
    url,
    name: title,
    description,
    inLanguage: lang,
    isPartOf: { '@id': SITE_ID },
    about: { '@id': ORG_ID },
    publisher: { '@id': ORG_ID },
  };
}

function breadcrumbs(items) {
  return {
    '@context': 'https://schema.org',
    '@type': 'BreadcrumbList',
    itemListElement: items.map((item, i) => ({
      '@type': 'ListItem',
      position: i + 1,
      name: item.name,
      item: `${SITE.host}${item.path}`,
    })),
  };
}

function faqPage(items) {
  return {
    '@context': 'https://schema.org',
    '@type': 'FAQPage',
    mainEntity: items.map((item) => ({
      '@type': 'Question',
      name: item.q,
      acceptedAnswer: { '@type': 'Answer', text: item.a },
    })),
  };
}

module.exports = { organization, website, webpage, breadcrumbs, faqPage };
