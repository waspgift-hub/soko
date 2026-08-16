require('dotenv').config();
const express = require('express');
const compression = require('compression');
const cors = require('cors');
const crypto = require('crypto');
const admin = require('firebase-admin');
const nodemailer = require('nodemailer');
const axios = require('axios');

// Firebase init — MUST be before any module that calls admin.firestore() at require time
let db;
if (process.env.FIREBASE_SERVICE_ACCOUNT_JSON) {
  try {
    const sa = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON);
    admin.initializeApp({ credential: admin.credential.cert(sa) });
    db = admin.firestore();
  } catch (e) {
    console.error('[FIREBASE] Init failed:', e.message);
  }
}

const {
  clickpesaCollect, clickpesaPayout, clickpesaBalance, clickpesaPayoutPreview,
  clickpesaCreateBillPayOrder, clickpesaRawBalances, clickpesaQueryPayments,
  clickpesaQueryPayouts, clickpesaPaymentStatus,
  getUssdPushFee, getPayoutFee, calcGatewayFee, ALL_PAYMENT_METHODS,
  canonicalize, createPayloadChecksum,
} = require('./clickpesa');
const orderEngine = require('./orders');
const searchRouter = require('./search').router;
const notificationRouter = require('./notification').router;
const notifPrefs = require('./notificationPrefs');
const { parseFlashSaleEndTime, isFlashSaleStillActive, resolveEffectivePrice } = require('./money');

const DEFAULT_PAYOUT_FEE = 2000; // Estimated payout fee (actual varies by amount via clickpesaPayoutPreview)
const { groqChat, groqTranscribe } = require('./groq');

const ADMIN_EMAILS = ["admin@soko-langu.com", "admin@soko-vibe.com"];

// Catch uncaught exceptions & rejections — log but don't exit
process.on('uncaughtException', (err) => {
  console.error('[FATAL] Uncaught Exception:', err?.stack || err?.message || err);
});
process.on('unhandledRejection', (reason) => {
  console.error('[MEM] Unhandled Rejection:', reason?.message || reason);
});
process.on('warning', (warning) => {
  if (warning.name === 'MaxListenersExceededWarning') {
    console.warn('[MEM] Warning:', warning.message);
  }
});

const app = express();

// gzip all responses — JSON payloads shrink ~70% on the mobile data plans most
// users are on. Compress before the raw-body verify so webhook HMACs still see
// exact bytes (compression only affects outbound bodies, not inbound req.body).
app.use(compression());

const REQUEST_TIMEOUT = 20000; // 20 seconds

// Manual security headers (lightweight replacement for helmet)
app.use((req, res, next) => {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('X-XSS-Protection', '0');
  res.setHeader('Strict-Transport-Security', 'max-age=31536000; includeSubDomains');
  next();
});

// Tight CORS — only allow the Flutter app + admin panel origins
const ALLOWED_ORIGINS = [
  'https://soko-langu-server.onrender.com',
  'https://soko-langu-server-production.up.railway.app',
  'https://sokonimoko-8c171-a8d14.web.app',
  'https://sokonimoko-8c171-a8d14.firebaseapp.com',
  'capacitor://localhost',
  'http://localhost',
  'http://localhost:3000',
  'https://localhost',
];
app.use(cors({
  origin: (origin, cb) => {
    if (!origin || ALLOWED_ORIGINS.some(o => origin.startsWith(o))) return cb(null, true);
    cb(null, false); // Reject unknown origins
  },
  methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization', 'x-admin-secret', 'x-webhook-secret', 'x-notify-signature', 'x-malipopay-signature'],
  maxAge: 86400,
}));

// Keep the raw body for HMAC verification — Malipopay signs the exact bytes received.
app.use(express.json({
  limit: '1mb',
  verify: (req, res, buf) => { req.rawBody = buf; },
}));

app.use((req, res, next) => {
  res.setTimeout(REQUEST_TIMEOUT, () => {
    res.status(504).json({ error: 'Request timed out' });
  });
  next();
});

// ─── WhatsApp webhook — provider status callbacks (sent/delivered/read/failed) ───
// Registered before the rate limiter so provider callbacks are never throttled.
// Provider signs the raw body with HMAC-SHA256 and sends it in the
// X-Notify-Signature header only when a secret is configured. Set
// WHATSAPP_WEBHOOK_SECRET on the server to verify; without it we still accept.
app.post('/api/whatsapp/webhook', async (req, res) => {
  try {
    const body = req.body || {};
    const signature = req.headers['x-notify-signature'] || '';
    const secret = process.env.WHATSAPP_WEBHOOK_SECRET;
    if (secret && signature) {
      const raw = JSON.stringify(body);
      const expected = crypto.createHmac('sha256', secret).update(raw).digest('hex');
      const provided = String(signature).replace(/^sha256=/, '');
      if (expected !== provided) {
        console.warn(`[WA-WEBHOOK] invalid signature: got=${provided} expected=${expected}`);
        return res.status(401).json({ error: 'invalid signature' });
      }
    }
    const status = body.status || body.event || body.eventType || body.type || 'unknown';
    const phone = body.phone || body.to || body.recipient || body.phoneNumber || '';
    console.log(`[WA-WEBHOOK] status=${status} phone=${phone}`, JSON.stringify(body).slice(0, 500));
    if (db) {
      db.collection('whatsapp_webhook_logs').add({
        status,
        phone,
        event: body,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      }).catch((e) => console.error('[WA-WEBHOOK] log write error:', e.message));
    }
    res.status(200).json({ received: true });
  } catch (e) {
    console.error('[WA-WEBHOOK] error:', e.message);
    res.status(200).json({ received: true });
  }
});

// ─── Malipopay webhook — payment status callbacks (collection/disbursement) ───
// Registered before the rate limiter so payment callbacks are never throttled.
// Malipopay signs the raw request body with HMAC-SHA256 (header
// X-Malipopay-Signature: sha256=<hex>). Set MALIPOPAY_WEBHOOK_SECRET (dashboard
// Settings > Webhooks — per-webhook signing secret, not the API key) to verify;
// without it we still accept. Respond 2xx fast — provider retries up to 5 times
// with exponential backoff until it gets 2xx.
app.post('/api/malipopay/webhook', async (req, res) => {
  try {
    const signature = req.headers['x-malipopay-signature'] || '';
    const secret = process.env.MALIPOPAY_WEBHOOK_SECRET;
    if (secret && signature) {
      const raw = req.rawBody || Buffer.from(JSON.stringify(req.body));
      const expected = crypto.createHmac('sha256', secret).update(raw).digest('hex');
      const provided = String(signature).replace(/^sha256=/, '');
      const a = Buffer.from(provided, 'hex');
      const b = Buffer.from(expected, 'hex');
      const valid = a.length === b.length && crypto.timingSafeEqual(a, b);
      if (!valid) {
        console.warn(`[MALIPOPAY-WEBHOOK] invalid signature: got=${provided} expected=${expected}`);
        return res.status(401).json({ error: 'invalid signature' });
      }
    }
    const body = req.body || {};
    const reference = body.reference || body.customerReference || '';
    const status = body.status || 'unknown';
    console.log(`[MALIPOPAY-WEBHOOK] reference=${reference} status=${status}`, JSON.stringify(body).slice(0, 500));
    if (db && reference) {
      const refId = `mp_${String(reference).replace(/[^A-Za-z0-9_-]/g, '_')}`;
      const snap = await db.collection('malipopay_webhook_logs').doc(refId).get();
      if (!snap.exists) {
        await db.collection('malipopay_webhook_logs').doc(refId).set({
          reference,
          status,
          event: body,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      } else {
        console.log(`[MALIPOPAY-WEBHOOK] duplicate reference ${reference} ignored`);
      }
    }
    res.status(200).json({ received: true });
  } catch (e) {
    console.error('[MALIPOPAY-WEBHOOK] error:', e.message);
    res.status(200).json({ received: true });
  }
});

app.use('/api/', rateLimit);

// ─── Mount routers ──────────────────────────────────────────
app.use('/api/search', searchRouter);
app.use('/api/notification', notificationRouter);

function asyncHandler(fn) {
  return (req, res, next) => {
    Promise.resolve(fn(req, res, next)).catch(next);
  };
}

// ─── OneSignal helpers ──────────────────────────────────────────
const ONE_SIGNAL_APP_ID = process.env.ONE_SIGNAL_APP_ID;
const ONE_SIGNAL_REST_API_KEY = process.env.ONE_SIGNAL_REST_API_KEY;
const { randomUUID } = require('node:crypto');

const OS_AUTH = `Key ${ONE_SIGNAL_REST_API_KEY}`;
const OS_URL = 'https://api.onesignal.com/notifications';

function osHeaders() {
  return { 'Content-Type': 'application/json', 'Authorization': OS_AUTH };
}

// Map notification type → Android notification channel ID (v5 = IMPORTANCE_MAX for heads-up)
function notifTypeToChannel(type) {
  if (!type) return 'general_notifications_v6';
  if (type === 'chat' || type === 'group_chat') return 'chat_messages_v6';
  if (type === 'system' || type === 'admin' || type === 'alert') return 'system_alerts_v6';
  if (['payment','order','payout','dispute','refund','withdrawal',
       'escrow_release','auto_payout','escrow_auto_release',
       'dispute_resolved','cancelled','auto_withdrawal',
       'delivery_confirmed','payment_failed','kyc','deposit','deposit_failed'].includes(type)) return 'payments_notifications_v6';
  return 'general_notifications_v6';
}

// Retry with exponential backoff so transient OneSignal failures don't drop
// money-critical pushes — every call site inherits this via the helpers below.
async function postOneSignalWithRetry(payload, attempts = 3) {
  let delayMs = 1000;
  for (let attempt = 1; attempt <= attempts; attempt++) {
    try {
      return await axios.post(OS_URL, payload, { headers: osHeaders() });
    } catch (e) {
      const errBody = e.response?.data ? JSON.stringify(e.response.data) : e.message;
      if (attempt === attempts) {
        console.error(`[OS] FAILED after ${attempts} attempts: ${errBody}`);
        return null;
      }
      console.warn(`[OS] attempt ${attempt}/${attempts} failed, retrying in ${delayMs}ms: ${errBody}`);
      await new Promise((resolve) => setTimeout(resolve, delayMs));
      delayMs *= 2;
    }
  }
  return null;
}

// Money/account notifications must never be silently dropped by user
// preferences — a payment or dispute affecting funds must always reach the
// device. Only advisory channels (chat, marketing, general) honor toggles.
const CRITICAL_PUSH_TYPES = new Set([
  'order','payment','payment_failed','payment_received',
  'dispute','disputed','dispute_resolved',
  'refund','refund_processed','cancelled',
  'escrow_release','escrow_auto_release',
  'auto_payout','payout','payout_completed','payout_failed',
  'withdrawal','withdrawal_failed','auto_withdrawal',
  'kyc','kyc_approved','kyc_rejected','kyc_revoked',
  'deposit','deposit_failed','delivery_confirmed',
]);

// Firestore read cache for each user's notification language. We read the
// in-app language per user (the push must match what they chose, not the
// device locale) but the read hits the Spark 50K/day limit if every push
// re-fetches, so cache for 5 minutes — a stale language is only a cosmetic
// concern on a single notification.
const notifLangCache = require('./cache');
const NOTIF_LANG_TTL_MS = 5 * 60 * 1000;
const { localizeNotif, localizeEmailOtp, localizeDefaultReason, smsSafeForGateway } = require('./notif_lang');

async function getUserNotifLang(userId) {
  if (!db) return 'sw';
  const cached = notifLangCache.get(`notif_lang:${userId}`);
  if (cached) return cached;
  try {
    const snap = await db.collection('users').doc(userId).get();
    const lang = (snap.exists && snap.data().langCode) || 'sw';
    notifLangCache.set(`notif_lang:${userId}`, lang, NOTIF_LANG_TTL_MS);
    return lang;
  } catch (e) {
    console.error(`[OS] lang lookup failed for ${userId}: ${e.message}`);
    return 'sw';
  }
}

// The SMS language is a SEPARATE user preference from the in-app language
// (push/in-app follow `langCode`; SMS follows `smsLangCode`). The settings
// screen writes it via /api/user/sms-language; without the split a user who
// set SMS to English while the app is Swahili would still get Swahili SMS.
// Users who never chose an SMS language keep their in-app language.
async function getUserSmsLang(userId) {
  if (!db) return 'sw';
  const cached = notifLangCache.get(`sms_lang:${userId}`);
  if (cached) return cached;
  try {
    const snap = await db.collection('users').doc(userId).get();
    const data = snap.data() || {};
    const lang = data.smsLangCode || data.langCode || 'sw';
    notifLangCache.set(`sms_lang:${userId}`, lang, NOTIF_LANG_TTL_MS);
    return lang;
  } catch (e) {
    console.error(`[SMS] lang lookup failed for ${userId}: ${e.message}`);
    return 'sw';
  }
}

async function sendOneSignalNotification(userId, title, body, data = {}, opts = {}) {
  if (!userId) { console.log('[OS] No userId'); return null; }
  if (!ONE_SIGNAL_APP_ID || !ONE_SIGNAL_REST_API_KEY) {
    console.error('[OS] Missing ONE_SIGNAL_APP_ID or ONE_SIGNAL_REST_API_KEY'); return null;
  }
  const notifType = (data && data.type) || 'general';
  if (!opts.bypassPrefs && !CRITICAL_PUSH_TYPES.has(notifType)) {
    if (!(await notifPrefs.isPushAllowed(userId, notifType))) {
      console.log(`[OS] skipped push to ${userId} type=${notifType} (preferences)`);
      return null;
    }
  }
  // Localize the Swahili server copy to the user's in-app language. The server
  // strings are the source of truth; notif_lang falls back to Swahili when a
  // message isn't in the translation table. Chat pushes carry user-generated
  // text (sender name + message), never a server template, so skip them.
  const lang = await getUserNotifLang(userId);
  const isUserText = notifType === 'chat' || notifType === 'group_chat';
  const localized = isUserText
    ? { title: title || '', body: body || '' }
    : localizeNotif(lang, title || '', body || '');
  const localizedTitle = localized.title;
  const localizedBody = localized.body;
  // Both language keys carry the SAME localized text so the heading resolves to
  // the user's in-app choice regardless of device locale. OneSignal needs an
  // `en` fallback key or a Swahili-locale phone picks the first key; providing
  // en+sw both set to the localized string covers every device.
  const headings = { en: localizedTitle || '', sw: localizedTitle || '' };
  const contents = { en: localizedBody || '', sw: localizedBody || '' };

  // Push-only targeting: accounts carry email aliases in OneSignal and email
  // sending is disabled on this app, so without channel_for_external_user_ids
  // the whole notification fails 400 ("Email sending for this app has been
  // disabled") before it ever reaches the subscribed device.
  const payload = { ...(data || {}), type: notifType };

  const resp = await postOneSignalWithRetry({
    app_id: ONE_SIGNAL_APP_ID,
    idempotency_key: randomUUID(),
    include_external_user_ids: [userId],
    channel_for_external_user_ids: 'push',
    headings,
    contents,
    data: payload,
    priority: 10, android_priority: 'high', android_visibility: 1,
    existing_android_channel_id: notifTypeToChannel(notifType),
    android_sound: 'soko_notification',
    android_icon: 'ic_notification',
  });
  if (!resp) return null;
  const result = resp.data;
  if (result.id) {
    console.log(`[OS] sent push to ${userId} type=${(data && data.type) || 'general'} id=${result.id} recipients=${result.recipients ?? '?'} sent=${result.total_sent ?? '?'}`);
    if ((result.recipients ?? 0) === 0 || result.invalid_external_user_ids?.length) {
      console.warn(`[OS] WARNING: push accepted but 0 targeted recipients (external_user_id "${userId}" not subscribed?) invalid_external_user_ids=${result.invalid_external_user_ids?.length ?? 0}`);
    }
  } else console.error(`[OS] push send failed:`, JSON.stringify(result));

  const criticalTypes = ['order', 'payment', 'dispute', 'refund', 'boost', 'kyc', 'withdrawal'];
  if (criticalTypes.includes(notifType)) {
    sendEmailSmtp(userId, title, body).catch(() => {});
  }

  return result;
}

// ─── SMTP Email (free via Gmail — no domain needed) ─────
const smtpTransporter = nodemailer.createTransport({
  host: process.env.SMTP_HOST || 'smtp.gmail.com',
  port: parseInt(process.env.SMTP_PORT || '587'),
  secure: process.env.SMTP_SECURE === 'true',
  auth: { user: process.env.SMTP_USER, pass: process.env.SMTP_PASS },
});

async function sendEmailSmtp(userId, subject, bodyText) {
  if (!userId) { console.log('[SMTP] No userId'); return false; }
  try {
    const userRecord = await admin.auth().getUser(userId);
    const email = userRecord.email;
    if (!email) { console.log(`[SMTP] No email for user ${userId}`); return false; }
    const html = `<html><body style="font-family:Arial,sans-serif;padding:20px;max-width:600px;margin:0 auto"><h2 style="color:#40916C">${subject || ''}</h2><p>${bodyText || ''}</p><hr style="border:none;border-top:1px solid #e0e0e0;margin:20px 0"/><p style="color:#999;font-size:12px">Soko Vibe</p></body></html>`;
    await smtpTransporter.sendMail({
      from: process.env.SMTP_FROM || 'Soko Vibe <waspgift@gmail.com>',
      to: email,
      subject: subject || '',
      html,
    });
    console.log(`[SMTP] sent to ${email} subject="${subject}"`);
    return true;
  } catch (e) { console.error(`[SMTP] FAILED user=${userId}: ${e.message}`); return false; }
}

async function sendOneSignalBulk(userIds, title, body, data = {}, opts = {}) {
  if (!userIds || userIds.length === 0) return { successCount: 0 };
  if (!ONE_SIGNAL_APP_ID || !ONE_SIGNAL_REST_API_KEY) { console.error('[OS] Missing config'); return { successCount: 0 }; }
  const notifType = (data && data.type) || 'general';
  // Admin broadcasts bypass user preference gating so operators can always
  // reach their full audience; time-sensitive types deliver to everyone too.
  const allowedUserIds = opts.bypassPrefs || CRITICAL_PUSH_TYPES.has(notifType)
    ? userIds
    : await notifPrefs.filterAllowedUserIds(userIds, notifType);
  if (allowedUserIds.length === 0) { console.log(`[OS] bulk skipped type=${notifType} (no eligible users)`); return { successCount: 0 }; }
  let successCount = 0;
  const batchSize = 2000;
  for (let i = 0; i < allowedUserIds.length; i += batchSize) {
    const resp = await postOneSignalWithRetry({
      app_id: ONE_SIGNAL_APP_ID,
      idempotency_key: randomUUID(),
      include_external_user_ids: allowedUserIds.slice(i, i + batchSize),
      channel_for_external_user_ids: 'push',
      headings: { en: title || '', sw: title || '' },
      contents: { en: body || '', sw: body || '' },
      data: { ...(data || {}), type: notifType },
      priority: 10, android_priority: 'high', android_visibility: 1,
      existing_android_channel_id: notifTypeToChannel(notifType),
      android_sound: 'soko_notification',
      android_icon: 'ic_notification',
    });
    if (!resp) continue;
    const result = resp.data;
    if (result.id) {
      successCount += result.recipients || allowedUserIds.length;
      console.log(`[OS] bulk sent — id=${result.id} recipients=${result.recipients ?? allowedUserIds.length}`);
    } else {
      console.error(`[OS] bulk send failed:`, JSON.stringify(result));
    }
  }
  return { successCount };
}

/** @deprecated Replaced by sendOneSignalNotification — kept for backward compat */
// sendFcmToToken moved to OneSignal helpers above




const PORT = process.env.PORT || 3000;
const WEBHOOK_SECRET = process.env.WEBHOOK_SECRET || '';
// ESCROW_AUTO_RELEASE_DAYS is a single global override (default 0 = unset). When
// set it applies to BOTH local and regional escrows; otherwise local=3, regional=7.
const ESCROW_AUTO_RELEASE_DAYS = parseInt(process.env.ESCROW_AUTO_RELEASE_DAYS) || 0;
const ESCROW_LOCAL_DAYS = ESCROW_AUTO_RELEASE_DAYS > 0 ? ESCROW_AUTO_RELEASE_DAYS : 3;
const ESCROW_REGIONAL_DAYS = ESCROW_AUTO_RELEASE_DAYS > 0 ? ESCROW_AUTO_RELEASE_DAYS : 7;
const MAX_DAILY_SALE_AMOUNT = parseInt(process.env.MAX_DAILY_SALE_AMOUNT) || 5000000;

// ─── (All FCM helpers migrated to OneSignal helpers above) ───



// ─── Rate limiter (in-memory) ───
const rateHits = new Map();
const walletHits = new Map(); // per-wallet rate limit for payments
const RATE_WINDOW = 60 * 1000;
const RATE_MAX = 30;
const PAYMENT_RATE_MAX = 5; // max 5 payment attempts per 60s per IP

// The Maps above only ever grow — on the free 512MB plan a long-lived process
// would slowly OOM under sustained traffic. Sweep expired buckets every 5 min.
setInterval(() => {
  const now = Date.now();
  for (const map of [rateHits, walletHits]) {
    for (const [key, times] of map) {
      const live = times.filter((t) => now - t < RATE_WINDOW);
      if (live.length === 0) map.delete(key);
      else map.set(key, live);
    }
  }
}, 5 * 60 * 1000).unref();

function rateLimit(req, res, next) {
  const ip = req.ip || req.connection.remoteAddress || 'unknown';
  const now = Date.now();
  if (!rateHits.has(ip)) rateHits.set(ip, []);
  const hits = rateHits.get(ip).filter(t => now - t < RATE_WINDOW);
  hits.push(now);
  rateHits.set(ip, hits);
  if (hits.length > RATE_MAX) {
    return res.status(429).json({ error: 'Too many requests. Please slow down.' });
  }
  next();
}

// Stricter rate limit for payment endpoints
function paymentRateLimit(req, res, next) {
  const ip = req.ip || req.connection.remoteAddress || 'unknown';
  const now = Date.now();
  if (!walletHits.has(ip)) walletHits.set(ip, []);
  const hits = walletHits.get(ip).filter(t => now - t < RATE_WINDOW);
  hits.push(now);
  walletHits.set(ip, hits);
  if (hits.length > PAYMENT_RATE_MAX) {
    return res.status(429).json({ error: 'Too many payment attempts. Please wait before trying again.' });
  }
  next();
}

// Verify webhook checksum to prevent forged payment callbacks.
// ClickPesa signs the canonicalized JSON payload (sorted keys) with
// HMAC-SHA256 using CLICKPESA_CHECKSUM_KEY and sends it as `checksum` in the body.
function verifyWebhook(req, res, next) {
  const secret = process.env.CLICKPESA_CHECKSUM_KEY;
  if (!secret) {
    // Manual/dev mode — no secret configured, accept but log loudly.
    console.warn('[WEBHOOK] CLICKPESA_CHECKSUM_KEY not set — webhook checksum NOT verified');
    return next();
  }
  const body = req.body || {};
  const provided = typeof body.checksum === 'string' ? body.checksum : '';
  if (!provided) {
    console.warn('[WEBHOOK] missing checksum — rejecting forged callback');
    return res.status(401).json({ error: 'invalid checksum' });
  }
  const { checksum: _omit, checksumMethod: _omitMethod, ...rest } = body;
  const expected = createPayloadChecksum(rest);
  const match = expected && crypto.timingSafeEqual(Buffer.from(provided, 'hex'), Buffer.from(expected, 'hex'));
  if (!expected || !match) {
    console.warn('[WEBHOOK] invalid checksum — rejecting callback');
    return res.status(401).json({ error: 'invalid checksum' });
  }
  next();
}

// Check if user is suspended
async function checkSuspended(userId) {
  if (!db) return false;
  try {
    const userDoc = await db.collection('users').doc(userId).get();
    if (!userDoc.exists) return false;
    return userDoc.data().isSuspended === true;
  } catch { return false; }
}

// Check daily transaction limit for a buyer
async function checkDailyLimit(buyerId, amount) {
  if (!db) return true;
  try {
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const snap = await db.collection('transactions')
      .where('buyerId', '==', buyerId)
      .where('createdAt', '>=', admin.firestore.Timestamp.fromDate(today))
      .get();
    let dailyTotal = 0;
    snap.docs.forEach(doc => {
      const d = doc.data();
      if (d.status === 'completed' || d.status === 'pending' || d.status === 'escrow_hold') {
        dailyTotal += (d.productPrice || 0);
      }
    });
    if (dailyTotal + amount > MAX_DAILY_SALE_AMOUNT) {
      return false;
    }
    return true;
  } catch { return true; }
}

// Check for duplicate pending payment on same product by same buyer
// Auto-cancel stale pending transactions older than 30 minutes
async function checkDuplicatePayment(productId, buyerId) {
  if (!db) return false;
  try {
    const snap = await db.collection('transactions')
      .where('productId', '==', productId)
      .where('buyerId', '==', buyerId)
      .where('status', 'in', ['pending', 'escrow_hold'])
      .get();

    if (snap.docs.length === 0) return false;

    const now = Date.now();
    const PENDING_TIMEOUT = 5 * 60 * 1000;   // 5 min — pending STK expired
    let activeEscrow = false;

    for (const doc of snap.docs) {
      const data = doc.data();
      const createdAt = data.createdAt?.toDate?.()?.getTime?.() || 0;

      if (data.status === 'escrow_hold') {
        // Real escrow — never cancel automatically
        activeEscrow = true;
      } else if (createdAt > 0 && (now - createdAt) > PENDING_TIMEOUT) {
        // Stale pending (>5 min) — auto-cancel, allow retry
        await doc.ref.update({ status: 'failed', cancelledAt: admin.firestore.FieldValue.serverTimestamp(), cancelReason: 'auto-cancelled (stale)' });
      } else {
        // Recent pending — cancel it so user can retry now
        await doc.ref.update({ status: 'cancelled', cancelledAt: admin.firestore.FieldValue.serverTimestamp(), cancelReason: 'superseded by new payment' });
      }
    }

    return activeEscrow;
  } catch { return false; }
}

function sanitize(str) {
  if (typeof str !== 'string') return '';
  return str.replace(/<[^>]*>/g, '').trim().slice(0, 1000);
}

function isValidPhone(phone) {
  // Tanzanian phone numbers: +255XXXXXXXXX or 0XXXXXXXXX
  return /^(\+255|0)[67]\d{8}$/.test(phone.replace(/[\s-]/g, ''));
}

function isValidAmount(amount) {
  return typeof amount === 'number' && amount > 0 && Number.isFinite(amount) && amount < 100_000_000;
}

// Flash-sale helpers (parseFlashSaleEndTime, isFlashSaleStillActive,
// resolveEffectivePrice) live in server/money.js so they are unit-testable.

/** Accept x-admin-secret OR Firebase Bearer token from an admin user. */
async function requireAdmin(req, res) {
  const secret = req.headers['x-admin-secret'];
  if (secret && process.env.ADMIN_SECRET && secret === process.env.ADMIN_SECRET) {
    return { ok: true, uid: 'admin-secret' };
  }
  const authHeader = req.headers['authorization'] || req.headers['Authorization'] || '';
  if (authHeader.startsWith('Bearer ')) {
    try {
      const decoded = await admin.auth().verifyIdToken(authHeader.slice(7));
      const email = decoded.email || '';
      if (ADMIN_EMAILS.includes(email)) {
        return { ok: true, uid: decoded.uid };
      }
      if (db) {
        const userDoc = await db.collection('users').doc(decoded.uid).get();
        if (userDoc.exists && userDoc.data().isAdmin === true) {
          return { ok: true, uid: decoded.uid };
        }
      }
    } catch (_) {}
  }
  res.status(401).json({ error: 'Unauthorized' });
  return { ok: false };
}

/** Verify a Firebase Bearer token and return the authenticated user's uid. */
async function requireUser(req, res) {
  const authHeader = req.headers['authorization'] || req.headers['Authorization'] || '';
  if (!authHeader.startsWith('Bearer ')) {
    res.status(401).json({ error: 'Unauthorized' });
    return { ok: false };
  }
  try {
    const decoded = await admin.auth().verifyIdToken(authHeader.slice(7));
    return { ok: true, uid: decoded.uid };
  } catch (_) {
    res.status(403).json({ error: 'Invalid token' });
    return { ok: false };
  }
}

/** Allow the authenticated user OR an admin (secret/Bearer) to view private data. */
async function isOwnerOrAdmin(req, res, ownerId) {
  const auth = await requireUser(req, res);
  if (!auth.ok) return false;
  if (auth.uid === ownerId) return true;
  const adminAuth = await requireAdmin(req, res);
  return adminAuth.ok;
}

// ============================================================
// ⭐ BOOST PRODUCT — TIER-BASED FEATURED LISTING
// ============================================================
const BOOST_TIERS = {
  bronze: { price: 1500, days: 3 },
  silver: { price: 3000, days: 7 },
  gold: { price: 10000, days: 30 },
};

const PLATFORM_COMMISSION_PERCENT = 0.035; // 3.5% platform commission
const AD_REVENUE_PER_VIEW = 15;        // TZS per ad view (estimate only)
const MIN_WITHDRAWAL = 5000;          // Minimum withdrawal TZS 5,000

// Transaction statuses that mean money really came in. Used everywhere a
// transaction record is counted as a payment (buyer statement, admin
// dashboards) so a single source of truth prevents drift.
const PAID_STATUSES = new Set([
  'escrow_hold',
  'paid_escrow_hold',
  'paid_escrow_held',
  'dispatched',
  'delivered',
  'delivery_confirmed',
  'confirmed',
  'completed',
  'refunded',
]);

// Statuses where the escrow has actually been released to the seller (buyer
// confirmation, admin release, or auto-release). Escrow-hold statuses are NOT
// credits: the money is still held in pendingEscrow until release, so counting
// them here would inflate the seller's earnings before they earn them.
const SELLER_CREDIT_STATUSES = new Set([
  'delivered',
  'delivery_confirmed',
  'completed',
]);

// DEFAULT_PAYOUT_FEE (2000 TZS estimate) — actual ClickPesa payout fee varies by amount; use clickpesaPayoutPreview for exact fee

function generatePayoutReference(prefix = 'po') {
  return `${prefix}_${Date.now().toString(36)}_${Math.random().toString(36).substring(2, 8)}`;
}

const PAYOUT_RETRY_MAX = 3;
const PAYOUT_STATUSES = { PENDING: 'pending', PROCESSING: 'processing', SUCCESS: 'success', FAILED: 'failed', REFUNDED: 'refunded', REVERSED: 'reversed' };

async function createPayoutRecord({ userId, phone, amount, fee, netAmount, source, type, metadata }) {
  const payoutId = generatePayoutReference();
  const now = admin.firestore.FieldValue.serverTimestamp();
  const record = {
    payoutId,
    userId,
    userPhone: phone,
    amount: Math.round(amount),
    fee: Math.round(fee),
    netAmount: Math.round(netAmount),
    status: PAYOUT_STATUSES.PENDING,
    type,
    source: source || '',
    retryCount: 0,
    maxRetries: PAYOUT_RETRY_MAX,
    createdAt: now,
    updatedAt: now,
    metadata: metadata || {},
  };
  await db.collection('payouts').doc(payoutId).set(record);
  return payoutId;
}

async function updatePayoutStatus(payoutId, status, extra = {}) {
  if (!db || !payoutId) return;
  const updates = { status, updatedAt: admin.firestore.FieldValue.serverTimestamp(), ...extra };
  if (status === PAYOUT_STATUSES.SUCCESS || status === PAYOUT_STATUSES.FAILED) {
    updates.completedAt = admin.firestore.FieldValue.serverTimestamp();
  }
  await db.collection('payouts').doc(payoutId).update(updates);
}

async function processPayout({ payoutId, userId, phone, amount, fee, netAmount, source, type, metadata }) {
  if (!payoutId) {
    payoutId = await createPayoutRecord({ userId, phone, amount, fee, netAmount, source, type, metadata });
  }
  await updatePayoutStatus(payoutId, PAYOUT_STATUSES.PROCESSING);

  // Log a PENDING transaction record in the transactions collection for seller withdrawals
  if (type === 'seller_withdrawal' && db) {
    await db.collection('transactions').doc(payoutId).set({
      type: 'seller_withdrawal',
      userId,
      userPhone: phone,
      amount: Math.round(amount),
      fee: Math.round(fee),
      netAmount: Math.round(netAmount),
      status: 'PENDING',
      paymentMethod: 'ClickPesa',
      source: source || '',
      metadata: metadata || {},
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }

  const result = await clickpesaPayout({
    amount: netAmount,
    recipientPhone: phone,
    recipientName: metadata?.sellerName || '',
    narration: `Soko Vibe withdrawal: ${type || 'payout'}`,
    externalReference: payoutId,
  });

  const clickpesaRef = result.id || result.orderReference || '';
  await updatePayoutStatus(payoutId, PAYOUT_STATUSES.SUCCESS, { clickpesaReference: clickpesaRef });

  return { payoutId, clickpesaReference: clickpesaRef, netAmount, fee };
}

async function retryFailedPayout(payoutId) {
  const doc = await db.collection('payouts').doc(payoutId).get();
  if (!doc.exists) throw new Error('Payout not found');
  const payout = doc.data();
  if (payout.status !== PAYOUT_STATUSES.FAILED) throw new Error(`Cannot retry payout with status: ${payout.status}`);
  if (payout.retryCount >= payout.maxRetries) throw new Error('Max retries reached');

  await db.collection('payouts').doc(payoutId).update({
    retryCount: admin.firestore.FieldValue.increment(1),
    failureReason: '',
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return processPayout({
    payoutId, userId: payout.userId, phone: payout.userPhone,
    amount: payout.amount, fee: payout.fee, netAmount: payout.netAmount,
    source: payout.source, type: payout.type, metadata: payout.metadata,
  });
}

// ─── Payout Configuration ───
// Payouts use ClickPesa API. Fee is estimated at 2,000 TZS; actual fee from clickpesaPayoutPreview.

async function updateSellerKycOnProducts(sellerId, kycApproved) {
  if (!db || !sellerId) return;
  try {
    const productsSnap = await db.collection('products')
      .where('sellerId', '==', sellerId)
      .get();
    const batch = db.batch();
    let count = 0;
    productsSnap.docs.forEach(doc => {
      batch.update(doc.ref, { sellerKycApproved: kycApproved });
      count++;
    });
    if (count > 0) await batch.commit();
    console.log(`Updated sellerKycApproved=${kycApproved} on ${count} products for seller ${sellerId}`);
  } catch (e) {
    console.error(`Failed to update sellerKycApproved for ${sellerId}:`, e);
  }
}

app.post('/api/boost-product', async (req, res) => {
  try {
    const authHeader = req.headers.authorization || '';
    const token = authHeader.replace('Bearer ', '');
    if (!token) return res.status(401).json({ error: 'Unauthorized' });
    let decoded;
    try { decoded = await admin.auth().verifyIdToken(token); } catch (_) { return res.status(403).json({ error: 'Invalid token' }); }

    const { productId, tier, amount, durationDays, phone, userId, productName, productImage, productPrice, paymentMethod } = req.body;
    if (!userId || decoded.uid !== userId) {
      return res.status(403).json({ error: 'User ID mismatch' });
    }

    // Cancel stale pending boosts for same user+product so they don't get stuck
    if (db && userId && productId) {
      const staleSnap = await db.collection('transactions')
        .where('type', '==', 'boost')
        .where('productId', '==', productId)
        .where('userId', '==', userId)
        .where('status', '==', 'pending')
        .get();
      if (!staleSnap.empty) {
        const now = Date.now();
        const PENDING_TIMEOUT = 5 * 60 * 1000;
        for (const doc of staleSnap.docs) {
          const data = doc.data();
          const createdAt = data.createdAt?.toDate?.()?.getTime?.() || 0;
          const reason = createdAt > 0 && (now - createdAt) > PENDING_TIMEOUT
            ? 'auto-cancelled (stale)'
            : 'superseded by new boost';
          await doc.ref.update({
            status: 'failed',
            cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
            cancelReason: reason,
          });
        }
      }
    }
    if (!productId || !tier || !phone) {
      return res.status(400).json({ error: 'Missing required fields (productId, tier, phone)' });
    }

    // Normalize phone to 255 format
    const phoneDigits = phone.replace(/\D/g, '');
    const normalizedPhone = phoneDigits.startsWith('0')
      ? '255' + phoneDigits.substring(1)
      : phoneDigits.startsWith('255')
        ? phoneDigits
        : '255' + phoneDigits;

    const tierConfig = BOOST_TIERS[tier];
    if (!tierConfig) {
      return res.status(400).json({ error: 'Invalid boost tier' });
    }

    // BillPay fee (1%) is deducted from the collected amount, so we add it on top
    // so Soko Vibe still receives the full tier price. USSD Push fee is charged to
    // the customer by ClickPesa on top of the amount, so we send the real tier price
    // (never pre-added) to avoid charging the processing fee twice.
    const isBillPay = (paymentMethod || 'ussd_push') === 'billpay';
    const gatewayFee = calcGatewayFee(isBillPay ? 'billpay' : 'ussd_push', tierConfig.price, req.body.provider);
    const totalToCollect = isBillPay ? tierConfig.price + gatewayFee : tierConfig.price;

    const order_id = `boost${Date.now()}`;

    if (isBillPay) {
      // ── BillPay flow ──
      const billResult = await clickpesaCreateBillPayOrder({
        billAmount: totalToCollect,
        billDescription: `Soko Vibe boost: ${tier} - ${productName || 'Product'}`,
        billPaymentMode: 'EXACT',
        billReference: order_id,
      });

      if (!billResult || billResult.success === false || (!billResult.billPayNumber && !billResult.data?.billPayNumber)) {
        const errMsg = billResult?.message || billResult?.error || 'BillPay API failed to generate control number';
        return res.status(502).json({ error: `BillPay error: ${errMsg}` });
      }

      const billPayNumber = billResult.billPayNumber || billResult.data?.billPayNumber || billResult.billReference || '';
      const clickpesaRef = billResult.id || billResult.data?.id || billPayNumber || '';

      if (db) {
        await db.collection('transactions').doc(order_id).set({
          type: 'boost',
          productId,
          productName: productName || '',
          productImage: productImage || '',
          productPrice: productPrice || 0,
          tier: tier.toLowerCase(),
          amount: tierConfig.price,
          gatewayFee,
          totalAmount: totalToCollect,
          durationDays: tierConfig.days,
          userId: userId || '',
          buyerId: userId || '',
          buyerName: userId || '',
          buyerPhone: normalizedPhone,
          sellerName: 'Soko Vibe',
          billPayNumber,
          clickpesaReference: clickpesaRef,
          status: 'pending',
          paymentMethod: 'BillPay',
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      res.json({
        order_id,
        amount: tierConfig.price,
        gatewayFee,
        totalAmount: totalToCollect,
        billPayNumber,
        clickpesaReference: clickpesaRef,
        message: `BillPay control number: ${billPayNumber}. Jumla TZS ${totalToCollect.toLocaleString()} (Boost TZS ${tierConfig.price.toLocaleString()} + Ada TZS ${gatewayFee.toLocaleString()}). Open M-Pesa > Lipa > BillPay > enter ${billPayNumber} > amount TZS ${totalToCollect.toLocaleString()} > PIN.`,
      });
    } else {
      // ── USSD Push flow (async — return immediately) ──
      if (db) {
        await db.collection('transactions').doc(order_id).set({
          type: 'boost', productId, productName: productName || '',
          productImage: productImage || '', productPrice: productPrice || 0,
          tier: tier.toLowerCase(), amount: tierConfig.price, gatewayFee,
          totalAmount: totalToCollect, durationDays: tierConfig.days,
          userId: userId || '', buyerId: userId || '', buyerName: userId || '',
          buyerPhone: normalizedPhone, sellerName: 'Soko Vibe',
          status: 'pending', paymentMethod: paymentMethod || 'ussd_push',
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      // Fire ClickPesa async
      const baseUrl2 = process.env.PUBLIC_SERVER_URL || `${req.protocol}://${req.get('host')}`;
      clickpesaCollect({ amount: totalToCollect, orderReference: order_id, phoneNumber: normalizedPhone, callbackUrl: `${baseUrl2}/api/clickpesa/webhook` })
        .then((result) => {
          const ref = result?.id || result?.orderReference || '';
          if (!ref) { console.error(`[USSD] Boost ClickPesa no ref for ${order_id}`); return; }
          return db.collection('transactions').doc(order_id).update({ clickpesaReference: ref, ussdSent: true });
        })
        .then(() => console.log(`[USSD] Boost push sent for ${order_id}`))
        .catch((err) => {
          console.error(`[USSD] Boost ClickPesa error:`, err?.response?.data || err.message);
          const reason = err?.response?.data?.message || err?.message || 'USSD push haikufika';
          db.collection('transactions').doc(order_id).get().then(txSnap => {
            if (!txSnap.exists) return;
            const txData = txSnap.data();
            return txSnap.ref.update({
              status: 'failed',
              ussdFailed: true,
              failureReason: reason,
              completedAt: admin.firestore.FieldValue.serverTimestamp(),
            }).then(() => notifyBoostPaymentFailed(txData, reason));
          }).catch(() => {});
        });

      res.json({
        order_id, amount: tierConfig.price, gatewayFee, totalAmount: totalToCollect,
        message: `Jumla TZS ${totalToCollect.toLocaleString()} (Boost TZS ${tierConfig.price.toLocaleString()}). Ada ya ClickPesa inaongezwa kwenye malipo yako. Tuma PIN yako kwenye simu.`,
      });
    }
  } catch (e) {
    console.error('/api/boost-product error:', e?.message || e);
    const msg = e?.message?.includes('ClickPesa') ? e.message : 'Internal server error';
    res.status(500).json({ error: msg });
  }
});

// ============================================================
// 📱 SMS — SEND VIA MESEJI (falls back to Notify Africa)
// ============================================================
app.post('/api/sms/send', async (req, res) => {
  try {
    const auth = await requireUser(req, res);
    if (!auth.ok) return;
    const { phone, message } = req.body;
    if (!phone || !message) {
      return res.status(400).json({ error: 'Missing phone or message' });
    }
      const apiKey = process.env.MESEJI_API_KEY;
      if (apiKey) {
        const digits = phone.replace(/\D/g, '');
        // Meseji expects `contacts` as a single local-format STRING. The array
        // form returns `finalContacts.split is not a function` (verified live).
        const local = digits.startsWith('255') ? '0' + digits.slice(3) : !digits.startsWith('0') ? '0' + digits : digits;
        const configured = process.env.MESEJI_SENDER_ID || 'MESEJI';
        const senders = configured === 'MESEJI' ? ['MESEJI'] : [configured, 'MESEJI'];
        for (const sender of senders) {
          try {
            const resp = await axios.post('https://meseji.co.tz/api/v1/sms/send', {
              sender_id: sender,
              message,
              contacts: local,
            }, {
              headers: { 'x-api-key': apiKey, 'Content-Type': 'application/json' },
              timeout: 15000,
            });
            console.log(`/api/sms/send: ok sender=${sender} to ${local} batch=${resp.data?.batch_id || ''}`);
          return res.json({ sent: true, provider: 'meseji', sender, batchId: resp.data?.batch_id || null });
        } catch (e) {
          const errBody = e.response?.data ? JSON.stringify(e.response.data) : e.message;
          console.error(`/api/sms/send: sender ${sender} error: ${errBody}`);
        }
      }
    }
    if (await notifyAfricaSms(phone, message)) {
      return res.json({ sent: true, provider: 'notify_africa' });
    }
    console.error('/api/sms/send: no SMS provider delivered (Meseji or Notify Africa)');
    return res.status(502).json({ error: 'SMS provider error' });
  } catch (e) {
    console.error('/api/sms/send error:', e.message);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 💬 WHATSAPP — SEND VIA NOTIFY AFRICA (WABA)
// ============================================================
app.post('/api/whatsapp/send', async (req, res) => {
  try {
    const auth = await requireUser(req, res);
    if (!auth.ok) return;
    const { phone, message, templateName, templateParameters } = req.body;
    if (!phone) return res.status(400).json({ error: 'Missing phone' });
    if (!message && !templateName) {
      return res.status(400).json({ error: 'Missing message or templateName' });
    }
    if (templateName) {
      const result = await sendWhatsAppTemplate(phone, templateName, templateParameters);
      return res.json({ sent: result.success, messageId: result.messageId, error: result.error, ...(result.data ? { data: result.data } : {}) });
    }
    const result = await sendWhatsAppText(phone, message);
    res.json({ sent: result.success, messageId: result.messageId, error: result.error, ...(result.data ? { data: result.data } : {}) });
  } catch (e) {
    console.error('/api/whatsapp/send error:', e.message);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── SMS helper (prefers Meseji, falls back to Notify Africa) ───
async function sendSms(phone, message) {
  try {
    const apiKey = process.env.MESEJI_API_KEY;
    if (apiKey) {
      const digits = phone.replace(/\D/g, '');
      // Meseji expects `contacts` as a single local-format STRING; array form
      // fails with `finalContacts.split is not a function` (verified live).
      const local = digits.startsWith('255') ? '0' + digits.slice(3) : !digits.startsWith('0') ? '0' + digits : digits;
      const configured = process.env.MESEJI_SENDER_ID || 'MESEJI';
      const senders = configured === 'MESEJI' ? ['MESEJI'] : [configured, 'MESEJI'];
      for (const sender of senders) {
        try {
          const resp = await axios.post('https://meseji.co.tz/api/v1/sms/send', {
            sender_id: sender,
            message,
            contacts: local,
          }, {
            headers: { 'x-api-key': apiKey, 'Content-Type': 'application/json' },
            timeout: 15000,
          });
          console.log(`sendSms: ok sender=${sender} to ${local} batch=${resp.data?.batch_id || ''}`);
          return true;
        } catch (e) {
          const errBody = e.response?.data ? JSON.stringify(e.response.data) : e.message;
          console.error(`sendSms: sender ${sender} error: ${errBody}`);
        }
      }
    }
    if (await notifyAfricaSms(phone, message)) return true;
    console.error('sendSms: no SMS provider delivered (Meseji or Notify Africa)');
    return false;
  } catch (e) {
    console.error('sendSms error:', e.message);
    return false;
  }
}

// Resolves the recipient's in-app language, localizes the Swahili SMS template,
// then sends. Keeps every SMS in a single language matching the app.
async function sendLocalizedSms(phone, swMessage, userId) {
  const lang = userId ? await getUserSmsLang(userId) : 'sw';
  return sendSms(phone, smsSafeForGateway(lang, swMessage));
}

// ─── Notify Africa — SMS + WhatsApp (WABA) helpers ───
const NOTIFY_SMS_BASE = 'https://api.notify.africa';
const NOTIFY_WABA_BASE = 'https://notify-web-assistant-api.beagile.africa';

// Notify Africa requires international format (2557XXXXXXXX).
function toInternational(phone) {
  const d = String(phone).replace(/\D/g, '');
  return d.startsWith('0') ? '255' + d.slice(1) : d;
}

// Sends via Notify Africa; returns false if not configured or the send failed.
async function notifyAfricaSms(phone, message) {
  const apiKey = process.env.NOTIFY_AFRICA_SMS_API_KEY;
  const senderId = process.env.NOTIFY_AFRICA_SENDER_ID;
  if (!apiKey || !senderId) {
    console.error('notifyAfricaSms: missing NOTIFY_AFRICA_SMS_API_KEY / NOTIFY_AFRICA_SENDER_ID');
    return false;
  }
  try {
    const resp = await axios.post(`${NOTIFY_SMS_BASE}/api/v1/api/messages/send`, {
      phone_number: toInternational(phone),
      message,
      sender_id: senderId,
    }, {
      headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
      timeout: 15000,
    });
    const data = resp.data || {};
    const ok = data.status === 200 || (data.data && data.data.messageId);
    console.log(`notifyAfricaSms: ok to ${toInternational(phone)} msgId=${data.data?.messageId || ''} status=${data.data?.status || data.status || ''}`);
    return ok;
  } catch (e) {
    const errBody = e.response?.data ? JSON.stringify(e.response.data) : e.message;
    console.error(`notifyAfricaSms error: ${errBody}`);
    return false;
  }
}

async function sendWhatsAppText(phone, text) {
  const apiKey = process.env.NOTIFY_WABA_API_KEY;
  if (!apiKey) return { success: false, error: 'NOTIFY_WABA_API_KEY not configured' };
  try {
    const resp = await axios.post(`${NOTIFY_WABA_BASE}/v1/waba-api/messages/text`, {
      to: [toInternational(phone)],
      text,
    }, {
      headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
      timeout: 15000,
    });
    const r = resp.data?.data?.results?.[0] || {};
    console.log(`sendWhatsAppText: ok to ${toInternational(phone)} msgId=${r.messageId || ''}`);
    return { success: r.success === true, messageId: r.messageId || '', error: r.error || null, data: resp.data };
  } catch (e) {
    const errBody = e.response?.data ? JSON.stringify(e.response.data) : e.message;
    console.error(`sendWhatsAppText error: ${errBody}`);
    return { success: false, error: e.response?.data?.message || e.message };
  }
}

async function sendWhatsAppTemplate(phone, templateName, templateParameters) {
  const apiKey = process.env.NOTIFY_WABA_API_KEY;
  if (!apiKey) return { success: false, error: 'NOTIFY_WABA_API_KEY not configured' };
  try {
    const resp = await axios.post(`${NOTIFY_WABA_BASE}/v1/waba-api/messages/template`, {
      to: [toInternational(phone)],
      template_name: templateName,
      template_parameters: templateParameters || {},
    }, {
      headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
      timeout: 15000,
    });
    const r = resp.data?.data?.results?.[0] || {};
    console.log(`sendWhatsAppTemplate: ok to ${toInternational(phone)} msgId=${r.messageId || ''}`);
    return { success: r.success === true, messageId: r.messageId || '', error: r.error || null, data: resp.data };
  } catch (e) {
    const errBody = e.response?.data ? JSON.stringify(e.response.data) : e.message;
    console.error(`sendWhatsAppTemplate error: ${errBody}`);
    return { success: false, error: e.response?.data?.message || e.message };
  }
}

// ─── Boost payment failure — SMS + OneSignal push + in-app notification ───
async function notifyBoostPaymentFailed(tx, reason = '') {
  try {
    if (!tx || !tx.userId) return;
    // The gateway may pass an English default; project it to the user's
    // language so the boost-failure message stays a single language.
    const reasonLang = await getUserNotifLang(tx.userId);
    const reasonText = reason ? `. Sababu: ${localizeDefaultReason(reasonLang, reason)}` : '';
    const title = 'Malipo ya Boost Yameshindikana';
    const body = `Boost ya ${tx.productName || 'bidhaa yako'} haikukamilika${reasonText}. Jaribu tena kwenye app.`;
    await db.collection('notifications').add({
      userId: tx.userId,
      title,
      body,
      isRead: false,
      type: 'boost',
      data: { type: 'boost', status: 'failed', productId: tx.productId || '' },
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    await sendOneSignalNotification(tx.userId, title, body, { type: 'boost', status: 'failed', productId: tx.productId || '' });
    const userSnap = await db.collection('users').doc(tx.userId).get();
    const phone = userSnap.data()?.phone || tx.buyerPhone || '';
    if (phone) {
      const amount = tx.totalAmount || tx.amount || 0;
      const msg = `Soko Vibe: Malipo ya Boost ya TZS ${amount.toLocaleString()} hayakukamilika${reasonText}. Jaribu tena kwenye app.`;
      await sendLocalizedSms(phone, msg, tx.userId);
    } else {
      console.error(`notifyBoostPaymentFailed: no phone for user ${tx.userId} (tx ${tx.buyerPhone || 'none'}) — SMS skipped`);
    }
  } catch (e) {
    console.error('notifyBoostPaymentFailed error:', e.message);
  }
}

// ─── Admin notification helper — sends OneSignal + in-app to ALL admins ───
async function notifyAdmins(title, body, data = {}) {
  try {
    const adminSnap = await db.collection('users').where('isAdmin', '==', true).get();
    const promises = [];
    adminSnap.forEach(doc => {
      const uid = doc.id;
      promises.push(db.collection('notifications').add({
        userId: uid,
        title, body,
        isRead: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        data,
      }));
      promises.push(sendOneSignalNotification(uid, title, body, data));
    });
    await Promise.allSettled(promises);
  } catch (e) {
    console.error('notifyAdmins error:', e.message);
  }
}

// 🔐 PHONE OTP — SEND VIA SMS
// ============================================================
const otpPhoneHits = new Map();
const OTP_PHONE_WINDOW = 15 * 60 * 1000;
const OTP_PHONE_MAX = 3;

setInterval(() => {
  const now = Date.now();
  for (const map of [otpPhoneHits, otpVerifyHits]) {
    for (const [key, times] of map) {
      const live = times.filter((t) => now - t < OTP_PHONE_WINDOW);
      if (live.length === 0) map.delete(key);
      else map.set(key, live);
    }
  }
}, 5 * 60 * 1000).unref();

function otpPhoneRateLimit(req, res, next) {
  const phone = (req.body?.phone || '').replace(/\D/g, '');
  if (!phone) return next();
  const now = Date.now();
  if (!otpPhoneHits.has(phone)) otpPhoneHits.set(phone, []);
  const hits = otpPhoneHits.get(phone).filter(t => now - t < OTP_PHONE_WINDOW);
  hits.push(now);
  otpPhoneHits.set(phone, hits);
  if (hits.length > OTP_PHONE_MAX) {
    return res.status(429).json({ error: 'auth_otp_rate_limited' });
  }
  next();
}

const otpVerifyHits = new Map();
const OTP_VERIFY_WINDOW = 15 * 60 * 1000;
const OTP_VERIFY_MAX = 5;

function otpVerifyRateLimit(req, res, next) {
  const phone = (req.body?.phone || '').replace(/\D/g, '');
  const key = phone || (req.body?.email || '').trim().toLowerCase();
  if (!key) return next();
  const now = Date.now();
  if (!otpVerifyHits.has(key)) otpVerifyHits.set(key, []);
  const hits = otpVerifyHits.get(key).filter(t => now - t < OTP_VERIFY_WINDOW);
  hits.push(now);
  otpVerifyHits.set(key, hits);
  if (hits.length > OTP_VERIFY_MAX) {
    return res.status(429).json({ error: 'auth_otp_rate_limited' });
  }
  next();
}

app.post('/api/auth/send-otp', otpPhoneRateLimit, async (req, res) => {
  try {
    const { phone } = req.body;
    if (!phone) return res.status(400).json({ error: 'Phone number is required' });
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    // Generate 6-digit OTP
    const otp = Math.floor(100000 + Math.random() * 900000).toString();
    const hashed = crypto.createHash('sha256').update(otp).digest('hex');
    const expiresAt = Date.now() + 10 * 60 * 1000; // 10 minutes

    const cleanPhone = phone.replace(/\D/g, '');

    // Save to Firestore
    await db.collection('otp_codes').doc(cleanPhone).set({
      otpHash: hashed,
      expiresAt,
      used: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Send OTP via Meseji SMS — reuse shared sendSms helper
    const message = `Soko Vibe: OTP yako ni ${otp}. Inaisha kwa dakika 10.`;
    // send-otp runs pre-auth, so the app tells us its language via langCode
    // (defaults to Swahili for clients that don't send it).
    const langCode = ['sw', 'en', 'zh'].includes(req.body.langCode) ? req.body.langCode : 'sw';
    const sent = await sendSms(cleanPhone, smsSafeForGateway(langCode, message));

    // Save send status to the same OTP document for debugging
    await db.collection('otp_codes').doc(cleanPhone).update({
      smsSent: sent,
      smsAttemptedAt: admin.firestore.FieldValue.serverTimestamp(),
    }).catch(() => {});

    if (!sent) {
      console.error('/api/auth/send-otp: sendSms returned false for', cleanPhone);
      return res.status(502).json({ error: 'auth_otp_send_failed' });
    }

    res.json({ sent: true, message: 'OTP imetumwa kwa simu yako' });
  } catch (e) {
    console.error('/api/auth/send-otp error:', e.message);
    res.status(500).json({ error: 'auth_otp_send_failed' });
  }
});

// ============================================================
// 🔐 PHONE OTP — VERIFY
// ============================================================
app.post('/api/auth/verify-otp', otpVerifyRateLimit, async (req, res) => {
  try {
    const { phone, otp } = req.body;
    if (!phone || !otp) return res.status(400).json({ error: 'Phone and OTP are required' });
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const cleanPhone = phone.replace(/\D/g, '');
    const doc = await db.collection('otp_codes').doc(cleanPhone).get();
    if (!doc.exists) return res.status(400).json({ error: 'auth_otp_expired' });

    const data = doc.data();
    if (data.used) return res.status(400).json({ error: 'auth_otp_invalid' });
    if (Date.now() > data.expiresAt) return res.status(400).json({ error: 'auth_otp_expired' });

    const hashed = crypto.createHash('sha256').update(otp).digest('hex');
    if (hashed !== data.otpHash) return res.status(400).json({ error: 'auth_otp_invalid' });

    // Mark as used
    await doc.ref.update({ used: true });

    res.json({ valid: true });
  } catch (e) {
    console.error('/api/auth/verify-otp error:', e.message);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 🔐 EMAIL OTP — SEND (6-digit code sent to the email address)
// ============================================================
app.post('/api/auth/send-email-otp', async (req, res) => {
  try {
    const { email, langCode } = req.body;
    if (!email) return res.status(400).json({ error: 'Email is required' });
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const cleanEmail = email.trim().toLowerCase();
    const otp = Math.floor(100000 + Math.random() * 900000).toString();
    const hashed = crypto.createHash('sha256').update(otp).digest('hex');
    const expiresAt = Date.now() + 10 * 60 * 1000; // 10 minutes

    // Same otp_codes collection as phone OTP, keyed by the email address
    await db.collection('otp_codes').doc(cleanEmail).set({
      otpHash: hashed,
      expiresAt,
      used: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Pre-auth, so the app tells us its language via langCode (same as send-otp).
    const lang = ['sw', 'en', 'zh'].includes(langCode) ? langCode : 'sw';
    const copy = localizeEmailOtp(lang);

    // SMTP directly to the address (unlike sendEmailSmtp, the email may
    // not be a registered Firebase user yet at this stage)
    const subject = copy.subject;
    const html = `<html><body style="font-family:Arial,sans-serif;padding:20px;max-width:600px;margin:0 auto"><h2 style="color:#40916C">${copy.heading}</h2><p>${copy.body}</p><p style="font-size:32px;font-weight:bold;letter-spacing:8px;color:#40916C">${otp}</p><p>${copy.expires}</p><hr style="border:none;border-top:1px solid #e0e0e0;margin:20px 0"/><p style="color:#999;font-size:12px">Soko Vibe</p></body></html>`;

    try {
      await smtpTransporter.sendMail({
        from: process.env.SMTP_FROM || 'Soko Vibe <waspgift@gmail.com>',
        to: cleanEmail,
        subject,
        html,
      });
      console.log(`[SMTP] email OTP sent to ${cleanEmail}`);
    } catch (e) {
      console.error('/api/auth/send-email-otp SMTP error:', e.message);
      return res.status(502).json({ error: 'auth_otp_send_failed' });
    }

    res.json({ sent: true, message: 'OTP imetumwa kwa barua pepe yako' });
  } catch (e) {
    console.error('/api/auth/send-email-otp error:', e.message);
    res.status(500).json({ error: 'auth_otp_send_failed' });
  }
});

// ============================================================
// 🔐 EMAIL OTP — VERIFY
// ============================================================
app.post('/api/auth/verify-email-otp', otpVerifyRateLimit, async (req, res) => {
  try {
    const { email, otp } = req.body;
    if (!email || !otp) return res.status(400).json({ error: 'Email and OTP are required' });
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const cleanEmail = email.trim().toLowerCase();
    const doc = await db.collection('otp_codes').doc(cleanEmail).get();
    if (!doc.exists) return res.status(400).json({ error: 'auth_otp_expired' });

    const data = doc.data();
    if (data.used) return res.status(400).json({ error: 'auth_otp_invalid' });
    if (Date.now() > data.expiresAt) return res.status(400).json({ error: 'auth_otp_expired' });

    const hashed = crypto.createHash('sha256').update(otp).digest('hex');
    if (hashed !== data.otpHash) return res.status(400).json({ error: 'auth_otp_invalid' });

    await doc.ref.update({ used: true });

    res.json({ valid: true });
  } catch (e) {
    console.error('/api/auth/verify-email-otp error:', e.message);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 🔐 AUTH — Check if phone already registered
// ============================================================
app.post('/api/auth/check-phone', async (req, res) => {
  try {
    const { phone } = req.body;
    if (!phone) return res.status(400).json({ error: 'Phone is required' });
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const cleanPhone = phone.replace(/\D/g, '');
    const snap = await db.collection('users')
      .where('phone', 'in', [cleanPhone, `0${cleanPhone.slice(-9)}`, `+${cleanPhone}`])
      .limit(1)
      .get();

    res.json({ exists: !snap.empty });
  } catch (e) {
    console.error('/api/auth/check-phone error:', e.message);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 🔐 AUTH — Check if email already registered
// ============================================================
app.post('/api/auth/check-email', async (req, res) => {
  try {
    const { email } = req.body;
    if (!email) return res.status(400).json({ error: 'Email is required' });
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const snap = await db.collection('users')
      .where('email', '==', email.trim().toLowerCase())
      .limit(1)
      .get();

    let exists = !snap.empty;
    if (!exists) {
      try {
        await admin.auth().getUserByEmail(email.trim().toLowerCase());
        exists = true;
      } catch (_) {}
    }

    res.json({ exists });
  } catch (e) {
    console.error('/api/auth/check-email error:', e.message);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 🔐 AUTH — Reset password by phone + OTP
// ============================================================
app.post('/api/auth/reset-password-by-phone', otpVerifyRateLimit, async (req, res) => {
  try {
    const { phone, otp, newPassword } = req.body;
    if (!phone || !otp || !newPassword) {
      return res.status(400).json({ error: 'Phone, OTP, and new password are required' });
    }
    if (newPassword.length < 8) {
      return res.status(400).json({ error: 'Password must be at least 8 characters' });
    }
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const cleanPhone = phone.replace(/\D/g, '');

    // Verify OTP
    const otpDoc = await db.collection('otp_codes').doc(cleanPhone).get();
    if (!otpDoc.exists) return res.status(400).json({ error: 'auth_otp_expired' });

    const otpData = otpDoc.data();
    if (otpData.used) return res.status(400).json({ error: 'auth_otp_invalid' });
    if (Date.now() > otpData.expiresAt) return res.status(400).json({ error: 'auth_otp_expired' });

    const hashed = crypto.createHash('sha256').update(otp).digest('hex');
    if (hashed !== otpData.otpHash) return res.status(400).json({ error: 'auth_otp_invalid' });

    await otpDoc.ref.update({ used: true });

    // Look up user by phone
    const usersSnap = await db.collection('users')
      .where('phone', 'in', [cleanPhone, `0${cleanPhone.slice(-9)}`, `+${cleanPhone}`])
      .limit(1)
      .get();

    if (usersSnap.empty) {
      return res.status(404).json({ error: 'auth_no_account' });
    }

    const uid = usersSnap.docs[0].id;

    // Update Firebase Auth password
    try {
      await admin.auth().updateUser(uid, { password: newPassword });
    } catch (authErr) {
      return res.status(500).json({ error: 'failed_to_reset_password' });
    }

    res.json({ success: true, message: 'Nenosiri limebadilishwa kwa mafanikio.' });
  } catch (e) {
    console.error('/api/auth/reset-password-by-phone error:', e.message);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 🔐 PHONE LOGIN — Login with phone + OTP, returns Firebase custom token
// ============================================================
app.post('/api/phone-login', async (req, res) => {
  try {
    const { phone, otp } = req.body;
    if (!phone || !otp) return res.status(400).json({ error: 'Phone and OTP are required' });
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const cleanPhone = phone.replace(/\D/g, '');

    // Verify OTP
    const otpDoc = await db.collection('otp_codes').doc(cleanPhone).get();
    if (!otpDoc.exists) return res.status(400).json({ error: 'auth_otp_expired' });

    const otpData = otpDoc.data();
    if (otpData.used) return res.status(400).json({ error: 'auth_otp_invalid' });
    if (Date.now() > otpData.expiresAt) return res.status(400).json({ error: 'auth_otp_expired' });

    const hashed = crypto.createHash('sha256').update(otp).digest('hex');
    if (hashed !== otpData.otpHash) return res.status(400).json({ error: 'auth_otp_invalid' });

    await otpDoc.ref.update({ used: true });

    // Look up user by phone
    const usersSnap = await db.collection('users')
      .where('phone', 'in', [cleanPhone, `0${cleanPhone.slice(-9)}`, `+${cleanPhone}`])
      .limit(1)
      .get();

    let uid;
    if (usersSnap.empty) {
      // No account — create one with phone-based email
      const email = `phone_${cleanPhone}@soko-vibe.com`;
      const password = cleanPhone.slice(-6) + 'Sv!';
      const userRecord = await admin.auth().createUser({
        email,
        password,
        displayName: `User ${cleanPhone.slice(-4)}`,
      });
      uid = userRecord.uid;
      await db.collection('users').doc(uid).set({
        displayName: `User ${cleanPhone.slice(-4)}`,
        email,
        phone: cleanPhone,
        username: '',
        bio: '',
        location: '',
        mood: '',
        profileImage: '',
        paymentNumbers: {},
        shopBanner: '',
        shopBannerColor: '',
        shopAccentColor: '',
        latitude: null,
        longitude: null,
        coins: 0,
        viewerCoins: 0,
        sellerBalance: 0,
        soldCount: 0,
        isAdmin: false,
        isSuspended: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } else {
      uid = usersSnap.docs[0].id;
    }

    // Generate Firebase custom token
    const token = await admin.auth().createCustomToken(uid);
    res.json({ success: true, token });
  } catch (e) {
    console.error('/api/phone-login error:', e.message);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// 📲 OneSignal — SEND PUSH NOTIFICATION
// ============================================================
app.post('/api/send-notification', async (req, res) => {
  try {
    const auth = await requireUser(req, res);
    if (!auth.ok) return;
    const { userId, title, body, data } = req.body;
    if (!userId || !title) {
      return res.status(400).json({ error: 'Missing userId or title' });
    }

    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const userDoc = await db.collection('users').doc(userId).get();
    if (!userDoc.exists) return res.status(404).json({ error: 'User not found' });

    // Write in-app notification to Firestore
    await db.collection('notifications').add({
      userId,
      title,
      body: body || '',
      data: data || {},
      isRead: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    const notifType = data && data.type;
    await sendOneSignalNotification(userId, title, body || '', { ...(data || {}), type: notifType || 'general' });

    res.json({ sent: true });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 🔧 SETUP — Create admin account (requires ADMIN_SECRET)
// ============================================================
app.post('/api/setup-admin', async (req, res) => {
  try {
    const secret = req.headers['x-admin-secret'];
    if (!secret || secret !== process.env.ADMIN_SECRET) {
      return res.status(401).json({ error: 'Unauthorized' });
    }
    const { password } = req.body;
    if (!password || password.length < 6) {
      return res.status(400).json({ error: 'Password must be at least 6 characters' });
    }
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const email = 'admin@soko-langu.com';

    // Create Firebase Auth user
    let userRecord;
    try {
      userRecord = await admin.auth().getUserByEmail(email);
      await admin.auth().updateUser(userRecord.uid, { password, emailVerified: true });
    } catch {
      userRecord = await admin.auth().createUser({ email, password, emailVerified: true });
    }

    // Set admin flag in Firestore
    await db.collection('users').doc(userRecord.uid).set({
      email,
      isAdmin: true,
      isSuspended: false,
      coins: 0,
      viewerCoins: 0,
      sellerBalance: 0,
      totalSales: 0,
      grossSalesVolume: 0,
      pendingEscrow: 0,
      totalWithdrawn: 0,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    res.json({ success: true, uid: userRecord.uid, email });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 👑 ADMIN — LIST ALL USERS
// ============================================================
app.get('/api/admin/users', async (req, res) => {
  try {
    const secret = req.headers['x-admin-secret'];
    if (secret !== process.env.ADMIN_SECRET) {
      return res.status(401).json({ error: 'Unauthorized' });
    }
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const snap = await db.collection('users').orderBy('createdAt', 'desc').get();
    const users = snap.docs.map(doc => {
      const u = { uid: doc.id, ...doc.data() };
      if (typeof u.sellerBalance !== 'undefined') u.sellerBalance = Math.max(0, u.sellerBalance || 0);
      if (typeof u.pendingEscrow !== 'undefined') u.pendingEscrow = Math.max(0, u.pendingEscrow || 0);
      if (typeof u.coins !== 'undefined') u.coins = Math.max(0, u.coins || 0);
      return u;
    });
    res.json({ users });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 👑 ADMIN — LIST ALL PRODUCTS
// ============================================================
app.get('/api/admin/products', async (req, res) => {
  try {
    const secret = req.headers['x-admin-secret'];
    if (secret !== process.env.ADMIN_SECRET) {
      return res.status(401).json({ error: 'Unauthorized' });
    }
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const snap = await db.collection('products').orderBy('createdAt', 'desc').get();
    const products = snap.docs.map(doc => ({ id: doc.id, ...doc.data() }));
    res.json({ products });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 👑 ADMIN — UPDATE USER
// ============================================================
app.put('/api/admin/users/:uid', async (req, res) => {
  try {
    const secret = req.headers['x-admin-secret'];
    if (secret !== process.env.ADMIN_SECRET) {
      return res.status(401).json({ error: 'Unauthorized' });
    }
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const { uid } = req.params;
    const updates = {};
    const allowed = ['isAdmin', 'isSuspended', 'displayName', 'phone'];
    for (const field of allowed) {
      if (req.body[field] !== undefined) updates[field] = req.body[field];
    }
    if (Object.keys(updates).length === 0) {
      return res.status(400).json({ error: 'No valid fields to update' });
    }
    await db.collection('users').doc(uid).update(updates);
    res.json({ updated: true, uid, updates });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 👑 ADMIN — UPDATE PRODUCT
// ============================================================
app.put('/api/admin/products/:id', async (req, res) => {
  try {
    const secret = req.headers['x-admin-secret'];
    if (secret !== process.env.ADMIN_SECRET) {
      return res.status(401).json({ error: 'Unauthorized' });
    }
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const { id } = req.params;
    const updates = {};
    const allowed = ['isActive', 'isFeatured', 'featuredUntil'];
    for (const field of allowed) {
      if (req.body[field] !== undefined) updates[field] = req.body[field];
    }
    if (Object.keys(updates).length === 0) {
      return res.status(400).json({ error: 'No valid fields to update' });
    }
    await db.collection('products').doc(id).update(updates);
    res.json({ updated: true, id, updates });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 👑 ADMIN — UPDATE ORDER STATUS
// ============================================================
app.put('/api/admin/orders/:id', async (req, res) => {
  try {
    const secret = req.headers['x-admin-secret'];
    if (secret !== process.env.ADMIN_SECRET) {
      return res.status(401).json({ error: 'Unauthorized' });
    }
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const { id } = req.params;
    const { status } = req.body;
    const validStatuses = ['pending', 'confirmed', 'processing', 'shipped', 'delivered', 'cancelled'];
    if (!status || !validStatuses.includes(status)) {
      return res.status(400).json({ error: 'Invalid status' });
    }
    await db.collection('orders').doc(id).update({ status });
    res.json({ updated: true, id, status });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 👑 ADMIN — LIST ALL ORDERS
// ============================================================
app.get('/api/admin/orders', async (req, res) => {
  try {
    const secret = req.headers['x-admin-secret'];
    if (secret !== process.env.ADMIN_SECRET) {
      return res.status(401).json({ error: 'Unauthorized' });
    }
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const snap = await db.collection('orders').orderBy('createdAt', 'desc').get();
    const orders = snap.docs.map(doc => ({ id: doc.id, ...doc.data() }));
    res.json({ orders });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 📲 OneSignal — SEND BULK PUSH NOTIFICATION
// ============================================================
app.post('/api/send-bulk-notification', async (req, res) => {
  try {
    const auth = await requireAdmin(req, res);
    if (!auth.ok) return;

    const { title, body, userIds, target, data } = req.body;
    if (!title || !userIds || !Array.isArray(userIds) || userIds.length === 0) {
      return res.status(400).json({ error: 'Missing title or userIds array' });
    }

    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const result = await sendOneSignalBulk(userIds, title, body || '', { ...(data || {}), type: (data && data.type) || 'general' });

    // Log the notification in Firestore
    await db.collection('admin_notifications').add({
      title,
      body,
      target: target || 'all',
      sentCount: result.successCount,
      sentAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    res.json({
      sent: true,
      totalUsers: userIds.length,
      delivered: result.successCount,
    });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 🔒 ESCROW — Seller marks order as dispatched with proof
// ============================================================
app.post('/api/escrow/dispatch', async (req, res) => {
  try {
    const { orderId, userId, courierName, trackingNumber, driverPhone, notes, receiptUrl, photoUrl, note } = req.body;
    if (!orderId || !userId) {
      return res.status(400).json({ error: 'Missing orderId or userId' });
    }
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    // Verify the caller is the seller they claim to be
    const authHeader = req.headers.authorization || '';
    const token = authHeader.replace('Bearer ', '');
    if (!token) return res.status(401).json({ error: 'Unauthorized' });
    let decodedToken;
    try {
      decodedToken = await admin.auth().verifyIdToken(token);
    } catch (_) {
      return res.status(403).json({ error: 'Invalid token' });
    }
    if (decodedToken.uid !== userId) {
      return res.status(403).json({ error: 'Token does not match seller' });
    }

    const txDoc = await db.collection('transactions').doc(orderId).get();
    if (!txDoc.exists) {
      return res.status(404).json({ error: 'Transaction not found' });
    }

    const tx = txDoc.data();
    if (tx.sellerId !== userId) {
      return res.status(403).json({ error: 'Only the seller can dispatch' });
    }
    if (tx.status !== 'escrow_hold') {
      return res.status(400).json({ error: `Cannot dispatch from status: ${tx.status}` });
    }
    if (tx.escrowReleased === true) {
      return res.status(400).json({ error: 'Escrow already released' });
    }

    const dispatchProof = {
      courierName: courierName || '',
      trackingNumber: trackingNumber || '',
      driverPhone: driverPhone || '',
      receiptUrl: receiptUrl || '',
      photoUrl: photoUrl || '',
      note: note || notes || '',
      dispatchedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    await txDoc.ref.update({
      status: 'dispatched',
      dispatchProof,
      busName: req.body.busName || '',
      plateNumber: req.body.plateNumber || '',
      dispatchedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Notify buyer
    await db.collection('notifications').add({
      userId: tx.buyerId,
      title: '📦 Bidhaa Imesafirishwa!',
      body: `${tx.productName || 'Bidhaa'} imesafirishwa. Angalia proof of delivery na thibitisha upokeaji.`,
      isRead: false,
      data: { type: 'dispatched', transactionId: orderId },
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Push to buyer
    try {
      await sendOneSignalNotification(tx.buyerId, 'Bidhaa Imesafirishwa!', `${tx.productName || 'Bidhaa'} imesafirishwa. Thibitisha upokeaji ukishapata mzigo.`, { type: 'dispatched', transactionId: orderId });
    } catch (_) {}

    res.json({ success: true, message: 'Bidhaa imesafirishwa. Mnunuzi ataarifiwa.' });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 🔒 ESCROW — Buyer fills transport details after payment is held.
//     Buyer states how the goods will be sent (bus/bodaboda/pikipiki),
//     which the seller then uses to dispatch. Status must be escrow_hold.
// ============================================================
app.post('/api/escrow/buyer-transport', async (req, res) => {
  try {
    const auth = await requireUser(req, res);
    if (!auth.ok) return;
    const { orderId, userId, transportMethod, companyName, plateNumber, driverName, driverPhone, note } = req.body;
    if (!orderId || !userId) {
      return res.status(400).json({ error: 'Missing orderId or userId' });
    }
    if (!transportMethod || !['bus', 'bodaboda', 'pikipiki'].includes(transportMethod)) {
      return res.status(400).json({ error: 'transportMethod must be bus, bodaboda or pikipiki' });
    }
    if (auth.uid !== userId) {
      return res.status(403).json({ error: 'Forbidden: cannot set transport for another account' });
    }
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const txDoc = await db.collection('transactions').doc(orderId).get();
    if (!txDoc.exists) {
      return res.status(404).json({ error: 'Transaction not found' });
    }
    const tx = txDoc.data();
    if (tx.buyerId !== userId) {
      return res.status(403).json({ error: 'Only the buyer can set transport details' });
    }
    if (tx.status !== 'escrow_hold') {
      return res.status(400).json({ error: `Transport can only be set while payment is held. Current status: ${tx.status}` });
    }
    if (tx.escrowReleased === true) {
      return res.status(400).json({ error: 'Escrow already released' });
    }

    const buyerTransport = {
      method: transportMethod,
      companyName: companyName || '',
      plateNumber: plateNumber || '',
      driverName: driverName || '',
      driverPhone: driverPhone || '',
      note: note || '',
      submittedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    await txDoc.ref.update({ buyerTransport });

    // Notify seller (notification screen)
    await db.collection('notifications').add({
      userId: tx.sellerId,
      title: '🚚 Mnunuzi Amechagua Usafirishaji!',
      body: `${tx.buyerName || 'Mnunuzi'} ameweka taarifa za usafirishaji kwa Oda #${orderId}. Fungua app na tuma bidhaa.`,
      isRead: false,
      data: { type: 'buyer_transport', transactionId: orderId },
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Push to seller
    try {
      await sendOneSignalNotification(tx.sellerId, 'Mnunuzi Amechagua Usafirishaji!', `${tx.buyerName || 'Mnunuzi'} ameweka taarifa za usafirishaji. Tumia hizo taarifa kutuma bidhaa.`, { type: 'buyer_transport', transactionId: orderId });
    } catch (_) {}

    res.json({ success: true, message: 'Taarifa za usafirishaji zimehifadhiwa' });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 🔒 ESCROW — Release payment to seller (buyer confirms delivery)
//     Requires status to be 'dispatched' first
// ============================================================
app.post('/api/escrow/release', async (req, res) => {
  try {
    const auth = await requireUser(req, res);
    if (!auth.ok) return;
    const { orderId, userId } = req.body;
    if (!orderId || !userId) {
      return res.status(400).json({ error: 'Missing orderId or userId' });
    }
    if (auth.uid !== userId) {
      return res.status(403).json({ error: 'Forbidden: cannot confirm delivery for another account' });
    }
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    // Try transaction-based escrow first, then fall back to orders
    let txDoc = await db.collection('transactions').doc(orderId).get();
    let orderDoc = null;

    if (!txDoc.exists) {
      orderDoc = await db.collection('orders').doc(orderId).get();
    }

    if (!txDoc.exists && (!orderDoc || !orderDoc.exists)) {
      return res.status(404).json({ error: 'Transaction not found' });
    }

    let sellerId, sellerReceives, productName, productPrice, escrowReleased, platformFee, payoutMethod;

    if (txDoc.exists) {
      const tx = txDoc.data();
      if (tx.buyerId !== userId) {
        return res.status(403).json({ error: 'Only the buyer can confirm delivery' });
      }
      if (tx.status !== 'dispatched') {
        return res.status(400).json({ error: `Seller must dispatch the order first. Current status: ${tx.status}` });
      }
      if (tx.escrowReleased === true) {
        return res.status(400).json({ error: 'Escrow already released' });
      }
      sellerId = tx.sellerId;
      sellerReceives = tx.sellerReceives || 0;
      productName = tx.productName || 'Product';
      productPrice = tx.productPrice || 0;
      escrowReleased = tx.escrowReleased;
      platformFee = tx.platformFee || 0;
      payoutMethod = tx.payoutMethod;
    } else {
      const order = orderDoc.data();
      if (order.buyerId !== userId) {
        return res.status(403).json({ error: 'Only the buyer can confirm delivery' });
      }
      if (order.status !== 'shipped' && order.status !== 'confirmed') {
        return res.status(400).json({ error: `Order cannot be released from status: ${order.status}` });
      }
      if (order.escrowReleased === true) {
        return res.status(400).json({ error: 'Escrow already released' });
      }
      sellerId = order.sellerId;
      sellerReceives = order.totalAmount || 0;
      productName = order.items?.map(i => i.name).join(', ') || 'Product';
      productPrice = order.totalAmount || 0;
      escrowReleased = order.escrowReleased;
      platformFee = 0;
      payoutMethod = order.payoutMethod;
    }

    // Do not release escrow to a suspended seller — funds stay in escrow until
    // an admin resolves the case (see /api/escrow/admin-release).
    if (await checkSuspended(sellerId)) {
      return res.status(403).json({ error: 'Seller account is suspended; funds remain in escrow' });
    }

    // Mark as released
    const ref = txDoc.exists ? txDoc.ref : orderDoc.ref;
    await ref.update({
      status: 'delivered',
      escrowReleased: true,
      escrowReleasedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    const sellerDoc = await db.collection('users').doc(sellerId).get();
    const balanceBefore = sellerDoc.exists ? (sellerDoc.data().sellerBalance || 0) : 0;
    const pendingBefore = sellerDoc.exists ? (sellerDoc.data().pendingEscrow || 0) : 0;

    // Move from pendingEscrow to sellerBalance (safe decrement)
    const actualPending = Math.min(sellerReceives, pendingBefore);
    await db.collection('users').doc(sellerId).update({
      sellerBalance: admin.firestore.FieldValue.increment(sellerReceives),
      pendingEscrow: admin.firestore.FieldValue.increment(-actualPending),
    });

    // Record in revenue_transactions for seller
    await db.collection('revenue_transactions').add({
      userId: sellerId,
      type: 'sale',
      amount: sellerReceives,
      orderId,
      description: `Escrow released: ${productName} - TZS ${sellerReceives}`,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Audit log
    await auditLog({
      userId: sellerId,
      type: 'escrow_release',
      amount: sellerReceives,
      balanceBefore,
      balanceAfter: balanceBefore + sellerReceives,
      reason: `Escrow released for ${orderId}`,
      relatedId: orderId,
      metadata: { buyerId: userId, productName, pendingBefore, pendingAfter: pendingBefore - sellerReceives },
    });

    // Auto payout if seller enabled it (skip if payout method already set)
    let autoPaidOut = false;
    try {
      const sellerData = sellerDoc.data();
      if (sellerData?.autoPayout === true && !payoutMethod) {
        const sellerPhone = sellerData?.phone;
        const payoutFee = getPayoutFee(sellerReceives);
        if (sellerPhone && sellerReceives > payoutFee) {
          const netPayout = sellerReceives - payoutFee;
          const payoutRef = generatePayoutReference('ap');
          await db.collection('users').doc(sellerId).update({
            sellerBalance: admin.firestore.FieldValue.increment(-sellerReceives),
          });
          const mRef = await clickpesaPayout({
            amount: netPayout,
            phoneNumber: sellerPhone,
            orderReference: payoutRef,
          });
          await db.collection('payouts').doc(payoutRef).set({
            userId: sellerId, userPhone: sellerPhone,
            type: 'auto_payout', amount: sellerReceives, fee: payoutFee,
            netAmount: netPayout, clickpesaReference: mRef.id || '',
            status: 'completed', transactionId: orderId,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          await ref.update({ payoutMethod: 'auto' });
          autoPaidOut = true;
        }
      }
    } catch (_) {}

    // Notify seller
    if (autoPaidOut) {
      const payoutFee = getPayoutFee(sellerReceives);
      const netPayout = sellerReceives - payoutFee;
      await db.collection('notifications').add({
        userId: sellerId,
        title: 'Pesa Zimetumwa Moja kwa Moja!',
        body: `${productName} — TZS ${netPayout.toLocaleString()} zimetumwa kwa simu yako. Fee ya TZS ${payoutFee.toLocaleString()} imekatwa.`,
        isRead: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      try {
        sendOneSignalNotification(sellerId, 'Pesa Zimetumwa Moja kwa Moja!', `TZS ${netPayout.toLocaleString()} zimetumwa kwa simu yako (fee TZS ${payoutFee.toLocaleString()}).`, { type: 'auto_payout', transactionId: orderId }).catch(() => {});
      } catch (_) {}
    } else {
      await db.collection('notifications').add({
        userId: sellerId,
        title: 'Escrow Imefunguliwa!',
        body: `Mnunuzi amethibitisha upokeaji wa ${productName}. TZS ${sellerReceives.toLocaleString()} zimewekwa kwenye salio lako.`,
        isRead: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      try {
        await sendOneSignalNotification(sellerId, 'Escrow Imefunguliwa!', `${productName} — TZS ${sellerReceives.toLocaleString()} zimewekwa salio lako.`, { type: 'escrow_release', transactionId: orderId });
      } catch (_) {}
    }

    // Notify buyer
    await db.collection('notifications').add({
      userId: userId,
      title: 'Umethibitisha Upokeaji',
      body: `Umethibitisha kuwa umepokea ${productName}. Pesa zimefunguliwa kwa muuzaji.`,
      isRead: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    // Push to buyer
    try {
      await sendOneSignalNotification(userId, 'Umethibitisha Upokeaji', `${productName} — asante kwa kununua ndani ya SokoVibe!`, { type: 'delivery_confirmed', transactionId: orderId });
    } catch (_) {}

    // SMS seller about escrow release / auto payout
    try {
      const sellerUser = await db.collection('users').doc(sellerId).get();
      const sellerPhone = sellerUser.data()?.phone;
      if (sellerPhone) {
        const sellerMsg = autoPaidOut
          ? `Soko Vibe: TZS ${(sellerReceives - getPayoutFee(sellerReceives)).toLocaleString()} zimetumwa kwa simu yako kwa mauzo ya ${productName} (fee TZS ${getPayoutFee(sellerReceives).toLocaleString()}).`
          : `Soko Vibe: Mteja amethibitisha kupokea mzigo #${orderId}. TZS ${sellerReceives.toLocaleString()} zimetolewa Escrow na kuwekwa kwenye pochi yako.`;
        sendLocalizedSms(sellerPhone, sellerMsg, sellerId);
      }
    } catch (_) {}

    res.json({
      success: true,
      message: autoPaidOut
        ? `Auto payout: TZS ${(sellerReceives - getPayoutFee(sellerReceives)).toLocaleString()} sent to seller phone`
        : 'Escrow released. Seller balance credited.',
      autoPaidOut,
    });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 🔔 CLICKPESA WEBHOOK — Handle payment status updates
// ============================================================
// ClickPesa calls this when a USSD push payment is completed, failed,
// or when a payout status changes.
// Shared processor: applies a confirmed ClickPesa payment status to a deposit,
// boost, or purchase. Used by the webhook AND by the ClickPesa status poller so
// slow/lost webhooks never leave a payment stuck in pending.
async function applyClickPesaPayment(orderId, paymentStatus, extra = {}) {
  try {
    if (!orderId || !paymentStatus) return;
    if (!db) return;

    // Check if this is a deposit (wallet top-up)
    const depDoc = orderId.startsWith('dep')
      ? await db.collection('deposits').doc(orderId).get()
      : null;

    if (depDoc?.exists) {
      const dep = depDoc.data();
      if (dep.status === 'completed') {
        return;
      }
      if (paymentStatus === 'success') {
        const amount = dep.amount || 0;
        await db.collection('users').doc(dep.userId).update({
          walletBalance: admin.firestore.FieldValue.increment(amount),
        });
        await depDoc.ref.update({
          status: 'completed',
          clickpesaReference: extra.clickpesaReference || '',
          completedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        console.log(`Wallet deposit: TZS ${amount} credited to ${dep.userId} (ref: ${orderId})`);
        // Send push notification
        sendOneSignalNotification(dep.userId, 'Deposit Imethibitishwa!', `TZS ${amount.toLocaleString()} zimeongezwa kwenye pochi yako.`, { type: 'deposit', depositRef: orderId }).catch(() => {});
        // Write in-app notification
        try {
          await db.collection('notifications').add({
            userId: dep.userId,
            title: 'Deposit Imethibitishwa!',
            body: `TZS ${amount.toLocaleString()} zimeongezwa kwenye pochi yako.`,
            type: 'deposit',
            data: { depositRef: orderId, amount },
            read: false,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        } catch (_) {}
      } else {
        const failAmount = dep.amount || 0;
        const depLang = await getUserNotifLang(dep.userId);
        const failReason = extra.failureReason || localizeDefaultReason(depLang, 'Payment failed');
        await depDoc.ref.update({
          status: 'failed',
          failureReason: failReason,
          completedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        sendOneSignalNotification(dep.userId, 'Deposit Imeshindikana', `Malipo ya TZS ${failAmount.toLocaleString()} hayakukamilika. Sababu: ${failReason}`, { type: 'deposit_failed', depositRef: orderId, failureReason: failReason }).catch(() => {});
        try {
          const depUserSnap = await db.collection('users').doc(dep.userId).get();
          const depPhone = depUserSnap.data()?.phone || dep.phone || '';
          if (depPhone) {
            sendLocalizedSms(depPhone, `Soko Vibe: Malipo ya TZS ${failAmount.toLocaleString()} hayakukamilika. Sababu: ${failReason}. Jaribu tena kwenye app.`, dep.userId).catch(() => {});
          }
        } catch (_) {}
      }
      return;
    }

    const txDoc = await db.collection('transactions').doc(orderId).get();
    if (!txDoc.exists) {
      console.warn(`ClickPesa: transaction ${orderId} not found`);
      return;
    }

    const tx = txDoc.data();

    // Prevent double-processing — skip if already finalized, BUT a boost/order that
    // was prematurely auto-failed by the stale-timeout sweeper must be recoverable
    // when ClickPesa later confirms the payment actually succeeded (real money moved).
    if (tx.status === 'completed' || tx.status === 'escrow_hold') {
      return;
    }
    if (tx.status === 'failed' && paymentStatus !== 'success') {
      return;
    }

    const clickpesaRef = extra.clickpesaReference || tx.clickpesaReference || '';

    if (paymentStatus === 'success') {

      if (tx.type === 'boost') {
        // ── Activate product boost ──
        const tier = tx.tier || 'bronze';
        const tierConfig = BOOST_TIERS[tier] || BOOST_TIERS.bronze;
        const boostedUntil = new Date(Date.now() + tierConfig.days * 24 * 60 * 60 * 1000);

        // Mark transaction as completed FIRST so the UI updates immediately
        await txDoc.ref.update({
          status: 'completed',
          clickpesaReference: clickpesaRef,
          completedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        // Update product boost — non-blocking, don't await
        db.collection('products').doc(tx.productId).update({
          isBoosted: true,
          boostedUntil: admin.firestore.Timestamp.fromDate(boostedUntil),
          boostTier: tier,
          isFeatured: true,
          featuredUntil: admin.firestore.Timestamp.fromDate(boostedUntil),
        }).catch(err => console.error(`Boost product update failed: ${err.message}`));

        // Notify user — non-blocking
        if (tx.userId) {
          db.collection('notifications').add({
            userId: tx.userId,
            title: '✅ Boost imewashwa!',
            body: `Bidhaa yako imepandishwa kwa daraja la ${tier} kwa siku ${tierConfig.days}.`,
            data: { type: 'boost', productId: tx.productId },
            isRead: false,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          }).catch(() => {});
          sendOneSignalNotification(tx.userId, '✅ Boost imewashwa!', `Bidhaa yako imepandishwa kwa daraja la ${tier} kwa siku ${tierConfig.days}.`, { type: 'boost', productId: tx.productId || '' }).catch(() => {});
        }

        notifyBoostBroadcast(tx.productId, tier, tx.userId).catch(() => {});

        // Record boost revenue
        const boostAmount = tx.amount || tierConfig.price;
        db.collection('revenue_transactions').add({
          userId: 'platform',
          amount: boostAmount,
          sokoLanguCommission: boostAmount,
          type: 'boost',
          subType: tier,
          productId: tx.productId,
          transactionId: orderId,
          buyerPhone: tx.buyerPhone || '',
          paymentMethod: 'ClickPesa',
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        }).catch(() => {});

        db.collection('users').doc(tx.userId).get().then(sellerSnap => {
          const sellerPhone = sellerSnap.data()?.phone;
          if (sellerPhone) {
            const expiryStr = new Date(Date.now() + tierConfig.days * 24 * 60 * 60 * 1000).toLocaleDateString('sw-TZ');
            const msg = `Soko Vibe: Malipo ya Boost ya TZS ${boostAmount.toLocaleString()} yamefanikiwa! Bidhaa yako sasa inaonyeshwa kipaumbele hadi ${expiryStr}.`;
            sendLocalizedSms(sellerPhone, msg, tx.userId);
          }
        }).catch(() => {});

      } else if (tx.type === 'purchase') {
        // ── Move to escrow hold ──
        const productPrice = tx.productPrice || 0;
        const platformFee = Math.round(productPrice * PLATFORM_COMMISSION_PERCENT);
        const processingFee = getUssdPushFee(productPrice);
        // Seller is reimbursed the shipping cost from escrow on delivery
        const sellerReceives = productPrice + Math.round(tx.shippingCost || 0);
        const deliveryType = tx.deliveryType || 'local';
        const autoReleaseDays = tx.autoReleaseDays || (deliveryType === 'regional' ? ESCROW_REGIONAL_DAYS : ESCROW_LOCAL_DAYS);
        const escrowExpiry = new Date(Date.now() + autoReleaseDays * 24 * 60 * 60 * 1000);

        await txDoc.ref.update({
          processingFee,
          platformFee,
          sokoLanguCommission: platformFee,
          totalAmount: tx.totalAmount || (productPrice + Math.round(tx.shippingCost || 0) + platformFee + processingFee),
          sellerReceives,
          status: 'escrow_hold',
          paymentMethod: 'ClickPesa',
          clickpesaReference: clickpesaRef,
          transactionReference: orderId,
          escrowStatus: 'held',
          escrowHeldAt: admin.firestore.FieldValue.serverTimestamp(),
          escrowExpiresAt: admin.firestore.Timestamp.fromDate(escrowExpiry),
        });

        // Keep the mirrored orders doc in sync so both collections agree.
        db.collection('orders').doc(orderId).update({
          status: 'escrow_hold',
          escrowStatus: 'held',
          escrowHeldAt: admin.firestore.FieldValue.serverTimestamp(),
        }).catch(() => {});

        // Everything below is non-critical — fire-and-forget for speed
        db.collection('revenue_transactions').add({
          userId: 'platform',
          amount: platformFee,
          type: 'commission',
          description: `Commission for ${tx.productName || 'Product'} (escrow)`,
          transactionId: orderId,
          productName: tx.productName || '',
          productPrice,
          sokoLanguCommission: platformFee,
          buyerName: tx.buyerName || '',
          paymentMethod: 'ClickPesa',
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
        }).catch(() => {});

        db.collection('flash_sales')
          .where('productId', '==', tx.productId)
          .where('isActive', '==', true)
          .limit(5)
          .get().then(fsSnap => {
            const payNow = new Date();
            const activeDoc = fsSnap.docs.find(d => isFlashSaleStillActive(d.data(), payNow));
            if (activeDoc) {
              const fsData = activeDoc.data();
              const newStock = Math.max(0, (fsData.stock || 0) - 1);
              const newSold = (fsData.soldCount || 0) + 1;
              activeDoc.ref.update({ stock: newStock, soldCount: newSold, isActive: newStock > 0 });
            }
          }).catch(() => {});

        if (sellerReceives > 0 && tx.sellerId) {
          db.collection('users').doc(tx.sellerId).set({
            pendingEscrow: admin.firestore.FieldValue.increment(sellerReceives),
            totalSales: admin.firestore.FieldValue.increment(1),
            grossSalesVolume: admin.firestore.FieldValue.increment(productPrice),
            lastSaleAt: admin.firestore.FieldValue.serverTimestamp(),
          }, { merge: true }).then(() => {
            db.collection('notifications').add({
              userId: tx.sellerId,
              title: 'Umepata Mauzo!',
              body: `${tx.productName || 'Bidhaa'} imeuzwa. TZS ${sellerReceives.toLocaleString()} zimewekwa escrow.`,
              isRead: false,
              type: 'sale',
              transactionId: orderId,
              buyerPhone: tx.buyerPhone || '',
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
            }).catch(() => {});
            sendOneSignalNotification(tx.sellerId, 'Umepata Mauzo!', `${tx.productName || 'Bidhaa'} imeuzwa. TZS ${sellerReceives.toLocaleString()} zimewekwa escrow.`, { type: 'order', productId: tx.productId || '', transactionId: orderId }).catch(() => {});
          }).catch(() => {});
        }

        if (tx.buyerId) {
          db.collection('notifications').add({
            userId: tx.buyerId,
            title: 'Malipo Yamekamilika!',
            body: `Malipo ya ${tx.productName || 'Bidhaa'} yamepokelewa. Thibitisha upokeaji ili muuzaji apate hela zake.`,
            isRead: false,
            type: 'escrow_confirm',
            transactionId: orderId,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          }).catch(() => {});
          sendOneSignalNotification(tx.buyerId, 'Malipo Yamekamilika!', `Malipo ya ${tx.productName || 'Bidhaa'} yamepokelewa.`, { type: 'order', productId: tx.productId || '', transactionId: orderId }).catch(() => {});
        }

        // SMS notifications for escrow_hold
        try {
          const buyerMsg = `Soko Vibe: Malipo ya TZS ${productPrice.toLocaleString()} kwa Oda #${orderId} yamepokelewa na kuwekwa salama Escrow. Muuzaji anajiandaa kutuma mzigo wako.`;
          if (tx.buyerPhone) sendLocalizedSms(tx.buyerPhone, buyerMsg, tx.buyerId);
        } catch (_) {}
        try {
          if (tx.sellerId) {
            const sellerSnap = await db.collection('users').doc(tx.sellerId).get();
            const sellerPhone = sellerSnap.data()?.phone;
            if (sellerPhone) {
              const sellerMsg = `Soko Vibe: Oda #${orderId} imelipiwa! Fedha ipo salama Escrow. Tafadhali kamilisha usafirishaji stendi na ujaze risiti ya basi kwenye app.`;
              sendLocalizedSms(sellerPhone, sellerMsg, tx.sellerId);
            }
          }
        } catch (_) {}
      }
    } else if (paymentStatus === 'failed') {
      const buyerLang = tx.buyerId ? await getUserNotifLang(tx.buyerId) : 'sw';
      const failureReason = extra.failureReason || localizeDefaultReason(buyerLang, 'payment failed');
      await txDoc.ref.update({
        status: 'failed',
        clickpesaReference: clickpesaRef,
        failureReason,
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // Keep the mirrored orders doc in sync on failure too.
      db.collection('orders').doc(orderId).update({
        status: 'failed',
        failureReason,
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
      }).catch(() => {});

      // Boost failure — SMS + push + in-app to the boost user (buyerId === userId)
      if (tx.type === 'boost') {
        await notifyBoostPaymentFailed(tx, failureReason);
      } else if (tx.buyerId) {
        await db.collection('notifications').add({
          userId: tx.buyerId,
          title: 'Malipo Yameshindikana',
          body: `Malipo ya ${tx.productName || 'Bidhaa'} hayakukamilika. Jaribu tena au wasiliana nasi. Sababu: ${failureReason}`,
          isRead: false,
          type: 'payment_failed',
          transactionId: orderId,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        try {
          await sendOneSignalNotification(tx.buyerId, 'Malipo Yameshindikana', `Malipo ya ${tx.productName || 'Bidhaa'} hayakukamilika. Jaribu tena kwenye app.`, { type: 'payment_failed', productId: tx.productId || '', transactionId: orderId });
        } catch (_) {}
        try {
          const buyerSnap = await db.collection('users').doc(tx.buyerId).get();
          const buyerPhone = buyerSnap.data()?.phone || tx.buyerPhone || '';
          if (buyerPhone) {
            sendLocalizedSms(buyerPhone, `Soko Vibe: Malipo ya ${tx.productName || 'Bidhaa'} hayakukamilika. Tafadhali jaribu tena kwenye app. Sababu: ${failureReason}`, tx.buyerId).catch(() => {});
          }
        } catch (_) {}
      }
    }

  } catch (e) {
    console.error('applyClickPesaPayment error:', e);
  }
}

// ============================================================
// CLICKPESA WEBHOOK — real-time payment callbacks from ClickPesa
//     (statuses also polled by the ClickPesa poller below as backup)
// ============================================================
app.post('/api/clickpesa/webhook', verifyWebhook, async (req, res) => {
  try {
    let payload = req.body;
    if (payload.data && typeof payload.data === 'object') {
      payload = payload.data;
    }

    const orderId = payload.orderReference || payload.order_id || payload.externalId || '';
    const rawStatus = (payload.status || payload.paymentStatus || payload.event || '').toString().toLowerCase();
    const paymentStatus = rawStatus === 'completed' || rawStatus === 'payment_received' || rawStatus === 'payment_completed' || rawStatus === 'success' || rawStatus === 'settled'
      ? 'success'
      : rawStatus === 'failed' || rawStatus === 'cancelled' || rawStatus === 'expired'
        ? 'failed'
        : rawStatus;

    console.log(`ClickPesa webhook: order ${orderId} status=${paymentStatus} (raw=${rawStatus})`);

    await applyClickPesaPayment(orderId, paymentStatus, {
      clickpesaReference: payload.id || payload.transactionId || payload.reference || '',
      failureReason: payload.message || payload.error || '',
    });

    return res.status(200).json({ received: true });
  } catch (e) {
    console.error('ClickPesa webhook error:', e);
    return res.status(200).json({ received: true });
  }
});

// ============================================================
// 🔁 RETRY PAYMENT — Manually process a pending transaction
//     (fallback if webhook never arrived)
// ============================================================
app.post('/api/escrow/admin-release', async (req, res) => {
  try {
    const secret = req.headers['x-admin-secret'];
    if (secret !== process.env.ADMIN_SECRET) {
      return res.status(401).json({ error: 'Unauthorized' });
    }
    const { orderId } = req.body;
    if (!orderId) return res.status(400).json({ error: 'Missing orderId' });
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    // Try transaction first, then order
    let txDoc = await db.collection('transactions').doc(orderId).get();
    let orderDoc = null;

    if (!txDoc.exists) {
      orderDoc = await db.collection('orders').doc(orderId).get();
    }

    if (!txDoc.exists && (!orderDoc || !orderDoc.exists)) {
      return res.status(404).json({ error: 'Transaction/Order not found' });
    }

    let sellerId, sellerReceives, productName;

    if (txDoc.exists) {
      const tx = txDoc.data();
      sellerId = tx.sellerId;
      sellerReceives = tx.sellerReceives || tx.productPrice || 0;
      productName = tx.productName || 'Product';
      if (tx.escrowReleased) {
        return res.status(400).json({ error: 'Escrow already released' });
      }
      await txDoc.ref.update({
        status: 'delivered',
        escrowReleased: true,
        escrowReleasedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } else {
      const order = orderDoc.data();
      sellerId = order.sellerId;
      sellerReceives = order.totalAmount || 0;
      productName = order.items?.map(i => i.name).join(', ') || 'Product';
      if (order.escrowReleased) {
        return res.status(400).json({ error: 'Escrow already released' });
      }
      await orderDoc.ref.update({
        status: 'delivered',
        escrowReleased: true,
        escrowReleasedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    if (sellerId) {
      const adminSellerDoc = await db.collection('users').doc(sellerId).get();
      const adminPending = adminSellerDoc.exists ? (adminSellerDoc.data().pendingEscrow || 0) : 0;
      const actualPending = Math.min(sellerReceives, adminPending);
      await db.collection('users').doc(sellerId).update({
        sellerBalance: admin.firestore.FieldValue.increment(sellerReceives),
        pendingEscrow: admin.firestore.FieldValue.increment(-actualPending),
      });
      await db.collection('revenue_transactions').add({
        userId: sellerId,
        type: 'sale',
        amount: sellerReceives,
        orderId,
        description: `Sale (admin release): ${productName} - TZS ${sellerReceives}`,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });

      // Notify seller of admin release
      try {
        await db.collection('notifications').add({
          userId: sellerId,
          title: 'Admin Amefungua Escrow!',
          body: `${productName} — TZS ${sellerReceives.toLocaleString()} zimewekwa salio lako.`,
          type: 'escrow_release',
          data: { orderId, adminRelease: true },
          isRead: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        await sendOneSignalNotification(sellerId,
          'Admin Amefungua Escrow!',
          `${productName} — TZS ${sellerReceives.toLocaleString()} zimewekwa salio lako.`,
          { type: 'escrow_release', orderId, adminRelease: true }
        );
      } catch (_) {}
    }

    res.json({ success: true, message: 'Escrow force-released by admin' });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 🔄 ESCROW — Buyer cancels order & gets instant refund (before dispatch)
// ============================================================
app.post('/api/escrow/cancel', async (req, res) => {
  try {
    const auth = await requireUser(req, res);
    if (!auth.ok) return;
    const { orderId, userId } = req.body;
    if (!orderId || !userId) {
      return res.status(400).json({ error: 'Missing orderId or userId' });
    }
    if (auth.uid !== userId) {
      return res.status(403).json({ error: 'Forbidden: cannot cancel another account' });
    }
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const txDoc = await db.collection('transactions').doc(orderId).get();
    if (!txDoc.exists) {
      return res.status(404).json({ error: 'Transaction not found' });
    }

    const tx = txDoc.data();
    if (tx.buyerId !== userId) {
      return res.status(403).json({ error: 'Only the buyer can cancel this order' });
    }
    if (tx.status !== 'escrow_hold' && tx.status !== 'paid_escrow_held') {
      return res.status(400).json({ error: `Cannot cancel from status: ${tx.status}` });
    }
    if (tx.escrowReleased === true) {
      return res.status(400).json({ error: 'Escrow already released, cannot cancel' });
    }

    const buyerPhone = tx.buyerPhone || '';
    const productPrice = tx.productPrice || 0;
    const shippingCost = tx.shippingCost || 0;
    const sellerId = tx.sellerId;
    const sellerReceives = tx.sellerReceives || 0;
    const productName = tx.productName || 'Product';

    if (!buyerPhone) {
      return res.status(400).json({ error: 'Buyer phone not found for refund' });
    }

    if (productPrice + shippingCost <= DEFAULT_PAYOUT_FEE) {
      return res.status(400).json({ error: `Refund amount must exceed fee of TZS ${DEFAULT_PAYOUT_FEE.toLocaleString()}` });
    }

    // Refund includes the shipping cost the buyer paid, minus the payout fee
    const refundAmount = productPrice + shippingCost - DEFAULT_PAYOUT_FEE;

    // Refund minus payout fee to buyer via ClickPesa
    try {
      await clickpesaPayout({
        amount: refundAmount,
        phoneNumber: buyerPhone,
        orderReference: `refund_${orderId}`,
      });
    } catch (payoutErr) {
      return res.status(500).json({ error: `Refund failed: ${payoutErr.message}` });
    }

    // Update transaction
    await txDoc.ref.update({
      status: 'refunded',
      escrowReleased: true,
      cancellationType: 'buyer_cancel',
      refundFee: DEFAULT_PAYOUT_FEE,
      cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Deduct from seller's pendingEscrow
    if (sellerId && sellerReceives > 0) {
      const sellerDoc = await db.collection('users').doc(sellerId).get();
      const pendingEscrow = sellerDoc.exists ? (sellerDoc.data().pendingEscrow || 0) : 0;
      const actualPending = Math.min(sellerReceives, pendingEscrow);
      await db.collection('users').doc(sellerId).update({
        pendingEscrow: admin.firestore.FieldValue.increment(-actualPending),
        totalSales: admin.firestore.FieldValue.increment(-1),
        grossSalesVolume: admin.firestore.FieldValue.increment(-productPrice),
      });
    }

    // Record refund
    await db.collection('revenue_transactions').add({
      userId: 'platform',
      amount: -refundAmount,
      type: 'refund',
      orderId,
      fee: DEFAULT_PAYOUT_FEE,
      description: `Buyer cancel: ${productName} - TZS ${refundAmount} (fee TZS ${DEFAULT_PAYOUT_FEE})`,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Notify buyer
    await db.collection('notifications').add({
      userId: tx.buyerId,
      title: '💰 Pesa Zimerudishwa',
      body: `TZS ${refundAmount.toLocaleString()} zimerudishwa kwa ${productName}. Ada ya TZS ${DEFAULT_PAYOUT_FEE.toLocaleString()} imekatwa kwa gharama za payout.`,
      isRead: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      data: { type: 'refund', orderId },
    });
    try {
      await sendOneSignalNotification(tx.buyerId, '💰 Pesa Zimerudishwa', `TZS ${refundAmount.toLocaleString()} zimerudishwa kwa ${productName}. Ada ya TZS ${DEFAULT_PAYOUT_FEE.toLocaleString()} imekatwa kwa gharama za payout.`, { type: 'refund', orderId });
    } catch (_) {}

    // Notify seller
    if (sellerId) {
      await db.collection('notifications').add({
        userId: sellerId,
        title: '❌ Oda Imeghairiwa',
        body: `${productName} imeghairiwa na mnunuzi. Pesa zimetolewa kwenye pendingEscrow yako.`,
        isRead: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        data: { type: 'cancelled', orderId },
      });
      try {
        await sendOneSignalNotification(sellerId, '❌ Oda Imeghairiwa', `${productName} imeghairiwa na mnunuzi. Pesa zimetolewa kwenye pendingEscrow yako.`, { type: 'cancelled', orderId });
      } catch (_) {}
    }

    res.json({ success: true, refundAmount, fee: DEFAULT_PAYOUT_FEE, message: `Oda imeghairiwa. TZS ${refundAmount.toLocaleString()} zimerudishwa kwa simu yako (ada TZS ${DEFAULT_PAYOUT_FEE.toLocaleString()}).` });
  } catch (e) {
    console.error('Escrow cancel error:', e);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// ⚠️  ESCROW — Buyer raises dispute (instead of direct refund)
// ============================================================
app.post('/api/escrow/dispute', async (req, res) => {
  try {
    const auth = await requireUser(req, res);
    if (!auth.ok) return;
    const { orderId, userId, reason, evidenceUrls } = req.body;
    if (!orderId || !userId) {
      return res.status(400).json({ error: 'Missing orderId or userId' });
    }
    if (auth.uid !== userId) {
      return res.status(403).json({ error: 'Forbidden: cannot raise a dispute for another account' });
    }
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const txDoc = await db.collection('transactions').doc(orderId).get();
    if (!txDoc.exists) {
      return res.status(404).json({ error: 'Transaction not found' });
    }

    const tx = txDoc.data();
    if (tx.buyerId !== userId) {
      return res.status(403).json({ error: 'Only the buyer can raise a dispute' });
    }
    if (tx.status !== 'dispatched' && tx.status !== 'escrow_hold') {
      return res.status(400).json({ error: `Cannot dispute from status: ${tx.status}` });
    }
    if (tx.escrowReleased === true) {
      return res.status(400).json({ error: 'Escrow already released, cannot dispute' });
    }

    // Change to disputed status — funds stay held
    await txDoc.ref.update({
      status: 'disputed',
      disputeInfo: {
        reason: reason || 'Sijapata mzigo',
        evidenceUrls: evidenceUrls || [],
        raisedAt: admin.firestore.FieldValue.serverTimestamp(),
        resolved: false,
      },
    });

    const productName = tx.productName || 'Bidhaa';

    // Notify seller
    await db.collection('notifications').add({
      userId: tx.sellerId,
      title: '\u2696\uFE0F Mgogoro Umefunguliwa',
      body: `Mnunuzi amefungua mgogoro kwa ${productName}. Tafadhali wasilisha ushahidi wako.`,
      isRead: false,
      data: { type: 'disputed', transactionId: orderId },
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    try {
      await sendOneSignalNotification(tx.sellerId, '\u2696\uFE0F Mgogoro Umefunguliwa', `Mnunuzi amefungua mgogoro kwa ${productName}. Tafadhali wasilisha ushahidi wako.`, { type: 'disputed', transactionId: orderId });
    } catch (_) {}

    // Notify buyer
    await db.collection('notifications').add({
      userId,
      title: '\u2696\uFE0F Mgogoro Umefunguliwa',
      body: `Tumepokea mgogoro wako kwa ${productName}. Admin atakagua na kutoa uamuzi.`,
      isRead: false,
      data: { type: 'disputed', transactionId: orderId },
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    try {
      await sendOneSignalNotification(userId, '\u2696\uFE0F Mgogoro Umefunguliwa', `Tumepokea mgogoro wako kwa ${productName}. Admin atakagua na kutoa uamuzi.`, { type: 'disputed', transactionId: orderId });
    } catch (_) {}

    // Alert admin
    notifyAdmins(
      '\u2696\uFE0F Mgogoro Mpya Unahitaji Uamuzi',
      `Mgogoro kwa ${productName} \u2014 ${orderId}. Pitia ushahidi na toa uamuzi.`,
      { type: 'disputed', transactionId: orderId },
    );

    res.json({ success: true, message: 'Dispute imefunguliwa. Admin atakagua na kutoa uamuzi.' });
  } catch (e) {
    console.error('Escrow dispute error:', e);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// ⚖️  ESCROW — Admin resolves a dispute (release or refund)
// ============================================================
app.post('/api/escrow/admin-resolve-dispute', async (req, res) => {
  try {
    const auth = await requireAdmin(req, res);
    if (!auth.ok) return;

    const { orderId, resolution, note } = req.body;
    // resolution: 'release' (release to seller) or 'refund' (refund to buyer)
    if (!orderId || !resolution) {
      return res.status(400).json({ error: 'Missing orderId or resolution' });
    }
    if (!['release', 'refund'].includes(resolution)) {
      return res.status(400).json({ error: 'Resolution must be "release" or "refund"' });
    }
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const txDoc = await db.collection('transactions').doc(orderId).get();
    if (!txDoc.exists) {
      return res.status(404).json({ error: 'Transaction not found' });
    }

    const tx = txDoc.data();
    if (tx.status !== 'disputed') {
      return res.status(400).json({ error: `Cannot resolve from status: ${tx.status}` });
    }

    if (resolution === 'release') {
      // Release to seller
      const sellerId = tx.sellerId;
      const sellerReceives = tx.sellerReceives || 0;
      const sellerDoc = await db.collection('users').doc(sellerId).get();
      const pendingBefore = sellerDoc.exists ? (sellerDoc.data().pendingEscrow || 0) : 0;
      const actualPending = Math.min(sellerReceives, pendingBefore);

      await txDoc.ref.update({
        status: 'delivered',
        escrowReleased: true,
        escrowReleasedAt: admin.firestore.FieldValue.serverTimestamp(),
        'disputeInfo.resolved': true,
        'disputeInfo.resolution': 'released_to_seller',
        'disputeInfo.resolvedAt': admin.firestore.FieldValue.serverTimestamp(),
        'disputeInfo.adminNote': note || '',
      });

      if (sellerId && sellerReceives > 0) {
        await db.collection('users').doc(sellerId).update({
          sellerBalance: admin.firestore.FieldValue.increment(sellerReceives),
          pendingEscrow: admin.firestore.FieldValue.increment(-actualPending),
        });
      }

      await db.collection('notifications').add({
        userId: tx.buyerId,
        title: '\u2696\uFE0F Uamuzi wa Mgogoro',
        body: `Admin ameamua pesa zitolewe kwa muuzaji. ${note || ''}`,
        isRead: false,
        data: { type: 'dispute_resolved', transactionId: orderId },
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      try {
        await sendOneSignalNotification(tx.buyerId, '\u2696\uFE0F Uamuzi wa Mgogoro', `Admin ameamua pesa zitolewe kwa muuzaji. ${note || ''}`, { type: 'dispute_resolved', transactionId: orderId });
      } catch (_) {}
      await db.collection('notifications').add({
        userId: sellerId,
        title: '\u2696\uFE0F Uamuzi wa Mgogoro',
        body: `Admin ameamua pesa zikutolee. ${note || ''}`,
        isRead: false,
        data: { type: 'dispute_resolved', transactionId: orderId },
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      try {
        await sendOneSignalNotification(sellerId, '\u2696\uFE0F Uamuzi wa Mgogoro', `Admin ameamua pesa zikutolee. ${note || ''}`, { type: 'dispute_resolved', transactionId: orderId });
      } catch (_) {}

      return res.json({ success: true, message: 'Dispute resolved: funds released to seller' });
    }

    if (resolution === 'refund') {
      // FULL refund to buyer -- no deduction. Seller/platform bears gateway fee.
      const productPrice = tx.productPrice || 0;
      const sellerReceives = tx.sellerReceives || 0;
      const sellerId = tx.sellerId;
      const buyerPhone = tx.buyerPhone || '';
      const productName = tx.productName || 'Product';

      if (!buyerPhone) {
        return res.status(400).json({ error: 'Buyer phone number not found for refund' });
      }

      const refundAmount = productPrice; // Full refund to buyer
      const gatewayFee = DEFAULT_PAYOUT_FEE;

      // Send full refund to buyer via ClickPesa
      try {
        await clickpesaPayout({
          amount: refundAmount,
          phoneNumber: buyerPhone,
          orderReference: `dispute_refund_${orderId}`,
        });
      } catch (payoutErr) {
        return res.status(500).json({ error: `Refund payment failed: ${payoutErr.message}` });
      }

      // Deduct from seller's pendingEscrow and penalize seller for gateway fee
      if (sellerId && sellerReceives > 0) {
        const refundSellerDoc = await db.collection('users').doc(sellerId).get();
        const refundPending = refundSellerDoc.exists ? (refundSellerDoc.data().pendingEscrow || 0) : 0;
        const actualPending = Math.min(sellerReceives, refundPending);
        const currentBalance = refundSellerDoc.exists ? (refundSellerDoc.data().sellerBalance || 0) : 0;
        const sellerPenalty = Math.min(gatewayFee, sellerReceives, Math.max(0, currentBalance));
        await db.collection('users').doc(sellerId).update({
          pendingEscrow: admin.firestore.FieldValue.increment(-actualPending),
          totalSales: admin.firestore.FieldValue.increment(-1),
          grossSalesVolume: admin.firestore.FieldValue.increment(-productPrice),
          ...(sellerPenalty > 0 ? { sellerBalance: admin.firestore.FieldValue.increment(-sellerPenalty) } : {}),
        });
      }

      // Record refund
      await db.collection('revenue_transactions').add({
        userId: 'platform',
        amount: -productPrice,
        type: 'refund',
        orderId,
        description: `Refund (dispute): ${productName} - TZS ${productPrice}`,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });

      // Notify buyer
      await db.collection('notifications').add({
        userId: tx.buyerId,
        title: '\uD83D\uDCB0 Pesa Zimerudishwa Kamili',
        body: `Refund kamili ya TZS ${refundAmount.toLocaleString()} kwa ${productName} imetumwa kwa namba yako.`,
        isRead: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        data: { type: 'refund', orderId },
      });
      try {
        await sendOneSignalNotification(tx.buyerId, '\uD83D\uDCB0 Pesa Zimerudishwa Kamili', `Refund kamili ya TZS ${refundAmount.toLocaleString()} kwa ${productName} imetumwa kwa namba yako.`, { type: 'refund', orderId });
      } catch (_) {}

      // Notify seller
      if (sellerId) {
        await db.collection('notifications').add({
          userId: sellerId,
          title: '\u274C Mgogoro Umekamilika',
          body: `${productName} imerefundiwa mnunuzi. Pesa zimetolewa kwenye pendingEscrow yako.${gatewayFee > 0 ? ' Ada ya gateway imetozwa kwenye akaunti yako.' : ''}`,
          isRead: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          data: { type: 'refund', orderId },
        });
        try {
          await sendOneSignalNotification(sellerId, '\u274C Mgogoro Umekamilika', `${productName} imerefundiwa mnunuzi. Pesa zimetolewa kwenye pendingEscrow yako.${gatewayFee > 0 ? ' Ada ya gateway imetozwa kwenye akaunti yako.' : ''}`, { type: 'refund', orderId });
        } catch (_) {}
      }

      // Audit log
      await auditLog({
        userId: tx.buyerId, type: 'escrow_refund', amount: refundAmount,
        reason: `Dispute resolved: refund for ${orderId}`,
        relatedId: orderId,
        metadata: { productName, productPrice, buyerPhone, sellerId, gatewayFee },
      });

      return res.json({ success: true, refundAmount, message: `Refund kamili ya TZS ${refundAmount.toLocaleString()} imetumwa kwa namba ya mnunuzi.` });
    }
  } catch (e) {
    console.error('Admin resolve dispute error:', e);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 🔄 Escrow — Retry failed payout
// ============================================================
app.post('/api/escrow/retry-payout', async (req, res) => {
  try {
    const { orderId } = req.body;
    if (!orderId) return res.status(400).json({ error: 'Missing orderId' });
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const adminAuth = await requireAdmin(req, res);
    if (!adminAuth.ok) return;

    const txDoc = await db.collection('transactions').doc(orderId).get();
    if (!txDoc.exists) return res.status(404).json({ error: 'Transaction not found' });

    const tx = txDoc.data();
    if (tx.payoutStatus !== 'failed_retry') {
      return res.status(400).json({ error: `Cannot retry: payoutStatus is "${tx.payoutStatus}"` });
    }

    const sellerId = tx.sellerId;
    const sellerReceives = tx.sellerReceives || 0;
    const productName = tx.productName || 'Product';

    if (!sellerId || sellerReceives <= 0) {
      return res.status(400).json({ error: 'Invalid seller or amount for retry' });
    }

    // Look up seller phone
    const sellerDoc = await db.collection('users').doc(sellerId).get();
    if (!sellerDoc.exists) return res.status(404).json({ error: 'Seller not found' });
    const sellerPhone = sellerDoc.data().phone;
    if (!sellerPhone) return res.status(400).json({ error: 'Seller has no phone number for payout' });

    // Attempt payout
    const netPayout = sellerReceives - DEFAULT_PAYOUT_FEE;

    if (netPayout <= 0) {
      await txDoc.ref.update({
        payoutStatus: admin.firestore.FieldValue.delete(),
        payoutError: admin.firestore.FieldValue.delete(),
        payoutFailedAt: admin.firestore.FieldValue.delete(),
        payoutRetriedAt: admin.firestore.FieldValue.serverTimestamp(),
        payoutRetryNote: 'Net payout was zero, skipped payout',
      });
      return res.json({ success: true, message: 'Payout skipped: net amount <= 0. Flag cleared.' });
    }

    await processPayout({
      userId: sellerId, phone: sellerPhone,
      amount: sellerReceives, fee: DEFAULT_PAYOUT_FEE, netAmount: netPayout,
      source: `retry_escrow_${orderId}`,
      type: 'escrow_retry_payout',
      metadata: { orderId, sellerId, productName },
    });

    // Deduct from seller balance (it was already credited on initial release)
    const retryBalance = sellerDoc.data().sellerBalance || 0;
    const retryDeduct = Math.min(sellerReceives, Math.max(0, retryBalance));
    await db.collection('users').doc(sellerId).update({
      sellerBalance: admin.firestore.FieldValue.increment(-retryDeduct),
    });

    // Clear failed_retry flags
    await txDoc.ref.update({
      payoutStatus: admin.firestore.FieldValue.delete(),
      payoutError: admin.firestore.FieldValue.delete(),
      payoutFailedAt: admin.firestore.FieldValue.delete(),
      payoutRetriedAt: admin.firestore.FieldValue.serverTimestamp(),
      payoutRetrySuccess: true,
    });

    res.json({ success: true, message: `Payout ya TZS ${sellerReceives.toLocaleString()} imetumwa kwa ${sellerPhone}` });
  } catch (e) {
    console.error('Escrow retry payout error:', e);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 🪪 KYC — Seller identity verification
// ============================================================
app.post('/api/kyc/submit', async (req, res) => {
  try {
    const { userId, fullName, idType, idNumber, idImageUrl, selfieUrl } = req.body;
    if (!userId || !fullName || !idType || !idNumber) {
      return res.status(400).json({ error: 'Missing required KYC fields' });
    }
    if (!(await isOwnerOrAdmin(req, res, userId))) return;
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const userDoc = await db.collection('users').doc(userId).get();
    if (!userDoc.exists) return res.status(404).json({ error: 'User not found' });

    const existing = userDoc.data().kyc;
    if (existing && existing.status === 'approved') {
      return res.status(400).json({ error: 'KYC already approved' });
    }

    // Auto-validate KYC fields
    const errors = [];
    const nameParts = fullName.trim().split(/\s+/);
    if (nameParts.length < 2) errors.push('Jina kamili linahitaji angalau majina mawili');
    if (!idImageUrl) errors.push('Picha ya kitambulisho haijapakiwa');
    if (!selfieUrl) errors.push('Selfie haijapakiwa');

    // TODO: Integrate NIDA API for real-time National ID verification
    //   - Call NIDA endpoint with idNumber + fullName to confirm identity
    //   - If NIDA returns mismatch → auto-reject with clear reason
    //   - Skip NIDA for non-Tanzanian ID types (Passport)

    // TODO: Integrate Face Matching microservice (e.g. AWS Rekognition / Azure Face API)
    //   - Compare selfieUrl against idImageUrl for a face match confidence score
    //   - Require confidence >= 0.85 for auto-approval
    //   - Log confidence score in KYC record for audit trail

    // Validate ID number format based on type
    const cleanId = idNumber.replace(/\s/g, '');
    switch (idType) {
      case 'National ID':
        if (!/^\d{20}$/.test(cleanId)) errors.push('Namba ya National ID inatakiwa kuwa na tarakimu 20');
        break;
      case 'Passport':
        if (cleanId.length < 6) errors.push('Namba ya Passport inatakiwa kuwa na angalau herufi 6');
        break;
      case 'Drivers License':
        if (cleanId.length < 6) errors.push('Namba ya Drivers License inatakiwa kuwa na angalau herufi 6');
        break;
      case 'Voters ID':
        if (cleanId.length < 6) errors.push('Namba ya Voters ID inatakiwa kuwa na angalau herufi 6');
        break;
    }

    const status = 'pending';
    const reason = errors.length > 0 ? errors.join('; ') : 'Inahitaji ukaguzi wa admin';

    await db.collection('users').doc(userId).update({
      kyc: {
        fullName,
        idType,
        idNumber: cleanId,
        idImageUrl: idImageUrl || '',
        selfieUrl: selfieUrl || '',
        status,
        approved: false,
        reviewNotes: reason,
        submittedAt: admin.firestore.FieldValue.serverTimestamp(),
        reviewedAt: null,
      },
    });

    await auditLog({
      userId,
      type: 'kyc_pending',
      amount: 0,
      reason: `KYC submitted: ${idType} ${cleanId}${reason ? ' — ' + reason : ''}`,
    });

    // Notify admin about new KYC submission
    const adminSnap = await db.collection('users').where('isAdmin', '==', true).limit(5).get();
    for (const adminDoc of adminSnap.docs) {
      await db.collection('notifications').add({
        userId: adminDoc.id,
        title: 'KYC Mpya Imewasilishwa',
        body: `${fullName} ametuma KYC yake. Tafadhali kagua.`,
        isRead: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        data: { type: 'kyc_review', userId },
      });
      await sendOneSignalNotification(adminDoc.id, 'KYC Mpya Imewasilishwa', `${fullName} ametuma KYC yake. Tafadhali kagua.`, { type: 'kyc', userId }).catch(() => {});
    }

    // Notify user
    await db.collection('notifications').add({
      userId,
      title: 'KYC Imewasilishwa',
      body: 'KYC yako imewasilishwa. Subiri ukaguzi wa admin. Utapata taarifa ikikubaliwa.',
      isRead: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    res.json({
      success: true,
      approved: false,
      reason,
      message: 'KYC imewasilishwa. Subiri ukaguzi wa admin.',
    });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.get('/api/kyc/status/:userId', async (req, res) => {
  try {
    const auth = await requireUser(req, res);
    if (!auth.ok) return;
    const { userId } = req.params;
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    // Only the owner (or an admin via secret/Bearer) may read KYC documents.
    if (auth.uid !== userId) {
      const adminAuth = await requireAdmin(req, res);
      if (!adminAuth.ok) return;
    }

    const userDoc = await db.collection('users').doc(userId).get();
    if (!userDoc.exists) return res.status(404).json({ error: 'User not found' });

    const kyc = userDoc.data().kyc || { status: 'none' };
    res.json({ kyc });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Admin KYC review
app.post('/api/admin/kyc/review', async (req, res) => {
  try {
    const auth = await requireAdmin(req, res);
    if (!auth.ok) return;
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const { userId, approve, notes } = req.body;
    if (!userId) return res.status(400).json({ error: 'Missing userId' });

    const status = approve ? 'approved' : 'rejected';

    await db.collection('users').doc(userId).update({
      'kyc.status': status,
      'kyc.reviewedAt': admin.firestore.FieldValue.serverTimestamp(),
      'kyc.reviewNotes': notes || '',
      'kyc.approved': approve === true,
    });

    await db.collection('notifications').add({
      userId,
      title: approve ? 'KYC Imekubaliwa!' : 'KYC Imekataliwa',
      body: approve
        ? 'Umekubaliwa kuuza bidhaa. Sasa unaweza kuongeza bidhaa mpya.'
        : `KYC yako imekataliwa. Sababu: ${notes || 'Tafadhali wasiliana na msaada'}. Wasilisha tena baada ya kurekebisha.`,
      isRead: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    try {
      const kycTitle = approve ? 'KYC Imekubaliwa!' : 'KYC Imekataliwa';
      const kycBody = approve
        ? 'Umekubaliwa kuuza bidhaa. Sasa unaweza kuongeza bidhaa mpya.'
        : `KYC yako imekataliwa. Sababu: ${notes || 'Tafadhali wasiliana na msaada'}. Wasilisha tena baada ya kurekebisha.`;
      await sendOneSignalNotification(userId, kycTitle, kycBody, { type: 'kyc', status: approve ? 'approved' : 'rejected' });
    } catch (_) {}

    // Update sellerKycApproved on all products if approved
    if (approve && userId) {
      await updateSellerKycOnProducts(userId, true);
    }

    await auditLog({
      userId,
      type: `kyc_${status}`,
      amount: 0,
      reason: `KYC ${status} by admin. Notes: ${notes || ''}`,
    });

    res.json({ success: true, message: `KYC ${status}` });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.post('/api/admin/kyc/revoke', async (req, res) => {
  try {
    const auth = await requireAdmin(req, res);
    if (!auth.ok) return;
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const { userId, reason } = req.body;
    if (!userId) return res.status(400).json({ error: 'Missing userId' });

    await db.collection('users').doc(userId).update({
      'kyc.status': 'revoked',
      'kyc.approved': false,
      'kyc.revokedAt': admin.firestore.FieldValue.serverTimestamp(),
      'kyc.reviewNotes': reason || 'KYC imefutwa na admin.',
    });

    await updateSellerKycOnProducts(userId, false);

    await auditLog({
      userId,
      type: 'kyc_revoked',
      amount: 0,
      reason: `KYC revoked by admin. Reason: ${reason || ''}`,
    });

    await db.collection('notifications').add({
      userId,
      title: 'KYC Imefutwa',
      body: `KYC yako imefutwa na admin. Sababu: ${reason || 'Wasiliana na msaada'}. Tuma tena KYC yako.`,
      isRead: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    res.json({ success: true, message: 'KYC revoked' });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.post('/api/admin/kyc/delete', async (req, res) => {
  try {
    const auth = await requireAdmin(req, res);
    if (!auth.ok) return;
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const { userId } = req.body;
    if (!userId) return res.status(400).json({ error: 'Missing userId' });

    await db.collection('users').doc(userId).update({
      'kyc.status': 'none',
      'kyc.approved': false,
      'kyc.fullName': admin.firestore.FieldValue.delete(),
      'kyc.idType': admin.firestore.FieldValue.delete(),
      'kyc.idNumber': admin.firestore.FieldValue.delete(),
      'kyc.idImageUrl': admin.firestore.FieldValue.delete(),
      'kyc.selfieUrl': admin.firestore.FieldValue.delete(),
      'kyc.submittedAt': admin.firestore.FieldValue.delete(),
      'kyc.reviewedAt': admin.firestore.FieldValue.delete(),
      'kyc.reviewNotes': admin.firestore.FieldValue.delete(),
      'kyc.revokedAt': admin.firestore.FieldValue.delete(),
    });

    await updateSellerKycOnProducts(userId, false);

    await auditLog({
      userId,
      type: 'kyc_deleted',
      amount: 0,
      reason: 'KYC data permanently deleted by admin.',
    });

    res.json({ success: true, message: 'KYC data permanently deleted' });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.get('/api/admin/kyc/pending', async (req, res) => {
  try {
    const auth = await requireAdmin(req, res);
    if (!auth.ok) return;
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const snap = await db.collection('users')
      .where('kyc.status', '==', 'pending')
      .limit(50)
      .get();

    const pending = snap.docs.map(doc => ({
      uid: doc.id,
      displayName: doc.data().displayName || '',
      email: doc.data().email || '',
      phone: doc.data().phone || '',
      kyc: doc.data().kyc || {},
    }));

    res.json({ pending });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.get('/api/admin/kyc/all', async (req, res) => {
  try {
    const auth = await requireAdmin(req, res);
    if (!auth.ok) return;
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const snap = await db.collection('users')
      .where('kyc.status', 'in', ['approved', 'pending', 'rejected', 'revoked'])
      .limit(100)
      .get();

    const all = snap.docs.map(doc => ({
      uid: doc.id,
      displayName: doc.data().displayName || '',
      email: doc.data().email || '',
      phone: doc.data().phone || '',
      kyc: doc.data().kyc || {},
    })).sort((a, b) => {
      const ta = a.kyc.submittedAt && (a.kyc.submittedAt.seconds || a.kyc.submittedAt);
      const tb = b.kyc.submittedAt && (b.kyc.submittedAt.seconds || b.kyc.submittedAt);
      return (tb || 0) - (ta || 0);
    });

    res.json({ all });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── Broadcast notification to ALL users ────────────────────
app.post('/api/admin/broadcast-notification', async (req, res) => {
  try {
    const auth = await requireAdmin(req, res);
    if (!auth.ok) return;
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const { title, body } = req.body;
    if (!title) return res.status(400).json({ error: 'Title is required' });

    // Get all active user IDs
    const usersSnap = await db.collection('users').get();
    const userIds = usersSnap.docs.map(doc => doc.id).filter(Boolean);

    if (userIds.length === 0) {
      return res.json({ success: true, message: 'No users to notify', sentCount: 0 });
    }

    // Send push via OneSignal to all users (admin broadcast always delivers)
    const pushResult = await sendOneSignalBulk(userIds, title, body || '', {
      type: 'system',
      broadcast: 'true',
    }, { bypassPrefs: true });

    // Save in-app notification for each user (batch of 500)
    let notifCount = 0;
    const BATCH_SIZE = 500;
    for (let i = 0; i < userIds.length; i += BATCH_SIZE) {
      const batch = db.batch();
      const chunk = userIds.slice(i, i + BATCH_SIZE);
      for (const uid of chunk) {
        const notifRef = db.collection('notifications').doc();
        batch.set(notifRef, {
          userId: uid,
          title: title,
          body: body || '',
          data: { type: 'system', broadcast: 'true' },
          isRead: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        notifCount++;
      }
      await batch.commit();
    }

    console.log(`[Broadcast] Sent to ${userIds.length} users, notifications saved: ${notifCount}`);

    res.json({
      success: true,
      message: `Notification sent to ${userIds.length} users`,
      totalUsers: userIds.length,
      pushNotifications: pushResult.successCount || 0,
      inAppNotifications: notifCount,
    });
  } catch (e) {
    console.error('[Broadcast] Error:', e);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Admin → single user message: in-app notification + OneSignal push + email
// for critical types, mirroring /api/send-notification but admin-authenticated.
app.post('/api/admin/send-notification', async (req, res) => {
  try {
    const auth = await requireAdmin(req, res);
    if (!auth.ok) return;
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const { userId, title, body, type } = req.body;
    if (!userId || !title) {
      return res.status(400).json({ error: 'userId and title are required' });
    }

    const userDoc = await db.collection('users').doc(userId).get();
    if (!userDoc.exists) return res.status(404).json({ error: 'User not found' });

    const notifType = type || 'system';
    await db.collection('notifications').add({
      userId,
      title,
      body: body || '',
      data: { type: notifType, fromAdmin: true },
      isRead: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Admin-initiated push bypasses user preference toggles so operators can
    // always reach users (e.g. account actions) regardless of channel settings
    await sendOneSignalNotification(userId, title, body || '', { type: notifType }, { bypassPrefs: true });

    res.json({ success: true, message: 'Notification sent to user' });
  } catch (e) {
    console.error('[Admin Send] Error:', e);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 🛒 MARKETPLACE — Initiate product purchase payment via ClickPesa
// ============================================================
app.post('/api/create-marketplace-payment-link', paymentRateLimit, async (req, res) => {
  try {
    const authHeader = req.headers.authorization || '';
    const token = authHeader.replace('Bearer ', '');
    if (!token) return res.status(401).json({ error: 'Unauthorized' });
    let decoded;
    try { decoded = await admin.auth().verifyIdToken(token); } catch (_) { return res.status(403).json({ error: 'Invalid token' }); }

    const { productPrice, productName, productId, sellerId, sellerName, email, phone, buyerId, deliveryType, shippingCost, existingTransactionId, paymentMethod, provider } = req.body;
    if (buyerId && decoded.uid !== buyerId) {
      return res.status(403).json({ error: 'Buyer ID mismatch' });
    }
    if (!productPrice || !productId || !sellerId || !phone) {
      return res.status(400).json({ error: 'Missing required fields' });
    }

    // Price the buyer is actually charged: an active flash sale overrides the
    // client-supplied (stale full) price so commission + total are computed on
    // the real sale price, and the buyer can't be overcharged at checkout.
    const effectivePrice = await resolveEffectivePrice(db, productId, productPrice);

    // Resolve buyer name before ClickPesa call
    let buyerName = '';
    if (buyerId) {
      try {
        const buyerDoc = await db.collection('users').doc(buyerId).get();
        buyerName = buyerDoc.data()?.name || buyerDoc.data()?.displayName || '';
      } catch (_) {}
    }

    // Fraud checks — skip if resubmitting existing transaction
    if (buyerId && !existingTransactionId) {
      const suspended = await checkSuspended(buyerId);
      if (suspended) return res.status(403).json({ error: 'Account suspended' });

      const isDuplicate = await checkDuplicatePayment(productId, buyerId);
      if (isDuplicate) return res.status(400).json({ error: 'A pending payment already exists for this product' });

      const withinLimit = await checkDailyLimit(buyerId, effectivePrice);
      if (!withinLimit) return res.status(400).json({ error: `Daily purchase limit of TZS ${MAX_DAILY_SALE_AMOUNT.toLocaleString()} exceeded` });
    }

    // Use existing transaction ID if provided, otherwise generate new one.
    // ClickPesa requires orderReference to be alphanumeric-only, so strip any
    // base64url chars (e.g. '-'/'_') from the buyer UID fragment.
    const orderIdSuffix = (buyerId ? buyerId.replace(/[^A-Za-z0-9]/g, '').substring(0, 4) : '') || 'x';
    const order_id = existingTransactionId || `p${Date.now().toString(36)}${orderIdSuffix}`;

    const isBillPay = (paymentMethod || 'ussd_push') === 'billpay';

    // Include shipping + platform commission + gateway fee in total sent to ClickPesa
    const commission = Math.round(effectivePrice * PLATFORM_COMMISSION_PERCENT);
    // BillPay 1% fee is deducted from collected amount (add it on top so seller still
    // gets full total). USSD Push fee is charged to the customer by ClickPesa on top,
    // so never pre-add it or the processing fee is charged twice.
    const gatewayFee = isBillPay ? calcGatewayFee('billpay', effectivePrice, provider) : 0;
    const totalAmount = effectivePrice + Math.round(shippingCost || 0) + commission + gatewayFee;

    if (isBillPay) {
      // ── BillPay flow: create order control number ──
      const billResult = await clickpesaCreateBillPayOrder({
        billAmount: totalAmount,
        billDescription: `Soko Vibe: ${sanitize(productName || 'Product')}`,
        billPaymentMode: 'EXACT',
        billReference: order_id,
      });

      if (!billResult || billResult.success === false || (!billResult.billPayNumber && !billResult.data?.billPayNumber)) {
        const errMsg = billResult?.message || billResult?.error || 'BillPay API failed to generate control number';
        return res.status(502).json({ error: `BillPay error: ${errMsg}` });
      }

      const billPayNumber = billResult.billPayNumber || billResult.data?.billPayNumber || billResult.billReference || '';
      const clickpesaRef = billResult.id || billResult.data?.id || billPayNumber || '';

      const productImg = req.body.productImage || '';
      if (db) {
        await db.collection('transactions').doc(order_id).set({
          type: 'purchase',
          productId,
          productName: sanitize(productName),
          productImage: productImg,
          sellerId,
          sellerName: sanitize(sellerName),
          buyerPhone: phone,
          buyerId: buyerId || '',
          buyerName,
          productPrice: effectivePrice,
          shippingCost: Math.round(shippingCost || 0),
          platformFee: commission,
          gatewayFee,
          totalAmount,
          status: 'pending',
          paymentMethod: 'BillPay',
          billPayNumber,
          deliveryType: deliveryType || 'local',
          autoReleaseDays: deliveryType === 'regional' ? ESCROW_REGIONAL_DAYS : ESCROW_LOCAL_DAYS,
          clickpesaReference: clickpesaRef,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
      }

      res.json({
        order_id,
        billPayNumber,
        gatewayFee,
        totalAmount,
        clickpesaReference: clickpesaRef,
        message: `BillPay control number: ${billPayNumber}. Open M-Pesa > Lipa > BillPay > enter ${billPayNumber} > amount TZS ${totalAmount.toLocaleString()} > PIN.`,
      });
    } else {
      // ── USSD Push flow (async — return immediately, ClickPesa fires in background) ──
      const phoneDigits = phone.replace(/\D/g, '');
      const normalizedPhone = phoneDigits.startsWith('0')
        ? '255' + phoneDigits.substring(1)
        : phoneDigits.startsWith('255')
          ? phoneDigits
          : '255' + phoneDigits;

      const productImg = req.body.productImage || '';
      const txData = {
        type: 'purchase',
        productId, productName: sanitize(productName), productImage: productImg,
        sellerId, sellerName: sanitize(sellerName), buyerPhone: normalizedPhone,
        buyerId: buyerId || '', buyerName,
        productPrice: effectivePrice, shippingCost: Math.round(shippingCost || 0),
        platformFee: commission, processingFee: gatewayFee,
        totalAmount, status: 'pending', paymentMethod: 'ClickPesa',
        deliveryType: deliveryType || 'local',
        autoReleaseDays: deliveryType === 'regional' ? ESCROW_REGIONAL_DAYS : ESCROW_LOCAL_DAYS,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      };
      await db.collection('transactions').doc(order_id).set(txData, { merge: true });

      // Fire ClickPesa async — don't wait for it
      const baseUrl = process.env.PUBLIC_SERVER_URL || `${req.protocol}://${req.get('host')}`;
      const callbackUrl = `${baseUrl}/api/clickpesa/webhook`;
      clickpesaCollect({ amount: totalAmount, orderReference: order_id, phoneNumber: normalizedPhone, callbackUrl })
        .then((result) => {
          const ref = result?.id || result?.orderReference || '';
          if (!ref) {
            console.error(`[USSD] ClickPesa no ref for ${order_id}`);
            return;
          }
          return db.collection('transactions').doc(order_id).update({ clickpesaReference: ref, ussdSent: true });
        })
        .then(() => console.log(`[USSD] Push sent for ${order_id}`))
        .catch((err) => {
          console.error(`[USSD] ClickPesa error for ${order_id}:`, err?.response?.data || err.message);
          db.collection('transactions').doc(order_id).update({ ussdFailed: true, ussdError: err?.message || 'ClickPesa error' }).catch(() => {});
        });

      res.json({
        order_id, gatewayFee, totalAmount,
        message: `Malipo ya TZS ${totalAmount.toLocaleString()} yanatuma USSD push kwa simu yako. Ada ya ClickPesa inaongezwa kwenye malipo yako.`,
      });
    }
  } catch (e) {
    console.error('create-marketplace-payment-link error:', e.message);
    const msg = e.message && e.message.includes('payment')
      ? e.message
      : 'Internal server error';
    res.status(500).json({ error: msg });
  }
});

// ============================================================
// 🔁 RETRY PAYMENT — Manually process a pending transaction
//     (fallback if webhook never arrived)
// ============================================================
app.post('/api/retry-payment', async (req, res) => {
  try {
    const authHeader = req.headers.authorization || '';
    const token = authHeader.replace('Bearer ', '');
    if (!token) return res.status(401).json({ error: 'Unauthorized' });

    const decoded = await admin.auth().verifyIdToken(token);
    const { order_id } = req.body || {};
    if (!order_id) return res.status(400).json({ error: 'Missing order_id' });

    const txDoc = await db.collection('transactions').doc(order_id).get();
    if (!txDoc.exists) return res.status(404).json({ error: 'Transaction not found' });

    const tx = txDoc.data();
    if (tx.status !== 'pending') {
      return res.status(400).json({ error: `Transaction is ${tx.status}, not pending` });
    }

    // Only the buyer or an admin can retry
    if (tx.buyerId && tx.buyerId !== decoded.uid) {
      const userDoc = await db.collection('users').doc(decoded.uid).get();
      if (!userDoc.exists || !userDoc.data().isAdmin) {
        return res.status(403).json({ error: 'Not authorized to retry this payment' });
      }
    }

    // Must be pending for at least 30 seconds
    const createdAt = tx.createdAt?.toDate?.() || new Date(0);
    const elapsed = (Date.now() - createdAt.getTime()) / 1000;
    if (elapsed < 30) {
      return res.status(400).json({ error: `Transaction too recent (${Math.round(elapsed)}s). Wait and try again.` });
    }

    // Re-process the transaction the same way the webhook would
    if (tx.type === 'boost') {
      const tier = tx.tier || 'bronze';
      const tierConfig = BOOST_TIERS[tier] || BOOST_TIERS.bronze;
      const now = new Date();
      const boostedUntil = new Date(now.getTime() + tierConfig.days * 24 * 60 * 60 * 1000);

      await db.collection('products').doc(tx.productId).update({
        isBoosted: true,
        boostedUntil: admin.firestore.Timestamp.fromDate(boostedUntil),
        boostTier: tier,
        isFeatured: true,
        featuredUntil: admin.firestore.Timestamp.fromDate(boostedUntil),
      });

      await txDoc.ref.update({ status: 'completed', completedAt: admin.firestore.FieldValue.serverTimestamp() });

      // Notification
      if (tx.userId) {
        await db.collection('notifications').add({
          userId: tx.userId,
          title: '✅ Boost imewashwa!',
          body: `Bidhaa yako imepandishwa kwa daraja la ${tier} kwa siku ${tierConfig.days}.`,
          data: { type: 'boost', productId: tx.productId },
          isRead: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      // Notify all users about this boost
      notifyBoostBroadcast(tx.productId, tier, tx.userId).catch(() => {});

      // Revenue
      const boostAmount = tx.amount || tierConfig.price;
      await db.collection('revenue_transactions').add({
        userId: 'platform',
        amount: boostAmount,
        sokoLanguCommission: boostAmount,
        type: 'boost',
        subType: tier,
        productId: tx.productId,
        transactionId: order_id,
        buyerPhone: tx.buyerPhone || '',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      return res.json({ status: 'completed', message: `Boost ${tier} activated for ${tierConfig.days} days` });
    }

    if (tx.type === 'purchase') {
      const productPrice = tx.productPrice || 0;
      const platformFee = Math.round(productPrice * PLATFORM_COMMISSION_PERCENT);
      const payoutFee = DEFAULT_PAYOUT_FEE;
      const processingFee = tx.processingFee || tx.clickpesaFee || 0;
      const sellerReceives = productPrice;
      const deliveryType = tx.deliveryType || 'local';
      const autoReleaseDays = tx.autoReleaseDays || (deliveryType === 'regional' ? ESCROW_REGIONAL_DAYS : ESCROW_LOCAL_DAYS);
      const escrowExpiry = new Date(Date.now() + autoReleaseDays * 24 * 60 * 60 * 1000);

      await txDoc.ref.update({
        processingFee,
        platformFee,
        payoutFee,
        sokoLanguCommission: platformFee,
        totalAmount: productPrice + platformFee,
        sellerReceives,
        status: 'escrow_hold',
        paymentMethod: 'ClickPesa',
        buyerId: tx.buyerId || '',
        buyerName: tx.buyerName || '',
        escrowStatus: 'held',
        escrowHeldAt: admin.firestore.FieldValue.serverTimestamp(),
        escrowExpiresAt: admin.firestore.Timestamp.fromDate(escrowExpiry),
      });

      // Record platform commission
      await db.collection('revenue_transactions').add({
        userId: 'platform',
        amount: platformFee,
        type: 'commission',
        description: `Commission for ${tx.productName || 'Product'} (escrow)`,
        transactionId: order_id,
        productName: tx.productName || '',
        productPrice,
        payoutFee,
        sokoLanguCommission: platformFee,
        buyerName: tx.buyerName || '',
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });

      // Credit seller's pendingEscrow
      if (sellerReceives > 0 && tx.sellerId) {
        await db.collection('users').doc(tx.sellerId).set({
          pendingEscrow: admin.firestore.FieldValue.increment(sellerReceives),
          totalSales: admin.firestore.FieldValue.increment(1),
          grossSalesVolume: admin.firestore.FieldValue.increment(productPrice),
          lastSaleAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });

        // Notify seller
        await db.collection('notifications').add({
          userId: tx.sellerId,
          title: 'Umepata Mauzo!',
          body: `${tx.productName || 'Bidhaa'} imeuzwa. TZS ${sellerReceives.toLocaleString()} imewekwa escrow.`,
          isRead: false,
          type: 'sale',
          transactionId: order_id,
          buyerPhone: tx.buyerPhone || '',
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        // Notify buyer
        if (tx.buyerId) {
          await db.collection('notifications').add({
            userId: tx.buyerId,
            title: 'Malipo Yamekamilika!',
            body: `Malipo ya ${tx.productName || 'Bidhaa'} yamepokelewa. Thibitisha upokeaji ili muuzaji apate hela zake.`,
            isRead: false,
            type: 'escrow_confirm',
            transactionId: order_id,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        }
      }

      return res.json({ status: 'escrow_hold', message: `Payment of TZS ${productPrice.toLocaleString()} processed. Seller credited TZS ${sellerReceives.toLocaleString()}.` });
    }

    res.status(400).json({ error: `Unknown transaction type: ${tx.type}` });
  } catch (e) {
    console.error('Retry-payment error:', e);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 🔙 ADMIN — Retro-boost: fix boost transactions that were paid
//           but never applied to the product (old webhook bug)
// ============================================================
app.post('/api/admin/retro-boost', async (req, res) => {
  try {
    const authHeader = req.headers.authorization || '';
    const token = authHeader.replace('Bearer ', '');
    if (!token) return res.status(401).json({ error: 'Unauthorized' });

    const decoded = await admin.auth().verifyIdToken(token);
    const userDoc = await db.collection('users').doc(decoded.uid).get();
    if (!userDoc.exists || !userDoc.data().isAdmin) {
      return res.status(403).json({ error: 'Admin access required' });
    }

    const { transactionId } = req.body || {};

    let txDocs;
    if (transactionId) {
      // Retro-boost a specific transaction
      const doc = await db.collection('transactions').doc(transactionId).get();
      if (!doc.exists) return res.status(404).json({ error: 'Transaction not found' });
      txDocs = [doc];
    } else {
      // Find all boost transactions that are completed but product may not be boosted
      txDocs = await db.collection('transactions')
        .where('type', '==', 'boost')
        .where('status', '==', 'completed')
        .get();
      txDocs = txDocs.docs;
    }

    let fixed = 0;
    let skipped = 0;
    let errors = 0;

    for (const doc of txDocs) {
      const tx = doc.data();
      if (!tx.productId) { skipped++; continue; }

      try {
        const productDoc = await db.collection('products').doc(tx.productId).get();
        if (!productDoc.exists) { skipped++; continue; }

        const product = productDoc.data();
        if (product.isBoosted) { skipped++; continue; }

        const tier = tx.tier || 'bronze';
        const tierConfig = BOOST_TIERS[tier] || BOOST_TIERS.bronze;
        const now = new Date();
        const boostedUntil = new Date(now.getTime() + tierConfig.days * 24 * 60 * 60 * 1000);

        await db.collection('products').doc(tx.productId).update({
          isBoosted: true,
          boostedUntil: admin.firestore.Timestamp.fromDate(boostedUntil),
          boostTier: tier,
          isFeatured: true,
          featuredUntil: admin.firestore.Timestamp.fromDate(boostedUntil),
        });

        // Add notification for the seller
        if (tx.userId) {
          await db.collection('notifications').add({
            userId: tx.userId,
            title: '✅ Boost imewashwa!',
            body: `Bidhaa yako imepandishwa kwa daraja la ${tier} kwa siku ${tierConfig.days}.`,
            data: { type: 'boost', productId: tx.productId },
            isRead: false,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        }

        fixed++;
      } catch (e) {
        console.error(`Retro-boost error for tx ${doc.id}:`, e);
        errors++;
      }
    }

    res.json({ fixed, skipped, errors, total: txDocs.length });
  } catch (e) {
    console.error('Retro-boost endpoint error:', e);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 💰 SELLER — Check balance
// ============================================================
app.get('/api/seller/balance', async (req, res) => {
  try {
    const { userId } = req.query;
    if (!userId) return res.status(400).json({ error: 'Missing userId' });
    if (!db) return res.status(503).json({ error: 'Database not configured' });
    if (!(await isOwnerOrAdmin(req, res, userId))) return;

    const userDoc = await db.collection('users').doc(userId).get();
    if (!userDoc.exists) return res.status(404).json({ error: 'User not found' });

    const user = userDoc.data();
    res.json({
      sellerBalance: user.sellerBalance || 0,
      totalSales: user.totalSales || 0,
      grossSalesVolume: user.grossSalesVolume || 0,
      phone: user.phone || '',
    });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 💰 SELLER WITHDRAW — Send seller balance to mobile money
// ============================================================
// 💰 SELLER WITHDRAW — Send seller balance to mobile money via ClickPesa
// Deducts (amount + 2000 TZS fee) from seller balance atomically.
// ============================================================
app.post('/api/seller/withdraw', async (req, res) => {
  try {
    const auth = await requireUser(req, res);
    if (!auth.ok) return;
    const { userId, amount, phone } = req.body;
    if (!userId || !amount || !phone) {
      return res.status(400).json({ error: 'Missing userId, amount, or phone' });
    }
    if (auth.uid !== userId) {
      return res.status(403).json({ error: 'Forbidden: cannot withdraw from another account' });
    }
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const withdrawAmount = Math.round(amount);
    if (withdrawAmount < MIN_WITHDRAWAL) {
      return res.status(400).json({ error: `Minimum withdrawal is TZS ${MIN_WITHDRAWAL.toLocaleString()}` });
    }

    // Real ClickPesa payout fee tier — not the old flat 2000 estimate
    const payoutFee = getPayoutFee(withdrawAmount);
    const totalCost = withdrawAmount + payoutFee;

    // Atomic transaction: read balance, validate, deduct
    let sellerName = '';
    let balanceSnapshot = 0;
    try {
      await db.runTransaction(async (tx) => {
        const userRef = db.collection('users').doc(userId);
        const userSnap = await tx.get(userRef);
        if (!userSnap.exists) throw new Error('User not found');

        const userData = userSnap.data();
        if (userData.isSuspended) throw new Error('Account suspended');

        sellerName = userData.name || userData.displayName || '';
        const currentBalance = userData.sellerBalance || 0;
        balanceSnapshot = currentBalance;

        if (currentBalance < totalCost) {
          throw new Error(`Insufficient balance. You need TZS ${totalCost.toLocaleString()} (${withdrawAmount.toLocaleString()} withdrawal + ${payoutFee.toLocaleString()} fee). Available: TZS ${currentBalance.toLocaleString()}`);
        }

        tx.update(userRef, {
          sellerBalance: admin.firestore.FieldValue.increment(-totalCost),
        });
      });
    } catch (txErr) {
      return res.status(400).json({ error: txErr.message });
    }

    // Balance deducted atomically — now call ClickPesa to send the withdrawal amount
    const netAmount = withdrawAmount; // Seller receives the full withdrawal amount
    let payoutResult;
    try {
      payoutResult = await processPayout({
        userId,
        phone,
        amount: totalCost,       // total deducted from seller
        fee: payoutFee,
        netAmount,               // what seller actually receives
        source: `seller_withdraw_${Date.now()}`,
        type: 'seller_withdrawal',
        metadata: { sellerName, balanceBefore: balanceSnapshot },
      });
    } catch (payoutErr) {
      // ClickPesa call failed — reverse the deduction
      try {
        await db.collection('users').doc(userId).update({
          sellerBalance: admin.firestore.FieldValue.increment(totalCost),
        });
      } catch (reverseErr) {
        console.error(`CRITICAL: Failed to reverse seller balance for ${userId} after failed payout:`, reverseErr);
      }
      return res.status(502).json({ error: `Payout failed: ${payoutErr.message}` });
    }

    await auditLog({
      userId, type: 'seller_withdraw', amount: -totalCost,
      balanceBefore: balanceSnapshot, balanceAfter: balanceSnapshot - totalCost,
      reason: `Seller withdrawal: TZS ${netAmount.toLocaleString()} to ${phone} (fee: TZS ${payoutFee.toLocaleString()})`,
      relatedId: payoutResult.payoutId,
      metadata: { phone, netAmount, fee: payoutFee, payoutId: payoutResult.payoutId },
    });

    // Notify seller about withdrawal initiation
    try {
      await db.collection('notifications').add({
        userId,
        title: '💰 Utoaji wa Pesa Umeanzishwa',
        body: `TZS ${netAmount.toLocaleString()} zinaandaliwa kutuma kwa ${phone}.`,
        isRead: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        data: { type: 'withdrawal', payoutId: payoutResult.payoutId },
      });
      await sendOneSignalNotification(userId, '💰 Utoaji wa Pesa Umeanzishwa', `TZS ${netAmount.toLocaleString()} zinaandaliwa kutuma kwa ${phone}.`, { type: 'withdrawal', payoutId: payoutResult.payoutId });
    } catch (_) {}

    res.json({
      success: true,
      netAmount,
      fee: payoutFee,
      payoutId: payoutResult.payoutId,
      message: `TZS ${netAmount.toLocaleString()} zimetumwa kwa ${phone}`,
    });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 📊 ADMIN WITHDRAW — Send ad revenue to mobile money
// ============================================================
app.post('/api/admin/withdraw', async (req, res) => {
  try {
    const auth = await requireAdmin(req, res);
    if (!auth.ok) return;

    const { userId, amount, phone } = req.body;
    if (!userId || !amount || !phone) {
      return res.status(400).json({ error: 'Missing userId, amount, or phone' });
    }
    if (auth.uid !== 'admin-secret' && auth.uid !== userId) {
      return res.status(403).json({ error: 'Token does not match userId' });
    }
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const userDoc = await db.collection('users').doc(userId).get();
    if (!userDoc.exists) return res.status(404).json({ error: 'User not found' });

    const user = userDoc.data();
    if (!user.isAdmin) return res.status(403).json({ error: 'Admin access required' });
    if (user.isSuspended) return res.status(403).json({ error: 'Account suspended' });

    const revSnap = await db.collection('revenue_transactions').get();
    let totalCommissions = 0;
    let totalBoostRevenue = 0;
    revSnap.docs.forEach(doc => {
      const d = doc.data();
      if (d.type === 'boost') {
        totalBoostRevenue += (d.sokoLanguCommission || 0);
      } else {
        totalCommissions += (d.sokoLanguCommission || 0);
      }
    });
    // Withdrawable balance = platform commissions + boost revenue only. AdMob
    // revenue lives in Google's account, not the Soko Vibe ClickPesa wallet,
    // so it must never be part of what the admin withdraws.
    const totalAdminBalance = totalCommissions + totalBoostRevenue;

    const withdrawnSnap = await db.collection('admin_withdrawals')
      .where('userId', '==', userId)
      .get();
    let totalWithdrawn = 0;
    withdrawnSnap.docs.forEach(doc => {
      const d = doc.data();
      if (d.status === 'completed') totalWithdrawn += (d.netAmount || d.amount || 0);
    });
    const availableBalance = totalAdminBalance - totalWithdrawn;

    if (amount > availableBalance) {
      return res.status(400).json({ error: `Insufficient admin balance. Available: TZS ${availableBalance.toLocaleString()}` });
    }

    const payoutFee = getPayoutFee(amount);
    const netAmount = amount - payoutFee;
    if (netAmount <= 0) {
      return res.status(400).json({ error: `Amount too small after fee (min TZS ${payoutFee + 1})` });
    }

    let payoutId;
    try {
      const payout = await processPayout({
        userId, phone, amount, fee: payoutFee, netAmount,
        source: `admin_withdraw_${Date.now()}`,
        type: 'admin_withdrawal',
      });
      payoutId = payout.payoutId;
    } catch (payoutErr) {
      return res.status(502).json({ error: `Payout failed: ${payoutErr.message}` });
    }

    await db.collection('admin_withdrawals').add({
      userId,
      amount,
      fee: payoutFee,
      netAmount,
      phone,
      payoutId,
      status: 'completed',
      paymentMethod: 'ClickPesa',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    await auditLog({
      userId, type: 'admin_withdraw', amount: -amount,
      reason: `Admin ad revenue withdrawal: TZS ${netAmount} to ${phone}`,
      relatedId: payoutId,
      metadata: { phone, netAmount, fee: payoutFee, payoutId },
    });

    res.json({
      success: true,
      netAmount,
      fee: payoutFee,
      payoutId,
      message: `TZS ${netAmount.toLocaleString()} zimetumwa kwa ${phone}`,
    });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 💰 CREATE PAYOUT — Admin-initiated payout
// ============================================================
app.post('/api/create-payout', async (req, res) => {
  try {
    const auth = await requireAdmin(req, res);
    if (!auth.ok) return;

    const { userId, amount, phone, type, source } = req.body;
    if (!userId || !amount || !phone) {
      return res.status(400).json({ error: 'Missing userId, amount, or phone' });
    }
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    // Check for duplicate payout (same source reference)
    if (source) {
      const dupSnap = await db.collection('payouts')
        .where('source', '==', source)
        .where('status', 'in', [PAYOUT_STATUSES.PROCESSING, PAYOUT_STATUSES.SUCCESS])
        .limit(1).get();
      if (!dupSnap.empty) {
        const dup = dupSnap.docs[0].data();
        return res.status(400).json({ error: 'Duplicate payout', existingPayoutId: dup.payoutId });
      }
    }

    const payoutFee = getPayoutFee(amount);
    const netAmount = amount - payoutFee;
    if (netAmount <= 0) {
      return res.status(400).json({ error: `Amount too small after fee (min TZS ${payoutFee + 1})` });
    }

    const payoutResult = await processPayout({
      userId, phone, amount, fee: payoutFee, netAmount,
      source: source || generatePayoutReference('src'),
      type: type || 'manual',
    });

    await auditLog({
      userId, type: 'admin_create_payout', amount: -amount,
      reason: `Admin-created payout: TZS ${netAmount} to ${phone}`,
      relatedId: payoutResult.payoutId,
      metadata: { phone, netAmount, fee: payoutFee, source },
    });

    res.json({ success: true, ...payoutResult });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 📊 GET PAYOUT STATUS — Check payout status by ID
// ============================================================
app.get('/api/payout-status/:id', async (req, res) => {
  try {
    if (!db) return res.status(503).json({ error: 'Database not configured' });
    const doc = await db.collection('payouts').doc(req.params.id).get();
    if (!doc.exists) return res.status(404).json({ error: 'Payout not found' });
    if (!(await isOwnerOrAdmin(req, res, doc.data().userId || ''))) return;
    res.json({ id: doc.id, ...doc.data() });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 📋 LIST PAYOUTS — Get payouts for a user or all
// ============================================================
app.get('/api/payouts', async (req, res) => {
  try {
    if (!db) return res.status(503).json({ error: 'Database not configured' });
    const { userId, limit: qLimit } = req.query;
    // Only an admin may list all payouts; a user may list only their own.
    if (userId) {
      if (!(await isOwnerOrAdmin(req, res, userId))) return;
    } else {
      const adminAuth = await requireAdmin(req, res);
      if (!adminAuth.ok) return;
    }
    let query = db.collection('payouts').orderBy('createdAt', 'desc');
    if (userId) query = query.where('userId', '==', userId);
    const snap = await query.limit(parseInt(qLimit) || 50).get();
    const payouts = snap.docs.map(d => ({ id: d.id, ...d.data() }));
    res.json({ payouts });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 🔁 RETRY PAYOUT — Retry a failed payout
// ============================================================
app.post('/api/payout/retry/:id', async (req, res) => {
  try {
    const auth = await requireAdmin(req, res);
    if (!auth.ok) return;
    if (!db) return res.status(503).json({ error: 'Database not configured' });
    const result = await retryFailedPayout(req.params.id);
    res.json({ success: true, ...result });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 📝 AUDIT LOG — Log every balance change for fraud prevention
// ============================================================
async function auditLog({ userId, type, amount, balanceBefore, balanceAfter, reason, relatedId, metadata }) {
  if (!db) return;
  try {
    await db.collection('audit_log').add({
      userId,
      type,
      amount,
      balanceBefore: balanceBefore ?? 0,
      balanceAfter: balanceAfter ?? 0,
      reason: reason || '',
      relatedId: relatedId || '',
      metadata: metadata || {},
      ip: '',
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });
  } catch (e) {
    console.error('Audit log error:', e);
  }
}

// ============================================================
// 📊 ADMIN — Dashboard statistics
// ============================================================
app.get('/api/admin/stats', async (req, res) => {
  try {
    const secret = req.headers['x-admin-secret'];
    if (secret !== process.env.ADMIN_SECRET) return res.status(401).json({ error: 'Unauthorized' });
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const [usersSnap, ordersSnap, withdrawalsSnap, adViewsSnap] = await Promise.all([
      db.collection('users').count().get(),
      db.collection('orders').count().get(),
      db.collection('withdrawals').count().get(),
      db.collection('ad_views').count().get(),
    ]);

    const totalUsers = usersSnap.data().count;
    const totalOrders = ordersSnap.data().count;
    const totalWithdrawals = withdrawalsSnap.data().count;
    const totalAdViews = adViewsSnap.data().count;

    const balanceSnap = await db.collection('users').get();
    let totalSellerBalance = 0;
    balanceSnap.docs.forEach(doc => {
      const d = doc.data();
      totalSellerBalance += d.sellerBalance || 0;
    });

    res.json({
      totalUsers,
      totalOrders,
      totalWithdrawals,
      totalAdViews,
      totalSellerBalance,

    });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 📊 ADMIN — All transactions
// ============================================================
app.get('/api/admin/transactions', async (req, res) => {
  try {
    const secret = req.headers['x-admin-secret'];
    if (secret !== process.env.ADMIN_SECRET) return res.status(401).json({ error: 'Unauthorized' });
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const limit = Math.min(parseInt(req.query.limit) || 100, 500);
    const snap = await db.collection('transactions').orderBy('createdAt', 'desc').limit(limit).get();
    const transactions = snap.docs.map(doc => ({ id: doc.id, ...doc.data() }));
    res.json({ transactions });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 📊 ADMIN — All withdrawals (viewer + seller)
// ============================================================
app.get('/api/admin/withdrawals', async (req, res) => {
  try {
    const secret = req.headers['x-admin-secret'];
    if (secret !== process.env.ADMIN_SECRET) return res.status(401).json({ error: 'Unauthorized' });
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const limit = Math.min(parseInt(req.query.limit) || 100, 500);
    const snap = await db.collection('withdrawals').orderBy('createdAt', 'desc').limit(limit).get();
    const withdrawals = snap.docs.map(doc => ({ id: doc.id, ...doc.data() }));
    res.json({ withdrawals });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 📊 ADMIN — App-wide analytics (users, products, revenue, growth)
// ============================================================
app.get('/api/admin/analytics', async (req, res) => {
  try {
    const secret = req.headers['x-admin-secret'];
    if (secret !== process.env.ADMIN_SECRET) {
      const authHeader = req.headers['authorization'];
      if (authHeader && authHeader.startsWith('Bearer ')) {
        try {
          const decoded = await admin.auth().verifyIdToken(authHeader.slice(7));
          const userDoc = await db.collection('users').doc(decoded.uid).get();
          if (!userDoc.exists || !userDoc.data().isAdmin) return res.status(401).json({ error: 'Unauthorized' });
        } catch { return res.status(401).json({ error: 'Unauthorized' }); }
      } else { return res.status(401).json({ error: 'Unauthorized' }); }
    }
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const now = new Date();
    const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const monthStart = new Date(now.getFullYear(), now.getMonth(), 1);

    // Users
    const usersSnap = await db.collection('users').get();
    let totalUsers = 0, newUsersToday = 0, newUsersThisMonth = 0;
    const locationDistribution = {};
    const ageDistribution = {};
    for (const doc of usersSnap.docs) {
      totalUsers++;
      const d = doc.data();
      const createdAt = d.createdAt ? (d.createdAt.toDate ? d.createdAt.toDate() : new Date(d.createdAt)) : null;
      if (createdAt) {
        if (createdAt >= todayStart) newUsersToday++;
        if (createdAt >= monthStart) newUsersThisMonth++;
      }
      const loc = d.location;
      if (loc) locationDistribution[loc] = (locationDistribution[loc] || 0) + 1;
      const dob = d.dateOfBirth;
      if (dob) {
        try {
          const birth = new Date(dob);
          const age = now.getFullYear() - birth.getFullYear();
          const group = age < 18 ? 'Under 18' : age < 25 ? '18-24' : age < 35 ? '25-34' : age < 50 ? '35-49' : '50+';
          ageDistribution[group] = (ageDistribution[group] || 0) + 1;
        } catch (_) {}
      }
    }

    // Products
    const productsSnap = await db.collection('products').get();
    let totalProducts = 0, activeProducts = 0, inactiveProducts = 0;
    const productsByCategory = {};
    for (const doc of productsSnap.docs) {
      totalProducts++;
      const d = doc.data();
      if (d.isActive !== false) activeProducts++; else inactiveProducts++;
      const cat = d.category || 'Other';
      productsByCategory[cat] = (productsByCategory[cat] || 0) + 1;
    }

    // Transactions — revenue
    const txSnap = await db.collection('transactions').get();
    let totalRevenue = 0, revenueToday = 0, revenueThisMonth = 0;
    const completedStatuses = PAID_STATUSES;
    for (const doc of txSnap.docs) {
      const d = doc.data();
      const status = d.status || '';
      const amount = d.totalAmount || 0;
      const createdAt = d.createdAt ? (d.createdAt.toDate ? d.createdAt.toDate() : new Date(d.createdAt)) : null;
      if (completedStatuses.has(status)) {
        totalRevenue += amount;
        if (createdAt) {
          if (createdAt >= todayStart) revenueToday += amount;
          if (createdAt >= monthStart) revenueThisMonth += amount;
        }
      }
    }

    // Last 7 days revenue & user growth
    const revenueOverTime = [];
    const userGrowth = [];
    for (let i = 6; i >= 0; i--) {
      const day = new Date(now.getFullYear(), now.getMonth(), now.getDate() - i);
      const nextDay = new Date(day.getTime() + 86400000);
      let dayRev = 0, dayUsers = 0;
      for (const doc of txSnap.docs) {
        const d = doc.data();
        const status = d.status || '';
        const amount = d.totalAmount || 0;
        const createdAt = d.createdAt ? (d.createdAt.toDate ? d.createdAt.toDate() : new Date(d.createdAt)) : null;
        if (createdAt && createdAt >= day && createdAt < nextDay && completedStatuses.has(status)) {
          dayRev += amount;
        }
      }
      revenueOverTime.push({ date: day.toISOString(), count: Math.round(dayRev) });
      for (const doc of usersSnap.docs) {
        const d = doc.data();
        const createdAt = d.createdAt ? (d.createdAt.toDate ? d.createdAt.toDate() : new Date(d.createdAt)) : null;
        if (createdAt && createdAt >= day && createdAt < nextDay) dayUsers++;
      }
      userGrowth.push({ date: day.toISOString(), count: dayUsers });
    }

    // Active user counts from user_sessions
    const sessionsSnap = await db.collection('user_sessions').get();
    let perSecond = 0, perMinute = 0, perHour = 0, perDay = 0, perMonth = 0, perYear = 0;
    const allTime = sessionsSnap.docs.length;
    for (const doc of sessionsSnap.docs) {
      const ts = doc.data().lastActive;
      const lastActive = ts ? (ts.toDate ? ts.toDate() : new Date(ts)) : null;
      if (!lastActive) continue;
      const diffMs = now - lastActive;
      if (diffMs <= 1000) perSecond++;
      if (diffMs <= 60000) perMinute++;
      if (diffMs <= 3600000) perHour++;
      if (diffMs <= 86400000) perDay++;
      if (diffMs <= 2592000000) perMonth++;
      if (diffMs <= 31536000000) perYear++;
    }

    res.json({
      success: true,
      totalUsers, newUsersToday, newUsersThisMonth,
      totalProducts, activeProducts, inactiveProducts,
      productsByCategory,
      totalRevenue, revenueToday, revenueThisMonth,
      revenueOverTime, userGrowth,
      locationDistribution, ageDistribution,
      activeUserCounts: { perSecond, perMinute, perHour, perDay, perMonth, perYear, allTime },
    });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 📊 ADMIN — Daily time-series (money volume, commissions, new users)
// ============================================================
app.get('/api/admin/timeseries', async (req, res) => {
  try {
    const secret = req.headers['x-admin-secret'];
    if (secret !== process.env.ADMIN_SECRET) return res.status(401).json({ error: 'Unauthorized' });
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const days = Math.min(parseInt(req.query.days) || 30, 90);
    const now = new Date();

    // Build empty per-day buckets (oldest → newest)
    const series = [];
    for (let i = days - 1; i >= 0; i--) {
      const day = new Date(now.getFullYear(), now.getMonth(), now.getDate() - i);
      series.push({ date: day.toISOString().slice(0, 10), money: 0, commission: 0, users: 0 });
    }
    const index = new Map(series.map((s, i) => [s.date, i]));
    const start = new Date(now.getFullYear(), now.getMonth(), now.getDate() - (days - 1));

    const [txSnap, usersSnap] = await Promise.all([
      db.collection('transactions').get(),
      db.collection('users').get(),
    ]);

    for (const doc of txSnap.docs) {
      const d = doc.data();
      if (!PAID_STATUSES.has(d.status || '')) continue;
      const created = d.createdAt ? (d.createdAt.toDate ? d.createdAt.toDate() : new Date(d.createdAt)) : null;
      if (!created || created < start) continue;
      const i = index.get(created.toISOString().slice(0, 10));
      if (i === undefined) continue;
      series[i].money += (d.totalAmount || 0);
      series[i].commission += (d.sokoLanguCommission || d.sokovibeCommission || d.platformFee || d.platformCommission || 0);
    }

    for (const doc of usersSnap.docs) {
      const d = doc.data();
      const created = d.createdAt ? (d.createdAt.toDate ? d.createdAt.toDate() : new Date(d.createdAt)) : null;
      if (!created || created < start) continue;
      const i = index.get(created.toISOString().slice(0, 10));
      if (i === undefined) continue;
      series[i].users++;
    }

    res.json({ success: true, series });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 📊 ADMIN — Online / presence (lightweight, polled every few seconds)
// ============================================================
app.get('/api/admin/online', async (req, res) => {
  try {
    const secret = req.headers['x-admin-secret'];
    if (secret !== process.env.ADMIN_SECRET) return res.status(401).json({ error: 'Unauthorized' });
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const [sessionsSnap, usersCountSnap] = await Promise.all([
      db.collection('user_sessions').get(),
      db.collection('users').count().get(),
    ]);

    const now = Date.now();
    let lastMinute = 0, last5Min = 0, last15Min = 0, lastHour = 0, lastDay = 0;
    const recent = [];
    for (const doc of sessionsSnap.docs) {
      const ts = doc.data().lastActive;
      const lastActive = ts ? (ts.toDate ? ts.toDate().getTime() : new Date(ts).getTime()) : 0;
      if (!lastActive) continue;
      const diff = now - lastActive;
      if (diff <= 60000) lastMinute++;
      if (diff <= 300000) last5Min++;
      if (diff <= 900000) last15Min++;
      if (diff <= 3600000) lastHour++;
      if (diff <= 86400000) lastDay++;
      if (diff <= 600000) recent.push({ uid: doc.id, lastActive: lastActive });
    }
    recent.sort((a, b) => b.lastActive - a.lastActive);

    res.json({
      success: true,
      totalUsers: (usersCountSnap.data() || {}).count || 0,
      online: { lastMinute, last5Min, last15Min, lastHour, lastDay },
      recentlyActive: recent.slice(0, 30),
      asOf: now,
    });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 📊 SELLER — Seller-specific analytics (products, views, orders, reviews)
// ============================================================
app.get('/api/seller-analytics/:sellerId', async (req, res) => {
  try {
    const { sellerId } = req.params;
    if (!sellerId) return res.status(400).json({ error: 'sellerId required' });

    // Auth: verify Firebase token, uid must match sellerId or be admin
    const authHeader = req.headers['authorization'];
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({ error: 'Unauthorized' });
    }
    let decoded;
    try {
      decoded = await admin.auth().verifyIdToken(authHeader.slice(7));
    } catch {
      return res.status(401).json({ error: 'Unauthorized' });
    }
    if (decoded.uid !== sellerId) {
      const userDoc = await db.collection('users').doc(decoded.uid).get();
      if (!userDoc.exists || !userDoc.data().isAdmin) {
        return res.status(401).json({ error: 'Unauthorized' });
      }
    }

    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const now = new Date();
    const monthStart = new Date(now.getFullYear(), now.getMonth(), 1);

    // ── Products & Views ──────────────────────────────────────
    const productsSnap = await db.collection('products')
      .where('sellerId', '==', sellerId)
      .get();

    const totalProducts = productsSnap.docs.length;
    let totalProductViews = 0;
    const genderBreakdown = {};
    const locationBreakdown = {};
    const ageBreakdown = {};
    let boostImpressions = 0;
    const boostLocationBreakdown = {};
    const topProducts = [];

    for (const productDoc of productsSnap.docs) {
      const pid = productDoc.id;
      const pData = productDoc.data();
      totalProductViews += (pData.viewCount || 0);

      const viewsSnap = await db.collection('product_analytics').doc(pid).collection('views').get();
      const boostSnap = await db.collection('boost_analytics').doc(pid).collection('impressions').get();
      const prodLocBreakdown = {};

      for (const vDoc of viewsSnap.docs) {
        const v = vDoc.data();
        if (v.gender) genderBreakdown[v.gender] = (genderBreakdown[v.gender] || 0) + 1;
        if (v.location) {
          locationBreakdown[v.location] = (locationBreakdown[v.location] || 0) + 1;
          prodLocBreakdown[v.location] = (prodLocBreakdown[v.location] || 0) + 1;
        }
        if (v.age != null) {
          const age = v.age;
          const group = age < 18 ? 'Under 18' : age < 25 ? '18-24' : age < 35 ? '25-34' : age < 50 ? '35-49' : '50+';
          ageBreakdown[group] = (ageBreakdown[group] || 0) + 1;
        }
      }

      boostImpressions += boostSnap.docs.length;
      for (const bDoc of boostSnap.docs) {
        const loc = bDoc.data().location || 'unknown';
        boostLocationBreakdown[loc] = (boostLocationBreakdown[loc] || 0) + 1;
      }

      topProducts.push({
        productId: pid,
        productName: pData.name || 'Bidhaa',
        productImage: Array.isArray(pData.images) ? pData.images[0] : (pData.image || null),
        viewCount: viewsSnap.docs.length,
        locationBreakdown: prodLocBreakdown,
      });
    }

    topProducts.sort((a, b) => b.viewCount - a.viewCount);

    // ── Transactions & Order Stats ──────────────────────────
    const txSnap = await db.collection('transactions')
      .where('sellerId', '==', sellerId)
      .get();

    let totalOrders = 0, successfulOrders = 0, failedOrders = 0;
    let totalTransactions = 0, successfulTransactions = 0, failedTransactions = 0;
    let monthlyEarnings = 0;
    const completedStatuses = PAID_STATUSES;
    const monthlySales = [];

    for (let i = 0; i < 12; i++) {
      const m = new Date(now.getFullYear(), (now.getMonth() - 11 + i + 12) % 12, 1);
      monthlySales.push({ date: m.toISOString(), count: 0 });
    }

    for (const doc of txSnap.docs) {
      const d = doc.data();
      totalOrders++;
      totalTransactions++;
      const status = d.status || '';
      const amount = d.totalAmount || 0;
      const createdAt = d.createdAt ? (d.createdAt.toDate ? d.createdAt.toDate() : new Date(d.createdAt)) : null;

      // Only count earnings/orders once the escrow is released to the seller.
      // escrow_hold / dispatched are still held in pendingEscrow.
      const escrowReleasedToSeller = d.escrowReleased === true || SELLER_CREDIT_STATUSES.has(status);
      if (completedStatuses.has(status) && escrowReleasedToSeller && status !== 'refunded') {
        successfulOrders++;
        successfulTransactions++;
        if (createdAt && createdAt >= monthStart) {
          monthlyEarnings += (typeof amount === 'number' ? amount : 0);
        }
        if (createdAt) {
          for (let i = 0; i < monthlySales.length; i++) {
            const saleMonth = new Date(monthlySales[i].date);
            if (createdAt.getMonth() === saleMonth.getMonth() && createdAt.getFullYear() === saleMonth.getFullYear()) {
              monthlySales[i].count++;
              break;
            }
          }
        }
      } else if (status === 'failed' || status === 'refunded') {
        failedOrders++;
        failedTransactions++;
      }
    }

    // ── Reviews ──────────────────────────────────────────────
    const reviewSnap = await db.collection('reviews')
      .where('sellerId', '==', sellerId)
      .get();

    let totalReviews = 0, positiveReviews = 0, negativeReviews = 0;
    let totalRating = 0;
    for (const doc of reviewSnap.docs) {
      totalReviews++;
      const rating = doc.data().rating || 0;
      totalRating += rating;
      if (rating >= 4) positiveReviews++;
      if (rating <= 2) negativeReviews++;
    }
    const averageRating = totalReviews > 0 ? totalRating / totalReviews : 0;

    res.json({
      success: true,
      sellerId,
      totalProducts,
      totalProductViews,
      genderBreakdown,
      locationBreakdown,
      ageBreakdown,
      boostImpressions,
      boostLocationBreakdown,
      monthlyEarnings,
      totalOrders,
      successfulOrders,
      failedOrders,
      totalTransactions,
      successfulTransactions,
      failedTransactions,
      averageRating,
      totalReviews,
      positiveReviews,
      negativeReviews,
      lastUpdated: now.toISOString(),
      topProducts: topProducts.slice(0, 10),
      monthlySales,
    });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 📋 SELLER STATEMENT — Bank-statement-style financial report for sellers
// ============================================================
app.get('/api/seller-statement/:sellerId', async (req, res) => {
  try {
    const { sellerId } = req.params;
    if (!sellerId) return res.status(400).json({ error: 'sellerId required' });

    const authHeader = req.headers['authorization'];
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({ error: 'Unauthorized' });
    }
    let decoded;
    try {
      decoded = await admin.auth().verifyIdToken(authHeader.slice(7));
    } catch {
      return res.status(401).json({ error: 'Unauthorized' });
    }
    if (decoded.uid !== sellerId) {
      const userDoc = await db.collection('users').doc(decoded.uid).get();
      if (!userDoc.exists || !userDoc.data().isAdmin) {
        return res.status(401).json({ error: 'Unauthorized' });
      }
    }

    if (!db) return res.status(503).json({ error: 'Database not configured' });

    // Seller info
    const sellerDoc = await db.collection('users').doc(sellerId).get();
    if (!sellerDoc.exists) return res.status(404).json({ error: 'Seller not found' });
    const sellerData = sellerDoc.data();
    const sellerName = sellerData.businessName || sellerData.name || sellerData.displayName || 'Muuzaji';
    const sellerPhone = sellerData.phone || sellerData.phoneNumber || '';
    const sellerEmail = sellerData.email || '';
    const sellerLocation = sellerData.location || '';

    // Single-field queries only — composite (sellerId, createdAt) index is not
    // guaranteed on production, so filter + sort in memory instead.
    const twelveMonthsAgo = new Date();
    twelveMonthsAgo.setMonth(twelveMonthsAgo.getMonth() - 12);

    const txSnap = await db.collection('transactions')
      .where('sellerId', '==', sellerId)
      .get();
    const txDocs = txSnap.docs.filter((doc) => {
      const createdAt = doc.data().createdAt;
      const t = createdAt ? (createdAt.toDate ? createdAt.toDate() : new Date(createdAt)) : null;
      return t != null && t >= twelveMonthsAgo;
    });

    const paidStatuses = PAID_STATUSES;
    const entries = [];
    let runningBalance = 0;

    for (const doc of txDocs) {
      const d = doc.data();
      const status = d.status || '';
      const createdAt = d.createdAt ? (d.createdAt.toDate ? d.createdAt.toDate() : new Date(d.createdAt)) : null;
      const amount = d.sellerReceives || d.totalAmount || 0;
      const commission = d.platformCommission || d.platformFee || 0;
      const buyerName = d.buyerName || d.buyerPhone || 'Mnunuzi';
      const productName = d.productName || 'Bidhaa';

      // Only count a sale as credit once the escrow has been released to the
      // seller. escrow_hold / dispatched are still held in pendingEscrow and
      // would inflate the seller's earnings if counted here. 'refunded' never
      // credits the seller even though orders.js flags it as released.
      const escrowReleasedToSeller = d.escrowReleased === true || SELLER_CREDIT_STATUSES.has(status);
      if (paidStatuses.has(status) && escrowReleasedToSeller && status !== 'refunded') {
        runningBalance += amount;
        entries.push({
          type: 'credit',
          date: createdAt ? createdAt.toISOString() : null,
          description: `Uuzaji: ${productName} - ${buyerName}`,
          grossAmount: amount,
          commission: commission,
          netAmount: amount - commission,
          runningBalance: runningBalance,
          transactionId: doc.id,
          status: 'completed',
        });
      }
    }

    // Payouts/withdrawals for this seller (last 12 months)
    const withdrawSnap = await db.collection('withdrawals')
      .where('userId', '==', sellerId)
      .get();
    const withdrawDocs = withdrawSnap.docs.filter((doc) => {
      const createdAt = doc.data().createdAt;
      const t = createdAt ? (createdAt.toDate ? createdAt.toDate() : new Date(createdAt)) : null;
      return t != null && t >= twelveMonthsAgo;
    });

    for (const doc of withdrawDocs) {
      const d = doc.data();
      const status = d.status || '';
      const createdAt = d.createdAt ? (d.createdAt.toDate ? d.createdAt.toDate() : new Date(d.createdAt)) : null;
      const amount = d.netAmount || d.amount || 0;

      if (status === 'completed') {
        runningBalance -= amount;
        entries.push({
          type: 'debit',
          date: createdAt ? createdAt.toISOString() : null,
          description: `Utoaji wa pesa: TSh ${amount.toLocaleString()}`,
          grossAmount: amount,
          commission: 0,
          netAmount: amount,
          runningBalance: runningBalance,
          transactionId: doc.id,
          status: 'completed',
        });
      }
    }

    // Refunds (money taken back from seller for failed orders)
    for (const doc of txDocs) {
      const d = doc.data();
      const status = d.status || '';
      const createdAt = d.createdAt ? (d.createdAt.toDate ? d.createdAt.toDate() : new Date(d.createdAt)) : null;
      const amount = d.totalAmount || 0;

      if (status === 'refunded') {
        runningBalance -= amount;
        entries.push({
          type: 'debit',
          date: createdAt ? createdAt.toISOString() : null,
          description: `Marejesho: ${d.productName || 'Bidhaa'} - agizo limeghairiwa`,
          grossAmount: amount,
          commission: 0,
          netAmount: amount,
          runningBalance: runningBalance,
          transactionId: doc.id,
          status: 'refunded',
        });
      }
    }

    // Sort all entries by date
    entries.sort((a, b) => {
      if (!a.date && !b.date) return 0;
      if (!a.date) return -1;
      if (!b.date) return 1;
      return new Date(a.date) - new Date(b.date);
    });

    // Recalculate running balance chronologically
    let balance = 0;
    for (const entry of entries) {
      if (entry.type === 'credit') balance += entry.netAmount;
      else balance -= entry.netAmount;
      entry.runningBalance = balance;
    }

    const totalCredits = entries.filter(e => e.type === 'credit').reduce((s, e) => s + e.netAmount, 0);
    const totalDebits = entries.filter(e => e.type === 'debit').reduce((s, e) => s + e.netAmount, 0);

    res.json({
      success: true,
      statementTitle: 'Soko Vibe Seller Statement',
      generatedAt: new Date().toISOString(),
      seller: {
        sellerId,
        name: sellerName,
        phone: sellerPhone,
        email: sellerEmail,
        location: sellerLocation,
      },
      summary: {
        totalCredits: Math.round(totalCredits * 100) / 100,
        totalDebits: Math.round(totalDebits * 100) / 100,
        currentBalance: Math.round(balance * 100) / 100,
        totalTransactions: entries.length,
      },
      entries,
    });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 📄 BUYER STATEMENT — Financial record of a buyer's payments
//     Lists every payment (debit) and refund (credit) made by the
//     buyer over the last 12 months, with running balance.
// ============================================================
app.get('/api/buyer-statement/:buyerId', async (req, res) => {
  try {
    const { buyerId } = req.params;
    if (!buyerId) return res.status(400).json({ error: 'buyerId required' });

    const authHeader = req.headers['authorization'];
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({ error: 'Unauthorized' });
    }
    let decoded;
    try {
      decoded = await admin.auth().verifyIdToken(authHeader.slice(7));
    } catch {
      return res.status(401).json({ error: 'Unauthorized' });
    }
    if (decoded.uid !== buyerId) {
      const userDoc = await db.collection('users').doc(decoded.uid).get();
      if (!userDoc.exists || !userDoc.data().isAdmin) {
        return res.status(401).json({ error: 'Unauthorized' });
      }
    }

    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const buyerDoc = await db.collection('users').doc(buyerId).get();
    if (!buyerDoc.exists) return res.status(404).json({ error: 'Buyer not found' });
    const buyerData = buyerDoc.data();
    const buyerName = buyerData.name || buyerData.displayName || 'Mnunuzi';
    const buyerPhone = buyerData.phone || buyerData.phoneNumber || '';
    const buyerEmail = buyerData.email || '';
    const buyerLocation = buyerData.location || '';

    const twelveMonthsAgo = new Date();
    twelveMonthsAgo.setMonth(twelveMonthsAgo.getMonth() - 12);

    const txSnap = await db.collection('transactions')
      .where('buyerId', '==', buyerId)
      .get();
    const txDocs = txSnap.docs.filter((doc) => {
      const createdAt = doc.data().createdAt;
      const t = createdAt ? (createdAt.toDate ? createdAt.toDate() : new Date(createdAt)) : null;
      return t != null && t >= twelveMonthsAgo;
    });

    // Payments made by the buyer (money out). 'paid' is intentionally excluded:
    // it is set client-side the moment a USSD push is sent, BEFORE payment is
    // actually confirmed, so counting it here would show unpaid orders as paid.
    const paidStatuses = PAID_STATUSES;
    const entries = [];
    let runningBalance = 0;

    for (const doc of txDocs) {
      const d = doc.data();
      const status = d.status || '';
      const createdAt = d.createdAt ? (d.createdAt.toDate ? d.createdAt.toDate() : new Date(d.createdAt)) : null;
      const totalAmount = d.totalAmount || 0;
      const sellerName = d.sellerName || 'Muuzaji';
      const productName = d.productName || 'Bidhaa';

      if (paidStatuses.has(status)) {
        runningBalance -= totalAmount;
        entries.push({
          type: 'debit',
          date: createdAt ? createdAt.toISOString() : null,
          description: `Malipo: ${productName} - ${sellerName}`,
          grossAmount: totalAmount,
          commission: 0,
          netAmount: totalAmount,
          runningBalance: runningBalance,
          transactionId: doc.id,
          status,
        });
      }

      // Only a genuinely refunded order adds money back. A 'failed' order was
      // never paid, so crediting it would fabricate income in the statement.
      if (status === 'refunded') {
        const refundAmount = d.refundAmount || d.totalAmount || 0;
        if (refundAmount > 0) {
          runningBalance += refundAmount;
          entries.push({
            type: 'credit',
            date: createdAt ? createdAt.toISOString() : null,
            description: `Marejesho: ${productName} - pesa zimerudishwa`,
            grossAmount: refundAmount,
            commission: 0,
            netAmount: refundAmount,
            runningBalance: runningBalance,
            transactionId: doc.id,
            status: 'refunded',
          });
        }
      }
    }

    // Wallet deposits (money added to the buyer's Soko wallet) — money IN, so
    // they are credits. The deposit is only counted once ClickPesa confirms it
    // ('completed'); pending/failed top-ups never touch the balance.
    const depositSnap = await db.collection('deposits')
      .where('userId', '==', buyerId)
      .get();
    for (const doc of depositSnap.docs) {
      const d = doc.data();
      if (d.status !== 'completed') continue;
      const createdAt = d.createdAt ? (d.createdAt.toDate ? d.createdAt.toDate() : new Date(d.createdAt)) : null;
      if (createdAt && createdAt >= twelveMonthsAgo) {
        const amount = d.amount || 0;
        runningBalance += amount;
        entries.push({
          type: 'credit',
          date: createdAt.toISOString(),
          description: `Uwekaji wa fedha: ${d.paymentMethod === 'BillPay' ? 'BillPay' : 'Mobile Money'}`,
          grossAmount: amount,
          commission: 0,
          netAmount: amount,
          runningBalance: runningBalance,
          transactionId: doc.id,
          status: 'completed',
        });
      }
    }

    // Legacy wallet_transactions records (if ever written by older builds).
    // A wallet 'deposit' is money in (credit), a wallet 'refund' is also money
    // back to the buyer (credit).
    const walletSnap = await db.collection('wallet_transactions')
      .where('userId', '==', buyerId)
      .get();
    for (const doc of walletSnap.docs) {
      const d = doc.data();
      const createdAt = d.createdAt ? (d.createdAt.toDate ? d.createdAt.toDate() : new Date(d.createdAt)) : null;
      if (createdAt && createdAt >= twelveMonthsAgo) {
        const amount = d.amount || 0;
        const type = d.type || '';
        if (type === 'deposit' || type === 'refund') {
          runningBalance += amount;
          entries.push({
            type: 'credit',
            date: createdAt.toISOString(),
            description: `Tapo la pochi: ${d.description || ''}`,
            grossAmount: amount,
            commission: 0,
            netAmount: amount,
            runningBalance: runningBalance,
            transactionId: doc.id,
            status: 'completed',
          });
        }
      }
    }

    // Sort all entries by date
    entries.sort((a, b) => {
      if (!a.date && !b.date) return 0;
      if (!a.date) return -1;
      if (!b.date) return 1;
      return new Date(a.date) - new Date(b.date);
    });

    // Recalculate running balance chronologically
    let balance = 0;
    for (const entry of entries) {
      if (entry.type === 'credit') balance += entry.netAmount;
      else balance -= entry.netAmount;
      entry.runningBalance = balance;
    }

    const totalCredits = entries.filter(e => e.type === 'credit').reduce((s, e) => s + e.netAmount, 0);
    const totalDebits = entries.filter(e => e.type === 'debit').reduce((s, e) => s + e.netAmount, 0);

    res.json({
      success: true,
      statementTitle: 'Soko Vibe Buyer Statement',
      generatedAt: new Date().toISOString(),
      buyer: {
        buyerId,
        name: buyerName,
        phone: buyerPhone,
        email: buyerEmail,
        location: buyerLocation,
      },
      summary: {
        totalCredits: Math.round(totalCredits * 100) / 100,
        totalDebits: Math.round(totalDebits * 100) / 100,
        currentBalance: Math.round(balance * 100) / 100,
        totalTransactions: entries.length,
      },
      entries,
    });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 💳 PAYMENT — Check transaction status (fallback if webhook delayed)
// ============================================================
app.get('/api/transaction-status/:orderId', async (req, res) => {
  try {
    const { orderId } = req.params;
    if (!orderId) return res.status(400).json({ error: 'Missing orderId' });
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const doc = await db.collection('transactions').doc(orderId).get();
    if (!doc.exists) return res.status(404).json({ error: 'Transaction not found' });

    const data = doc.data();
    if (!(await isOwnerOrAdmin(req, res, data.buyerId || data.userId || ''))) return;
    res.json({
      success: true,
      status: data.status || 'pending',
      failureReason: data.failureReason || null,
      completedAt: data.completedAt || null,
    });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 📊 ADMIN — Finance summary (all admin money + ClickPesa balance)
// ============================================================
app.get('/api/admin/finance-summary', async (req, res) => {
  try {
    // Allow either admin secret OR Firebase Auth admin
    const secret = req.headers['x-admin-secret'];
    if (secret !== process.env.ADMIN_SECRET) {
      const authHeader = req.headers['authorization'];
      if (authHeader && authHeader.startsWith('Bearer ')) {
        const token = authHeader.slice(7);
        try {
          const decoded = await admin.auth().verifyIdToken(token);
          const userDoc = await db.collection('users').doc(decoded.uid).get();
          if (!userDoc.exists || !userDoc.data().isAdmin) {
            return res.status(401).json({ error: 'Unauthorized' });
          }
        } catch {
          return res.status(401).json({ error: 'Unauthorized' });
        }
      } else {
        return res.status(401).json({ error: 'Unauthorized' });
      }
    }
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    // 1. Estimated ad revenue (each ad view = configured rate)
    const adSnap = await db.collection('ad_views').count().get();
    const estimatedAdRevenue = (adSnap.data().count || 0) * AD_REVENUE_PER_VIEW;

    // 2. Actual Google AdMob revenue (manually entered by admin)
    const admobSnap = await db.collection('admob_earnings').orderBy('month', 'desc').limit(1).get();
    let actualAdRevenue = 0;
    if (!admobSnap.empty) {
      actualAdRevenue = admobSnap.docs[0].data().amount || 0;
    }

    // 3. Total platform commissions from revenue_transactions
    const revSnap = await db.collection('revenue_transactions').get();
    let totalCommissions = 0;
    let totalBoostRevenue = 0;
    revSnap.docs.forEach(doc => {
      const d = doc.data();
      if (d.type === 'boost') {
        totalBoostRevenue += (d.sokoLanguCommission || 0);
      } else {
        totalCommissions += (d.sokoLanguCommission || 0);
      }
    });

    // 4. Total admin balance = actual ad revenue + commissions + boost revenue
    const totalAdminBalance = actualAdRevenue + totalCommissions + totalBoostRevenue;

    // 5. Total money ever processed (only REAL completed/paid transactions)
    const txSnap = await db.collection('transactions').get();
    let totalProcessed = 0;
    const paidStatuses = PAID_STATUSES;
    txSnap.docs.forEach(doc => {
      const d = doc.data();
      if (paidStatuses.has(d.status)) {
        totalProcessed += (d.totalAmount || 0);
      }
    });

    // 6. Total payouts sent
    const withdrawSnap = await db.collection('withdrawals').get();
    let totalPaidOut = 0;
    withdrawSnap.docs.forEach(doc => {
      const d = doc.data();
      if (d.status === 'completed') totalPaidOut += (d.netAmount || d.amount || 0);
    });

    const adminWithdrawSnap = await db.collection('admin_withdrawals').get();
    let totalAdminPaidOut = 0;
    adminWithdrawSnap.docs.forEach(doc => {
      const d = doc.data();
      if (d.status === 'completed') totalAdminPaidOut += (d.netAmount || d.amount || 0);
    });

    const totalPayouts = totalPaidOut + totalAdminPaidOut;

    // Money the admin can actually withdraw: platform commissions + boost
    // revenue only. AdMob revenue sits in Google's account, never in the Soko
    // Vibe ClickPesa wallet, so it must not be withdrawable.
    const availableBalance = totalCommissions + totalBoostRevenue - totalAdminPaidOut;

    // 7. Admin withdrawal history
    let totalAdminWithdrawn = 0;
    adminWithdrawSnap.docs.forEach(doc => {
      const d = doc.data();
      if (d.status === 'completed') totalAdminWithdrawn += (d.amount || 0);
    });

    // 8. Actual ClickPesa wallet balance
    let actualClickPesaBalance = 0;
    try {
      actualClickPesaBalance = await clickpesaBalance();
    } catch (_) {
      actualClickPesaBalance = 0;
    }

    res.json({
      success: true,
      estimatedAdRevenue,
      actualAdRevenue,
      totalCommissions,
      totalBoostRevenue,
      totalAdminBalance,
      totalProcessed,
      totalUserPaidOut: totalPaidOut,
      totalAdminPaidOut,
      totalPayouts,
      totalPaidOut: totalPayouts,
      availableBalance,
      totalAdminWithdrawn,
      actualClickPesaBalance,
      paymentProcessor: 'ClickPesa',
      platformCommissionPercent: PLATFORM_COMMISSION_PERCENT,
      adRevenuePerView: AD_REVENUE_PER_VIEW,
    });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 📊 ADMIN — ClickPesa full visibility (balances, payments, payouts)
// ============================================================
// Mirrors what the ClickPesa merchant dashboard shows so the admin
// can audit everything without leaving the app.
app.get('/api/admin/clickpesa/transactions', async (req, res) => {
  try {
    const auth = await requireAdmin(req, res);
    if (!auth.ok) return;
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const { type = 'all', status = '', channel = '', currency = '', startDate = '', endDate = '', limit = '100' } = req.query;
    const maxLimit = Math.min(Math.max(parseInt(limit, 10) || 100, 1), 500);
    const baseFilters = { limit: String(maxLimit), sortBy: 'createdAt', orderBy: 'DESC' };
    if (status) baseFilters.status = String(status).toUpperCase();
    if (channel) baseFilters.channel = String(channel);
    if (currency) baseFilters.collectedCurrency = String(currency).toUpperCase();
    if (startDate) baseFilters.startDate = String(startDate);
    if (endDate) baseFilters.endDate = String(endDate);

    const [balancesRes, paymentsRes, payoutsRes] = await Promise.allSettled([
      clickpesaRawBalances(),
      type === 'payouts' ? Promise.resolve({ data: [], totalCount: 0 }) : clickpesaQueryPayments(baseFilters),
      type === 'payments' ? Promise.resolve({ data: [], totalCount: 0 }) : clickpesaQueryPayouts({ ...baseFilters, collectedCurrency: undefined, channel: channel || undefined }),
    ]);

    const balances = balancesRes.status === 'fulfilled' ? balancesRes.value : [];
    const payments = paymentsRes.status === 'fulfilled' ? paymentsRes.value : { data: [], totalCount: 0 };
    const payouts = payoutsRes.status === 'fulfilled' ? payoutsRes.value : { data: [], totalCount: 0 };

    const paymentsData = Array.isArray(payments.data) ? payments.data : [];
    const payoutsData = Array.isArray(payouts.data) ? payouts.data : [];

    // Normalize amounts (string values) and summarize
    const summarize = (rows, moneyField) => {
      const totals = {};
      const channelTotals = {};
      let sum = 0;
      for (const row of rows) {
        const amt = Number(row[moneyField] || 0) || 0;
        const st = (row.status || 'UNKNOWN').toUpperCase();
        totals[st] = (totals[st] || 0) + amt;
        const ch = row.channel || 'OTHER';
        channelTotals[ch] = (channelTotals[ch] || 0) + amt;
        sum += amt;
      }
      return { total: sum, byStatus: totals, byChannel: channelTotals };
    };

    res.json({
      success: true,
      balances,
      payments: {
        data: paymentsData,
        totalCount: payments.totalCount || paymentsData.length,
        summary: summarize(paymentsData, 'collectedAmount'),
      },
      payouts: {
        data: payoutsData,
        totalCount: payouts.totalCount || payoutsData.length,
        summary: summarize(payoutsData, 'amount'),
      },
      asOf: new Date().toISOString(),
    });
  } catch (e) {
    console.error('ClickPesa admin transactions error:', e?.message || e);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 📊 ADMIN — Save actual Google AdMob revenue
// ============================================================
app.post('/api/admin/admob-revenue', async (req, res) => {
  try {
    const auth = await requireAdmin(req, res);
    if (!auth.ok) return;
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const { amount, month } = req.body;
    if (amount == null || amount < 0) return res.status(400).json({ error: 'Valid amount required' });
    const monthLabel = month || `${new Date().getMonth() + 1}_${new Date().getFullYear()}`;

    await db.collection('admob_earnings').add({
      amount,
      month: monthLabel,
      enteredAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    await auditLog({
      userId: req.body.userId || 'admin',
      type: 'admob_revenue_entered',
      amount,
      reason: `Actual AdMob revenue entered: TZS ${amount}`,
      metadata: { month: monthLabel },
    });

    res.json({ success: true, amount, month: monthLabel });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 📊 ADMIN — Revenue transactions
// ============================================================
app.get('/api/admin/revenue-transactions', async (req, res) => {
  try {
    const secret = req.headers['x-admin-secret'];
    if (secret !== process.env.ADMIN_SECRET) return res.status(401).json({ error: 'Unauthorized' });
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const limit = Math.min(parseInt(req.query.limit) || 100, 500);
    const snap = await db.collection('revenue_transactions').orderBy('timestamp', 'desc').limit(limit).get();
    const items = snap.docs.map(doc => ({ id: doc.id, ...doc.data() }));
    res.json({ items });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 📊 ADMIN — Audit log (all balance changes)
// ============================================================
app.get('/api/admin/audit-log', async (req, res) => {
  try {
    const secret = req.headers['x-admin-secret'];
    if (secret !== process.env.ADMIN_SECRET) return res.status(401).json({ error: 'Unauthorized' });
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const limit = Math.min(parseInt(req.query.limit) || 100, 500);
    const snap = await db.collection('audit_log').orderBy('timestamp', 'desc').limit(limit).get();
    const logs = snap.docs.map(doc => ({ id: doc.id, ...doc.data() }));
    res.json({ logs });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 📊 ADMIN — Ad views
// ============================================================
app.get('/api/admin/ad-views', async (req, res) => {
  try {
    const secret = req.headers['x-admin-secret'];
    if (secret !== process.env.ADMIN_SECRET) return res.status(401).json({ error: 'Unauthorized' });
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const limit = Math.min(parseInt(req.query.limit) || 100, 500);
    const snap = await db.collection('ad_views').orderBy('createdAt', 'desc').limit(limit).get();
    const items = snap.docs.map(doc => ({ id: doc.id, ...doc.data() }));
    res.json({ items });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 👑 ADMIN — Full user detail (with all balances + orders)
// ============================================================
app.get('/api/admin/user-detail/:uid', async (req, res) => {
  try {
    const secret = req.headers['x-admin-secret'];
    if (secret !== process.env.ADMIN_SECRET) return res.status(401).json({ error: 'Unauthorized' });
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const { uid } = req.params;
    const [userDoc, ordersSnap, withdrawalsSnap, txSnap, auditSnap, sessionSnap] = await Promise.all([
      db.collection('users').doc(uid).get(),
      db.collection('orders').where('sellerId', '==', uid).limit(50).get(),
      db.collection('withdrawals').where('userId', '==', uid).limit(50).get(),
      db.collection('revenue_transactions').where('userId', '==', uid).limit(50).get(),
      db.collection('audit_log').where('userId', '==', uid).orderBy('timestamp', 'desc').limit(50).get(),
      db.collection('user_sessions').doc(uid).get(),
    ]);

    if (!userDoc.exists) return res.status(404).json({ error: 'User not found' });

    // Orders the user bought (as buyer) + chat history for the activity trail
    const buyerOrdersSnap = await db.collection('orders').where('buyerId', '==', uid).limit(50).get();
    const roomsSnap = await db.collection('chat_rooms').where('participants', 'array-contains', uid).limit(10).get();
    const chatMessages = [];
    await Promise.all(roomsSnap.docs.map(async (roomDoc) => {
      try {
        const msgs = await db.collection('chat_rooms').doc(roomDoc.id).collection('messages')
          .orderBy('timestamp', 'desc').limit(5).get();
        msgs.docs.forEach(m => {
          const md = m.data();
          if (md.sender_id === uid || md.receiver_id === uid) {
            chatMessages.push({
              id: m.id, roomId: roomDoc.id,
              senderId: md.sender_id || '', receiverId: md.receiver_id || '',
              text: md.text || '', isRead: !!md.is_read,
              timestamp: md.timestamp || null,
            });
          }
        });
      } catch (_) {}
    }));
    chatMessages.sort((a, b) => {
      const av = a.timestamp ? (a.timestamp.toDate ? a.timestamp.toDate().getTime() : new Date(a.timestamp).getTime()) : 0;
      const bv = b.timestamp ? (b.timestamp.toDate ? b.timestamp.toDate().getTime() : new Date(b.timestamp).getTime()) : 0;
      return bv - av;
    });
    const lastActive = sessionSnap.exists
      ? (sessionSnap.data().lastActive ? sessionSnap.data().lastActive.toDate() : null)
      : null;

    const sortDesc = (arr, field) => arr.sort((a, b) => {
      const ts = (x) => {
        const v = x && x[field];
        if (!v) return 0;
        if (typeof v.seconds === 'number') return v.seconds;
        if (v instanceof Date) return v.getTime() / 1000;
        return typeof v === 'number' ? v : 0;
      };
      return ts(b) - ts(a);
    });

    const raw = userDoc.data();
    const user = { uid, ...raw };
    if (typeof user.sellerBalance !== 'undefined') user.sellerBalance = Math.max(0, user.sellerBalance || 0);
    if (typeof user.pendingEscrow !== 'undefined') user.pendingEscrow = Math.max(0, user.pendingEscrow || 0);
    if (typeof user.coins !== 'undefined') user.coins = Math.max(0, user.coins || 0);

    res.json({
      user,
      orders: sortDesc(ordersSnap.docs.map(d => ({ id: d.id, ...d.data() })), 'createdAt'),
      buyerOrders: sortDesc(buyerOrdersSnap.docs.map(d => ({ id: d.id, ...d.data() })), 'createdAt'),
      withdrawals: sortDesc(withdrawalsSnap.docs.map(d => ({ id: d.id, ...d.data() })), 'createdAt'),
      revenueTransactions: sortDesc(txSnap.docs.map(d => ({ id: d.id, ...d.data() })), 'timestamp'),
      auditLog: sortDesc(auditSnap.docs.map(d => ({ id: d.id, ...d.data() })), 'timestamp'),
      chatMessages: chatMessages.slice(0, 30),
      lastActive: lastActive ? lastActive.getTime() : null,
    });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 👑 ADMIN — Suspend user
// ============================================================
app.delete('/api/admin/users/:uid', async (req, res) => {
  try {
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const secret = req.headers['x-admin-secret'];
    if (secret !== process.env.ADMIN_SECRET) {
      const authHeader = req.headers['authorization'];
      if (authHeader && authHeader.startsWith('Bearer ')) {
        const token = authHeader.slice(7);
        try {
          const decoded = await admin.auth().verifyIdToken(token);
          const userDoc = await db.collection('users').doc(decoded.uid).get();
          if (!userDoc.exists || !userDoc.data().isAdmin) {
            return res.status(401).json({ error: 'Unauthorized' });
          }
        } catch {
          return res.status(401).json({ error: 'Unauthorized' });
        }
      } else {
        return res.status(401).json({ error: 'Unauthorized' });
      }
    }

    const { uid } = req.params;
    await db.collection('users').doc(uid).update({
      isSuspended: true,
      suspendedAt: admin.firestore.FieldValue.serverTimestamp(),
      suspendedBy: 'admin',
    });

    await auditLog({
      userId: uid,
      type: 'admin_suspend',
      amount: 0,
      reason: 'User suspended by admin',
    });
    try {
      await db.collection('notifications').add({
        userId: uid,
        title: 'Akaunti Yako Imesitishwa',
        body: 'Akaunti yako imesitishwa. Wasiliana na msaada kwa maelezo zaidi.',
        isRead: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        data: { type: 'account', status: 'suspended' },
      });
      await sendOneSignalNotification(uid, 'Akaunti Yako Imesitishwa', 'Akaunti yako imesitishwa. Wasiliana na msaada kwa maelezo zaidi.', { type: 'account', status: 'suspended' });
    } catch (_) {}

    res.json({ success: true, message: 'User suspended' });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 👑 ADMIN — Unsuspend user
// ============================================================
app.post('/api/admin/users/:uid/unsuspend', async (req, res) => {
  try {
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const secret = req.headers['x-admin-secret'];
    if (secret !== process.env.ADMIN_SECRET) {
      const authHeader = req.headers['authorization'];
      if (authHeader && authHeader.startsWith('Bearer ')) {
        const token = authHeader.slice(7);
        try {
          const decoded = await admin.auth().verifyIdToken(token);
          const userDoc = await db.collection('users').doc(decoded.uid).get();
          if (!userDoc.exists || !userDoc.data().isAdmin) {
            return res.status(401).json({ error: 'Unauthorized' });
          }
        } catch {
          return res.status(401).json({ error: 'Unauthorized' });
        }
      } else {
        return res.status(401).json({ error: 'Unauthorized' });
      }
    }

    const { uid } = req.params;
    await db.collection('users').doc(uid).update({
      isSuspended: false,
      suspendedAt: admin.firestore.FieldValue.delete(),
      suspendedBy: admin.firestore.FieldValue.delete(),
    });
    try {
      await db.collection('notifications').add({
        userId: uid,
        title: 'Akaunti Yako Imerejeshwa',
        body: 'Akaunti yako imerejeshwa. Sasa unaweza kuendelea kutumia Soko Vibe.',
        isRead: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        data: { type: 'account', status: 'unsuspended' },
      });
      await sendOneSignalNotification(uid, 'Akaunti Yako Imerejeshwa', 'Akaunti yako imerejeshwa. Sasa unaweza kuendelea kutumia Soko Vibe.', { type: 'account', status: 'unsuspended' });
    } catch (_) {}

    res.json({ success: true, message: 'User unsuspended' });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 👑 ADMIN — Policy warning (escalation: warn x3 → block)
// ============================================================
app.post('/api/admin/users/:uid/warn', async (req, res) => {
  try {
    if (!db) return res.status(503).json({ error: 'Database not configured' });
    const auth = await requireAdmin(req, res);
    if (!auth.ok) return;

    const { uid } = req.params;
    const { reason } = req.body || {};
    if (!reason || typeof reason !== 'string' || !reason.trim()) {
      return res.status(400).json({ error: 'Missing warning reason' });
    }

    const userDoc = await db.collection('users').doc(uid).get();
    if (!userDoc.exists) return res.status(404).json({ error: 'User not found' });
    const userData = userDoc.data() || {};

    const current = typeof userData.policyWarnings === 'number' ? userData.policyWarnings : 0;
    const next = current + 1;

    // Record this warning in a subcollection so admins can review the history.
    await db.collection('users').doc(uid).collection('policy_warnings').add({
      reason: reason.trim(),
      by: auth.uid,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    const blocked = next >= 3;
    await db.collection('users').doc(uid).update({
      policyWarnings: next,
      lastWarningReason: reason.trim(),
      lastWarningAt: admin.firestore.FieldValue.serverTimestamp(),
      ...(blocked
        ? {
            isSuspended: true,
            suspendedAt: admin.firestore.FieldValue.serverTimestamp(),
            suspendedBy: 'policy',
            suspendedReason: reason.trim(),
          }
        : {}),
    });

    const warningTitle = `Onyo ${next}/3 — Sera ya Soko Vibe`;
    const warningBody = `Unaonywa (${next}/3): ${reason.trim()}. Ukiingia makosa 3, akaunti itasimamishwa kabisa.`;
    const blockedTitle = 'Akaunti Yako Imefungwa';
    const blockedBody = 'Umefikia maonyo 3 na akaunti yako imefungwa kwa kukiuka sera. Wasiliana na msaada.';

    try {
      await db.collection('notifications').add({
        userId: uid,
        title: blocked ? blockedTitle : warningTitle,
        body: blocked ? blockedBody : warningBody,
        isRead: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        data: { type: 'account', status: blocked ? 'blocked' : 'warned', warningCount: next },
      });
      await sendOneSignalNotification(
        uid,
        blocked ? blockedTitle : warningTitle,
        blocked ? blockedBody : warningBody,
        { type: 'account', status: blocked ? 'blocked' : 'warned', warningCount: next },
      );
    } catch (_) {}

    await auditLog({
      userId: uid,
      type: blocked ? 'admin_policy_block' : 'admin_warning',
      amount: 0,
      reason: reason.trim(),
    });

    res.json({ success: true, warnings: next, blocked });
  } catch (e) {
    console.error('/api/admin/users/:uid/warn error:', e?.message || e);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 👑 ADMIN — Delete order
// ============================================================
app.delete('/api/admin/orders/:id', async (req, res) => {
  try {
    const secret = req.headers['x-admin-secret'];
    if (secret !== process.env.ADMIN_SECRET) return res.status(401).json({ error: 'Unauthorized' });
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const { id } = req.params;
    await db.collection('orders').doc(id).delete();

    res.json({ success: true, message: 'Order deleted' });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

/**
 * Delete product images from Cloudinary by extracting public IDs from URLs.
 * Non-blocking — doesn't fail the request if image deletion fails.
 */
async function deleteProductImages(imageUrls = []) {
  if (!imageUrls.length) return;
  const cloudName = 'dgbsohnl4';
  for (const url of imageUrls) {
    try {
      // Extract public ID from Cloudinary URL: .../v12345/{folder}/{public_id}.ext
      const match = url.match(/\/v\d+\/(.+)\.\w+$/);
      if (!match) continue;
      const publicId = match[1];
      // Cloudinary delete API uses basic auth with API Key + Secret.
      // Since we use unsigned upload, we can't delete via API without keys.
      // Log the orphaned image for manual cleanup.
      console.log(`Orphaned Cloudinary image (needs manual cleanup): ${publicId}`);
    } catch (_) {}
  }
}

// ============================================================
// ☁️ CLOUDINARY — Generate signed upload signature
// ============================================================
app.post('/api/cloudinary/sign', async (req, res) => {
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({ error: 'Missing or invalid token' });
    }
    const token = authHeader.split(' ')[1];
    try {
      await admin.auth().verifyIdToken(token);
    } catch {
      return res.status(401).json({ error: 'Invalid token' });
    }

    const apiKey = process.env.CLOUDINARY_API_KEY;
    const apiSecret = process.env.CLOUDINARY_API_SECRET;
    if (!apiKey || !apiSecret) {
      return res.status(500).json({ error: 'Cloudinary not configured on server' });
    }

    const cloudName = 'dgbsohnl4';
    const folder = req.body.folder || 'soko_langu';
    const timestamp = Math.floor(Date.now() / 1000);

    const params = { folder, timestamp };
    const sortedKeys = Object.keys(params).sort();
    const signatureStr = sortedKeys.map(k => `${k}=${params[k]}`).join('&') + apiSecret;
    const signature = crypto.createHash('sha256').update(signatureStr).digest('hex');

    res.json({ signature, timestamp, apiKey, cloudName });
  } catch (e) {
    console.error('Cloudinary sign error:', e);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 🤖 GROQ AI — Secure proxy (API key stays server-side)
// ============================================================
// The Flutter app sends the full Groq-compatible payload + Firebase token.
// Server verifies auth, injects GROQ_API_KEY, proxies to Groq.
// ============================================================
app.post('/api/ai/chat', async (req, res) => {
  try {
    // Verify Firebase auth
    const authHeader = req.headers['authorization'];
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({ error: 'Missing or invalid token' });
    }
    try {
      await admin.auth().verifyIdToken(authHeader.slice(7));
    } catch {
      return res.status(401).json({ error: 'Invalid token' });
    }

    const { model, messages, temperature, max_tokens } = req.body;
    if (!model || !messages || !Array.isArray(messages)) {
      return res.status(400).json({ error: 'model and messages[] required' });
    }

    const body = await groqChat({ model, messages, temperature, max_tokens });
    res.set('Content-Type', 'application/json');
    res.send(body);
  } catch (e) {
    if (e.message === 'GROQ_API_KEY_NOT_CONFIGURED') {
      return res.status(503).json({ error: 'Groq API key not configured on server' });
    }
    console.error('Groq proxy error:', e.message);
    res.status(e.status || 500).json({ error: 'AI service error' });
  }
});

// Speech-to-text proxy (audio → text via Groq Whisper)
app.post('/api/ai/transcribe', async (req, res) => {
  try {
    const authHeader = req.headers['authorization'];
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({ error: 'Missing or invalid token' });
    }
    try {
      await admin.auth().verifyIdToken(authHeader.slice(7));
    } catch {
      return res.status(401).json({ error: 'Invalid token' });
    }

    const { audio, model, language } = req.body;
    if (!audio) {
      return res.status(400).json({ error: 'audio (base64) required' });
    }

    const body = await groqTranscribe(audio, model, language);
    res.set('Content-Type', 'application/json');
    res.send(body);
  } catch (e) {
    if (e.message === 'GROQ_API_KEY_NOT_CONFIGURED') {
      return res.status(503).json({ error: 'Groq API key not configured on server' });
    }
    console.error('Groq transcribe proxy error:', e.message);
    res.status(e.status || 500).json({ error: 'AI transcription error' });
  }
});

/**
 * Shared logic for deleting a product document + related data + images.
 */
async function deleteProductById(productId) {
  // Get product doc first to grab image URLs
  const productDoc = await db.collection('products').doc(productId).get();
  if (productDoc.exists) {
    const images = productDoc.data().images || [];
    deleteProductImages(images).catch(() => {});
  }

  // Delete related flash sales
  const flashSnap = await db.collection('flash_sales').where('productId', '==', productId).get();
  const batch = db.batch();
  flashSnap.docs.forEach(doc => batch.delete(doc.ref));
  if (flashSnap.docs.length > 0) await batch.commit();

  // Delete the product document
  await db.collection('products').doc(productId).delete();
}

// ============================================================
// 👤 USER — Delete own product (checks ownership)
// ============================================================
app.delete('/api/products/:id', async (req, res) => {
  try {
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const authHeader = req.headers['authorization'];
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const decoded = await admin.auth().verifyIdToken(authHeader.slice(7));
    const { id } = req.params;

    const productDoc = await db.collection('products').doc(id).get();
    if (!productDoc.exists) {
      return res.status(404).json({ error: 'Product not found' });
    }

    const product = productDoc.data();
    if (product.sellerId !== decoded.uid) {
      return res.status(403).json({ error: 'You can only delete your own products' });
    }

    await deleteProductById(id);

    res.json({ success: true, message: 'Product deleted' });
  } catch (e) {
    if (e.code === 'auth/argument-error') {
      return res.status(401).json({ error: 'Invalid token' });
    }
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// ⭐ PRODUCT — Recompute aggregated rating from real reviews
// (client cannot update products/{id}; server admin SDK recomputes
//  averageRating + reviewCount from the reviews collection)
// ============================================================
app.post('/api/products/:id/rating', async (req, res) => {
  try {
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const authHeader = req.headers['authorization'];
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    let decoded;
    try {
      decoded = await admin.auth().verifyIdToken(authHeader.slice(7));
    } catch {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const { id } = req.params;
    if (!id) return res.status(400).json({ error: 'productId required' });

    const productDoc = await db.collection('products').doc(id).get();
    if (!productDoc.exists) {
      return res.status(404).json({ error: 'Product not found' });
    }

    // Prevent the seller from rating their own product
    const productSellerId = productDoc.data().sellerId;
    if (productSellerId && productSellerId === decoded.uid) {
      return res.status(403).json({ error: 'You cannot rate your own product' });
    }
    // Prevent the seller from recomputing the aggregate for someone else's rating request
    // (idempotency is safe here: aggregate reflects all reviews)

    const reviewsSnap = await db.collection('reviews')
      .where('productId', '==', id)
      .get();

    let total = 0;
    for (const doc of reviewsSnap.docs) {
      total += Number(doc.data().rating) || 0;
    }
    const count = reviewsSnap.docs.length;
    const average = count > 0 ? total / count : 0;

    await db.collection('products').doc(id).update({
      rating: average,
      reviewCount: count,
    });

    res.json({ success: true, rating: average, reviewCount: count });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 👑 ADMIN — Delete any product
// ============================================================
app.delete('/api/admin/products/:id', async (req, res) => {
  try {
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const secret = req.headers['x-admin-secret'];
    if (secret !== process.env.ADMIN_SECRET) {
      const authHeader = req.headers['authorization'];
      if (authHeader && authHeader.startsWith('Bearer ')) {
        const token = authHeader.slice(7);
        try {
          const decoded = await admin.auth().verifyIdToken(token);
          const userDoc = await db.collection('users').doc(decoded.uid).get();
          if (!userDoc.exists || !userDoc.data().isAdmin) {
            return res.status(401).json({ error: 'Unauthorized' });
          }
        } catch {
          return res.status(401).json({ error: 'Unauthorized' });
        }
      } else {
        return res.status(401).json({ error: 'Unauthorized' });
      }
    }

    const { id } = req.params;
    await deleteProductById(id);

    res.json({ success: true, message: 'Product deleted' });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 👑 ADMIN — Delete user completely (all data)
// ============================================================
app.delete('/api/admin/users/:uid/full-delete', async (req, res) => {
  try {
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const secret = req.headers['x-admin-secret'];
    if (secret !== process.env.ADMIN_SECRET) {
      const authHeader = req.headers['authorization'];
      if (authHeader && authHeader.startsWith('Bearer ')) {
        const token = authHeader.slice(7);
        try {
          const decoded = await admin.auth().verifyIdToken(token);
          const userDoc = await db.collection('users').doc(decoded.uid).get();
          if (!userDoc.exists || !userDoc.data().isAdmin) {
            return res.status(401).json({ error: 'Unauthorized' });
          }
        } catch {
          return res.status(401).json({ error: 'Unauthorized' });
        }
      } else {
        return res.status(401).json({ error: 'Unauthorized' });
      }
    }

    const { uid } = req.params;

    // Delete user doc
    await db.collection('users').doc(uid).delete();

    // Delete related data in batches
    const batch = db.batch();
    const [orders, withdrawals, notifications, products, reviews, warnings] = await Promise.all([
      db.collection('orders').where('sellerId', '==', uid).get(),
      db.collection('orders').where('buyerId', '==', uid).get(),
      db.collection('withdrawals').where('userId', '==', uid).get(),
      db.collection('notifications').where('userId', '==', uid).get(),
      db.collection('products').where('sellerId', '==', uid).get(),
      db.collection('reviews').where('userId', '==', uid).get(),
      db.collection('users').doc(uid).collection('policy_warnings').get(),
    ]);

    orders.docs.forEach(d => batch.delete(d.ref));
    withdrawals.docs.forEach(d => batch.delete(d.ref));
    notifications.docs.forEach(d => batch.delete(d.ref));
    products.docs.forEach(d => batch.delete(d.ref));
    reviews.docs.forEach(d => batch.delete(d.ref));
    warnings.docs.forEach(d => batch.delete(d.ref));

    await batch.commit();

    // Remove the Firebase Auth record so the deleted account can't be reused.
    try {
      await admin.auth().deleteUser(uid);
    } catch (e) {
      console.error(`Full-delete: auth user ${uid} removal failed (likely already gone): ${e?.message || e}`);
    }

    await auditLog({
      userId: uid, type: 'admin_full_delete', amount: 0,
      reason: 'User fully deleted by admin',
    });

    res.json({ success: true, message: 'User and all related data deleted' });
  } catch (e) {
    console.error('/api/admin/users/:uid/full-delete error:', e?.message || e);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 👑 ADMIN — Update user (toggle_admin, etc.)
// ============================================================
app.patch('/api/admin/users/:uid', async (req, res) => {
  try {
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const secret = req.headers['x-admin-secret'];
    if (secret !== process.env.ADMIN_SECRET) {
      const authHeader = req.headers['authorization'];
      if (authHeader && authHeader.startsWith('Bearer ')) {
        const token = authHeader.slice(7);
        try {
          const decoded = await admin.auth().verifyIdToken(token);
          const userDoc = await db.collection('users').doc(decoded.uid).get();
          if (!userDoc.exists || !userDoc.data().isAdmin) {
            return res.status(401).json({ error: 'Unauthorized' });
          }
        } catch {
          return res.status(401).json({ error: 'Unauthorized' });
        }
      } else {
        return res.status(401).json({ error: 'Unauthorized' });
      }
    }

    const { uid } = req.params;
    const { updates } = req.body;
    if (!updates || typeof updates !== 'object') {
      return res.status(400).json({ error: 'Missing updates object' });
    }

    const allowedFields = ['isSuspended', 'isAdmin'];
    const sanitized = {};
    for (const field of allowedFields) {
      if (field in updates) sanitized[field] = updates[field];
    }
    if (Object.keys(sanitized).length === 0) {
      return res.status(400).json({ error: 'No allowed fields provided' });
    }

    await db.collection('users').doc(uid).update(sanitized);
    res.json({ success: true, message: 'User updated' });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 👑 ADMIN — Delete any document (use with extreme caution)
// ============================================================
app.post('/api/admin/delete-doc', async (req, res) => {
  try {
    const secret = req.headers['x-admin-secret'];
    if (secret !== process.env.ADMIN_SECRET) return res.status(401).json({ error: 'Unauthorized' });
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const { collection, docId } = req.body;
    if (!collection || !docId) return res.status(400).json({ error: 'Missing collection or docId' });

    const allowed = ['transactions', 'withdrawals', 'revenue_transactions', 'ad_views', 'notifications', 'products', 'orders', 'reviews', 'audit_log', 'viewer_ad_views'];
    if (!allowed.includes(collection)) return res.status(403).json({ error: 'Collection not allowed for deletion' });

    await db.collection(collection).doc(docId).delete();

    await auditLog({
      userId: 'admin', type: 'admin_delete', amount: 0,
      reason: `Admin deleted ${collection}/${docId}`,
      metadata: { collection, docId },
    });

    res.json({ success: true, message: `Document ${collection}/${docId} deleted` });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ---- Handle boost payment completion in webhook ----
// (Insert right after the 'coins' handler in the webhook)
// ============================================================

app.use((err, req, res, next) => {
  console.error('Unhandled error:', err);
  res.status(500).json({ error: err.message || 'Internal server error' });
});

// ============================================================
// ⏰ CRON — Auto-release expired escrows
// Call this endpoint every hour from cron-job.org or similar
// ============================================================
app.post('/api/cron/release-escrows', async (req, res) => {
  try {
    const secret = req.headers['x-cron-secret'];
    if (secret !== process.env.ADMIN_SECRET) {
      return res.status(401).json({ error: 'Unauthorized' });
    }
    await releaseExpiredEscrows();
    await failStalePendingBoosts();
    res.json({ success: true, message: 'Escrow release triggered' });
  } catch (e) {
    console.error('Cron release-escrows error:', e);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 📊 Stats endpoint for monitoring
// ============================================================
app.get('/api/stats', async (req, res) => {
  try {
    const auth = await requireAdmin(req, res);
    if (!auth.ok) return;
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const [txSnap, pendingKycSnap, userSnap] = await Promise.all([
      db.collection('transactions').where('status', '==', 'escrow_hold').count().get(),
      db.collection('users').where('kyc.status', '==', 'pending').count().get(),
      db.collection('users').count().get(),
    ]);

    res.json({
      activeEscrows: txSnap.data().count,
      pendingKyc: pendingKycSnap.data().count,
      totalUsers: userSnap.data().count,
    });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 📋 Report endpoints
// ============================================================

// Submit a report
app.post('/api/reports', asyncHandler(async (req, res) => {
  try {
    const { reporterId, reporterName, reportedUserId, reportedUserName, productId, productName, reason, description } = req.body;

    if (!reporterId || !reportedUserId || !reason || !description) {
      return res.status(400).json({ error: 'Missing required fields' });
    }

    // Verify Firebase Auth token
    const authHeader = req.headers['authorization'];
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({ error: 'Unauthorized' });
    }
    let decoded;
    try {
      decoded = await admin.auth().verifyIdToken(authHeader.slice(7));
      if (decoded.uid !== reporterId) {
        return res.status(403).json({ error: 'Reporter ID mismatch' });
      }
    } catch {
      return res.status(401).json({ error: 'Invalid token' });
    }

    // Check if user is suspended
    const userDoc = await db.collection('users').doc(reporterId).get();
    if (userDoc.exists && userDoc.data().isSuspended === true) {
      return res.status(403).json({ error: 'Account suspended' });
    }

    await db.collection('reports').add({
      reporterId,
      reporterName: reporterName || 'Anonymous',
      reportedUserId,
      reportedUserName: reportedUserName || 'Anonymous',
      productId: productId || null,
      productName: productName || null,
      reason,
      description,
      status: 'pending',
      adminNote: null,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    notifyAdmins(
      '🚩 Ripoti Mpya Imewasilishwa',
      `${reporterName || 'Mtumiaji'} ameripoti ${reportedUserName || 'mtumiaji'}. Sababu: ${reason}`,
      { type: 'report', reporterId, reportedUserId },
    );

    res.json({ success: true, message: 'Report submitted' });
  } catch (e) {
    console.error('Submit report error:', e);
    res.status(500).json({ error: 'Internal server error' });
  }
}));

// Get reports (admin only)
app.get('/api/reports', asyncHandler(async (req, res) => {
  try {
    const auth = await requireAdmin(req, res);
    if (!auth.ok) return;
    const { status } = req.query;
    let query = db.collection('reports').orderBy('createdAt', 'desc');
    if (status) query = query.where('status', '==', status);

    const snap = await query.get();
    const reports = snap.docs.map(d => ({ id: d.id, ...d.data() }));
    res.json({ success: true, reports });
  } catch (e) {
    console.error('Get reports error:', e);
    res.status(500).json({ error: 'Internal server error' });
  }
}));

// Update report status (admin only)
app.patch('/api/reports/:id', asyncHandler(async (req, res) => {
  try {
    const auth = await requireAdmin(req, res);
    if (!auth.ok) return;
    const { id } = req.params;
    const { status, adminNote } = req.body;

    if (!status) return res.status(400).json({ error: 'Status is required' });

    const update = { status };
    if (adminNote !== undefined) update.adminNote = adminNote;

    await db.collection('reports').doc(id).update(update);
    res.json({ success: true, message: 'Report updated' });
  } catch (e) {
    console.error('Update report error:', e);
    res.status(500).json({ error: 'Internal server error' });
  }
}));

// ============================================================
// 🚨 Fraud prevention endpoints
// ============================================================

// Get fraud alerts
app.get('/api/fraud/alerts', asyncHandler(async (req, res) => {
  try {
    const auth = await requireAdmin(req, res);
    if (!auth.ok) return;
    const { resolved } = req.query;
    let query = db.collection('fraud_alerts').orderBy('detectedAt', 'desc');
    if (resolved !== undefined) query = query.where('resolved', '==', resolved === 'true');
    const snap = await query.get();
    const alerts = snap.docs.map(d => ({ id: d.id, ...d.data() }));
    res.json({ success: true, alerts });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
}));

// Dismiss a fraud alert
app.patch('/api/fraud/alerts/:id/dismiss', asyncHandler(async (req, res) => {
  try {
    const auth = await requireAdmin(req, res);
    if (!auth.ok) return;
    await db.collection('fraud_alerts').doc(req.params.id).update({ resolved: true });
    res.json({ success: true });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
}));

// Check seller risk score
app.get('/api/fraud/risk/:sellerId', asyncHandler(async (req, res) => {
  try {
    const { sellerId } = req.params;
    if (!(await isOwnerOrAdmin(req, res, sellerId))) return;
    const sellerDoc = await db.collection('users').doc(sellerId).get();
    if (!sellerDoc.exists) return res.status(404).json({ error: 'Seller not found' });

    const seller = sellerDoc.data();
    let riskScore = 0;
    const reasons = [];

    // No KYC
    if (!seller?.kyc?.approved) { riskScore += 30; reasons.push('No KYC'); }

    // New account
    const createdAt = seller?.createdAt?.toDate();
    if (createdAt) {
      const ageDays = (Date.now() - createdAt.getTime()) / 86400000;
      if (ageDays < 1) { riskScore += 20; reasons.push('Account less than 1 day old'); }
      else if (ageDays < 7) { riskScore += 10; reasons.push('Account less than 1 week old'); }
    }

    // Check for active fraud alerts
    const alertSnap = await db.collection('fraud_alerts')
      .where('sellerId', '==', sellerId)
      .where('resolved', '==', false)
      .count()
      .get();
    if ((alertSnap.data().count || 0) > 0) { riskScore += 25; reasons.push('Active fraud alerts'); }

    res.json({
      success: true,
      sellerId,
      riskScore: Math.min(riskScore, 100),
      riskLevel: riskScore >= 50 ? 'high' : riskScore >= 25 ? 'medium' : 'low',
      reasons,
    });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
}));

// ─── FLASH SALE: CREATE ────────────────────────────────
app.post('/api/flash-sale/create', asyncHandler(async (req, res) => {
  try {
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const {
      productId, productName, productImage, originalPrice, salePrice,
      discountPercent, sellerId, sellerName, sellerPhone, location,
      stock, startTime, endTime,
    } = req.body;

    if (!productId || !sellerId || !productName) {
      return res.status(400).json({ error: 'Missing required fields' });
    }

    // Verify Firebase Auth token
    const authHeader = req.headers['authorization'];
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({ error: 'Unauthorized' });
    }
    try {
      const decoded = await admin.auth().verifyIdToken(authHeader.slice(7));
      if (decoded.uid !== sellerId) {
        return res.status(403).json({ error: 'Seller ID does not match authenticated user' });
      }
    } catch {
      return res.status(401).json({ error: 'Invalid token' });
    }

    // Check if user is suspended
    const userDoc = await db.collection('users').doc(sellerId).get();
    if (userDoc.exists && userDoc.data().isSuspended === true) {
      return res.status(403).json({ error: 'Account suspended' });
    }

    // Prevent duplicate active flash sales for the same product.
    // Deactivate any expired ones (isActive may still be true until cron runs).
    const existing = await db.collection('flash_sales')
      .where('productId', '==', productId)
      .where('isActive', '==', true)
      .get();
    const now = new Date();
    let hasActive = false;
    const deactivateBatch = db.batch();
    let batchCount = 0;
    existing.docs.forEach(doc => {
      const data = doc.data();
      if (isFlashSaleStillActive(data, now)) {
        hasActive = true;
      } else {
        deactivateBatch.update(doc.ref, { isActive: false });
        batchCount++;
      }
    });
    if (batchCount > 0) await deactivateBatch.commit();
    if (hasActive) {
      return res.status(400).json({ error: 'Product already has an active flash sale', code: 'FLASH_SALE_ALREADY_ACTIVE' });
    }

    const ref = await db.collection('flash_sales').add({
      productId,
      productName: productName || '',
      productImage: productImage || '',
      originalPrice: originalPrice || 0,
      salePrice: salePrice || 0,
      discountPercent: discountPercent || 0,
      sellerId,
      sellerName: sellerName || '',
      sellerPhone: sellerPhone || '',
      location: location || '',
      stock: stock || 0,
      soldCount: 0,
      isActive: true,
      startTime: startTime ? new Date(startTime) : admin.firestore.FieldValue.serverTimestamp(),
      endTime: endTime ? new Date(endTime) : new Date(Date.now() + 24 * 3600000),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    res.json({ success: true, flashSaleId: ref.id });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
}));

// ─── FLASH SALE: SCAN PRODUCTS ─────────────────────────
app.post('/api/flash-sale/scan', asyncHandler(async (req, res) => {
  try {
    const auth = await requireUser(req, res);
    if (!auth.ok) return;
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const sevenDaysAgo = new Date(Date.now() - 7 * 86400000);
    const productsSnap = await db.collection('products')
      .where('isActive', '==', true)
      .where('createdAt', '<=', sevenDaysAgo)
      .orderBy('createdAt', 'desc')
      .limit(20)
      .get();

    let created = 0;
    const now = new Date();

    for (const doc of productsSnap.docs) {
      const data = doc.data();
      const viewCount = data.viewCount || 0;
      const soldCount = data.soldCount || 0;
      if (soldCount > 5 || viewCount > 200) continue;

      const existing = await db.collection('flash_sales')
        .where('productId', '==', doc.id)
        .where('isActive', '==', true)
        .get();
      // Skip only if there is a truly active (non-expired) flash sale
      const scanNow = new Date();
      const hasActive = existing.docs.some(d => isFlashSaleStillActive(d.data(), scanNow));
      if (hasActive) continue;

      const originalPrice = (data.price || 0).toDouble ? data.price : Number(data.price || 0);
      const discountPercent = soldCount === 0 ? 30 : 20;
      const salePrice = originalPrice * (1 - discountPercent / 100);
      const images = data.images || [];

      await db.collection('flash_sales').add({
        productId: doc.id,
        productName: data.name || '',
        productImage: images.length > 0 ? images[0] : '',
        originalPrice: Math.round(originalPrice),
        salePrice: Math.round(salePrice),
        discountPercent,
        sellerId: data.sellerId || '',
        sellerName: data.sellerName || '',
        sellerPhone: data.sellerPhone || '',
        location: data.location || '',
        stock: data.stock || 0,
        soldCount,
        isActive: true,
        startTime: admin.firestore.FieldValue.serverTimestamp(),
        endTime: new Date(now.getTime() + 24 * 3600000),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      created++;
    }

    res.json({ success: true, flashSalesCreated: created });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
}));

// ─── FLASH SALE: NOTIFY USERS ──────────────────────────
app.post('/api/flash-sale/notify', asyncHandler(async (req, res) => {
  try {
    const auth = await requireUser(req, res);
    if (!auth.ok) return;
    const { productName, salePrice, discountPercent, sellerId, productImage } = req.body;
    if (!sellerId || auth.uid !== sellerId) {
      return res.status(403).json({ error: 'Seller ID mismatch' });
    }
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    // Get all users (paginated by document ID)
    let sentCount = 0;
    const PAGE_SIZE = 500;

    // Dedup: full-audience push at most once per 24h — each flash sale
    // creation would otherwise spam every device. In-app rows still go out.
    const cooldownRef = db.collection('app_settings').doc('flash_sale_push_cooldown');
    const cooldownSnap = await cooldownRef.get();
    const lastSentAt = cooldownSnap.exists && cooldownSnap.data()?.lastSentAt
      ? cooldownSnap.data().lastSentAt.toDate()
      : null;
    const cooldownMs = 24 * 60 * 60 * 1000;
    const pushSkipped = lastSentAt != null && Date.now() - lastSentAt.getTime() < cooldownMs;

    if (!pushSkipped) {
      try {
        // Group recipients by their in-app language and send a localized bulk
        // push per group. The Swahili title/body are server templates; without
        // this split an en/zh user would receive the raw Swahili copy.
        const langBuckets = new Map();
        let lastPushId = null;
        while (true) {
          let query = db.collection('users');
          if (lastPushId) query = query.startAfter(lastPushId);
          query = query.limit(PAGE_SIZE);
          const usersSnap = await query.get();
          if (usersSnap.empty) break;
          for (const doc of usersSnap.docs) {
            // The creator gets a dedicated confirmation push below, so skip
            // them here to avoid a duplicate broadcast to the seller.
            if (doc.id && doc.id !== sellerId) {
              const lang = (doc.data()?.langCode === 'en' || doc.data()?.langCode === 'zh') ? doc.data().langCode : 'sw';
              if (!langBuckets.has(lang)) langBuckets.set(lang, []);
              langBuckets.get(lang).push(doc.id);
            }
          }
          lastPushId = usersSnap.docs[usersSnap.docs.length - 1].id;
        }
        const swTitle = `⚡ Flash Sale! -${discountPercent}%`;
        const swBody = `${productName} sasa TSh ${salePrice} pekee!`;
        sentCount = 0;
        for (const [lang, ids] of langBuckets) {
          const loc = localizeNotif(lang, swTitle, swBody);
          const osResult = await sendOneSignalBulk(ids, loc.title, loc.body, { type: 'flash_sale', productName: productName || '', image: productImage || '' });
          sentCount += osResult.successCount;
          console.log(`[flash-sale] bulk push sent lang=${lang} users=${ids.length} sent=${osResult.successCount}`);
        }
        await cooldownRef.set({ lastSentAt: admin.firestore.Timestamp.now() }, { merge: true });
        console.log(`[flash-sale] bulk push total sentCount=${sentCount}`);
      } catch (pushErr) {
        console.error('OneSignal push skipped for flash sale:', pushErr.message);
      }
    } else {
      console.log(`[flash-sale] push skipped — cooldown active (last sent ${lastSentAt.toISOString()})`);
    }

    // Always confirm to the flash-sale creator that the sale is live, even when
    // the full-audience broadcast is cooldown-gated.
    try {
      if (sellerId) {
        await sendOneSignalNotification(sellerId,
          'Flash Sale Yako Imeanzishwa!',
          `${productName} inauzwa TSh ${salePrice} pekee (-${discountPercent}%).`,
          { type: 'flash_sale', productName: productName || '' }
        );
      }
    } catch (creatorErr) {
      console.error('[flash-sale] creator notify error:', creatorErr.message);
    }

    // Write in-app notification for all users
    let inAppNotified = 0;
    let lastNotifId = null;

    while (true) {
      let query = db.collection('users');
      if (lastNotifId) query = query.startAfter(lastNotifId);
      query = query.limit(PAGE_SIZE);
      const usersForNotif = await query.get();
      if (usersForNotif.empty) break;

      const batch = db.batch();
      let batched = 0;
      for (const doc of usersForNotif.docs) {
        batch.set(db.collection('notifications').doc(), {
          userId: doc.id,
          title: `⚡ Flash Sale! -${discountPercent}%`,
          body: `${productName} sasa TSh ${salePrice} pekee!`,
          type: 'flash_sale',
          data: { type: 'flash_sale', image: productImage || '' },
          isRead: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        batched++;
      }
      if (batched > 0) await batch.commit();
      inAppNotified += batched;
      lastNotifId = usersForNotif.docs[usersForNotif.docs.length - 1].id;
    }

    res.json({ success: true, pushSent: sentCount, inAppNotified, pushSkipped });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
}));

// ─── Boost notification API endpoint (client-callable) ───
app.post('/api/boost/notify', asyncHandler(async (req, res) => {
  try {
    const auth = await requireUser(req, res);
    if (!auth.ok) return;
    const { productId, tier, sellerId } = req.body;
    if (!productId || !tier) {
      return res.status(400).json({ error: 'Missing productId or tier' });
    }
    if (sellerId && auth.uid !== sellerId) {
      return res.status(403).json({ error: 'Seller ID mismatch' });
    }
    await notifyBoostBroadcast(productId, tier, sellerId);
    res.json({ success: true });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
}));

// ─── Boost notification broadcast to all users ───
async function notifyBoostBroadcast(productId, tier, sellerId) {
  if (!db) return;
  try {
    const [productSnap, sellerSnap] = await Promise.all([
      db.collection('products').doc(productId).get(),
      sellerId ? db.collection('users').doc(sellerId).get() : Promise.resolve(null),
    ]);
    const productData = productSnap.data() || {};
    const productName = productData.name || 'Bidhaa';
    const productImage = (productData.images && productData.images.length > 0) ? productData.images[0] : '';
    const sellerName = sellerSnap?.data()?.displayName || sellerSnap?.data()?.name || 'Muuzaji';
    const title = 'Bidhaa Mpya ya Moto! 🔥';
    const body = `${sellerName} ame-boost bidhaa mpya, angalia sasa!`;
    const imageUrl = productImage;

    let sentCount = 0;
    let lastDocId = null;
    const PAGE_SIZE = 500;

    try {
      const userIds = [];
      while (true) {
        let query = db.collection('users');
        if (lastDocId) query = query.startAfter(lastDocId);
        query = query.limit(PAGE_SIZE);
        const snap = await query.get();
        if (snap.empty) break;
        for (const doc of snap.docs) {
          if (doc.id) userIds.push(doc.id);
        }
        lastDocId = snap.docs[snap.docs.length - 1].id;
      }
      const osResult = await sendOneSignalBulk(userIds, title, body, { type: 'boost', productId: productId || '', productName: productName || '', image: imageUrl || '' });
      sentCount = osResult.successCount;
    } catch (pushErr) {
      console.error('OneSignal push skipped for boost:', pushErr.message);
    }

    let inAppNotified = 0;
    let lastNotifId = null;

    while (true) {
      let query = db.collection('users');
      if (lastNotifId) query = query.startAfter(lastNotifId);
      query = query.limit(PAGE_SIZE);
      const usersSnap = await query.get();
      if (usersSnap.empty) break;

      const batch = db.batch();
      let batched = 0;
      for (const doc of usersSnap.docs) {
        if (doc.id === sellerId) continue;
        batch.set(db.collection('notifications').doc(), {
          userId: doc.id,
          title,
          body,
          data: { type: 'boost', productId: productId || '', image: imageUrl || '' },
          isRead: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        batched++;
      }
      if (batched > 0) await batch.commit();
      inAppNotified += batched;
      lastNotifId = usersSnap.docs[usersSnap.docs.length - 1].id;
    }

    console.log(`Boost notify: ${sentCount} OneSignal, ${inAppNotified} in-app`);
  } catch (e) {
    console.error('Boost notify error:', e);
  }
}

app.get('/health', (req, res) => res.json({ status: 'ok' }));
app.get('/ping', (req, res) => res.json({ status: 'ok', timestamp: new Date().toISOString() }));

// ─── Deactivate expired flash sales so sellers can create new ones ───
async function deactivateExpiredFlashSales() {
  if (!db) return;
  try {
    const now = new Date();
    const expired = await db.collection('flash_sales')
      .where('isActive', '==', true)
      .where('endTime', '<=', now)
      .limit(100)
      .get();
    let deactivated = 0;
    const batch = db.batch();
    expired.docs.forEach(doc => {
      batch.update(doc.ref, { isActive: false });
      deactivated++;
    });
    if (deactivated > 0) {
      await batch.commit();
      console.log(`Deactivated ${deactivated} expired flash sales`);
    }
  } catch (e) {
    console.error('deactivateExpiredFlashSales error:', e);
  }
}

// ─── Built-in escrow auto-release check every hour ───
async function releaseExpiredEscrows() {
  if (!db) return;
  try {
    const now = admin.firestore.Timestamp.now();
    // Check both escrow_hold (before dispatch) and dispatched statuses
    const expired = await db.collection('transactions')
      .where('status', 'in', ['escrow_hold', 'dispatched'])
      .where('escrowExpiresAt', '<=', now)
      .where('escrowReleased', '!=', true)
      .limit(20)
      .get();

    for (const doc of expired.docs) {
      const tx = doc.data();
      const sellerReceives = tx.sellerReceives || 0;
      const sellerId = tx.sellerId;

      await doc.ref.update({
        status: 'delivered',
        escrowReleased: true,
        escrowReleasedAt: admin.firestore.FieldValue.serverTimestamp(),
        escrowAutoReleased: true,
      });

      if (sellerId && sellerReceives > 0) {
        const autoSellerDoc = await db.collection('users').doc(sellerId).get();
        const autoPending = autoSellerDoc.exists ? (autoSellerDoc.data().pendingEscrow || 0) : 0;
        const actualPending = Math.min(sellerReceives, autoPending);
        await db.collection('users').doc(sellerId).update({
          sellerBalance: admin.firestore.FieldValue.increment(sellerReceives),
          pendingEscrow: admin.firestore.FieldValue.increment(-actualPending),
        });

        await db.collection('notifications').add({
          userId: sellerId,
          title: 'Escrow Imefunguliwa Kiotomatiki',
          body: `${tx.productName || 'Bidhaa'} escrow imefunguliwa baada ya muda wake. TZS ${sellerReceives.toLocaleString()} zimewekwa kwenye salio lako.`,
          isRead: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        try {
          await sendOneSignalNotification(sellerId, 'Escrow Imefunguliwa Kiotomatiki', `${tx.productName || 'Bidhaa'} — TZS ${sellerReceives.toLocaleString()} zimewekwa salio lako.`, { type: 'escrow_auto_release', transactionId: doc.id });
        } catch (_) {}
      }

      if (tx.buyerId) {
        await db.collection('notifications').add({
          userId: tx.buyerId,
          title: 'Escrow Imefunguliwa Kiotomatiki',
          body: `Muda wa escrow ya ${tx.productName || 'Bidhaa'} umeisha. Pesa zimefunguliwa kwa muuzaji kwa sababu haukuthibitisha upokeaji kwa muda.`,
          isRead: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        try {
          await sendOneSignalNotification(tx.buyerId, 'Escrow Imefunguliwa Kiotomatiki', `${tx.productName || 'Bidhaa'} — muda wa escrow umeisha, pesa zimefunguliwa kwa muuzaji.`, { type: 'escrow_auto_release', transactionId: doc.id });
        } catch (_) {}
      }
    }
  } catch (e) {
    console.error('Auto-release escrow error:', e);
  }
}

// ─── Fail stale pending boost payments (USSD push ignored/declined/expired) ───
// IMPORTANT: before marking "muda wa malipo umeisha" we must ask ClickPesa for the
// real status. M-Pesa/Tigo/Airtel PIN callbacks take ~10-15 min, so a boost that is
// genuinely PAID can still be 'pending' here. If ClickPesa confirms success we apply
// it (never overwrite a completed payment with a spurious timeout); we only fail the
// boost for timeout when ClickPesa still reports it as unresolved and the session
// window has passed.
async function failStalePendingBoosts() {
  if (!db) return;
  try {
    const cutoff = new Date(Date.now() - 10 * 60 * 1000);
    const snap = await db.collection('transactions')
      .where('type', '==', 'boost')
      .where('status', '==', 'pending')
      .where('paymentMethod', '==', 'ussd_push')
      .limit(50)
      .get();
    for (const doc of snap.docs) {
      const tx = doc.data();
      const createdAt = tx.createdAt?.toDate?.() || new Date(0);
      if (createdAt.getTime() > cutoff.getTime()) continue;
      if (tx.status !== 'pending') continue;

      // Ask ClickPesa for the real outcome before deciding to time out.
      let cpStatus = '';
      let cpFailureReason = '';
      try {
        const resp = await clickpesaPaymentStatus(doc.id);
        cpStatus = clickPesaStatusFrom(resp, doc.id);
        cpFailureReason = clickPesaFailureReasonFrom(resp, doc.id);
      } catch (_) {
        // Status API unreachable — fall through and let the poller keep trying.
      }

      if (cpStatus === 'success') {
        // Payment actually completed — apply it instead of failing.
        await applyClickPesaPayment(doc.id, 'success', {});
        continue;
      }
      if (cpStatus === 'failed') {
        const reason = cpFailureReason || 'Malipo ya ussd yameshindikana';
        await doc.ref.update({
          status: 'failed',
          failureReason: reason,
          completedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        await notifyBoostPaymentFailed(tx, reason);
        continue;
      }

      // Still unresolved (pending/unknown) and past the session window → timeout.
      const reason = 'muda wa malipo umeisha';
      await doc.ref.update({
        status: 'failed',
        failureReason: reason,
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      await notifyBoostPaymentFailed(tx, reason);
    }
  } catch (e) {
    console.error('failStalePendingBoosts error:', e.message);
  }
}

// ─── ClickPesa payment status poller — resolve pending USSD payments even when the
// webhook is delayed or lost. ClickPesa only fires the webhook when the mobile-money
// operator reports (M-Pesa/Tigo/Airtel PIN timeouts take ~10-15 min, Mixx ~2s), so we
// poll the status API every 45s and apply the result ourselves.
let clickPesaPollInFlight = false;

/** Maps raw status rows (GET /payments/{orderReference}) to 'success' | 'failed' | '' (still pending/unknown). */
function clickPesaStatusFrom(resp, orderId) {
  let rows = [];
  if (resp && Array.isArray(resp.data)) rows = resp.data;
  else if (Array.isArray(resp)) rows = resp;
  else if (resp && resp.data && Array.isArray(resp.data.rows)) rows = resp.data.rows;
  const match = rows.find((r) => (r.orderReference || r.order_id || r.externalId || '') === orderId) || rows[0] || {};
  const raw = String(match.status || match.paymentStatus || resp?.status || '').toLowerCase();
  // Docs statuses: SUCCESS, SETTLED, PROCESSING, PENDING, FAILED
  if (/success|settled|completed|payment_received|paid/.test(raw)) return 'success';
  if (/fail|cancel|expire|reject|declin|error/.test(raw)) return 'failed';
  return '';
}

/** Extracts the human-readable failure reason from a GET /payments/{orderReference} response. */
function clickPesaFailureReasonFrom(resp, orderId) {
  let rows = [];
  if (resp && Array.isArray(resp.data)) rows = resp.data;
  else if (Array.isArray(resp)) rows = resp;
  else if (resp && resp.data && Array.isArray(resp.data.rows)) rows = resp.data.rows;
  const match = rows.find((r) => (r.orderReference || r.order_id || r.externalId || '') === orderId) || rows[0] || {};
  return String(match.message || match.failureMessage || match.error || resp?.message || '').trim();
}

async function pollPendingClickPesaPayments() {
  if (!db) return;
  if (clickPesaPollInFlight) return;
  clickPesaPollInFlight = true;
  try {
    // Only transactions inside the operator session window are worth polling.
    const since = new Date(Date.now() - 30 * 60 * 1000);

    const txSnap = await db.collection('transactions').where('status', '==', 'pending').limit(30).get();
    const depSnap = await db.collection('deposits').where('status', '==', 'pending').limit(20).get();

    const candidates = [];
    for (const doc of txSnap.docs) {
      const t = doc.data();
      if (t.paymentMethod !== 'ClickPesa' && t.paymentMethod !== 'ussd_push') continue;
      if ((t.createdAt?.toDate?.() || new Date(0)).getTime() < since.getTime()) continue;
      if (t.ussdFailed) continue;
      candidates.push({ id: doc.id, kind: 'tx' });
    }
    for (const doc of depSnap.docs) {
      const t = doc.data();
      if (t.paymentMethod !== 'ClickPesa' && t.paymentMethod !== 'ussd_push') continue;
      if ((t.createdAt?.toDate?.() || new Date(0)).getTime() < since.getTime()) continue;
      if (t.ussdFailed) continue;
      candidates.push({ id: doc.id, kind: 'dep' });
    }

    for (const c of candidates) {
      try {
        const resp = await clickpesaPaymentStatus(c.id);
        const status = clickPesaStatusFrom(resp, c.id);
        if (!status) continue;
        const failureReason = status === 'failed' ? clickPesaFailureReasonFrom(resp, c.id) : '';
        console.log(`[CP-POLL] ${c.id} -> ${status}${failureReason ? ` (${failureReason})` : ''}`);
        await applyClickPesaPayment(c.id, status, { failureReason });
      } catch (e) {
        console.warn(`[CP-POLL] ${c.id}: ${e.message}`);
      }
    }
  } catch (e) {
    console.error('pollPendingClickPesaPayments error:', e.message);
  } finally {
    clickPesaPollInFlight = false;
  }
}

// Run every hour as fallback (cron-job.org can also call the endpoint)
setInterval(releaseExpiredEscrows, 60 * 60 * 1000);
setInterval(deactivateExpiredFlashSales, 60 * 60 * 1000);
setInterval(failStalePendingBoosts, 5 * 60 * 1000);
// ClickPesa status poller — every 45s so successes/failures surface within seconds
// even when the webhook is slow (operator session timeouts) or lost.
setInterval(pollPendingClickPesaPayments, 45 * 1000);
// Also run once on startup
setTimeout(releaseExpiredEscrows, 60 * 1000);
setTimeout(deactivateExpiredFlashSales, 60 * 1000);
setTimeout(failStalePendingBoosts, 60 * 1000);
setTimeout(pollPendingClickPesaPayments, 15 * 1000);

// ============================================================
// 💰 CLICKPESA BALANCE — Check ClickPesa wallet balance
// ============================================================
app.get('/api/clickpesa/balance', async (req, res) => {
  try {
    const auth = await requireAdmin(req, res);
    if (!auth.ok) return;
    const balance = await clickpesaBalance();
    res.json({ success: true, balance });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 🔍 PAYOUT PREVIEW — Validate payout details before sending
// ============================================================
app.post('/api/clickpesa/payout-preview', async (req, res) => {
  try {
    const { amount, phone } = req.body;
    if (!amount || !phone) return res.status(400).json({ error: 'Missing amount or phone' });
    const payoutFee = getPayoutFee(Math.round(amount));
    const preview = {
      amount: Math.round(amount),
      fee: payoutFee,
      netAmount: Math.round(amount) - payoutFee,
      recipientPhone: phone,
    };
    res.json({ success: true, preview });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 🔔 CLICKPESA PAYOUT WEBHOOK — Handle payout status updates
// ============================================================
// ClickPesa calls this when a payout status changes (SUCCESS or FAILED).
// On SUCCESS: mark the Firestore payout record as completed.
// On FAILED: atomically reverse the deducted amount back to the seller's wallet.
app.post('/api/clickpesa/payout-webhook', verifyWebhook, async (req, res) => {
  try {
    let payload = req.body;
    if (payload.data && typeof payload.data === 'object') {
      payload = payload.data;
    }

    const payoutRef = payload.orderReference || payload.externalId || payload.reference || '';
    const rawStatus = (payload.status || payload.event || '').toString().toLowerCase();
    const eventStatus = rawStatus === 'success' || rawStatus === 'completed' ? 'SUCCESS'
      : rawStatus === 'failed' || rawStatus === 'cancelled' ? 'FAILED'
      : rawStatus;

    if (!payoutRef || !eventStatus) {
      return res.status(200).json({ received: false });
    }

    if (!db) return res.status(200).json({ received: false });

    const payoutDoc = await db.collection('payouts').doc(payoutRef).get();
    if (!payoutDoc.exists) {
      console.warn(`ClickPesa payout webhook: payout ${payoutRef} not found`);
      return res.status(200).json({ received: false });
    }

    const payout = payoutDoc.data();
    if (payout.status === PAYOUT_STATUSES.SUCCESS || payout.status === PAYOUT_STATUSES.FAILED) {
      return res.status(200).json({ received: true });
    }

    const clickpesaTxId = payload.id || payload.transactionId || '';

    if (eventStatus === 'SUCCESS') {
      await updatePayoutStatus(payoutRef, PAYOUT_STATUSES.SUCCESS, { clickpesaReference: clickpesaTxId });

      // Update the transactions collection record if it exists
      try {
        await db.collection('transactions').doc(payoutRef).update({
          status: 'completed',
          clickpesaReference: clickpesaTxId,
          completedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      } catch (_) {}

      if (payout.metadata?.sellerId) {
        const sellerId = payout.metadata.sellerId;
        await db.collection('notifications').add({
          userId: sellerId,
          title: 'Payout imefanikiwa!',
          body: `TZS ${(payout.netAmount || payout.amount).toLocaleString()} zimetumwa kwenye mobile money yako.`,
          isRead: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        try {
          await sendOneSignalNotification(sellerId, 'Payout imefanikiwa!', `TZS ${(payout.netAmount || payout.amount).toLocaleString()} zimetumwa kwenye mobile money yako.`, { type: 'withdrawal', status: 'completed' });
        } catch (_) {}
      }
    } else if (eventStatus === 'FAILED') {
      await updatePayoutStatus(payoutRef, PAYOUT_STATUSES.FAILED, {
        failureReason: payload.message || payload.error || 'payout failed',
        clickpesaReference: clickpesaTxId,
      });

      // Update the transactions collection record to failed
      try {
        await db.collection('transactions').doc(payoutRef).update({
          status: 'failed',
          failureReason: payload.message || payload.error || 'payout failed',
          clickpesaReference: clickpesaTxId,
          completedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      } catch (_) {}

      // Atomically reverse the deducted amount back to the seller's wallet
      if (payout.userId && payout.amount) {
        try {
          await db.runTransaction(async (tx) => {
            const userRef = db.collection('users').doc(payout.userId);
            const userSnap = await tx.get(userRef);
            if (!userSnap.exists) return;
            tx.update(userRef, {
              sellerBalance: admin.firestore.FieldValue.increment(payout.amount),
            });
          });
          console.log(`ClickPesa payout reversed: ${payoutRef} — TZS ${payout.amount} returned to ${payout.userId}`);
        } catch (reverseErr) {
          console.error(`CRITICAL: Failed to reverse payout ${payoutRef} for user ${payout.userId}:`, reverseErr);
        }
      }

      // Notify user about failed payout
      if (payout.userId) {
        try {
          await db.collection('notifications').add({
            userId: payout.userId,
            title: '❌ Utoaji wa Pesa Umeshindwa',
            body: `TZS ${(payout.netAmount || payout.amount).toLocaleString()} hazikutumwa. Pesa zimerudishwa kwenye pochi yako. Jaribu tena.`,
            isRead: false,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            data: { type: 'withdrawal', status: 'failed', payoutId: payoutRef },
          });
          await sendOneSignalNotification(payout.userId, '❌ Utoaji wa Pesa Umeshindwa', `TZS ${(payout.netAmount || payout.amount).toLocaleString()} hazikutumwa. Pesa zimerudishwa kwenye pochi yako. Jaribu tena.`, { type: 'withdrawal', status: 'failed', payoutId: payoutRef });
        } catch (_) {}
      }

      // Attempt auto-retry if under max retries
      try {
        await retryFailedPayout(payoutRef);
      } catch (_) {}
    }

    res.status(200).json({ received: true });
  } catch (e) {
    console.error('ClickPesa payout webhook error:', e);
    res.status(200).json({ received: false });
  }
});

// ─── TRANSACTIONS: CREATE ───────────────────────────────────
app.post('/api/transactions/create', asyncHandler(async (req, res) => {
  if (!db) return res.status(503).json({ error: 'Database not configured' });
  const { buyerId, buyerName, buyerPhone, sellerId, sellerName, productId, productName, productPrice, transactionReference } = req.body;
  if (!buyerId || !sellerId || !productId || !productName || productPrice == null) {
    return res.status(400).json({ error: 'Missing required fields' });
  }
  const authHeader = req.headers['authorization'];
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  let decoded;
  try {
    decoded = await admin.auth().verifyIdToken(authHeader.slice(7));
  } catch {
    return res.status(401).json({ error: 'Invalid token' });
  }
  if (decoded.uid !== buyerId) {
    return res.status(403).json({ error: 'Buyer ID does not match authenticated user' });
  }
  const userDoc = await db.collection('users').doc(sellerId).get();
  if (userDoc.exists && userDoc.data().isSuspended === true) {
    return res.status(403).json({ error: 'Seller is suspended' });
  }

  const price = await resolveEffectivePrice(db, productId, productPrice);
  // USSD Push fee is charged to the customer by ClickPesa on top of the amount, so
  // we don't pre-add it here — totalAmount reflects what is actually sent to ClickPesa.
  const processingFee = 0;
  const platformFee = Math.round(price * PLATFORM_COMMISSION_PERCENT);
  // Buyer (payer) bears commission; seller receives the full price.
  const totalAmount = price + platformFee;
  const sellerReceives = price;

  const txRef = await db.collection('transactions').doc();
  await txRef.set({
    buyerId, buyerName: buyerName || '', buyerPhone: buyerPhone || '',
    sellerId, sellerName: sellerName || '',
    productId, productName,
    productPrice: price, processingFee, platformFee,
    sokovibeCommission: platformFee,
    totalAmount, sellerReceives,
    // Never mark a sale complete from this endpoint — real payment must be
    // confirmed via the ClickPesa webhook before money moves to the seller.
    status: 'pending',
    paymentMethod: 'ClickPesa',
    transactionReference: transactionReference || '',
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  res.json({ success: true, transactionId: txRef.id });
}));

// ─── CATEGORIES: ADD DEFAULTS ───────────────────────────────
app.post('/api/categories/add-defaults', asyncHandler(async (req, res) => {
  if (!db) return res.status(503).json({ error: 'Database not configured' });
  const auth = await requireAdmin(req, res);
  if (!auth.ok) return;
  const categories = [
    { id: 'electronics', name: 'Electronics', icon: 'electronics', order: 1, isActive: true },
    { id: 'fashion', name: 'Fashion & Clothing', icon: 'fashion', order: 2, isActive: true },
    { id: 'home', name: 'Home & Garden', icon: 'home', order: 3, isActive: true },
    { id: 'vehicles', name: 'Vehicles', icon: 'vehicles', order: 4, isActive: true },
    { id: 'property', name: 'Property', icon: 'property', order: 5, isActive: true },
    { id: 'services', name: 'Services', icon: 'services', order: 6, isActive: true },
    { id: 'jobs', name: 'Jobs', icon: 'jobs', order: 7, isActive: true },
    { id: 'agriculture', name: 'Agriculture', icon: 'agriculture', order: 8, isActive: true },
    { id: 'health', name: 'Health & Beauty', icon: 'health', order: 9, isActive: true },
    { id: 'education', name: 'Education', icon: 'education', order: 10, isActive: true },
    { id: 'sports', name: 'Sports & Leisure', icon: 'sports', order: 11, isActive: true },
    { id: 'pets', name: 'Pets', icon: 'pets', order: 12, isActive: true },
    { id: 'food', name: 'Food & Drinks', icon: 'food', order: 13, isActive: true },
    { id: 'phones', name: 'Phones & Tablets', icon: 'phones', order: 14, isActive: true },
    { id: 'computing', name: 'Computing', icon: 'computing', order: 15, isActive: true },
  ];
  const batch = db.batch();
  for (const cat of categories) {
    batch.set(db.collection('categories').doc(cat.id), cat);
  }
  await batch.commit();
  res.json({ success: true });
}));

// ─── CATEGORIES: UPDATE ─────────────────────────────────────
app.post('/api/categories/update', asyncHandler(async (req, res) => {
  if (!db) return res.status(503).json({ error: 'Database not configured' });
  const auth = await requireAdmin(req, res);
  if (!auth.ok) return;
  const { categoryId, data } = req.body;
  if (!categoryId || !data) {
    return res.status(400).json({ error: 'categoryId and data required' });
  }
  await db.collection('categories').doc(categoryId).update(data);
  res.json({ success: true });
}));

// ─── FLASH SALES: DEACTIVATE EXPIRED ──────────────────────────
app.post('/api/flash-sales/deactivate-expired', asyncHandler(async (req, res) => {
  if (!db) return res.status(503).json({ error: 'Database not configured' });
  const authHeader = req.headers['authorization'];
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  try {
    await admin.auth().verifyIdToken(authHeader.slice(7));
  } catch {
    return res.status(401).json({ error: 'Invalid token' });
  }
  const { productId } = req.body;
  if (!productId) return res.status(400).json({ error: 'productId required' });
  const snap = await db.collection('flash_sales')
    .where('productId', '==', productId)
    .where('isActive', '==', true)
    .get();
  const now = new Date();
  const batch = db.batch();
  let count = 0;
  snap.forEach(doc => {
    const sale = doc.data();
    if (now > sale.endTime.toDate()) {
      batch.update(doc.ref, { isActive: false });
      count++;
    }
  });
  if (count > 0) await batch.commit();
  res.json({ success: true, deactivated: count });
}));

// ─── FLASH SALES: DELETE ─────────────────────────────────────
app.post('/api/flash-sales/delete', asyncHandler(async (req, res) => {
  if (!db) return res.status(503).json({ error: 'Database not configured' });
  const auth = await requireAdmin(req, res);
  if (!auth.ok) return;
  const { flashSaleId } = req.body;
  if (!flashSaleId) return res.status(400).json({ error: 'flashSaleId required' });
  await db.collection('flash_sales').doc(flashSaleId).delete();
  res.json({ success: true });
}));

// ─── NOTIFICATIONS: BROADCAST TO ALL USERS ──────────────────
app.post('/api/notifications/broadcast', asyncHandler(async (req, res) => {
  if (!db) return res.status(503).json({ error: 'Database not configured' });
  const auth = await requireAdmin(req, res);
  if (!auth.ok) return;
  const { title, body, data } = req.body;
  if (!title) return res.status(400).json({ error: 'title required' });

  const usersSnap = await db.collection('users').get();
  const userIds = [];
  let notifCount = 0;
  const batch = db.batch();

  for (const userDoc of usersSnap.docs) {
    const uid = userDoc.id;
    const notifRef = db.collection('notifications').doc();
    batch.set(notifRef, {
      userId: uid,
      title,
      body: body || '',
      data: data || {},
      isRead: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    notifCount++;
    userIds.push(uid);
  }

  await batch.commit();

  let sent = 0;
  if (userIds.length > 0) {
    const osResult = await sendOneSignalBulk(userIds, title, body || '', { ...(data || {}), type: (data && data.type) || 'general' }, { bypassPrefs: true });
    sent = osResult.successCount;
  }

  await db.collection('admin_notifications').add({
    title,
    body,
    target: 'all',
    sentCount: sent,
    notifCount,
    sentAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  res.json({ success: true, notifications: notifCount, pushSent: sent });
}));

// ─── User language sync — write langCode AND drop the per-user cache so a
// language change applies to the very next SMS/push instead of waiting out the
// 5-minute TTL. The app calls this whenever the user switches language. ───
app.post('/api/user/language', asyncHandler(async (req, res) => {
  if (!db) return res.status(503).json({ error: 'Database not configured' });
  const auth = await requireUser(req, res);
  if (!auth.ok) return;
  const { langCode } = req.body || {};
  if (!['sw', 'en', 'zh'].includes(langCode)) {
    return res.status(400).json({ error: 'Invalid langCode' });
  }
  await db.collection('users').doc(auth.uid).set({ langCode }, { merge: true });
  notifLangCache.del(`notif_lang:${auth.uid}`);
  console.log(`[lang] user ${auth.uid} → ${langCode} (cache invalidated)`);
  res.json({ ok: true, langCode });
}));

// SMS has its own language, independent of the in-app/push language.
// AuthNotifier/UserService sends this from the settings picker; the SMS-only
// option guarantees the user's transactional SMS is never mixed-language.
app.post('/api/user/sms-language', asyncHandler(async (req, res) => {
  if (!db) return res.status(503).json({ error: 'Database not configured' });
  const auth = await requireUser(req, res);
  if (!auth.ok) return;
  const { smsLangCode } = req.body || {};
  if (!['sw', 'en', 'zh'].includes(smsLangCode)) {
    return res.status(400).json({ error: 'Invalid smsLangCode' });
  }
  await db.collection('users').doc(auth.uid).set({ smsLangCode }, { merge: true });
  notifLangCache.del(`sms_lang:${auth.uid}`);
  console.log(`[sms-lang] user ${auth.uid} → ${smsLangCode} (cache invalidated)`);
  res.json({ ok: true, smsLangCode });
}));

// ─── Global error handler (catches unhandled errors, never leaks internals) ───
app.use((err, req, res, _next) => {
  console.error('Unhandled error:', err?.stack || err?.message || err);
  res.status(500).json({ error: 'Internal server error' });
});

// ─── Clear-token (no-op — OneSignal manages tokens) ──
app.post('/api/clear-token', async (req, res) => {
  try {
    const { uid } = req.body;
    if (!uid) return res.status(400).json({ error: 'uid required' });
    console.log('[OS] Clear-token for ' + uid + ' — no-op (OneSignal manages tokens)');
    res.json({ success: true, note: 'OneSignal manages tokens' });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ─── Diagnostic: check OneSignal credentials ──────────────────
app.get('/api/fcm-check', async (req, res) => {
  try {
    const auth = await requireAdmin(req, res);
    if (!auth.ok) return;
    const hasConfig = !!(process.env.ONE_SIGNAL_APP_ID && process.env.ONE_SIGNAL_REST_API_KEY);
    res.json({
      status: hasConfig ? 'configured' : 'missing-config',
      provider: 'OneSignal',
      hasAppId: !!process.env.ONE_SIGNAL_APP_ID,
      hasApiKey: !!process.env.ONE_SIGNAL_REST_API_KEY,
      appIdPrefix: process.env.ONE_SIGNAL_APP_ID ? process.env.ONE_SIGNAL_APP_ID.substring(0, 8) + '...' : null,
      note: 'Use POST /api/test-fcm with userId + title to test push delivery',
    });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ─── Diagnostic: test OneSignal push (by userId) ─────
app.post('/api/test-fcm', async (req, res) => {
  try {
    const auth = await requireAdmin(req, res);
    if (!auth.ok) return;
    const { userId, title, body } = req.body;
    if (!title) return res.status(400).json({ error: 'title required' });
    if (!userId) return res.status(400).json({ error: 'userId required' });
    if (!db) return res.status(503).json({ error: 'Database not configured' });
    try {
      const result = await sendOneSignalNotification(userId, title || '', body || 'Test body', { type: 'general', test: 'true' });
      if (result && result.id) {
        return res.json({ success: true, method: 'OneSignal', notificationId: result.id, userId });
      }
      return res.status(502).json({ success: false, error: 'OneSignal send failed', result });
    } catch (e) {
      return res.status(502).json({ success: false, error: e.message });
    }
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});



// ============================================================
// 💬 CHAT — Send message via REST (replaces onSnapshot listener)
// ============================================================
app.post('/api/chat/send', async (req, res) => {
  try {
    const { senderId, receiverId, roomId, text, productId, productName, replyTo, replyToContent, replyToSender } = req.body;
    if (!senderId || !receiverId || !roomId || !text) {
      return res.status(400).json({ error: 'Missing required fields (senderId, receiverId, roomId, text)' });
    }
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    // Verify Firebase Auth token
    const authHeader = req.headers['authorization'];
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({ error: 'Unauthorized' });
    }
    let decoded;
    try {
      decoded = await admin.auth().verifyIdToken(authHeader.slice(7));
    } catch {
      return res.status(401).json({ error: 'Invalid token' });
    }
    if (decoded.uid !== senderId) {
      return res.status(403).json({ error: 'Sender ID mismatch' });
    }

    // Check sender is not suspended
    const senderDoc = await db.collection('users').doc(senderId).get();
    if (senderDoc.exists && senderDoc.data().isSuspended === true) {
      return res.status(403).json({ error: 'Account suspended' });
    }

    // Verify room exists and sender is a participant
    const roomDoc = await db.collection('chat_rooms').doc(roomId).get();
    if (!roomDoc.exists) {
      return res.status(404).json({ error: 'Chat room not found' });
    }
    const room = roomDoc.data();
    if (!room.participants.includes(senderId)) {
      return res.status(403).json({ error: 'You are not a participant in this room' });
    }

    // Write message to Firestore
    const msgRef = await db.collection('chat_rooms').doc(roomId).collection('messages').add({
      sender_id: senderId,
      receiver_id: receiverId,
      text,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      is_read: false,
      is_delivered: true,
      ...(productId ? { product_id: productId } : {}),
      ...(productName ? { product_name: productName } : {}),
      ...(replyTo ? { reply_to: replyTo } : {}),
      ...(replyToContent ? { reply_to_content: replyToContent } : {}),
      ...(replyToSender ? { reply_to_sender: replyToSender } : {}),
    });

    // Update room metadata
    await db.collection('chat_rooms').doc(roomId).update({
      last_message: text,
      last_timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Presence-aware delivery: a recipient currently viewing this exact
    // conversation (activeChatRoom === roomId) sees the message live, so we
    // skip the unread bump, push, and in-app banner. If they are in the app
    // elsewhere (fresh lastActive) we still bump unread + in-app badge but skip
    // the disruptive heads-up push.
    const RECEIVER_FRESH_MS = 2 * 60 * 1000;
    const senderName = senderDoc.exists
      ? (senderDoc.data().displayName || senderDoc.data().name || 'Mtumiaji')
      : 'Mtumiaji';
    let receiverActiveHere = false;
    let receiverFresh = false;
    let receiverData = null;
    let receiverRoomId = null;
    try {
      const receiverDoc = await db.collection('users').doc(receiverId).get();
      if (receiverDoc.exists) {
        receiverData = receiverDoc.data();
        receiverRoomId = receiverData.activeChatRoom || null;
        const lastActive = receiverData.lastActive;
        if (lastActive && typeof lastActive.toMillis === 'function') {
          receiverFresh = Date.now() - lastActive.toMillis() < RECEIVER_FRESH_MS;
        }
      }
    } catch (_) {}
    // activeChatRoom only counts as "watching live" while the user's presence
    // is fresh — lastActive stops refreshing when the app backgrounds, so
    // pushes resume ~2min after they leave the app.
    receiverActiveHere = receiverRoomId === roomId && receiverFresh;

    // Increment unread count for receiver (unless they're watching the room).
// Unread is tracked per-user (unread_counts.<uid>) so the sender never sees a
// bubble on their own sent messages — role fields below are kept for
// backward-compat with existing installations.
if (!receiverActiveHere) {
  try {
    await db.collection('chat_rooms').doc(roomId).update({
      [`unread_counts.${receiverId}`]: admin.firestore.FieldValue.increment(1),
    });
    const legacyField = receiverData?.isBuyer === true ? 'unread_count_buyer' : 'unread_count_seller';
    await db.collection('chat_rooms').doc(roomId).update({
      [legacyField]: admin.firestore.FieldValue.increment(1),
    });
  } catch (_) {}
}

    // Send OneSignal push to receiver (only when they're away from the app)
    if (!receiverActiveHere && !receiverFresh) {
      try {
        await sendOneSignalNotification(receiverId, senderName, text, { type: 'chat', senderId, senderName, roomId });
      } catch (_) {}
    }

    // Create in-app notification doc for receiver (unless watching the room)
    if (!receiverActiveHere) {
      try {
        await db.collection('notifications').add({
          userId: receiverId,
          title: senderName,
          body: text,
          type: 'chat',
          data: { senderId, senderName, roomId },
          isRead: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      } catch (_) {}
    }

    res.json({ success: true, messageId: msgRef.id });
  } catch (e) {
    console.error('/api/chat/send error:', e);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 💳 AVAILABLE PAYMENT METHODS
// ============================================================

/// Get all supported payment methods with fee info
app.get('/api/payment-methods', (req, res) => {
  res.json({ success: true, methods: ALL_PAYMENT_METHODS });
});

/// Calculate fee for a given method + amount
app.post('/api/payment-methods/calc-fee', (req, res) => {
  const { methodId, amount, provider } = req.body;
  if (!methodId || amount == null) {
    return res.status(400).json({ error: 'methodId and amount are required' });
  }
  const fee = calcGatewayFee(methodId, Number(amount), provider);
  const method = ALL_PAYMENT_METHODS.find(m => m.id === methodId);
  res.json({
    success: true,
    methodId,
    amount: Number(amount),
    fee,
    total: Number(amount) + fee,
    feeType: method?.feeType || 'tiered',
  });
});

// ============================================================
// 💰 WALLET — Deposit, balance, and history
// ============================================================

/// Get available deposit methods
app.get('/api/wallet/deposit/methods', (req, res) => {
  res.json({
    success: true,
    methods: [
      {
        id: 'ussd',
        name: 'Mobile Money USSD Push',
        nameSw: 'USSD Push (M-Pesa, Tigo, Airtel)',
        description: 'Receive a USSD prompt on your phone. Works with M-Pesa, Airtel Money, Tigo, HaloPesa.',
        descriptionSw: 'Pokea kidokezo cha USSD kwenye simu yako. Inafanya kazi na M-Pesa, Airtel, Tigo, HaloPesa.',
        feeDescription: 'Tiered fee (TZS 54 – 7,960)',
      },
      {
        id: 'billpay',
        name: 'BillPay (M-Pesa, Airtel, Tigo)',
        nameSw: 'BillPay (M-Pesa, Airtel, Tigo)',
        description: 'Pay directly via mobile money BillPay. 1% fee.',
        descriptionSw: 'Lipa moja kwa moja kwa BillPay. Ada 1%.',
        feeDescription: '1% fee',
      },
    ],
  });
});

/// Calculate gateway fee for a payment method and amount (no API keys exposed to client)
app.post('/api/gateway-fee', (req, res) => {
  try {
    const { method, amount, provider } = req.body;
    if (!method || !amount) {
      return res.status(400).json({ error: 'method and amount are required' });
    }
    const fee = calcGatewayFee(method, Math.round(amount), provider);
    res.json({ fee, method, amount: Math.round(amount) });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

/// Initiate wallet deposit
app.post('/api/wallet/deposit', async (req, res) => {
  try {
    // Verify Firebase auth token
    const authHeader = req.headers.authorization || '';
    const token = authHeader.replace('Bearer ', '');
    if (!token) {
      return res.status(401).json({ error: 'Unauthorized' });
    }
    let decodedToken;
    try {
      decodedToken = await admin.auth().verifyIdToken(token);
    } catch (_) {
      return res.status(401).json({ error: 'Invalid token' });
    }

    const { userId, phone, amount, method } = req.body;
    if (!userId || userId !== decodedToken.uid) {
      return res.status(403).json({ error: 'userId mismatch' });
    }
    if (!amount) {
      return res.status(400).json({ error: 'amount is required' });
    }
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const depositRef = `dep${Date.now().toString(36)}${Math.random().toString(36).substring(2, 8)}`;
    const depMethod = method || 'ussd';

    if (!phone) {
      return res.status(400).json({ error: 'phone is required' });
    }

    if (depMethod === 'billpay') {
      // ── BillPay flow: create order control number ──
      const gatewayFee = calcGatewayFee('billpay', Math.round(amount), req.body.provider);
      const totalCharge = Math.round(amount) + gatewayFee;

      await db.collection('deposits').doc(depositRef).set({
        userId,
        phone,
        amount: Math.round(amount),
        gatewayFee,
        totalCharge,
        status: 'pending',
        paymentMethod: 'BillPay',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      const billResult = await clickpesaCreateBillPayOrder({
        billAmount: totalCharge,
        billDescription: `Soko Vibe wallet deposit: TZS ${Math.round(amount)}`,
        billPaymentMode: 'EXACT',
        billReference: depositRef,
      });

      if (!billResult || billResult.success === false || (!billResult.billPayNumber && !billResult.data?.billPayNumber)) {
        const errMsg = billResult?.message || billResult?.error || 'BillPay API failed to generate control number';
        return res.status(502).json({ error: `BillPay error: ${errMsg}` });
      }

      const billPayNumber = billResult.billPayNumber || billResult.data?.billPayNumber || billResult.billReference || '';
      const clickpesaRef = billResult.id || billResult.data?.id || billPayNumber || '';

      await db.collection('deposits').doc(depositRef).update({
        billPayNumber,
        clickpesaReference: clickpesaRef,
      });

      res.json({
        success: true,
        depositRef,
        method: 'billpay',
        billPayNumber,
        totalCharge,
        gatewayFee,
        clickpesaId: clickpesaRef,
        message: `BillPay control number: ${billPayNumber}. Total charge: TZS ${totalCharge.toLocaleString()}. Open M-Pesa > Lipa > BillPay > enter ${billPayNumber} > amount TZS ${totalCharge.toLocaleString()} > PIN.`,
      });
    } else {
      // ── USSD Push flow ──
      // ClickPesa charges its USSD fee to the customer on top of the amount, so we
      // send the real deposit amount (never pre-add the fee) to avoid double-charging.
      const processingFee = 0;
      const totalCharge = Math.round(amount);

      const phoneDigits = phone.replace(/\D/g, '');
      const normalizedPhone = phoneDigits.startsWith('0')
        ? '255' + phoneDigits.substring(1)
        : phoneDigits.startsWith('255')
          ? phoneDigits
          : '255' + phoneDigits;

      await db.collection('deposits').doc(depositRef).set({
        userId,
        phone: normalizedPhone,
        amount: Math.round(amount),
        processingFee,
        totalCharge,
        status: 'pending',
        paymentMethod: 'ClickPesa',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // Fire ClickPesa async — return immediately
      const baseUrl3 = process.env.PUBLIC_SERVER_URL || `${req.protocol}://${req.get('host')}`;
      clickpesaCollect({ amount: totalCharge, orderReference: depositRef, phoneNumber: normalizedPhone, callbackUrl: `${baseUrl3}/api/clickpesa/webhook` })
        .then((result) => {
          const ref = result?.id || '';
          if (!ref) { console.error(`[USSD] Deposit ClickPesa no ref for ${depositRef}`); return; }
          return db.collection('deposits').doc(depositRef).update({ clickpesaReference: ref, ussdSent: true });
        })
        .then(() => console.log(`[USSD] Deposit push sent for ${depositRef}`))
        .catch((err) => {
          console.error(`[USSD] Deposit ClickPesa error:`, err?.response?.data || err.message);
          db.collection('deposits').doc(depositRef).update({ ussdFailed: true }).catch(() => {});
        });

      res.json({
        success: true, depositRef, method: 'ussd',
        message: `Malipo ya TZS ${totalCharge.toLocaleString()} yanatuma USSD push kwa ${normalizedPhone}. Ada ya ClickPesa inaongezwa kwenye malipo yako.`,
      });
    }
  } catch (e) {
    console.error('/api/wallet/deposit error:', e);
    res.status(500).json({ error: e.message || 'Deposit failed' });
  }
});

/// Purchase via wallet balance deduction
app.post('/api/wallet/purchase', async (req, res) => {
  try {
    const auth = await requireUser(req, res);
    if (!auth.ok) return;
    if (!db) return res.status(503).json({ error: 'Database not configured' });
    const {
      buyerId, buyerName, productId, productName, productImage,
      productPrice, sellerId, sellerName, processingFee, serviceFeePercent,
      totalAmount, region, district, ward, street, landmarks, deliveryType, orderId, shippingCost,
    } = req.body;

    if (!buyerId || !sellerId || !productId || !productName || productPrice == null) {
      return res.status(400).json({ error: 'Missing required fields' });
    }
    if (auth.uid !== buyerId) {
      return res.status(403).json({ error: 'Forbidden: cannot purchase from another account' });
    }

    // Verify buyer has sufficient balance
    const buyerDoc = await db.collection('users').doc(buyerId).get();
    if (!buyerDoc.exists) return res.status(404).json({ error: 'Buyer not found' });
    const buyerData = buyerDoc.data();
    if (buyerData.isSuspended === true) {
      return res.status(403).json({ error: 'Account is suspended' });
    }
    const balance = buyerData.walletBalance || 0;

    // Guard against paying the same order twice — only awaiting_payment orders
    // can still be paid (post-quote); anything already escrowed is a duplicate.
    if (orderId) {
      const existingTx = await db.collection('transactions').doc(orderId).get();
      if (existingTx.exists && !['awaiting_payment', 'pending', 'quoted'].includes(existingTx.data().status)) {
        return res.status(400).json({ error: 'Order already paid' });
      }
    }

    // Check seller is not suspended
    const sellerDoc = await db.collection('users').doc(sellerId).get();
    if (sellerDoc.exists && sellerDoc.data().isSuspended === true) {
      return res.status(403).json({ error: 'Seller is suspended' });
    }

    const price = await resolveEffectivePrice(db, productId, productPrice);
    const shipping = Math.round(Number(shippingCost) || 0);
    // Commission is always the platform rate — never trust serviceFeePercent from
    // the client, otherwise a buyer could set it to 0 and skip the platform fee.
    const commissionPercent = PLATFORM_COMMISSION_PERCENT;
    const commission = Math.round(price * commissionPercent);
    // Buyer already pays commission in totalAmount (see order_detail_screen).
    // sellerReceives must be computed server-side so a client-supplied totalAmount
    // can't overcredit the seller or deduct a different amount than was quoted.
    const sellerReceives = price + shipping;

    const committedTotal = price + shipping + commission;
    if (balance < committedTotal) {
      return res.status(400).json({ error: `Insufficient wallet balance: requires TZS ${committedTotal.toLocaleString()}` });
    }

    // Deduct from buyer wallet
    await db.collection('users').doc(buyerId).set({
      walletBalance: admin.firestore.FieldValue.increment(-committedTotal),
    }, { merge: true });

    const escrowDeliveryType = deliveryType || 'local';
    const autoReleaseDays = escrowDeliveryType === 'regional' ? ESCROW_REGIONAL_DAYS : ESCROW_LOCAL_DAYS;
    const escrowExpiry = new Date(Date.now() + autoReleaseDays * 24 * 60 * 60 * 1000);

    // Create transaction record — money goes to escrow, not straight to seller.
    // Reuse the mirrored order doc (from /api/orders/create) when an orderId is
    // supplied, so a wallet purchase doesn't create a duplicate transaction.
    const txRef = orderId
      ? db.collection('transactions').doc(orderId)
      : db.collection('transactions').doc();
    await txRef.set({
      type: 'purchase',
      buyerId, buyerName: buyerName || '',
      sellerId, sellerName: sellerName || '',
      productId, productName,
      productImage: productImage || '',
      productPrice: price,
      processingFee: 0,
      platformFee: commission,
      sokovibeCommission: commission,
      serviceFeePercent: commissionPercent,
      totalAmount: committedTotal,
      sellerReceives,
      shippingCost: shipping,
      region, district, street,
      ward: ward || '',
      landmarks: landmarks || '',
      deliveryType: escrowDeliveryType,
      autoReleaseDays,
      status: 'escrow_hold',
      paymentMethod: 'Wallet',
      escrowStatus: 'held',
      escrowHeldAt: admin.firestore.FieldValue.serverTimestamp(),
      escrowExpiresAt: admin.firestore.Timestamp.fromDate(escrowExpiry),
      orderId: orderId || '',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    }, orderId ? { merge: true } : undefined);

    // Hold the money in seller's escrow until delivery is confirmed
    await db.collection('users').doc(sellerId).set({
      pendingEscrow: admin.firestore.FieldValue.increment(sellerReceives),
      totalSales: admin.firestore.FieldValue.increment(1),
      grossSalesVolume: admin.firestore.FieldValue.increment(price),
      lastSaleAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    // Record revenue
    await db.collection('revenue_transactions').add({
      userId: sellerId,
      amount: sellerReceives,
      type: 'sale',
      description: `Sale of ${productName}`,
      transactionId: txRef.id,
      productName,
      productPrice: price,
      sokovibeCommission: commission,
      buyerName: buyerName || '',
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });

    // In-app + push notification: buyer's money is safe in escrow
    db.collection('notifications').add({
      userId: buyerId,
      title: 'Malipo Yamekamilika!',
      body: `Malipo ya ${productName} yamepokelewa na kuwekwa escrow salama. Thibitisha upokeaji ili muuzaji apate hela zake.`,
      isRead: false,
      type: 'escrow_confirm',
      transactionId: txRef.id,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    }).catch(() => {});
    sendOneSignalNotification(buyerId,
      'Malipo Yamekamilika!',
      `Malipo ya ${productName} yamepokelewa na kuwekwa escrow salama.`,
      { type: 'order', productId, transactionId: txRef.id }
    ).catch(() => {});

    res.json({ success: true, orderId: txRef.id });
  } catch (e) {
    console.error('/api/wallet/purchase error:', e);
    res.status(500).json({ error: e.message || 'Purchase failed' });
  }
});

/// Get wallet balance for a user
app.get('/api/wallet/balance/:userId', async (req, res) => {
  try {
    if (!db) return res.status(503).json({ error: 'Database not configured' });
    const { userId } = req.params;
    if (!(await isOwnerOrAdmin(req, res, userId))) return;
    const userDoc = await db.collection('users').doc(userId).get();
    if (!userDoc.exists) return res.status(404).json({ error: 'User not found' });
    const balance = userDoc.data().walletBalance || 0;
    res.json({ success: true, balance });
  } catch (e) {
    console.error('/api/wallet/balance error:', e);
    res.status(500).json({ error: e.message });
  }
});

/// Get wallet deposit/transaction history
app.get('/api/wallet/history/:userId', async (req, res) => {
  try {
    if (!db) return res.status(503).json({ error: 'Database not configured' });
    const { userId } = req.params;
    if (!(await isOwnerOrAdmin(req, res, userId))) return;
    const limit = parseInt(req.query.limit) || 50;
    const deposits = await db.collection('deposits')
      .where('userId', '==', userId)
      .orderBy('createdAt', 'desc')
      .limit(limit)
      .get();
    const history = deposits.docs.map(d => ({ id: d.id, ...d.data() }));
    res.json({ success: true, history });
  } catch (e) {
    // Fallback if no index
    try {
      const { userId } = req.params;
      const deposits = await db.collection('deposits')
        .where('userId', '==', userId)
        .limit(50)
        .get();
      const history = deposits.docs.map(d => ({ id: d.id, ...d.data() }));
      res.json({ success: true, history });
    } catch (e2) {
      console.error('/api/wallet/history error:', e2);
      res.json({ success: true, history: [] });
    }
  }
});

app.post('/api/wallet/delete-history', async (req, res) => {
  try {
    const { userId, ids } = req.body;
    if (!userId || !ids || !Array.isArray(ids) || ids.length === 0) {
      return res.status(400).json({ error: 'Missing userId or ids array' });
    }
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const authHeader = req.headers['authorization'];
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({ error: 'Unauthorized' });
    }
    const decoded = await admin.auth().verifyIdToken(authHeader.slice(7));
    if (decoded.uid !== userId) {
      return res.status(403).json({ error: 'User ID mismatch' });
    }

    const batch = db.batch();
    for (const id of ids) {
      const ref = db.collection('deposits').doc(id);
      // Only delete if the document belongs to this user
      const doc = await ref.get();
      if (doc.exists && doc.data().userId === userId) {
        batch.delete(ref);
      }
    }
    await batch.commit();

    res.json({ success: true, deleted: ids.length });
  } catch (e) {
    console.error('/api/wallet/delete-history error:', e);
    res.json({ success: true, deleted: 0 });
  }
});

// ============================================================
// ⏰ AUTO-RELEASE ESCROW — Check and release expired escrows
//     Can be called by a cron job (e.g., GitHub Actions, Render cron)
// ============================================================
// Periodic GC every 5 minutes to keep memory in check (--expose-gc must be enabled)
if (global.gc) {
  setInterval(() => {
    global.gc();
    console.log('[MEM] Garbage collection triggered');
  }, 5 * 60 * 1000);
}

// ============================================================
// 🔧 ORDER ENGINE ROUTES — Order state machine & timeline
// ============================================================

/** Verify Firebase Auth token and return decoded uid or null */
async function verifyAuthToken(req) {
  const authHeader = req.headers.authorization || req.headers['Authorization'] || '';
  const token = authHeader.replace('Bearer ', '');
  if (!token) return null;
  try {
    const decoded = await admin.auth().verifyIdToken(token);
    return decoded;
  } catch { return null; }
}

/// Create a new order (Place Order step)
app.post('/api/orders/create', async (req, res) => {
  try {
    if (!db) return res.status(503).json({ error: 'Database not configured' });
    const decoded = await verifyAuthToken(req);
    if (!decoded) return res.status(401).json({ error: 'Unauthorized' });

    const { buyerId, buyerName, buyerPhone, sellerId, sellerName, productId, productName, productImage, productPrice, shippingCost, deliveryType, region, district, ward, street, landmarks, latitude, longitude, phone, paymentMethod } = req.body;
    if (!buyerId || !sellerId || !productId || !productName || productPrice == null) {
      return res.status(400).json({ error: 'Missing required fields' });
    }
    if (decoded.uid !== buyerId) {
      return res.status(403).json({ error: 'Buyer ID mismatch' });
    }

    const effectivePrice = await resolveEffectivePrice(db, productId, productPrice);
    const platformFee = Math.round(effectivePrice * PLATFORM_COMMISSION_PERCENT);
    const totalAmount = effectivePrice + Math.round(Number(shippingCost) || 0) + platformFee;

    const result = await orderEngine.createOrder(db, {
      buyerId, buyerName: buyerName || '', buyerPhone: buyerPhone || '',
      sellerId, sellerName: sellerName || '',
      productId, productName, productImage: productImage || '',
      productPrice: effectivePrice,
      shippingCost: Math.round(Number(shippingCost) || 0),
      platformFee,
      totalAmount,
      deliveryType: deliveryType || 'local',
      region: region || '', district: district || '', street: street || '',
      ward: ward || '',
      landmarks: landmarks || '',
      latitude: latitude ?? null,
      longitude: longitude ?? null,
      phone: phone || '',
      paymentMethod: paymentMethod || 'ussd_push',
    });

    // Mirror the order into transactions/{orderId} so it appears immediately in
    // the buyer's My Purchases. 'awaiting_shipping_quote' blocks the buyer from
    // paying until the seller sets the shipping cost (the pay button only
    // shows for 'quoted'); the payment-link and webhook updates reuse the same
    // doc via merge.
    try {
      await db.collection('transactions').doc(result.orderId).set({
        type: 'purchase',
        productId, productName, productImage: productImage || '',
        sellerId, sellerName: sellerName || '',
        buyerId, buyerName: buyerName || '', buyerPhone: buyerPhone || '',
        productPrice: effectivePrice,
        shippingCost: Math.round(Number(shippingCost) || 0),
        platformFee,
        totalAmount,
        deliveryType: deliveryType || 'local',
        region: region || '', district: district || '', street: street || '',
        ward: ward || '',
        landmarks: landmarks || '',
        latitude: latitude ?? null,
        longitude: longitude ?? null,
        status: 'awaiting_shipping_quote',
        paymentMethod: paymentMethod || 'ussd_push',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    } catch (e) {
      console.error('order create tx mirror error:', e.message);
    }

    // Notify seller that a new order is pending — push + in-app + SMS so the
    // seller always hears about it even with the app closed. Include the
    // buyer's delivery location so the seller can price shipping immediately.
    try {
      const buyerLocation = [region, district, ward, street].filter(Boolean).join(', ');
      const orderBody = `${buyerName || 'Mnunuzi'} ametuma agizo la ${productName}.${buyerLocation ? ` Eneo: ${buyerLocation}.` : ''} Toa gharama ya usafirishaji sasa.`;
      await db.collection('notifications').add({
        userId: sellerId,
        title: 'Agizo Jipya Limewasilishwa!',
        body: orderBody,
        type: 'order',
        data: { orderId: result.orderId, buyerId, productId },
        isRead: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      await sendOneSignalNotification(sellerId,
        'Agizo Jipya Limewasilishwa!',
        orderBody,
        { type: 'order', orderId: result.orderId, buyerId, productId }
      );
    } catch (e) {
      console.error('order create notify error:', e.message);
    }

    // Confirm to the buyer that their order was received — in-app + push
    try {
      await db.collection('notifications').add({
        userId: buyerId,
        title: 'Agizo Limewasilishwa!',
        body: `Agizo lako la ${productName} limewasilishwa kwa muuzaji. Utapokea taarifa ya gharama ya usafirishaji hivi karibuni.`,
        type: 'order',
        data: { orderId: result.orderId, sellerId, productId },
        isRead: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      await sendOneSignalNotification(buyerId,
        'Agizo Limewasilishwa!',
        `Agizo lako la ${productName} limewasilishwa kwa muuzaji.`,
        { type: 'order', orderId: result.orderId, sellerId, productId }
      );
    } catch (e) {
      console.error('order create buyer notify error:', e.message);
    }

    res.json({ success: true, order: result });
  } catch (e) {
    console.error('/api/orders/create error:', e.message);
    res.status(500).json({ error: e.message || 'Internal server error' });
  }
});

/// Transition an order to a new status
app.post('/api/orders/transition', async (req, res) => {
  try {
    if (!db) return res.status(503).json({ error: 'Database not configured' });
    const decoded = await verifyAuthToken(req);
    if (!decoded) return res.status(401).json({ error: 'Unauthorized' });

    const { orderId, newStatus, note } = req.body;
    if (!orderId || !newStatus) {
      return res.status(400).json({ error: 'Missing orderId or newStatus' });
    }

    const doc = await db.collection('orders').doc(orderId).get();
    if (!doc.exists) return res.status(404).json({ error: 'Order not found' });
    const order = doc.data();

    // Authorization: buyer, seller, or admin
    const isBuyer = order.buyerId === decoded.uid;
    const isSeller = order.sellerId === decoded.uid;
    const userDoc = await db.collection('users').doc(decoded.uid).get();
    const isAdmin = userDoc.exists && userDoc.data().isAdmin === true;
    if (!isBuyer && !isSeller && !isAdmin) {
      return res.status(403).json({ error: 'Not authorized to transition this order' });
    }

    const result = await orderEngine.transitionOrder(db, orderId, newStatus, decoded.uid, { note });

    // Real-time status notifications: buyer on quote, buyer on dispatch
    // Payment confirmations are NOT sent here — the ClickPesa webhook is the
    // single source so the seller/buyer don't get duplicate "payment done" rows.
    try {
      if (newStatus === 'quoted') {
        // Seller set the shipping cost — buyer must pay the updated bill
        let costLabel = '';
        let shippingCost = 0;
        try {
          const parsed = JSON.parse(note || '{}');
          shippingCost = Number(parsed.shippingCost || 0);
          if (shippingCost > 0) costLabel = ` la TZS ${shippingCost.toLocaleString()}`;
        } catch (_) {}
        await db.collection('notifications').add({
          userId: order.buyerId,
          title: 'Gharama ya Usafirishaji Imewekwa!',
          body: `Muuzaji ameweka gharama ya usafirishaji${costLabel}. Lipa sasa ili agizo litumwe.`,
          type: 'payment',
          data: { type: 'order', orderId, sellerId: order.sellerId },
          isRead: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        await sendOneSignalNotification(order.buyerId,
          'Gharama ya Usafirishaji Imewekwa!',
          `Muuzaji ameweka gharama ya usafirishaji${costLabel}. Lipa sasa.`,
          { type: 'order', orderId, sellerId: order.sellerId }
        );
        // Confirm to the seller that their quote was delivered to the buyer
        const sellerConfirmBody = `Quote yako ya usafirishaji ya TZS ${shippingCost.toLocaleString()} imetumwa kwa ${order.buyerName || 'mnunuzi'}.`;
        await db.collection('notifications').add({
          userId: order.sellerId,
          title: 'Quote Imetumwa!',
          body: sellerConfirmBody,
          type: 'order',
          data: { type: 'order', orderId, buyerId: order.buyerId },
          isRead: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        await sendOneSignalNotification(order.sellerId,
          'Quote Imetumwa!',
          sellerConfirmBody,
          { type: 'order', orderId, buyerId: order.buyerId }
        );
      } else if (newStatus === 'dispatched') {
        await db.collection('notifications').add({
          userId: order.buyerId,
          title: 'Agizo Limetumwa!',
          body: `${order.productName || ''} limetumwa — fuatilia usafirishaji kwenye app.`,
          type: 'order',
          data: { type: 'order', orderId, sellerId: order.sellerId },
          isRead: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        await sendOneSignalNotification(order.buyerId,
          'Agizo Limetumwa!',
          `${order.productName || ''} limetumwa — fuatilia usafirishaji kwenye app.`,
          { type: 'order', orderId, sellerId: order.sellerId }
        );
      }
    } catch (e) {
      console.error('order transition notify error:', e.message);
    }

    res.json({ success: true, order: result });
  } catch (e) {
    console.error('/api/orders/transition error:', e.message);
    const status = e.message.startsWith('Cannot transition') ? 400 : 500;
    res.status(status).json({ error: e.message || 'Internal server error' });
  }
});

/// Get order timeline
app.get('/api/orders/:id/timeline', async (req, res) => {
  try {
    if (!db) return res.status(503).json({ error: 'Database not configured' });
    const decoded = await verifyAuthToken(req);
    if (!decoded) return res.status(401).json({ error: 'Unauthorized' });

    const { id } = req.params;
    const doc = await db.collection('orders').doc(id).get();
    if (!doc.exists) return res.status(404).json({ error: 'Order not found' });
    const order = doc.data();

    const isBuyer = order.buyerId === decoded.uid;
    const isSeller = order.sellerId === decoded.uid;
    const userDoc = await db.collection('users').doc(decoded.uid).get();
    const isAdmin = userDoc.exists && userDoc.data().isAdmin === true;
    if (!isBuyer && !isSeller && !isAdmin) {
      return res.status(403).json({ error: 'Not authorized' });
    }

    const snap = await db.collection('orderTimeline')
      .where('orderId', '==', id)
      .orderBy('createdAt', 'asc')
      .get();
    const entries = snap.docs.map(d => ({ id: d.id, ...d.data() }));
    res.json({ success: true, entries });
  } catch (e) {
    console.error('/api/orders/:id/timeline error:', e.message);
    res.status(500).json({ error: e.message || 'Internal server error' });
  }
});

/// Get order current status
app.get('/api/orders/:id/status', async (req, res) => {
  try {
    if (!db) return res.status(503).json({ error: 'Database not configured' });
    const decoded = await verifyAuthToken(req);
    if (!decoded) return res.status(401).json({ error: 'Unauthorized' });

    const { id } = req.params;
    const doc = await db.collection('orders').doc(id).get();
    if (!doc.exists) return res.status(404).json({ error: 'Order not found' });
    const order = doc.data();

    const isBuyer = order.buyerId === decoded.uid;
    const isSeller = order.sellerId === decoded.uid;
    const userDoc = await db.collection('users').doc(decoded.uid).get();
    const isAdmin = userDoc.exists && userDoc.data().isAdmin === true;
    if (!isBuyer && !isSeller && !isAdmin) {
      return res.status(403).json({ error: 'Not authorized' });
    }

    res.json({
      success: true,
      status: order.status,
      stepNumber: orderEngine.getOrderStepNumber(order.status),
      statusColor: orderEngine.STATUS_COLORS[order.status] || '#9E9E9E',
      statusHistory: order.statusHistory || [],
      validTransitions: orderEngine.isValidTransition(order.status, '__') ? [] : [],
    });
  } catch (e) {
    console.error('/api/orders/:id/status error:', e.message);
    res.status(500).json({ error: e.message || 'Internal server error' });
  }
});

/// Get full order details
app.get('/api/orders/:id', async (req, res) => {
  try {
    if (!db) return res.status(503).json({ error: 'Database not configured' });
    const decoded = await verifyAuthToken(req);
    if (!decoded) return res.status(401).json({ error: 'Unauthorized' });

    const { id } = req.params;
    const doc = await db.collection('orders').doc(id).get();
    if (!doc.exists) return res.status(404).json({ error: 'Order not found' });
    const order = doc.data();

    const isBuyer = order.buyerId === decoded.uid;
    const isSeller = order.sellerId === decoded.uid;
    const userDoc = await db.collection('users').doc(decoded.uid).get();
    const isAdmin = userDoc.exists && userDoc.data().isAdmin === true;
    if (!isBuyer && !isSeller && !isAdmin) {
      return res.status(403).json({ error: 'Not authorized' });
    }

    res.json({ success: true, order: { id: doc.id, ...order } });
  } catch (e) {
    console.error('/api/orders/:id error:', e.message);
    res.status(500).json({ error: e.message || 'Internal server error' });
  }
});

/// List orders for a user (as buyer or seller)
app.get('/api/orders/user/:userId', async (req, res) => {
  try {
    if (!db) return res.status(503).json({ error: 'Database not configured' });
    const decoded = await verifyAuthToken(req);
    if (!decoded) return res.status(401).json({ error: 'Unauthorized' });

    const { userId } = req.params;
    if (decoded.uid !== userId) {
      const userDoc = await db.collection('users').doc(decoded.uid).get();
      const isAdmin = userDoc.exists && userDoc.data().isAdmin === true;
      if (!isAdmin) return res.status(403).json({ error: 'Not authorized' });
    }

    const limit = Math.min(parseInt(req.query.limit) || 50, 200);
    const statusFilter = req.query.status || '';

    let snap;
    const role = req.query.role || 'buyer'; // 'buyer' or 'seller'
    if (role === 'seller') {
      let query = db.collection('orders').where('sellerId', '==', userId).orderBy('createdAt', 'desc');
      if (statusFilter) query = query.where('status', '==', statusFilter);
      snap = await query.limit(limit).get();
    } else {
      let query = db.collection('orders').where('buyerId', '==', userId).orderBy('createdAt', 'desc');
      if (statusFilter) query = query.where('status', '==', statusFilter);
      snap = await query.limit(limit).get();
    }

    const orders = snap.docs.map(d => ({ id: d.id, ...d.data() }));
    res.json({ success: true, orders });
  } catch (e) {
    console.error('/api/orders/user/:userId error:', e.message);
    // Fallback without filter if index doesn't exist
    try {
      const { userId } = req.params;
      const role = req.query.role || 'buyer';
      const field = role === 'seller' ? 'sellerId' : 'buyerId';
      const snap = await db.collection('orders').where(field, '==', userId).limit(50).get();
      const orders = snap.docs.map(d => ({ id: d.id, ...d.data() }));
      return res.json({ success: true, orders });
    } catch {
      res.status(500).json({ error: e.message || 'Internal server error' });
    }
  }
});

app.listen(PORT, () => {
  console.log(`Server running on port ${PORT} (PID ${process.pid})`);
  console.log(`[MEM] RSS: ${(process.memoryUsage().rss / 1024 / 1024).toFixed(1)}MB`);
  // Self-ping every 10 minutes to prevent Render free-tier spin-down
  const publicUrl = process.env.RENDER_EXTERNAL_URL || '';
  if (publicUrl) {
    console.log(`[SELF-PING] Auto-ping enabled for ${publicUrl}/ping every 10 minutes`);
    setInterval(async () => {
      try {
        const resp = await axios.get(`${publicUrl}/ping`, { timeout: 10000 });
        if (resp.status === 200) {
          console.log(`[SELF-PING] OK at ${new Date().toISOString()}`);
        }
      } catch (e) {
        // Silently ignore — server may be waking up or URL not yet set
      }
    }, 10 * 60 * 1000);
  } else {
    console.log('[SELF-PING] Disabled — RENDER_EXTERNAL_URL not set');
  }
});

// ============================================================
// 🔍 DIAGNOSTIC — Check legacy FCM token in user doc
app.get('/api/diag/fcm-token/:userId', async (req, res) => {
  try {
    const { userId } = req.params;
    if (!db) return res.status(503).json({ error: 'Database not configured' });
    if (!(await isOwnerOrAdmin(req, res, userId))) return;
    const userDoc = await db.collection('users').doc(userId).get();
    if (!userDoc.exists) return res.status(404).json({ error: 'User not found' });
    const fcmToken = userDoc.data()?.fcmToken || null;
    const email = userDoc.data()?.email || null;
    res.json({
      userId,
      email,
      hasLegacyFcmToken: !!fcmToken,
      tokenPrefix: fcmToken ? fcmToken.substring(0, 12) + '...' : null,
    });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});
