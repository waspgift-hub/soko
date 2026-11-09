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
  // Marketing consent: an explicit marketing opt-out always wins. Every
  // registered account with an email receives these messages unless they
  // have opted out — there is no separate opt-in flag.
  if (prefs.marketing === false) return false;
  if (prefs.daily_reminders === false) return false;
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

function escHtml(value) {
  return String(value ?? '').replace(/[&<>"']/g, (c) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  }[c]));
}

function buildMessages({ locale = 'sw', product, feature } = {}) {
  const sw = locale === 'sw';
  if (product) {
    const titleText = product.title || product.name || (sw ? 'Bidhaa' : 'Product');
    const price = Number(product.price);
    const priceText = Number.isFinite(price) ? `TSh ${price.toLocaleString('en-TZ')}` : '';
    const subject = sw ? 'Bidhaa inayokufaa leo' : 'A product for you today';
    const body = priceText ? `${titleText} — ${priceText}` : titleText;
    return {
      campaignType: 'product',
      subject,
      pushTitle: subject,
      pushBody: body,
      emailBody: body,
      productId: product.id,
      product: {
        id: product.id,
        title: titleText,
        price: Number.isFinite(price) ? price : null,
        image: product.image || product.thumbnail || product.imageUrl || null,
        shopName: product.shopName || product.storeName || product.sellerName || null,
      },
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

function renderProductCardEmail({ message, unsubUrl, baseUrl = 'https://www.sokovibe.co.tz' } = {}) {
  const sw = message?.locale !== 'en';
  const product = message?.product || {};
  const dest = `${baseUrl}${message?.destination || '/search'}`;
  const title = escHtml(product.title || (sw ? 'Bidhaa' : 'Product'));
  const price = Number.isFinite(Number(product.price))
    ? `TSh ${Number(product.price).toLocaleString('en-TZ')}` : '';
  const shop = product.shopName ? escHtml(product.shopName) : '';
  const image = typeof product.image === 'string' && /^https?:\/\//i.test(product.image) ? product.image : '';
  const cta = sw ? 'Tazama Bidhaa' : 'View Product';
  const intro = sw ? 'Tumekupatia bidhaa unayoweza kuipenda leo.' : 'Here is a product you might like today.';
  const unsubText = sw ? 'Huwezi kupokea barua hizi tena?' : 'Don’t want these emails?';
  const unsubCta = sw ? 'Jiondoe hapa' : 'Unsubscribe';
  const imageHtml = image
    ? `<a href="${dest}" style="display:block;text-decoration:none;"><img src="${escHtml(image)}" alt="${title}" width="520" style="display:block;width:100%;max-width:520px;height:auto;border:0;border-radius:14px;background:#1a1a1a;" /></a>`
    : `<div style="width:100%;height:220px;border-radius:14px;background:#1f2937;color:#9ca3af;display:flex;align-items:center;justify-content:center;font-size:14px;">Soko Vibe</div>`;
  return `
    <p style="margin:0 0 16px;color:#e5e7eb;font-size:15px;line-height:1.6;">${escHtml(intro)}</p>
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-collapse:separate;border-spacing:0;background:#141414;border:1px solid #2a2a2a;border-radius:18px;overflow:hidden;">
      <tr><td style="padding:14px 14px 0;">${imageHtml}</td></tr>
      <tr>
        <td style="padding:16px 18px 18px;">
          ${shop ? `<p style="margin:0 0 6px;font-size:12px;line-height:1.4;color:#9ca3af;">${shop}</p>` : ''}
          <h2 style="margin:0 0 8px;font-size:20px;line-height:1.3;color:#ffffff;font-weight:700;">${title}</h2>
          ${price ? `<p style="margin:0 0 16px;font-size:18px;line-height:1.3;color:#1F8F4E;font-weight:700;">${escHtml(price)}</p>` : ''}
          <a href="${dest}" style="display:inline-block;background:#1F8F4E;color:#ffffff;text-decoration:none;padding:13px 18px;border-radius:12px;font-weight:600;font-size:14px;">${escHtml(cta)}</a>
        </td>
      </tr>
    </table>
    <p style="font-size:12px;color:#888;margin-top:22px;line-height:1.5;">${escHtml(unsubText)} <a href="${escHtml(unsubUrl || baseUrl)}" style="color:#9ca3af;">${escHtml(unsubCta)}</a>.</p>
  `;
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
  renderProductCardEmail,
  validateOutbound,
};
