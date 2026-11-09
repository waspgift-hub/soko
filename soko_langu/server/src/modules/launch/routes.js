const express = require('express');

const { z } = require('zod');
const commerceStore = require('../../services/commerce-store');
const { jsonError } = require('../../utils/http');
const { validate } = require('../../middleware/validation');
const { rateLimit } = require('../../middleware/rateLimiter');
const { verifyAdminSecret } = require('../../../middlewares/security');
const { sendMail } = require('../../services/mailer');
const { esc } = require('../../services/email-layout');
const config = require('../../config');
const {
  normalizeEmail,
  isValidEmail,
  isSpam,
  hashValue,
  hashIp,
  randomToken,
} = require('../../utils/public-form');

const router = express.Router();
const WAITLIST_COLLECTION = 'landing_waitlist';
const CONSENT_VERSION = '2026-11';

const subscribeLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 8,
  keyGenerator: (req) => `launch:subscribe:${req.ip || 'unknown'}`,
  message: 'Too many requests. Please try again later.',
});

const unsubscribeLimiter = rateLimit({
  windowMs: 60 * 60 * 1000,
  max: 20,
  keyGenerator: (req) => `launch:unsubscribe:${req.ip || 'unknown'}`,
  message: 'Too many requests. Please try again later.',
});

function escapeCsv(value) {
  const text = String(value == null ? '' : value);
  if (/[",\n]/.test(text)) return `"${text.replace(/"/g, '""')}"`;
  return text;
}

function toIso(value) {
  if (!value) return '';
  if (typeof value.toDate === 'function') return value.toDate().toISOString();
  if (value instanceof Date) return value.toISOString();
  return String(value);
}

function serializeDoc(doc) {
  if (!doc) return null;
  return {
    id: doc.id,
    email: doc.email || '',
    name: doc.name || '',
    source: doc.source || 'launch_page',
    lang: doc.lang || doc.preferredLanguage || '',
    preferredLanguage: doc.preferredLanguage || doc.lang || '',
    userType: doc.userType || '',
    consent: Boolean(doc.consent),
    consentVersion: doc.consentVersion || '',
    consentAt: toIso(doc.consentAt),
    status: doc.status || (doc.unsubscribedAt ? 'unsubscribed' : 'subscribed'),
    confirmationStatus: doc.confirmationStatus || '',
    unsubscribedAt: toIso(doc.unsubscribedAt),
    createdAt: toIso(doc.createdAt),
    updatedAt: toIso(doc.updatedAt),
  };
}

async function requireLaunchAdmin(req, res, next) {
  const secret = req.headers['x-admin-secret'];
  if (verifyAdminSecret(secret)) return next();
  return jsonError(res, { status: 401, code: 'AUTH_REQUIRED', message: 'Admin authentication required' });
}

function frontendBaseUrl() {
  return String(config.urls.frontend || 'https://www.sokovibe.co.tz').replace(/\/+$/, '');
}

function unsubscribeUrl(token) {
  return `${frontendBaseUrl()}/unsubscribe?token=${encodeURIComponent(token)}`;
}

// The confirmation is a transactional consequence of the sign-up, not a
// marketing newsletter: it goes only to the address that submitted the form,
// states what was recorded, and carries a one-click unsubscribe link.
function confirmationHtml({ name, lang, link }) {
  const isEn = lang === 'en';
  const greeting = name ? `${isEn ? 'Hello' : 'Habari'} ${esc(name)},` : (isEn ? 'Hello,' : 'Habari,');
  return `
    <h2>${isEn ? 'You are on the launch list' : 'Umejiunga na orodha ya uzinduzi'}</h2>
    <p>${greeting}</p>
    <p>${isEn
      ? 'Thank you for joining the Soko Vibe launch list. We will email you when the app is ready and when there is important news about the launch.'
      : 'Asante kwa kujiunga na orodha ya uzinduzi ya Soko Vibe. Tutakutumia barua pepe app ikiwa tayari na tutakapokuwa na taarifa muhimu za uzinduzi.'}</p>
    <p>${isEn
      ? 'No spam, no selling your address. You can leave the list at any time.'
      : 'Hakuna barua taka, na hatuuzi anwani yako. Unaweza kuondoka kwenye orodha wakati wowote.'}</p>
    <p><a href="${esc(link)}" class="btn">${isEn ? 'Unsubscribe' : 'Jiondoe kwenye orodha'}</a></p>
    <p style="font-size:13px;color:#8b8b8b">${isEn
      ? 'If you did not sign up, ignore this email and you will not be added again.'
      : 'Kama hukujiunga, puuza barua hii na hutatajwa tena.'}</p>
  `;
}

async function sendConfirmation({ email, name, lang, token }) {
  const isEn = lang === 'en';
  const subject = isEn
    ? 'You are on the Soko Vibe launch list'
    : 'Umejiunga na orodha ya uzinduzi ya Soko Vibe';
  try {
    const sent = await sendMail(
      email,
      subject,
      confirmationHtml({ name, lang, link: unsubscribeUrl(token) }),
      undefined,
      { action: 'launch-waitlist', context: { recipientEmail: email } },
    );
    return sent ? 'sent' : 'failed';
  } catch (err) {
    console.error('[launch:subscribe] confirmation email failed:', err && err.message ? err.message : err);
    return 'failed';
  }
}

router.post(
  '/subscribe',
  subscribeLimiter,
  validate({
    body: z.object({
      email: z.string().trim().min(3).max(254),
      name: z.string().trim().max(120).optional().default(''),
      lang: z.string().trim().max(12).optional().default('sw'),
      preferredLanguage: z.enum(['sw', 'en']).optional(),
      source: z.string().trim().max(64).optional().default('website'),
      userType: z.enum(['buyer', 'seller', 'both']).optional().default('both'),
      consent: z.boolean().optional().default(false),
      consentVersion: z.string().trim().max(32).optional().default(CONSENT_VERSION),
      website: z.string().optional().default(''),
      company: z.string().optional().default(''),
      formStartedAt: z.union([z.number(), z.string()]).optional(),
    }),
  }),
  async (req, res) => {
    try {
      // Bots get a success-shaped response so they do not learn which control
      // caught them; nothing is stored.
      if (isSpam(req.body)) {
        return res.json({ success: true, data: { status: 'ok' } });
      }

      const email = normalizeEmail(req.body.email);
      if (!isValidEmail(email)) {
        return jsonError(res, { status: 400, code: 'INVALID_EMAIL', message: 'Please enter a valid email address.' });
      }

      const consent = req.body.consent === true;
      if (!consent) {
        return jsonError(res, {
          status: 400,
          code: 'CONSENT_REQUIRED',
          message: 'Please agree to receive launch updates before joining the list.',
        });
      }

      const requestedLang = req.body.preferredLanguage || req.body.lang;
      const lang = requestedLang === 'en' ? 'en' : 'sw';
      const name = String(req.body.name || '').trim().slice(0, 120);
      const source = String(req.body.source || 'website').trim().slice(0, 64);
      const userType = ['buyer', 'seller', 'both'].includes(req.body.userType) ? req.body.userType : 'both';
      const consentVersion = String(req.body.consentVersion || CONSENT_VERSION).slice(0, 32);
      const ipHash = hashIp(req);

      const existing = await commerceStore.getDocument(WAITLIST_COLLECTION, email);

      if (existing) {
        const wasUnsubscribed = existing.status === 'unsubscribed' || Boolean(existing.unsubscribedAt);

        // Someone who left the list and later asks to rejoin must be treated as
        // a fresh consent, not as a duplicate, or the confirmation (and its
        // unsubscribe link) would never reach them.
        if (wasUnsubscribed) {
          const token = randomToken();
          const confirmationStatus = await sendConfirmation({ email, name, lang, token });
          await commerceStore.upsertDocument(WAITLIST_COLLECTION, email, {
            email,
            name: name || existing.name || '',
            lang,
            preferredLanguage: lang,
            source: existing.source || source,
            userType,
            consent: true,
            consentVersion,
            consentAt: commerceStore.serverTimestamp(),
            consentIpHash: ipHash,
            status: 'subscribed',
            unsubscribedAt: null,
            unsubscribeTokenHash: hashValue(token),
            confirmationStatus,
            confirmationSentAt: confirmationStatus === 'sent' ? commerceStore.serverTimestamp() : null,
            updatedAt: commerceStore.serverTimestamp(),
            duplicateSignupCount: Number(existing.duplicateSignupCount || 0),
          });
          return res.status(201).json({ success: true, data: { status: 'subscribed', message: "You're on the list!" } });
        }

        const prevCount = Number(existing.duplicateSignupCount || 0);
        await commerceStore.upsertDocument(WAITLIST_COLLECTION, email, {
          email,
          name: name || existing.name || '',
          lang,
          preferredLanguage: lang,
          source: existing.source || source,
          userType,
          consent: true,
          consentVersion: existing.consentVersion || consentVersion,
          consentAt: existing.consentAt || commerceStore.serverTimestamp(),
          updatedAt: commerceStore.serverTimestamp(),
          duplicateSignupCount: prevCount + 1,
          lastDuplicateAt: commerceStore.serverTimestamp(),
        });
        return res.json({ success: true, data: { status: 'duplicate', message: "You're already on the list!" } });
      }

      const token = randomToken();
      const confirmationStatus = await sendConfirmation({ email, name, lang, token });

      await commerceStore.setDocument(WAITLIST_COLLECTION, email, {
        email,
        name,
        lang,
        preferredLanguage: lang,
        source,
        userType,
        consent: true,
        consentVersion,
        consentAt: commerceStore.serverTimestamp(),
        consentIpHash: ipHash,
        status: 'subscribed',
        unsubscribedAt: null,
        unsubscribeTokenHash: hashValue(token),
        confirmationStatus,
        confirmationSentAt: confirmationStatus === 'sent' ? commerceStore.serverTimestamp() : null,
        createdAt: commerceStore.serverTimestamp(),
        updatedAt: commerceStore.serverTimestamp(),
        duplicateSignupCount: 0,
      });

      return res.status(201).json({ success: true, data: { status: 'subscribed', message: "You're on the list!" } });
    } catch (err) {
      console.error('[launch:subscribe] failed:', err && err.message ? err.message : err);
      return jsonError(res, { status: 500, code: 'LAUNCH_SUBSCRIBE_FAILED', message: 'Unable to save your email right now. Please try again.' });
    }
  },
);

router.post(
  '/unsubscribe',
  unsubscribeLimiter,
  validate({ body: z.object({ token: z.string().trim().min(16).max(128) }) }),
  async (req, res) => {
    try {
      const tokenHash = hashValue(req.body.token);
      const matches = await commerceStore.listDocuments(WAITLIST_COLLECTION, {
        where: [{ field: 'unsubscribeTokenHash', op: '==', value: tokenHash }],
        limit: 1,
      });
      const subscriber = matches[0];
      if (!subscriber) {
        return jsonError(res, {
          status: 404,
          code: 'UNSUBSCRIBE_INVALID',
          message: 'This unsubscribe link is invalid or has already been replaced.',
        });
      }

      if (subscriber.status !== 'unsubscribed') {
        await commerceStore.upsertDocument(WAITLIST_COLLECTION, subscriber.id, {
          status: 'unsubscribed',
          unsubscribedAt: commerceStore.serverTimestamp(),
          updatedAt: commerceStore.serverTimestamp(),
        });
      }

      return res.json({ success: true, data: { status: 'unsubscribed' } });
    } catch (err) {
      console.error('[launch:unsubscribe] failed:', err && err.message ? err.message : err);
      return jsonError(res, { status: 500, code: 'UNSUBSCRIBE_FAILED', message: 'Unable to update your preference right now. Please try again.' });
    }
  },
);

router.get('/stats', requireLaunchAdmin, async (req, res) => {
  try {
    const rows = await commerceStore.listDocuments(WAITLIST_COLLECTION, {
      orderBy: 'createdAt',
      direction: 'desc',
      limit: 5000,
    });
    const byUserType = { buyer: 0, seller: 0, both: 0, unknown: 0 };
    let subscribed = 0;
    let unsubscribed = 0;
    let confirmed = 0;
    let failedConfirmation = 0;
    const sevenDaysAgo = Date.now() - 7 * 24 * 60 * 60 * 1000;
    let joinedLast7Days = 0;

    for (const row of rows) {
      const status = row.status || (row.unsubscribedAt ? 'unsubscribed' : 'subscribed');
      if (status === 'unsubscribed') unsubscribed += 1;
      else subscribed += 1;
      if (row.confirmationStatus === 'sent') confirmed += 1;
      if (row.confirmationStatus === 'failed') failedConfirmation += 1;
      const type = ['buyer', 'seller', 'both'].includes(row.userType) ? row.userType : 'unknown';
      byUserType[type] += 1;
      const created = typeof row.createdAt?.toDate === 'function' ? row.createdAt.toDate() : row.createdAt;
      if (created instanceof Date && created.getTime() >= sevenDaysAgo) joinedLast7Days += 1;
    }

    return res.json({
      success: true,
      data: {
        total: rows.length,
        subscribed,
        unsubscribed,
        confirmed,
        failedConfirmation,
        joinedLast7Days,
        byUserType,
      },
    });
  } catch (err) {
    console.error('[launch:stats] failed:', err && err.message ? err.message : err);
    return jsonError(res, { status: 500, code: 'LAUNCH_STATS_FAILED', message: 'Unable to read launch statistics.' });
  }
});

router.get('/subscribers', requireLaunchAdmin, async (req, res) => {
  const q = normalizeEmail(req.query.q);
  const limit = Math.min(Math.max(Number(req.query.limit) || 200, 1), 1000);
  const rows = await commerceStore.listDocuments(WAITLIST_COLLECTION, {
    orderBy: 'createdAt',
    direction: 'desc',
    limit,
  });
  let items = rows.map(serializeDoc).filter(Boolean);
  if (q) {
    items = items.filter((item) => item.email.includes(q) || String(item.name || '').toLowerCase().includes(q));
  }
  const duplicates = items.filter((item) => Number(rows.find((r) => r.id === item.id)?.duplicateSignupCount || 0) > 0).length;
  res.json({ success: true, data: { items, total: items.length, duplicates } });
});

router.get('/subscribers/export', requireLaunchAdmin, async (req, res) => {
  const rows = await commerceStore.listDocuments(WAITLIST_COLLECTION, {
    orderBy: 'createdAt',
    direction: 'desc',
    limit: 5000,
  });
  const header = [
    'email', 'name', 'source', 'lang', 'userType', 'consent', 'consentVersion',
    'status', 'confirmationStatus', 'createdAt', 'updatedAt', 'unsubscribedAt', 'duplicateSignupCount',
  ];
  const lines = [header.join(',')];
  for (const row of rows) {
    lines.push([
      escapeCsv(row.email),
      escapeCsv(row.name),
      escapeCsv(row.source),
      escapeCsv(row.lang || row.preferredLanguage),
      escapeCsv(row.userType),
      escapeCsv(Boolean(row.consent)),
      escapeCsv(row.consentVersion),
      escapeCsv(row.status || (row.unsubscribedAt ? 'unsubscribed' : 'subscribed')),
      escapeCsv(row.confirmationStatus),
      escapeCsv(toIso(row.createdAt)),
      escapeCsv(toIso(row.updatedAt)),
      escapeCsv(toIso(row.unsubscribedAt)),
      escapeCsv(row.duplicateSignupCount || 0),
    ].join(','));
  }
  const csv = '\ufeff' + lines.join('\n');
  res.setHeader('Content-Type', 'text/csv; charset=utf-8');
  res.setHeader('Content-Disposition', 'attachment; filename="soko-vibe-launch-subscribers.csv"');
  res.setHeader('Cache-Control', 'no-store');
  res.send(csv);
});

module.exports = router;
