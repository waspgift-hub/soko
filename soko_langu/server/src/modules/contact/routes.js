const express = require('express');

const { z } = require('zod');
const commerceStore = require('../../services/commerce-store');
const { jsonError } = require('../../utils/http');
const { validate } = require('../../middleware/validation');
const { rateLimit } = require('../../middleware/rateLimiter');
const { sendMail } = require('../../services/mailer');
const { esc } = require('../../services/email-layout');
const { verifyTurnstile } = require('../../utils/turnstile');
const {
  normalizeEmail,
  isValidEmail,
  isSpam,
  hashIp,
} = require('../../utils/public-form');

const router = express.Router();
const CONTACT_COLLECTION = 'landing_contact_messages';
const CONSENT_VERSION = '2026-11';

// Five messages per hour per IP is enough for a real conversation and stops a
// single client from using the form as a mail relay.
const contactLimiter = rateLimit({
  windowMs: 60 * 60 * 1000,
  max: 5,
  keyGenerator: (req) => `contact:submit:${req.ip || 'unknown'}`,
  message: 'Too many messages in a short time. Please try again later.',
});

const ALLOWED_SUBJECTS = ['general', 'buyer', 'seller', 'waitlist', 'privacy', 'press'];

function subjectLabel(subject, lang) {
  const labels = {
    general: { sw: 'Swali la jumla', en: 'General question' },
    buyer: { sw: 'Msaada kwa mnunuzi', en: 'Buyer support' },
    seller: { sw: 'Msaada kwa muuza', en: 'Seller support' },
    waitlist: { sw: 'Orodha ya uzinduzi', en: 'Waitlist or launch updates' },
    privacy: { sw: 'Faragha au data', en: 'Privacy or data request' },
    press: { sw: 'Vyombo vya habari na ushirikiano', en: 'Press and partnerships' },
  };
  const key = ALLOWED_SUBJECTS.includes(subject) ? subject : 'general';
  return (labels[key] || labels.general)[lang === 'en' ? 'en' : 'sw'];
}

function notificationHtml({ name, email, subject, message, lang, requestId, when }) {
  return `
    <h2>New message from the Soko Vibe website</h2>
    <p><strong>Name:</strong> ${esc(name)}</p>
    <p><strong>Email:</strong> ${esc(email)}</p>
    <p><strong>Subject:</strong> ${esc(subjectLabel(subject, 'en'))}</p>
    <p><strong>Language:</strong> ${esc(lang)}</p>
    <p><strong>Received:</strong> ${esc(when)}</p>
    <p><strong>Request ID:</strong> ${esc(requestId || '')}</p>
    <hr>
    <p style="white-space:pre-wrap">${esc(message)}</p>
  `;
}

async function notifySupport({ name, email, subject, message, lang, requestId, when }) {
  const to = process.env.WEBSITE_CONTACT_TO || process.env.SUPPORT_EMAIL_TO || 'support@sokovibe.co.tz';
  try {
    const sent = await sendMail(
      to,
      `[Website] ${subjectLabel(subject, 'en')} — ${name || email}`,
      notificationHtml({ name, email, subject, message, lang, requestId, when }),
      undefined,
      { action: 'website-contact', context: { recipientEmail: to } },
    );
    return sent ? 'sent' : 'failed';
  } catch (err) {
    console.error('[contact] notification failed:', err && err.message ? err.message : err);
    return 'failed';
  }
}

router.post(
  '/',
  contactLimiter,
  validate({
    body: z.object({
      name: z.string().trim().min(1).max(120),
      email: z.string().trim().toLowerCase().max(254),
      subject: z.string().trim().min(2).max(160),
      message: z.string().trim().min(20).max(4000),
      consent: z.boolean().optional().default(false),
      consentVersion: z.string().trim().max(32).optional().default(CONSENT_VERSION),
      preferredLanguage: z.enum(['sw', 'en']).optional(),
      lang: z.string().trim().max(12).optional().default('sw'),
      website: z.string().optional().default(''),
      company: z.string().optional().default(''),
      formStartedAt: z.union([z.number(), z.string()]).optional(),
      'cf-turnstile-response': z.string().optional(),
      turnstileToken: z.string().optional(),
      turnstile_token: z.string().optional(),
    }),
  }),
  async (req, res) => {
    try {
      // Same silent-success rule as the waitlist: a bot learns nothing, and no
      // message rows are created.
      if (isSpam(req.body)) {
        return res.json({ success: true, data: { status: 'ok' } });
      }

      const turnstile = await verifyTurnstile(req, { expectedAction: 'contact' });
      if (!turnstile.ok) {
        return jsonError(res, {
          status: turnstile.status || 403,
          code: turnstile.code || 'TURNSTILE_FAILED',
          message: turnstile.message || 'Bot verification failed. Please try again.',
        });
      }

      const email = normalizeEmail(req.body.email);
      if (!isValidEmail(email)) {
        return jsonError(res, { status: 400, code: 'INVALID_EMAIL', message: 'Please enter a valid email address.' });
      }

      if (req.body.consent !== true) {
        return jsonError(res, {
          status: 400,
          code: 'CONSENT_REQUIRED',
          message: 'Please agree to the privacy policy before sending your message.',
        });
      }

      const lang = (req.body.preferredLanguage || req.body.lang) === 'en' ? 'en' : 'sw';
      const subject = String(req.body.subject || 'general').trim().slice(0, 160);
      const name = String(req.body.name || '').trim().slice(0, 120);
      const message = String(req.body.message || '').trim().slice(0, 4000);
      const now = new Date();
      const requestId = req.id || null;

      const docId = await commerceStore.addDocument(CONTACT_COLLECTION, {
        name,
        email,
        subject,
        message,
        lang,
        consent: true,
        consentVersion: String(req.body.consentVersion || CONSENT_VERSION).slice(0, 32),
        consentAt: commerceStore.serverTimestamp(),
        ipHash: hashIp(req),
        userAgent: String(req.headers['user-agent'] || '').slice(0, 300),
        status: 'new',
        notificationStatus: 'pending',
        requestId,
        createdAt: commerceStore.serverTimestamp(),
        updatedAt: commerceStore.serverTimestamp(),
      });

      const notificationStatus = await notifySupport({
        name,
        email,
        subject,
        message,
        lang,
        requestId,
        when: now.toISOString(),
      });

      // The message is safely stored even when no mail channel is configured,
      // so the visitor still gets a truthful "received" response and an admin
      // can read it from Firestore.
      if (notificationStatus !== 'pending') {
        try {
          await commerceStore.updateDocument(CONTACT_COLLECTION, docId, {
            notificationStatus,
            updatedAt: commerceStore.serverTimestamp(),
          });
        } catch (err) {
          console.error('[contact] could not record notification status:', err && err.message ? err.message : err);
        }
      }

      return res.status(201).json({
        success: true,
        data: {
          status: 'received',
          requestId,
          message: 'Your message has been received.',
        },
      });
    } catch (err) {
      console.error('[contact] failed:', err && err.message ? err.message : err);
      return jsonError(res, {
        status: 500,
        code: 'CONTACT_FAILED',
        message: 'Unable to send your message right now. Please try again.',
      });
    }
  },
);

module.exports = router;
