'use strict';

// Daily re-engagement campaign helpers. Scheduling and eligibility are
// deterministic; AI wording is optional and never invents product facts.
// The campaign is paused unless admin settings explicitly enable it.

const DEFAULT_TZ = 'Africa/Dar_es_Salaam';

function pad(n) {
  return String(n).padStart(2, '0');
}

function localDayKey(date, timeZone = DEFAULT_TZ) {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(date);
  const map = Object.fromEntries(parts.map((p) => [p.type, p.value]));
  return `${map.year}-${map.month}-${map.day}`;
}

function campaignId(userId, dayKey) {
  return `daily:${userId}:${dayKey}`;
}

function alreadyOpenedToday(lastLoginAt, now, timeZone = DEFAULT_TZ) {
  if (!lastLoginAt) return false;
  const at = lastLoginAt instanceof Date ? lastLoginAt : new Date(lastLoginAt);
  if (Number.isNaN(at.getTime())) return false;
  return localDayKey(at, timeZone) === localDayKey(now, timeZone);
}

function isEligibleUser({ lastLoginAt, prefs = {}, now, timeZone = DEFAULT_TZ }) {
  if (prefs.daily_reminders !== true) return false;
  if (prefs.marketing === false) return false;
  if (alreadyOpenedToday(lastLoginAt, now, timeZone)) return false;
  return true;
}

function pickRecommendation({
  products = [],
  viewedIds = [],
  purchasedIds = [],
  dismissedIds = [],
} = {}) {
  const purchased = new Set(purchasedIds.map(String));
  const dismissed = new Set(dismissedIds.map(String));
  const viewed = viewedIds.map(String);

  const eligible = products.filter((p) => {
    if (!p || !p.id) return false;
    if (p.status && p.status !== 'active' && p.status !== 'published') return false;
    if (p.deleted === true || p.disabled === true) return false;
    if (purchased.has(String(p.id))) return false;
    if (dismissed.has(String(p.id))) return false;
    if (p.price == null || Number(p.price) < 0) return false;
    return true;
  });

  for (const id of viewed) {
    const match = eligible.find((p) => String(p.id) === id);
    if (match) return { type: 'product', product: match };
  }
  if (eligible[0]) return { type: 'product', product: eligible[0] };
  return { type: 'feature', feature: 'search' };
}

function buildMessages({ locale = 'sw', product, feature } = {}) {
  const sw = locale === 'sw';
  if (product) {
    const title = sw ? 'Bidhaa inayokufaa leo' : 'A product for you today';
    const body = sw
      ? `${product.title} — TSh ${Number(product.price).toLocaleString('en-TZ')}`
      : `${product.title} — TSh ${Number(product.price).toLocaleString('en-TZ')}`;
    return {
      campaignType: 'product',
      subject: title,
      pushTitle: title,
      pushBody: body,
      emailBody: body,
      productId: product.id,
      destination: `/product/${product.id}`,
      locale,
    };
  }
  const title = sw ? 'Tafuta bidhaa kwenye Soko Vibe' : 'Search products on Soko Vibe';
  const body = sw
    ? 'Fungua utafutaji na uone bidhaa halisi zinazouzwa sasa.'
    : 'Open search to browse live listings.';
  return {
    campaignType: 'feature',
    subject: title,
    pushTitle: title,
    pushBody: body,
    emailBody: body,
    productId: null,
    destination: '/search',
    feature: feature || 'search',
    locale,
  };
}

function validateOutbound(message) {
  if (!message || typeof message !== 'object') return false;
  if (!message.subject || !message.pushTitle || !message.pushBody) return false;
  if (!message.destination || !String(message.destination).startsWith('/')) return false;
  const html = `${message.subject}${message.pushBody}${message.emailBody || ''}`;
  if (/<\s*script/i.test(html) || /javascript:/i.test(html)) return false;
  if (/https?:\/\//i.test(message.destination)) return false;
  return true;
}

module.exports = {
  DEFAULT_TZ,
  localDayKey,
  campaignId,
  alreadyOpenedToday,
  isEligibleUser,
  pickRecommendation,
  buildMessages,
  validateOutbound,
};
