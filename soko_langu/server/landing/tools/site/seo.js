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
    alternateName: 'SokoVibe',
    url: `${SITE.host}/`,
    logo: {
      '@type': 'ImageObject',
      url: `${SITE.host}/assets/icon-512.png`,
      width: 512,
      height: 512,
    },
    description: 'Soko Vibe is a Tanzanian digital marketplace project founded by Gift Henry Wapalila in 2026. It is being developed to connect buyers, sellers, products and services across Tanzania.',
    email: SITE.email,
    telephone: SITE.phone,
    address: {
      '@type': 'PostalAddress',
      addressLocality: 'Dar es Salaam',
      addressCountry: 'TZ',
    },
    areaServed: { '@type': 'Country', name: 'Tanzania' },
    foundingDate: '2026',
    founder: { '@id': `${SITE.host}/#founder` },
  };
}

function founder() {
  return {
    '@context': 'https://schema.org',
    '@type': 'Person',
    '@id': `${SITE.host}/#founder`,
    name: 'Gift Henry Wapalila',
    givenName: 'Gift',
    familyName: 'Henry Wapalila',
    jobTitle: 'Founder of Soko Vibe',
    description: 'Gift Henry Wapalila is the founder of Soko Vibe, a Tanzanian digital marketplace project started in 2026.',
    worksFor: { '@id': ORG_ID },
    url: `${SITE.host}/about/founder`,
  };
}

function website() {
  return {
    '@context': 'https://schema.org',
    '@type': 'WebSite',
    '@id': SITE_ID,
    name: SITE.name,
    alternateName: 'SokoVibe',
    url: `${SITE.host}/`,
    description: 'Soko Vibe is a Tanzanian digital marketplace project founded by Gift Henry Wapalila in 2026. Currently under development.',
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

module.exports = { organization, website, webpage, breadcrumbs, faqPage, founder };
