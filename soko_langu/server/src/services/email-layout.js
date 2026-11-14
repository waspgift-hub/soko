// Transactional and engagement email layout. Table-based with inline styles so
// Gmail, Outlook and Apple Mail render it the same way. One primary action per
// email; everything else is quiet text.

const BRAND = '#0b7a3b';
const BASE_URL = 'https://www.sokovibe.co.tz';

function esc(value) {
  return String(value ?? '').replace(/[&<>"']/g, (c) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  }[c]));
}

function absoluteUrl(path) {
  if (!path) return BASE_URL;
  if (/^https?:\/\//i.test(path)) return path;
  return `${BASE_URL}${path.startsWith('/') ? path : `/${path}`}`;
}

const FOOTER = {
  sw: {
    reason: 'Umepokea barua pepe hii kwa sababu ya akaunti yako ya Soko Vibe.',
    manage: 'Badilisha mapendeleo ya arifa',
    rights: 'Haki zote zimehifadhiwa.',
  },
  en: {
    reason: 'You received this email because you have a Soko Vibe account.',
    manage: 'Manage notification settings',
    rights: 'All rights reserved.',
  },
};

// rows: [{ label, value }]. cta: { label, path }. Returns a full HTML document.
function renderEmail({
  lang = 'sw',
  preheader = '',
  title,
  paragraphs = [],
  rows = [],
  cta = null,
  footnote = '',
  settingsPath = '/notification-preferences',
} = {}) {
  const t = FOOTER[lang] || FOOTER.sw;
  const year = new Date().getUTCFullYear();

  const rowsHtml = rows.length
    ? `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin:20px 0 4px;border-collapse:collapse">
${rows.map((r, i) => `        <tr>
          <td style="padding:12px 0;${i ? 'border-top:1px solid #eef0f3;' : ''}font-size:14px;color:#6b7280;width:40%">${esc(r.label)}</td>
          <td style="padding:12px 0;${i ? 'border-top:1px solid #eef0f3;' : ''}font-size:14px;color:#111827;font-weight:600;text-align:right">${esc(r.value)}</td>
        </tr>`).join('\n')}
      </table>`
    : '';

  const paragraphsHtml = paragraphs
    .map((p) => `<p style="margin:0 0 14px;font-size:15px;line-height:1.6;color:#374151">${esc(p)}</p>`)
    .join('\n      ');

  const ctaHtml = cta
    ? `<table role="presentation" cellpadding="0" cellspacing="0" style="margin:24px 0 8px">
        <tr>
          <td style="border-radius:8px;background:${BRAND}">
            <a href="${esc(absoluteUrl(cta.path))}" style="display:inline-block;padding:12px 22px;font-size:15px;font-weight:600;color:#ffffff;text-decoration:none;border-radius:8px">${esc(cta.label)}</a>
          </td>
        </tr>
      </table>`
    : '';

  const footnoteHtml = footnote
    ? `<p style="margin:16px 0 0;font-size:13px;line-height:1.6;color:#6b7280">${esc(footnote)}</p>`
    : '';

  // Body-only content: the outer master layout (mailer.wrapEmailHtml) provides
  // the green header banner, logo and footer. Returning a full document here
  // would double-wrap the email.
  return `
      <h1 style="margin:0 0 16px;font-size:22px;line-height:1.3;font-weight:600;color:#111827">${esc(title)}</h1>
      ${paragraphsHtml}
      ${rowsHtml}
      ${ctaHtml}
      ${footnoteHtml}
    `;
}

module.exports = { renderEmail, esc };
