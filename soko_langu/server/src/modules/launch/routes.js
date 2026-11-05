const express = require('express');

const { z } = require('zod');
const commerceStore = require('../../services/commerce-store');
const { jsonError } = require('../../utils/http');
const { validate } = require('../../middleware/validation');
const { rateLimit } = require('../../middleware/rateLimiter');
const { verifyAdminSecret } = require('../../../middlewares/security');

const router = express.Router();
const WAITLIST_COLLECTION = 'landing_waitlist';

const subscribeLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 8,
  keyGenerator: (req) => `launch:subscribe:${req.ip || 'unknown'}`,
  message: 'Too many requests. Please try again later.',
});

function normalizeEmail(value) {
  return String(value || '').trim().toLowerCase();
}

function isValidEmail(value) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/i.test(value);
}

function isSpam(body) {
  const honeypot = String(body.website || body.company || '').trim();
  if (honeypot) return true;
  const started = Number(body.formStartedAt || 0);
  if (Number.isFinite(started) && started > 0) {
    const elapsed = Date.now() - started;
    if (elapsed >= 0 && elapsed < 1500) return true;
  }
  return false;
}

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
    lang: doc.lang || '',
    createdAt: toIso(doc.createdAt),
    updatedAt: toIso(doc.updatedAt),
  };
}

async function requireLaunchAdmin(req, res, next) {
  const secret = req.headers['x-admin-secret'];
  if (verifyAdminSecret(secret)) return next();
  return jsonError(res, { status: 401, code: 'AUTH_REQUIRED', message: 'Admin authentication required' });
}

router.post(
  '/subscribe',
  subscribeLimiter,
  validate({
    body: z.object({
      email: z.string().trim().min(3).max(254),
      name: z.string().trim().max(120).optional().default(''),
      lang: z.string().trim().max(12).optional().default('en'),
      source: z.string().trim().max(64).optional().default('web_launch'),
      website: z.string().optional().default(''),
      company: z.string().optional().default(''),
      formStartedAt: z.union([z.number(), z.string()]).optional(),
    }),
  }),
  async (req, res) => {
    if (isSpam(req.body)) {
      return res.json({ success: true, data: { status: 'ok' } });
    }

    const email = normalizeEmail(req.body.email);
    if (!isValidEmail(email)) {
      return jsonError(res, { status: 400, code: 'INVALID_EMAIL', message: 'Please enter a valid email address.' });
    }

    const name = String(req.body.name || '').trim().slice(0, 120);
    const lang = String(req.body.lang || 'en').trim().slice(0, 12);
    const source = String(req.body.source || 'web_launch').trim().slice(0, 64);
    const existing = await commerceStore.getDocument(WAITLIST_COLLECTION, email);

    if (existing) {
      await commerceStore.upsertDocument(WAITLIST_COLLECTION, email, {
        email,
        name: name || existing.name || '',
        lang: lang || existing.lang || 'en',
        source: existing.source || source,
        updatedAt: commerceStore.serverTimestamp(),
        duplicateSignupCount: commerceStore.increment(1),
        lastDuplicateAt: commerceStore.serverTimestamp(),
      });
      return res.json({ success: true, data: { status: 'duplicate', message: "You're already on the list!" } });
    }

    await commerceStore.setDocument(WAITLIST_COLLECTION, email, {
      email,
      name,
      lang,
      source,
      createdAt: commerceStore.serverTimestamp(),
      updatedAt: commerceStore.serverTimestamp(),
      duplicateSignupCount: 0,
    });

    return res.status(201).json({ success: true, data: { status: 'subscribed', message: "You're on the list!" } });
  },
);

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
  const header = ['email', 'name', 'source', 'lang', 'createdAt', 'updatedAt', 'duplicateSignupCount'];
  const lines = [header.join(',')];
  for (const row of rows) {
    lines.push([
      escapeCsv(row.email),
      escapeCsv(row.name),
      escapeCsv(row.source),
      escapeCsv(row.lang),
      escapeCsv(toIso(row.createdAt)),
      escapeCsv(toIso(row.updatedAt)),
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
