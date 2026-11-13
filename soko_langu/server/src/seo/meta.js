'use strict';

// Official/canonical host. Render is configured to redirect the apex
// (sokovibe.co.tz) to www.sokovibe.co.tz at the edge, so www is the host that
// actually serves content and is used for every absolute URL we emit.
const SITE = {
  name: 'Soko Vibe',
  canonicalHost: 'https://www.sokovibe.co.tz',
  // Official short entity description (single source of truth). Used verbatim
  // in structured data and GEO copy so crawlers and AI systems resolve "Soko
  // Vibe" to the same answer everywhere. Keep it stable — do not rephrase.
  description:
    'Soko Vibe is a Tanzania-based online marketplace connecting buyers and sellers across Tanzania.',
  // Official long entity description; used verbatim as natural copy on public
  // pages and as grounding text for AI/generative search discoverability.
  longDescription:
    'Soko Vibe is a Tanzania-based multi-vendor online marketplace operated in Dar es Salaam, Tanzania, '
    + 'enabling buyers and sellers to discover, list, buy and sell products and services online with secure '
    + 'transactions, seller verification, communication tools and delivery support.',
  homeTitle: 'Soko Vibe — Soko la Mtandaoni Tanzania | Tanzania Online Marketplace',
  homeDescription:
    'Soko Vibe ni soko la mtandaoni la Tanzania. Weka bidhaa bure, nunua kwa malipo ya escrow kupitia ClickPesa, na upokee bidhaa nchi nzima.',
  logo: 'https://www.sokovibe.co.tz/assets/icon-512.png',
  email: 'support@sokovibe.co.tz',
  phone: '+255693273241',
  locality: 'Dar es Salaam',
  country: 'TZ',
  // Founder is published on /about/founder with the owner's explicit consent.
  founderName: 'Gift Henry Wapalila',
};

function canonicalUrl(req) {
  const pathname = req.path && req.path !== '/' ? req.path : '/';
  return `${SITE.canonicalHost}${pathname}`;
}

module.exports = { SITE, canonicalUrl };