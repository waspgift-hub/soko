'use strict';

const SITE = {
  name: 'Soko Vibe',
  canonicalHost: 'https://sokovibe.co.tz',
  homeTitle: 'Soko Vibe | Nunua na Uze Salama Tanzania',
  homeDescription:
    'Soko Vibe ni marketplace ya Tanzania. Nunua na uze bidhaa mpya na za mitumba kwa malipo ya escrow, chat ya wakati halisi, msaidizi wa AI, na usafirishaji nchi nzima.',
  logo: 'https://sokovibe.co.tz/assets/icon-512.png',
};

function canonicalUrl(req) {
  const pathname = req.path && req.path !== '/' ? req.path : '/';
  return `${SITE.canonicalHost}${pathname}`;
}

module.exports = { SITE, canonicalUrl };