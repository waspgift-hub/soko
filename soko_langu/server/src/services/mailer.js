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

// Samsung One UI inspired email wrapper. Renders action-specific content
// blocks inside the branded card so every transactional email shares one
// shell but adapts its body to the trigger (otp, password-reset, etc.).
function wrapEmailHtml({ html, action = 'otp', context = {} }) {
  const { otp, expiresInMinutes, when, resetLink, supportEmail } = context;
  const support = supportEmail || 'support@sokovibe.co.tz';

  let actionBlock = '';
  if (action === 'otp' && otp) {
    actionBlock = `
      <div class="content">
        <p class="content p">Ingiza namba hapa chini kukamilisha kuingia. Inatumika mara moja tu na inaisha kwa dakika ${expiresInMinutes || 5}.</p>
        <div class="otp-box">${otp}</div>
        <p class="content p">Muda: dakika ${expiresInMinutes || 5} · kutumika mara moja tu</p>
      </div>
    `;
  } else if (action === 'password-reset' && resetLink) {
    actionBlock = `
      <div class="content">
        <p class="content p">Nenosiri lako la Soko Vibe limebadilishwa${when ? ` mnamo ${when}` : ''}. Vifaa vingine vyote vimetolewa nje kiotomatiki.</p>
        <a href="${resetLink}" class="btn">Sasisha Nenosiri</a>
      </div>
    `;
  } else {
    actionBlock = `<div class="content">${html}</div>`;
  }

  return `<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<meta name="color-scheme" content="dark light">
<meta name="supported-color-schemes" content="dark light">
<style>
  body { margin: 0; padding: 0; background-color: #0A0A0A; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif; }
  .wrapper { width: 100%; background-color: #0A0A0A; padding: 40px 0; }
  .container { max-width: 600px; margin: 0 auto; }
  .card { background-color: #141414; border-radius: 20px; overflow: hidden; border: 1px solid #2A2A2A; }
  .header { background: linear-gradient(135deg, #1F8F4E 0%, #0D5C33 100%); padding: 40px 32px; text-align: center; }
  .logo { width: 64px; height: 64px; border-radius: 16px; margin-bottom: 16px; }
  .title { font-size: 22px; font-weight: 700; color: #FFFFFF; margin: 0 0 4px; }
  .subtitle { font-size: 13px; color: rgba(255,255,255,0.8); margin: 0; }
  .body { padding: 32px; }
  .content { font-size: 15px; color: #E0E0E0; line-height: 1.7; }
  .content h2 { color: #FFFFFF; font-size: 20px; font-weight: 600; margin: 0 0 12px; }
  .content p { margin: 0 0 16px; }
  .content strong { color: #1F8F4E; }
  .content ul { margin: 0 0 16px; padding-left: 20px; }
  .content li { margin-bottom: 6px; }
  .otp-box { background: #1A1A1A; border: 1px solid #2A2A2A; border-radius: 14px; padding: 26px 16px; display: inline-block; min-width: 200px; text-align: center; margin: 16px 0; }
  .otp-box span { font-family: 'Roboto Mono', Consolas, 'Courier New', monospace; font-size: 40px; font-weight: 700; letter-spacing: 12px; color: #1F8F4E; display: inline-block; }
  .btn { display: inline-block; background: #1F8F4E; color: #FFFFFF; padding: 14px 32px; border-radius: 12px; text-decoration: none; font-weight: 600; font-size: 14px; margin: 16px 0; }
  .divider { height: 1px; background: #2A2A2A; margin: 24px 0; }
  .footer { padding: 24px 32px; text-align: center; }
  .footer-text { font-size: 12px; color: #666666; margin: 0 0 8px; }
  .footer a { color: #1F8F4E; text-decoration: none; }
  .security-box { background: rgba(255,59,48,0.08); border: 1px solid rgba(255,59,48,0.2); border-radius: 12px; padding: 16px; margin: 16px 0; }
  .security-title { color: #FF3B30; font-weight: 600; font-size: 13px; margin: 0 0 6px; }
  .security-text { color: #AAAAAA; font-size: 13px; margin: 0; }
</style>
</head>
<body>
<div class="wrapper">
  <div class="container">
    <div class="card">
      <div class="header">
        <img src="https://www.sokovibe.co.tz/assets/icon-512.png" width="64" height="64" alt="Soko Vibe" class="logo">
        <h1 class="title">Soko Vibe</h1>
        <p class="subtitle">Soko la mtandaoni - Tanzania</p>
      </div>
      <div class="body">
        ${actionBlock}
      </div>
      <div class="divider" style="margin:0;"></div>
      <div class="footer">
        <p class="footer-text">Soko Vibe &copy; 2026. Haki zote zimehifadhiwa.</p>
        <p class="footer-text">Barua pepe hii imetumwa kwa ${context.recipientEmail || ''}.</p>
        <p class="footer-text"><a href="https://www.sokovibe.co.tz">www.sokovibe.co.tz</a> &middot; <a href="mailto:${support}">${support}</a></p>
      </div>
    </div>
  </div>
</div>
</body>
</html>`;
}

// Every channel that is configured gets tried in turn, and the first one that
// actually delivers wins. The previous version returned false on the FIRST
// error, so the fallbacks described in the file header never ran: one Cloudflare
// hiccup (or a 409 while Email Sending setup was still in progress) silently
// cut off all email, including OTPs, with Resend credentials sitting unused.

async function sendMail(to, subject, html, recipientOverride, { action = 'otp', context = {}, headers = {} } = {}) {
  const recipient = recipientOverride || to;
  const wrappedHtml = wrapEmailHtml({ html, action, context: { ...context, recipientEmail: recipient } });
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