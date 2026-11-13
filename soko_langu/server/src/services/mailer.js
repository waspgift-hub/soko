// Transactional mailer (OTP codes + admin broadcast + KYC).
//
// Preferred channel is the Resend HTTP API: the domain (sokovibe.co.tz) is
// DNS-verified there, so recipients see no-reply@sokovibe.co.tz. HTTPS beats
// SMTP from Render (Frankfurt) â€” SMTP STARTTLS handshakes routinely push past
// the ~15s Cloudflare edge budget in front of api.sokovibe.co.tz, while the
// Resend HTTP call returns in ~1s.
//
// Cloudflare Email Sending (CF token) and nodemailer/SMTP remain as fallbacks
// for deployments/token setups that pre-date Resend, and they are genuinely
// tried in turn â€” sendMail() walks the configured channels and returns on the
// first that actually delivers.

const nodemailer = require('nodemailer');
const { maskEmail } = require('../utils/pii');

let transporter = null;

// Keeps the HTTP request budget: a slow relay must never stall the API. The
// Resend API answers in ~1s; 15s is guard-room for degraded networks that
// still fits inside the API's own 20s request timeout (30s used to 504 while
// the handler was still sending).
const SEND_TIMEOUT_MS = 15000;

function withTimeout(promise, ms = SEND_TIMEOUT_MS) {
  return Promise.race([
    promise,
    new Promise((_, reject) =>
      setTimeout(() => reject(new Error(`mailer send timeout after ${ms}ms`)), ms),
    ),
  ]);
}

function cloudFlareConfigured() {
  return Boolean(process.env.CLOUDFLARE_ACCOUNT_ID && process.env.CLOUDFLARE_API_TOKEN);
}

function resendConfigured() {
  return Boolean(process.env.RESEND_API_KEY);
}

function getTransporter() {
  if (!transporter) {
    transporter = nodemailer.createTransport({
      host: process.env.SMTP_HOST || 'smtp.gmail.com',
      port: parseInt(process.env.SMTP_PORT || '587', 10),
      secure: process.env.SMTP_SECURE === 'true',
      auth: { user: process.env.SMTP_USER, pass: process.env.SMTP_PASS },
      connectionTimeout: SEND_TIMEOUT_MS,
      greetingTimeout: SEND_TIMEOUT_MS,
      socketTimeout: SEND_TIMEOUT_MS,
    });
  }
  return transporter;
}

// Rough HTMLâ†’text so clients that only show plain text still render the code;
// dual-format also keeps spam scores lower.
function toPlainText(html) {
  return html
    .replace(/<[^>]+>/g, ' ')
    .replace(/&nbsp;/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

async function sendViaCloudflare(to, subject, html, headers = {}) {
  const accountId = process.env.CLOUDFLARE_ACCOUNT_ID;
  const res = await fetch(
    `https://api.cloudflare.com/client/v4/accounts/${accountId}/email/sending/send`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${process.env.CLOUDFLARE_API_TOKEN}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        to,
        from: {
          address: process.env.EMAIL_FROM || 'no-reply@sokovibe.co.tz',
          name: process.env.EMAIL_FROM_NAME || 'Soko Vibe',
        },
        subject,
        html,
        text: toPlainText(html),
        headers: Object.keys(headers).length
          ? Object.entries(headers).map(([name, value]) => ({ name, value }))
          : undefined,
      }),
    },
  );
  if (!res.ok) {
    const detail = await res.text();
    throw new Error(`Cloudflare email ${res.status}: ${detail.slice(0, 200)}`);
  }
  const body = await res.json();
  if (body && body.success === false) {
    throw new Error(`Cloudflare email rejected: ${(body.errors || []).map((e) => e.message).join('; ').slice(0, 200)}`);
  }

  // A 200 is NOT proof of delivery. The API answers 200 with
  // result.permanent_bounces / result.suppressed_recipients populated when the
  // address bounced or is on the suppression list â€” the mail never arrives. The
  // old code ignored those and reported success, so an OTP email to a dead
  // address looked sent, the code stayed in the store, and the user waited out
  // a cooldown for a message that was never going to arrive.
  const result = (body && body.result) || {};
  const undelivered = [
    ...(result.permanent_bounces || []),
    ...(result.suppressed_recipients || []),
  ];
  if (undelivered.length) {
    throw new Error(`Cloudflare email not delivered to ${undelivered.join(', ')}`);
  }
  if (!result.message_id) {
    throw new Error('Cloudflare email returned no message_id');
  }
  return result;
}

// Resend API: HTTPS beats SMTP from Render (see file header). The api async
// is one POST; the from address lives on a DNS-verified Resend domain.
async function sendViaResend(to, subject, html, headers = {}) {
  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${process.env.RESEND_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from: process.env.SMTP_FROM || 'Soko Vibe <no-reply@sokovibe.co.tz>',
      to: [to],
      subject,
      html,
      text: toPlainText(html),
      headers,
    }),
  });
  if (!res.ok) {
    const detail = await res.text();
    throw new Error(`Resend email ${res.status}: ${detail.slice(0, 200)}`);
  }
  return res.json();
}

function escapeHtml(value) {
  return String(value ?? '').replace(/[&<>"']/g, (c) => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#39;',
  }[c]));
}

function unwrapIfFullDocument(html) {
  const raw = String(html || '').trim();
  if (!/^<!doctype html|^<html[\s>]/i.test(raw)) return raw;
  const bodyMatch = raw.match(/<body[^>]*>([\s\S]*?)<\/body>/i);
  return bodyMatch ? bodyMatch[1].trim() : raw;
}

// Samsung One UI inspired email wrapper used for all transactional emails.
function wrapEmailHtml({ html, action = 'generic', context = {} }) {
  const lang = context.lang === 'en' ? 'en' : 'sw';
  const otp = context.otp ? String(context.otp) : '';
  const expiresInMinutes = Number(context.expiresInMinutes || 10);
  const when = context.when ? String(context.when) : '';
  const support = context.supportEmail || 'support@sokovibe.co.tz';
  const recipientEmail = escapeHtml(context.recipientEmail || '');
  const contentHtml = unwrapIfFullDocument(html);

  const copy = lang === 'en'
    ? {
        otpHeading: 'Your verification code',
        otpIntro: `Enter the code below to complete sign-in. It is valid for one use and expires in ${expiresInMinutes} minutes.`,
        otpMeta: `Expires in ${expiresInMinutes} minutes · single use`,
        securityTitle: "Didn't request this?",
        otpSecurity: 'Ignore this email. Never share this code with anyone, including someone claiming to be Soko Vibe support.',
        changedHeading: 'Password changed',
        changedIntro: `Your Soko Vibe password was changed${when ? ` on ${escapeHtml(when)}` : ''}. Other devices have been signed out.`,
        changedSecurity: 'If this was not you, contact Soko Vibe Support immediately at support@sokovibe.co.tz to secure your account.',
        rights: 'All rights reserved.',
        sentTo: 'This email was sent to',
      }
    : {
        otpHeading: 'Namba yako ya uthibitisho',
        otpIntro: `Ingiza namba hapa chini kukamilisha kuingia. Inatumika mara moja tu na inaisha kwa dakika ${expiresInMinutes}.`,
        otpMeta: `Muda: dakika ${expiresInMinutes} · kutumika mara moja tu`,
        securityTitle: 'Hukuitaka hii?',
        otpSecurity: 'Puuza barua hii. Usimpe mtu yeyote namba hii, hata kama anadai ni msaada wa Soko Vibe.',
        changedHeading: 'Nenosiri limebadilishwa',
        changedIntro: `Nenosiri lako la Soko Vibe limebadilishwa${when ? ` mnamo ${escapeHtml(when)}` : ''}. Vifaa vingine vimetolewa nje kiotomatiki.`,
        changedSecurity: 'Ikiwa si wewe, wasiliana na Msaada wa Soko Vibe mara moja kupitia support@sokovibe.co.tz ili kulinda akaunti yako.',
        rights: 'Haki zote zimehifadhiwa.',
        sentTo: 'Barua pepe hii imetumwa kwa',
      };

  let actionBlock = '';
  if (action === 'otp' && otp) {
    actionBlock = `
      <div class="content">
        <h2>${copy.otpHeading}</h2>
        <p>${copy.otpIntro}</p>
        <div class="otp-wrap"><div class="otp-box"><span>${escapeHtml(otp)}</span></div></div>
        <p class="meta">${copy.otpMeta}</p>
        <div class="security-box">
          <p class="security-title">${copy.securityTitle}</p>
          <p class="security-text">${copy.otpSecurity}</p>
        </div>
      </div>
    `;
  } else if (action === 'password-changed' || action === 'password-reset') {
    actionBlock = `
      <div class="content">
        <h2>${copy.changedHeading}</h2>
        <p>${copy.changedIntro}</p>
        <div class="security-box">
          <p class="security-title">${copy.securityTitle}</p>
          <p class="security-text">${copy.changedSecurity}</p>
        </div>
        ${contentHtml ? `<div class="extra">${contentHtml}</div>` : ''}
      </div>
    `;
  } else {
    actionBlock = `<div class="content">${contentHtml}</div>`;
  }

  return `<!DOCTYPE html>
<html lang="${lang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<meta name="color-scheme" content="dark light">
<meta name="supported-color-schemes" content="dark light">
<title>Soko Vibe</title>
</head>
<body style="margin:0;padding:0;background-color:#0A0A0A;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,'Helvetica Neue',Arial,sans-serif;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color:#0A0A0A;padding:32px 12px;">
    <tr>
      <td align="center">
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:600px;background-color:#141414;border-radius:24px;overflow:hidden;border:1px solid #2A2A2A;">
          <tr>
            <td align="center" style="background:linear-gradient(135deg,#1F8F4E 0%,#0D5C33 100%);padding:36px 28px;">
              <img src="https://www.sokovibe.co.tz/assets/icon-512.png" width="64" height="64" alt="Soko Vibe" style="display:block;border:0;border-radius:16px;margin:0 auto 14px;">
              <div style="font-size:24px;font-weight:700;color:#FFFFFF;letter-spacing:-0.2px;">Soko Vibe</div>
              <div style="font-size:13px;color:rgba(255,255,255,0.82);margin-top:4px;">Soko la mtandaoni - Tanzania</div>
            </td>
          </tr>
          <tr>
            <td style="padding:28px 28px 8px 28px;color:#E6E6E6;font-size:15px;line-height:1.7;">
              <style>
                .content h2 { margin:0 0 12px;font-size:22px;line-height:1.3;color:#FFFFFF;font-weight:700; }
                .content p { margin:0 0 14px;color:#DADADA;font-size:15px;line-height:1.7; }
                .meta { color:#9CA3AF !important;font-size:13px !important;margin:8px 0 0 !important; }
                .otp-wrap { text-align:center;margin:18px 0 6px; }
                .otp-box { display:inline-block;background:#1C1C1C;border:1px solid #2E2E2E;border-radius:16px;padding:18px 22px; }
                .otp-box span { font-family:'Roboto Mono',Consolas,'Courier New',monospace;font-size:38px;font-weight:700;letter-spacing:10px;color:#39B66A;display:inline-block;padding-left:10px; }
                .security-box { background:rgba(255,255,255,0.04);border:1px solid #2A2A2A;border-radius:14px;padding:14px 16px;margin:18px 0 0; }
                .security-title { margin:0 0 6px !important;color:#FFFFFF !important;font-weight:600;font-size:14px !important; }
                .security-text { margin:0 !important;color:#AFAFAF !important;font-size:13px !important;line-height:1.6 !important; }
                .extra { margin-top:16px; }
                .content a { color:#39B66A; }
              </style>
              ${actionBlock}
            </td>
          </tr>
          <tr>
            <td style="padding:18px 28px 28px 28px;border-top:1px solid #232323;text-align:center;">
              <p style="margin:0 0 6px;font-size:12px;color:#7A7A7A;">&copy; 2026 Soko Vibe. ${copy.rights}</p>
              <p style="margin:0 0 6px;font-size:12px;color:#7A7A7A;">${copy.sentTo} ${recipientEmail}.</p>
              <p style="margin:0;font-size:12px;color:#7A7A7A;"><a href="https://www.sokovibe.co.tz" style="color:#39B66A;text-decoration:none;">www.sokovibe.co.tz</a> &middot; <a href="mailto:${escapeHtml(support)}" style="color:#39B66A;text-decoration:none;">${escapeHtml(support)}</a></p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;
}

// Every channel that is configured gets tried in turn, and the first one that
// actually delivers wins. The previous version returned false on the FIRST
// error, so the fallbacks described in the file header never ran: one Cloudflare
// hiccup (or a 409 while Email Sending setup was still in progress) silently
// cut off all email, including OTPs, with Resend credentials sitting unused.

async function sendMail(to, subject, html, recipientOverride, { action = 'generic', context = {}, headers = {} } = {}) {
  const recipient = recipientOverride || to;
  const normalizedContext = { ...context };
  if (!normalizedContext.recipientEmail) normalizedContext.recipientEmail = recipient;
  const wrappedHtml = wrapEmailHtml({ html, action, context: normalizedContext });
  const channels = [];
  // Resend first: sokovibe.co.tz is DNS-verified there, so recipients see
  // no-reply@sokovibe.co.tz and the call is a single HTTPS POST that answers
  // in ~1s.
  if (resendConfigured()) channels.push(['Resend', () => sendViaResend(recipient, subject, wrappedHtml, headers)]);
  if (cloudFlareConfigured()) channels.push(['Cloudflare', () => sendViaCloudflare(recipient, subject, wrappedHtml, headers)]);
  if (process.env.SMTP_USER && process.env.SMTP_PASS) {
    channels.push(['SMTP', () => getTransporter().sendMail({
      from: process.env.SMTP_FROM || 'Soko Vibe <no-reply@sokovibe.co.tz>',
      to: recipient,
      subject,
      html: wrappedHtml,
      headers,
    })]);
  }

  if (!channels.length) {
    console.error('[MAILER] no channel configured (need RESEND_API_KEY, or CLOUDFLARE_API_TOKEN, or SMTP)');
    return false;
  }

  const failures = [];
  const masked = maskEmail(recipient);
  for (const [name, attempt] of channels) {
    try {
      await withTimeout(attempt());
      console.log(`[MAILER] sent via ${name} to ${masked}`);
      return true;
    } catch (e) {
      console.error(`[MAILER] ${name} failed:`, e.message);
      failures.push(`${name}: ${e.message}`);
    }
  }
  console.error(`[MAILER] all channels failed for ${masked}: ${failures.join(' | ')}`);
  return false;
}

module.exports = { sendMail };