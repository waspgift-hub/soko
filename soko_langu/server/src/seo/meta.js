'use strict';

// Official/canonical host. Render is configured to redirect the apex
// (sokovibe.co.tz) to www.sokovibe.co.tz at the edge, so www is the host that
// actually serves content and is used for every absolute URL we emit.
const SITE = {
  name: 'Soko Vibe',
  canonicalHost: 'https://www.sokovibe.co.tz',
  // English entity description used in structured data and GEO copy; mirrors
  // the platform: a Tanzania-based online marketplace for buyers and sellers.
  description: 'Soko Vibe is a Tanzania-based online marketplace connecting buyers and sellers.',
  homeTitle: 'Soko Vibe | Nunua na Uza Salama Tanzania',
  homeDescription:
    'Soko Vibe ni marketplace ya Tanzania. Nunua na uza bidhaa mpya na za mitumba kwa malipo ya escrow, chat ya wakati halisi, msaidizi wa AI, na usafirishaji nchi nzima.',
  logo: 'https://www.sokovibe.co.tz/assets/icon-512.png',
  email: 'support@soko-vibe.com',
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