// Transactional mailer (OTP codes + admin broadcast + KYC).
//
// Preferred channel is the Resend HTTP API: the domain (sokovibe.co.tz) is
// DNS-verified there, so recipients see no-reply@sokovibe.co.tz. HTTPS beats
// SMTP from Render (Frankfurt) — SMTP STARTTLS handshakes routinely push past
// the ~15s Cloudflare edge budget in front of api.sokovibe.co.tz, while the
// Resend HTTP call returns in ~1s.
//
// Cloudflare Email Sending (CF token) and nodemailer/SMTP remain as fallbacks
// for deployments/token setups that pre-date Resend. Reaching a fallback never
// costs the request: every channel is awaited under a hard timeout.

const nodemailer = require('nodemailer');

let transporter = null;

// Keeps the HTTP request budget: a slow relay must never stall the API. The
// Resend API answers in ~1s; 30s is guard-room for degraded networks without
// letting an SMTP relay idle the request away.
const SEND_TIMEOUT_MS = 30000;

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

// Rough HTML→text so clients that only show plain text still render the code;
// dual-format also keeps spam scores lower.
function toPlainText(html) {
  return html
    .replace(/<[^>]+>/g, ' ')
    .replace(/&nbsp;/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

async function sendViaCloudflare(to, subject, html) {
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
  return body;
}

// Resend API: HTTPS beats SMTP from Render (see file header). The api async
// is one POST; the from address lives on a DNS-verified Resend domain.
async function sendViaResend(to, subject, html) {
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
    }),
  });
  if (!res.ok) {
    const detail = await res.text();
    throw new Error(`Resend email ${res.status}: ${detail.slice(0, 200)}`);
  }
  return res.json();
}

async function sendMail(to, subject, html) {
  try {
    if (cloudFlareConfigured()) {
      await withTimeout(sendViaCloudflare(to, subject, html));
      console.log(`[MAILER] sent via Cloudflare to ${to}`);
      return true;
    }
    if (resendConfigured()) {
      await withTimeout(sendViaResend(to, subject, html));
      console.log(`[MAILER] sent via Resend to ${to}`);
      return true;
    }
    if (!process.env.SMTP_USER || !process.env.SMTP_PASS) {
      console.error('[MAILER] neither Cloudflare nor Resend nor SMTP configured');
      return false;
    }
    await withTimeout(getTransporter().sendMail({
      from: process.env.SMTP_FROM || 'Soko Vibe <no-reply@sokovibe.co.tz>',
      to,
      subject,
      html,
    }));
    return true;
  } catch (e) {
    console.error('[MAILER] send failed:', e.message);
    return false;
  }
}

module.exports = { sendMail };