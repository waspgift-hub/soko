// Transactional mailer (OTP codes + admin broadcast + KYC).
//
// Primary channel is Cloudflare Email Sending, which sends from the brand
// domain (sokovibe.co.tz) so recipients see no-reply@sokovibe.co.tz instead of
// a personal Gmail address. Needs CLOUDFLARE_ACCOUNT_ID + CLOUDFLARE_API_TOKEN
// and the domain onboarded to Email Sending (SPF/DKIM auto-added).
//
// nodemailer/SMTP stays as the local-dev fallback when no Cloudflare token is
// configured, so `npm run dev` still works without touching the live env.
const nodemailer = require('nodemailer');

let transporter = null;

// Keeps the HTTP request budget: a slow relay must never stall the API. A
// deployed Gmail relay can idle for 30s+, which is what Cloudflare reported as
// a 504 gateway timeout while verifying email OTP delivery.
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

async function sendMail(to, subject, html) {
  try {
    if (cloudFlareConfigured()) {
      await withTimeout(sendViaCloudflare(to, subject, html));
      console.log(`[MAILER] sent via Cloudflare to ${to}`);
      return true;
    }
    if (!process.env.SMTP_USER || !process.env.SMTP_PASS) {
      console.error('[MAILER] neither Cloudflare nor SMTP configured');
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