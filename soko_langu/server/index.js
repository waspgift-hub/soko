require('dotenv').config();
const express = require('express');
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
  clickpesaQueryPayouts,
  getUssdPushFee, getPayoutFee, calcGatewayFee, ALL_PAYMENT_METHODS,
} = require('./clickpesa');
const orderEngine = require('./orders');
const searchRouter = require('./search').router;
const notificationRouter = require('./notification').router;

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

const REQUEST_TIMEOUT = 20000; // 20 seconds

// Manual security headers (lightweight replacement for helmet)
app.use((req, res, next) => {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('X-XSS-Protection', '0');
  res.setHeader('Strict-Transport-Security', 'max-age=31536000; includeSubDomains');
  next();
});

// Tight CORS — only allow the Flutter app origins
const ALLOWED_ORIGINS = [
  'https://soko-langu-server.onrender.com',
  'https://soko-langu-server-production.up.railway.app',
  'capacitor://localhost',
  'http://localhost',
  'http://localhost:3000',
  'https://localhost',
];
app.use(cors({
  origin: (origin, cb) => {
    if (!origin || ALLOWED_ORIGINS.some(o => origin.startsWith(o))) return cb(null, true);
    cb(null, true); // Allow all in dev — tighten for production
  },
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization', 'x-admin-secret', 'x-webhook-secret'],
  maxAge: 86400,
}));

app.use(express.json({ limit: '1mb' }));

app.use((req, res, next) => {
  res.setTimeout(REQUEST_TIMEOUT, () => {
    res.status(504).json({ error: 'Request timed out' });
  });
  next();
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
  if (!type) return 'general_notifications_v5';
  if (type === 'chat' || type === 'group_chat') return 'chat_messages_v5';
  if (type === 'system' || type === 'admin' || type === 'alert') return 'system_alerts_v5';
  if (['payment','order','payout','dispute','refund','withdrawal',
       'escrow_release','auto_payout','escrow_auto_release',
       'dispute_resolved','cancelled','auto_withdrawal',
       'delivery_confirmed','payment_failed','kyc','deposit','deposit_failed'].includes(type)) return 'payments_notifications_v5';
  return 'general_notifications_v5';
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

async function sendOneSignalNotification(userId, title, body, data = {}) {
  if (!userId) { console.log('[OS] No userId'); return null; }
  if (!ONE_SIGNAL_APP_ID || !ONE_SIGNAL_REST_API_KEY) {
    console.error('[OS] Missing ONE_SIGNAL_APP_ID or ONE_SIGNAL_REST_API_KEY'); return null;
  }
  const notifType = (data && data.type) || 'general';
  // Server copy is already Swahili, so both language keys carry the same text —
  // sw ensures Swahili-locale devices resolve it explicitly instead of en-only.
  const headings = { en: title || '', sw: title || '' };
  const contents = { en: body || '', sw: body || '' };
  const resp = await postOneSignalWithRetry({
    app_id: ONE_SIGNAL_APP_ID,
    idempotency_key: randomUUID(),
    include_external_user_ids: [userId],
    headings,
    contents,
    data: { ...(data || {}), type: notifType },
    priority: 10, android_priority: 'high', android_visibility: 1,
    existing_android_channel_id: notifTypeToChannel(notifType),
    android_sound: 'soko_notification',
    android_icon: 'ic_notification',
  });
  if (!resp) return null;
  const result = resp.data;
  if (result.id) console.log(`[OS] sent push to ${userId} type=${(data && data.type) || 'general'} id=${result.id}`);
  else console.error(`[OS] push send failed:`, JSON.stringify(result));

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

async function sendOneSignalBulk(userIds, title, body, data = {}) {
  if (!userIds || userIds.length === 0) return { successCount: 0 };
  if (!ONE_SIGNAL_APP_ID || !ONE_SIGNAL_REST_API_KEY) { console.error('[OS] Missing config'); return { successCount: 0 }; }
  const notifType = (data && data.type) || 'general';
  let successCount = 0;
  const batchSize = 2000;
  for (let i = 0; i < userIds.length; i += batchSize) {
    const resp = await postOneSignalWithRetry({
      app_id: ONE_SIGNAL_APP_ID,
      idempotency_key: randomUUID(),
      included_segments: ['Total Subscriptions'],
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
      successCount += result.recipients || userIds.length;
      console.log(`[OS] bulk sent — id=${result.id} recipients=${result.recipients ?? userIds.length}`);
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
const ESCROW_AUTO_RELEASE_DAYS = parseInt(process.env.ESCROW_AUTO_RELEASE_DAYS) || 14;
const ESCROW_LOCAL_DAYS = 3;
const ESCROW_REGIONAL_DAYS = 7;
const MAX_DAILY_SALE_AMOUNT = parseInt(process.env.MAX_DAILY_SALE_AMOUNT) || 5000000;

// ─── (All FCM helpers migrated to OneSignal helpers above) ───



// ─── Rate limiter (in-memory) ───
const rateHits = new Map();
const walletHits = new Map(); // per-wallet rate limit for payments
const RATE_WINDOW = 60 * 1000;
const RATE_MAX = 30;
const PAYMENT_RATE_MAX = 5; // max 5 payment attempts per 60s per IP

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

// Verify webhook secret to prevent forged callbacks
function verifyWebhook(req, res, next) {
  // ClickPesa uses HMAC checksum in the body, not custom HTTP headers.
  // This middleware exists for manual testing; we skip header enforcement
  // because ClickPesa does not send x-webhook-secret.
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

/** Parse flash sale end/start time from Firestore Timestamp, ISO string, seconds, or legacy field names. */
function parseFlashSaleEndTime(data) {
  const raw = data?.endTime ?? data?.muda_wa_kuisha ?? data?.end_time;
  if (!raw) return null;
  if (raw.toDate && typeof raw.toDate === 'function') return raw.toDate();
  if (raw._seconds != null) return new Date(raw._seconds * 1000);
  if (raw.seconds != null) return new Date(raw.seconds * 1000);
  if (typeof raw === 'number') {
    // Treat values < 1e12 as seconds since epoch.
    return new Date(raw < 1e12 ? raw * 1000 : raw);
  }
  const parsed = new Date(raw);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function isFlashSaleStillActive(data, now = new Date()) {
  const end = parseFlashSaleEndTime(data);
  if (!end) return false;
  return end > now;
}

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

// ============================================================
// ⭐ BOOST PRODUCT — TIER-BASED FEATURED LISTING
// ============================================================
const BOOST_TIERS = {
  bronze: { price: 1500, days: 3 },
  silver: { price: 3000, days: 7 },
  gold: { price: 10000, days: 30 },
};

const PLATFORM_COMMISSION_PERCENT = 0.035; // 3.5% platform commission
const MIN_WITHDRAWAL = 5000;          // Minimum withdrawal TZS 5,000

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
    try { await admin.auth().verifyIdToken(token); } catch (_) { return res.status(403).json({ error: 'Invalid token' }); }

    const { productId, tier, amount, durationDays, phone, userId, productName, productImage, productPrice, paymentMethod } = req.body;

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

    // Gateway fee added on top so Soko Vibe receives the full tier price
    const gatewayFee = calcGatewayFee(paymentMethod || 'ussd_push', tierConfig.price);
    const totalToCollect = tierConfig.price + gatewayFee;

    const order_id = `boost${Date.now()}`;
    const isBillPay = (paymentMethod || 'ussd_push') === 'billpay';

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
        message: `Jumla TZS ${totalToCollect.toLocaleString()} (Boost TZS ${tierConfig.price.toLocaleString()} + Ada TZS ${gatewayFee.toLocaleString()}). Tuma PIN yako kwenye simu.`,
      });
    }
  } catch (e) {
    console.error('/api/boost-product error:', e?.message || e);
    const msg = e?.message?.includes('ClickPesa') ? e.message : 'Internal server error';
    res.status(500).json({ error: msg });
  }
});

// ============================================================
// 📱 SMS — SEND VIA MESEJI
// ============================================================
app.post('/api/sms/send', async (req, res) => {
  try {
    const { phone, message } = req.body;
    if (!phone || !message) {
      return res.status(400).json({ error: 'Missing phone or message' });
    }
    const apiKey = process.env.MESEJI_API_KEY;
    if (!apiKey) {
      console.error('/api/sms/send: MESEJI_API_KEY not configured');
      return res.status(500).json({ error: 'SMS not configured' });
    }
    const digits = phone.replace(/\D/g, '');
    // Meseji only accepts local-format numbers (07XXXXXXXX) inside a contacts
    // ARRAY — string or +255 format both come back HTTP 500 from the provider.
    const local = digits.startsWith('255') ? '0' + digits.slice(3) : !digits.startsWith('0') ? '0' + digits : digits;
    const configured = process.env.MESEJI_SENDER_ID || 'MESEJI';
    const senders = configured === 'MESEJI' ? ['MESEJI'] : [configured, 'MESEJI'];
    for (const sender of senders) {
      try {
        const resp = await axios.post('https://meseji.co.tz/api/v1/sms/send', {
          sender_id: sender,
          message,
          contacts: [local],
        }, {
          headers: { 'x-api-key': apiKey, 'Content-Type': 'application/json' },
          timeout: 15000,
        });
        console.log(`/api/sms/send: ok sender=${sender} to ${local} batch=${resp.data?.batch_id || ''}`);
        return res.json({ sent: true, sender, batchId: resp.data?.batch_id || null });
      } catch (e) {
        const errBody = e.response?.data ? JSON.stringify(e.response.data) : e.message;
        console.error(`/api/sms/send: sender ${sender} error: ${errBody}`);
      }
    }
    return res.status(502).json({ error: 'SMS provider error' });
  } catch (e) {
    console.error('/api/sms/send error:', e.message);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── SMS helper (reuses Meseji API from /api/sms/send) ───
async function sendSms(phone, message) {
  try {
    const apiKey = process.env.MESEJI_API_KEY;
    if (!apiKey) { console.error('sendSms: MESEJI_API_KEY not configured'); return false; }
    const digits = phone.replace(/\D/g, '');
    // Meseji only accepts local-format numbers (07XXXXXXXX) inside a contacts
    // ARRAY — string or +255 format both come back HTTP 500 from the provider.
    const local = digits.startsWith('255') ? '0' + digits.slice(3) : !digits.startsWith('0') ? '0' + digits : digits;
    const configured = process.env.MESEJI_SENDER_ID || 'MESEJI';
    const senders = configured === 'MESEJI' ? ['MESEJI'] : [configured, 'MESEJI'];
    for (const sender of senders) {
      try {
        const resp = await axios.post('https://meseji.co.tz/api/v1/sms/send', {
          sender_id: sender,
          message,
          contacts: [local],
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
    return false;
  } catch (e) {
    console.error('sendSms error:', e.message);
    return false;
  }
}

// ─── Boost payment failure — SMS + OneSignal push + in-app notification ───
async function notifyBoostPaymentFailed(tx, reason = '') {
  try {
    if (!tx || !tx.userId) return;
    const title = 'Malipo ya Boost Yameshindikana';
    const reasonText = reason ? `. Sababu: ${reason}` : '';
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
    const phone = userSnap.data()?.phone;
    if (phone) {
      const amount = tx.totalAmount || tx.amount || 0;
      const msg = `Soko Vibe: Malipo ya Boost ya TZS ${amount.toLocaleString()} hayakukamilika${reasonText}. Jaribu tena kwenye app.`;
      await sendSms(phone, msg);
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

function otpPhoneRateLimit(req, res, next) {
  const phone = (req.body?.phone || '').replace(/\D/g, '');
  if (!phone) return next();
  const now = Date.now();
  if (!otpPhoneHits.has(phone)) otpPhoneHits.set(phone, []);
  const hits = otpPhoneHits.get(phone).filter(t => now - t < OTP_PHONE_WINDOW);
  hits.push(now);
  otpPhoneHits.set(phone, hits);
  if (hits.length > OTP_PHONE_MAX) {
    return res.status(429).json({ error: 'Umejaribu mara nyingi. Subiri dakika 15.' });
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
    const sent = await sendSms(cleanPhone, message);

    // Save send status to the same OTP document for debugging
    await db.collection('otp_codes').doc(cleanPhone).update({
      smsSent: sent,
      smsAttemptedAt: admin.firestore.FieldValue.serverTimestamp(),
    }).catch(() => {});

    if (!sent) {
      console.error('/api/auth/send-otp: sendSms returned false for', cleanPhone);
      return res.status(502).json({ error: 'Imeshindwa kutuma OTP. Jaribu tena.' });
    }

    res.json({ sent: true, message: 'OTP imetumwa kwa simu yako' });
  } catch (e) {
    console.error('/api/auth/send-otp error:', e.message);
    res.status(500).json({ error: 'Imeshindwa kutuma OTP. Jaribu tena.' });
  }
});

// ============================================================
// 🔐 PHONE OTP — VERIFY
// ============================================================
app.post('/api/auth/verify-otp', async (req, res) => {
  try {
    const { phone, otp } = req.body;
    if (!phone || !otp) return res.status(400).json({ error: 'Phone and OTP are required' });
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const cleanPhone = phone.replace(/\D/g, '');
    const doc = await db.collection('otp_codes').doc(cleanPhone).get();
    if (!doc.exists) return res.status(400).json({ error: 'Hakuna OTP. Tuma mpya.' });

    const data = doc.data();
    if (data.used) return res.status(400).json({ error: 'OTP tayari imetumika' });
    if (Date.now() > data.expiresAt) return res.status(400).json({ error: 'OTP imeisha muda. Tuma mpya.' });

    const hashed = crypto.createHash('sha256').update(otp).digest('hex');
    if (hashed !== data.otpHash) return res.status(400).json({ error: 'OTP si sahihi' });

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
    const { email } = req.body;
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

    // SMTP directly to the address (unlike sendEmailSmtp, the email may
    // not be a registered Firebase user yet at this stage)
    const subject = 'Soko Vibe — OTP yako';
    const html = `<html><body style="font-family:Arial,sans-serif;padding:20px;max-width:600px;margin:0 auto"><h2 style="color:#40916C">Soko Vibe — Uthibitisho wa Barua Pepe</h2><p>OTP yako ni:</p><p style="font-size:32px;font-weight:bold;letter-spacing:8px;color:#40916C">${otp}</p><p>Inaisha kwa dakika 10. Usimshiriki mtu yeyote.</p><hr style="border:none;border-top:1px solid #e0e0e0;margin:20px 0"/><p style="color:#999;font-size:12px">Soko Vibe</p></body></html>`;

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
      return res.status(502).json({ error: 'Imeshindwa kutuma OTP kwa barua pepe. Jaribu tena.' });
    }

    res.json({ sent: true, message: 'OTP imetumwa kwa barua pepe yako' });
  } catch (e) {
    console.error('/api/auth/send-email-otp error:', e.message);
    res.status(500).json({ error: 'Imeshindwa kutuma OTP. Jaribu tena.' });
  }
});

// ============================================================
// 🔐 EMAIL OTP — VERIFY
// ============================================================
app.post('/api/auth/verify-email-otp', async (req, res) => {
  try {
    const { email, otp } = req.body;
    if (!email || !otp) return res.status(400).json({ error: 'Email and OTP are required' });
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const cleanEmail = email.trim().toLowerCase();
    const doc = await db.collection('otp_codes').doc(cleanEmail).get();
    if (!doc.exists) return res.status(400).json({ error: 'Hakuna OTP. Tuma mpya.' });

    const data = doc.data();
    if (data.used) return res.status(400).json({ error: 'OTP tayari imetumika' });
    if (Date.now() > data.expiresAt) return res.status(400).json({ error: 'OTP imeisha muda. Tuma mpya.' });

    const hashed = crypto.createHash('sha256').update(otp).digest('hex');
    if (hashed !== data.otpHash) return res.status(400).json({ error: 'OTP si sahihi' });

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
app.post('/api/auth/reset-password-by-phone', async (req, res) => {
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
    if (!otpDoc.exists) return res.status(400).json({ error: 'Hakuna OTP. Tuma mpya.' });

    const otpData = otpDoc.data();
    if (otpData.used) return res.status(400).json({ error: 'OTP tayari imetumika' });
    if (Date.now() > otpData.expiresAt) return res.status(400).json({ error: 'OTP imeisha muda. Tuma mpya.' });

    const hashed = crypto.createHash('sha256').update(otp).digest('hex');
    if (hashed !== otpData.otpHash) return res.status(400).json({ error: 'OTP si sahihi' });

    await otpDoc.ref.update({ used: true });

    // Look up user by phone
    const usersSnap = await db.collection('users')
      .where('phone', 'in', [cleanPhone, `0${cleanPhone.slice(-9)}`, `+${cleanPhone}`])
      .limit(1)
      .get();

    if (usersSnap.empty) {
      return res.status(404).json({ error: 'Hakuna akaunti yenye namba hii.' });
    }

    const uid = usersSnap.docs[0].id;

    // Update Firebase Auth password
    try {
      await admin.auth().updateUser(uid, { password: newPassword });
    } catch (authErr) {
      return res.status(500).json({ error: 'Imeshindwa kubadilisha nenosiri. Jaribu tena.' });
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
    if (!otpDoc.exists) return res.status(400).json({ error: 'Hakuna OTP. Tuma mpya.' });

    const otpData = otpDoc.data();
    if (otpData.used) return res.status(400).json({ error: 'OTP tayari imetumika' });
    if (Date.now() > otpData.expiresAt) return res.status(400).json({ error: 'OTP imeisha muda. Tuma mpya.' });

    const hashed = crypto.createHash('sha256').update(otp).digest('hex');
    if (hashed !== otpData.otpHash) return res.status(400).json({ error: 'OTP si sahihi' });

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
// 🔧 SETUP — Create admin account (one-time)
// ============================================================
app.post('/api/setup-admin', async (req, res) => {
  try {
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
    const users = snap.docs.map(doc => ({ uid: doc.id, ...doc.data() }));
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
    const { orderId, userId, trackingNumber, receiptUrl, photoUrl, note } = req.body;
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
      trackingNumber: trackingNumber || '',
      receiptUrl: receiptUrl || '',
      photoUrl: photoUrl || '',
      note: note || '',
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

    // SMS buyer about dispatch
    try {
      const busName = req.body.busName || 'basi';
      const plateNumber = req.body.plateNumber || '';
      const msg = `Soko Vibe: Mzigo wa Oda #${orderId} umesafirishwa kupitia basi la ${busName} (${plateNumber}). Fungua app kuona risiti yako ya kidijitali.`;
      if (tx.buyerPhone) sendSms(tx.buyerPhone, msg);
    } catch (_) {}

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
// 🔒 ESCROW — Release payment to seller (buyer confirms delivery)
//     Requires status to be 'dispatched' first
// ============================================================
app.post('/api/escrow/release', async (req, res) => {
  try {
    const { orderId, userId } = req.body;
    if (!orderId || !userId) {
      return res.status(400).json({ error: 'Missing orderId or userId' });
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
        sendSms(sellerPhone, sellerMsg);
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
app.post('/api/clickpesa/webhook', verifyWebhook, async (req, res) => {
  try {
    let payload = req.body;
    if (payload.data && typeof payload.data === 'object') {
      payload = payload.data;
    }

    const orderId = payload.orderReference || payload.order_id || payload.externalId || '';
    const rawStatus = (payload.status || payload.paymentStatus || payload.event || '').toString().toLowerCase();
    const paymentStatus = rawStatus === 'completed' || rawStatus === 'payment_received' || rawStatus === 'payment_completed' || rawStatus === 'success'
      ? 'success'
      : rawStatus === 'failed' || rawStatus === 'cancelled' || rawStatus === 'expired'
        ? 'failed'
        : rawStatus;

    if (!orderId || !paymentStatus) {
      return res.status(200).json({ received: true });
    }

    if (!db) return res.status(200).json({ received: true });

    // Check if this is a deposit (wallet top-up)
    const depDoc = orderId.startsWith('dep')
      ? await db.collection('deposits').doc(orderId).get()
      : null;

    if (depDoc?.exists) {
      const dep = depDoc.data();
      if (dep.status === 'completed') {
        return res.status(200).json({ received: true });
      }
      if (paymentStatus === 'success') {
        const amount = dep.amount || 0;
        await db.collection('users').doc(dep.userId).update({
          walletBalance: admin.firestore.FieldValue.increment(amount),
        });
        await depDoc.ref.update({
          status: 'completed',
          clickpesaReference: payload.id || '',
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
        await depDoc.ref.update({
          status: 'failed',
          failureReason: payload.message || 'Payment failed',
          completedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        sendOneSignalNotification(dep.userId, 'Deposit Imeshindikana', `Malipo ya TZS ${failAmount.toLocaleString()} hayakukamilika.`, { type: 'deposit_failed', depositRef: orderId }).catch(() => {});
      }
      return res.status(200).json({ received: true });
    }

    const txDoc = await db.collection('transactions').doc(orderId).get();
    if (!txDoc.exists) {
      console.warn(`ClickPesa webhook: transaction ${orderId} not found`);
      return res.status(200).json({ received: false });
    }

    const tx = txDoc.data();

    // Prevent double-processing — skip if already finalized
    if (tx.status === 'completed' || tx.status === 'escrow_hold' || tx.status === 'failed') {
      return res.status(200).json({ received: true });
    }

    const clickpesaRef = payload.id || payload.transactionId || payload.reference || tx.clickpesaReference || '';

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
            sendSms(sellerPhone, msg);
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
          if (tx.buyerPhone) sendSms(tx.buyerPhone, buyerMsg);
        } catch (_) {}
        try {
          if (tx.sellerId) {
            const sellerSnap = await db.collection('users').doc(tx.sellerId).get();
            const sellerPhone = sellerSnap.data()?.phone;
            if (sellerPhone) {
              const sellerMsg = `Soko Vibe: Oda #${orderId} imelipiwa! Fedha ipo salama Escrow. Tafadhali kamilisha usafirishaji stendi na ujaze risiti ya basi kwenye app.`;
              sendSms(sellerPhone, sellerMsg);
            }
          }
        } catch (_) {}
      }
    } else if (paymentStatus === 'failed') {
      await txDoc.ref.update({
        status: 'failed',
        clickpesaReference: clickpesaRef,
        failureReason: payload.message || payload.error || 'payment failed',
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // Boost failure — SMS + push + in-app to the boost user (buyerId === userId)
      if (tx.type === 'boost') {
        await notifyBoostPaymentFailed(tx, payload.message || payload.error || 'payment failed');
      } else if (tx.buyerId) {
        await db.collection('notifications').add({
          userId: tx.buyerId,
          title: 'Malipo Yameshindikana',
          body: `Malipo ya ${tx.productName || 'Bidhaa'} hayakukamilika. Jaribu tena au wasiliana nasi. Sababu: ${payload.message || payload.error || 'payment failed'}`,
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
          const buyerPhone = buyerSnap.data()?.phone;
          if (buyerPhone) {
            sendSms(buyerPhone, `Soko Vibe: Malipo ya ${tx.productName || 'Bidhaa'} hayakukamilika. Tafadhali jaribu tena kwenye app.`).catch(() => {});
          }
        } catch (_) {}
      }
    }

    res.status(200).json({ received: true });
  } catch (e) {
    console.error('ClickPesa webhook error:', e);
    res.status(200).json({ received: true });
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
    const { orderId, userId } = req.body;
    if (!orderId || !userId) {
      return res.status(400).json({ error: 'Missing orderId or userId' });
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
    const { orderId, userId, reason, evidenceUrls } = req.body;
    if (!orderId || !userId) {
      return res.status(400).json({ error: 'Missing orderId or userId' });
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
        const sellerPenalty = Math.min(gatewayFee, sellerReceives);
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

    // Verify admin
    const authHeader = req.headers.authorization || '';
    const token = authHeader.replace('Bearer ', '');
    if (true) {
      const decoded = await admin.auth().verifyIdToken(token);
      const userDoc = await db.collection('users').doc(decoded.uid).get();
      if (!userDoc.exists || !userDoc.data().isAdmin) {
        return res.status(403).json({ error: 'Admin only' });
      }
    } else {
      const secret = req.headers['x-admin-secret'];
      if (secret !== process.env.ADMIN_SECRET) {
        return res.status(401).json({ error: 'Unauthorized' });
      }
    }

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
    await db.collection('users').doc(sellerId).update({
      sellerBalance: admin.firestore.FieldValue.increment(-sellerReceives),
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
    const { userId } = req.params;
    if (!db) return res.status(503).json({ error: 'Database not configured' });

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
      .orderBy('kyc.submittedAt', 'desc')
      .limit(100)
      .get();

    const all = snap.docs.map(doc => ({
      uid: doc.id,
      displayName: doc.data().displayName || '',
      email: doc.data().email || '',
      phone: doc.data().phone || '',
      kyc: doc.data().kyc || {},
    }));

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

    // Send push via OneSignal to all users
    const pushResult = await sendOneSignalBulk(userIds, title, body || '', {
      type: 'system',
      broadcast: 'true',
    });

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

    await sendOneSignalNotification(userId, title, body || '', { type: notifType });

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
    try { await admin.auth().verifyIdToken(token); } catch (_) { return res.status(403).json({ error: 'Invalid token' }); }

    const { productPrice, productName, productId, sellerId, sellerName, email, phone, buyerId, deliveryType, shippingCost, existingTransactionId, paymentMethod } = req.body;
    if (!productPrice || !productId || !sellerId || !phone) {
      return res.status(400).json({ error: 'Missing required fields' });
    }

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

      const withinLimit = await checkDailyLimit(buyerId, productPrice);
      if (!withinLimit) return res.status(400).json({ error: `Daily purchase limit of TZS ${MAX_DAILY_SALE_AMOUNT.toLocaleString()} exceeded` });
    }

    // Use existing transaction ID if provided, otherwise generate new one
    const order_id = existingTransactionId || `p${Date.now().toString(36)}${buyerId ? buyerId.substring(0, 4) : 'x'}`;

    const isBillPay = (paymentMethod || 'ussd_push') === 'billpay';

    // Include shipping + platform commission + gateway fee in total sent to ClickPesa
    const commission = Math.round(Math.round(productPrice) * PLATFORM_COMMISSION_PERCENT);
    const gatewayFee = isBillPay ? calcGatewayFee('billpay', productPrice) : getUssdPushFee(productPrice);
    const totalAmount = Math.round(productPrice) + Math.round(shippingCost || 0) + commission + gatewayFee;

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
          productPrice: Math.round(productPrice),
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
        productPrice: Math.round(productPrice), shippingCost: Math.round(shippingCost || 0),
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
        message: 'Tuma PIN yako kwenye simu ili kukamilisha malipo.',
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
// 🔔 LEGACY WEBHOOK — Handle payment completion (legacy)
// ============================================================
app.post('/api/webhook', verifyWebhook, async (req, res) => {
  try {
    const { order_id, status, amount, buyer_phone } = req.body;
    const paymentStatus = status || (req.body.payment_status || '').toLowerCase() || '';
    if (!order_id || !paymentStatus) {
      return res.status(200).json({ received: false });
    }

    if (!db) return res.status(200).json({ received: false });

    const txDoc = await db.collection('transactions').doc(order_id).get();
    if (!txDoc.exists) return res.status(200).json({ received: false });

    const tx = txDoc.data();

    if (paymentStatus === 'success' || paymentStatus === 'completed') {

      if (tx.type === 'boost') {
        // Handle boost payment success — update product FIRST before marking tx completed
        const tier = tx.tier || 'bronze';
        const tierConfig = BOOST_TIERS[tier] || BOOST_TIERS.bronze;
        const now = new Date();
        const boostedUntil = new Date(now.getTime() + tierConfig.days * 24 * 60 * 60 * 1000);

        try {
          await db.collection('products').doc(tx.productId).update({
            isBoosted: true,
            boostedUntil: admin.firestore.Timestamp.fromDate(boostedUntil),
            boostTier: tier,
            isFeatured: true,
            featuredUntil: admin.firestore.Timestamp.fromDate(boostedUntil),
          });
        } catch (productErr) {
          console.error(`Failed to boost product ${tx.productId}:`, productErr);
          await txDoc.ref.update({ status: 'failed', failureReason: `Product update failed: ${productErr.message}` });
          return res.status(200).json({ received: true });
        }

        // Product updated successfully — now mark transaction completed
        await txDoc.ref.update({ status: 'completed' });

        // Send notification + push
        if (tx.userId) {
          await db.collection('notifications').add({
            userId: tx.userId,
            title: '✅ Boost imewashwa!',
            body: `Bidhaa yako imepandishwa kwa daraja la ${tier} kwa siku ${tierConfig.days}.`,
            data: { type: 'boost', productId: tx.productId },
            isRead: false,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          try {
            await sendOneSignalNotification(tx.userId, '✅ Boost imewashwa!', `Bidhaa yako imepandishwa kwa daraja la ${tier} kwa siku ${tierConfig.days}.`, { type: 'boost', productId: tx.productId || '' });
          } catch (_) {}
        }

        // Notify all users about this boost
        notifyBoostBroadcast(tx.productId, tier, tx.userId).catch(() => {});

        // Record boost payment as admin revenue
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

        // Also set totalAmount on the transaction for ClickPesa tracking
        await txDoc.ref.update({
          totalAmount: boostAmount,
          completedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      } else {
        // Non-boost: mark as completed (purchase handler overwrites to escrow_hold)
        await txDoc.ref.update({ status: 'completed' });
      }

      if (tx.type === 'purchase') {
        const productPrice = tx.productPrice || 0;
        const platformFee = Math.round(productPrice * PLATFORM_COMMISSION_PERCENT);
        const payoutFee = DEFAULT_PAYOUT_FEE;
        const processingFee = tx.processingFee || tx.clickpesaFee || 0;
        // Seller is reimbursed the shipping cost from escrow on delivery
        const sellerReceives = productPrice + Math.round(tx.shippingCost || 0);
        const deliveryType = tx.deliveryType || 'local';
        const autoReleaseDays = tx.autoReleaseDays || (deliveryType === 'regional' ? ESCROW_REGIONAL_DAYS : ESCROW_LOCAL_DAYS);
        const escrowExpiry = new Date(Date.now() + autoReleaseDays * 24 * 60 * 60 * 1000);

        // Update transaction — put in escrow instead of auto-paying
        await txDoc.ref.update({
          processingFee,
          platformFee,
          payoutFee,
          sokoLanguCommission: platformFee,
          totalAmount: tx.totalAmount || (productPrice + Math.round(tx.shippingCost || 0) + platformFee + processingFee),
          sellerReceives,
          status: 'escrow_hold',
          paymentMethod: 'ClickPesa',
          transactionReference: order_id,
          buyerId: tx.buyerId || '',
          buyerName: tx.buyerName || '',
          escrowStatus: 'held',
          escrowHeldAt: admin.firestore.FieldValue.serverTimestamp(),
          escrowExpiresAt: admin.firestore.Timestamp.fromDate(escrowExpiry),
        });

        // Record platform commission immediately
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
          paymentMethod: 'ClickPesa',
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
        });

        // Decrement flash sale stock only for a non-expired active flash sale
        try {
          const fsSnap = await db.collection('flash_sales')
            .where('productId', '==', tx.productId)
            .where('isActive', '==', true)
            .limit(5)
            .get();
          const payNow = new Date();
          const activeDoc = fsSnap.docs.find(d => isFlashSaleStillActive(d.data(), payNow));
          if (activeDoc) {
            const fsData = activeDoc.data();
            const newStock = (fsData.stock || 0) - 1;
            const newSold = (fsData.soldCount || 0) + 1;
            await activeDoc.ref.update({
              stock: Math.max(0, newStock),
              soldCount: newSold,
              isActive: newStock > 0,
            });
          }
        } catch (_) {}

        // Credit seller's pendingEscrow (not available for withdrawal until released)
        if (sellerReceives > 0 && tx.sellerId) {
          await db.collection('users').doc(tx.sellerId).set({
            pendingEscrow: admin.firestore.FieldValue.increment(sellerReceives),
            totalSales: admin.firestore.FieldValue.increment(1),
            grossSalesVolume: admin.firestore.FieldValue.increment(productPrice),
            lastSaleAt: admin.firestore.FieldValue.serverTimestamp(),
          }, { merge: true });

          // Notify seller — payment received, held in escrow
          await db.collection('notifications').add({
            userId: tx.sellerId,
            title: 'Umepata Mauzo!',
            body: `${tx.productName || 'Bidhaa'} imeuzwa. TZS ${sellerReceives.toLocaleString()} imewekwa escrow. Mnunuzi atathibitisha upokeaji ili pesa zifunguliwe.`,
            isRead: false,
            type: 'sale',
            transactionId: order_id,
            buyerPhone: tx.buyerPhone || '',
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          try {
            await sendOneSignalNotification(tx.sellerId, 'Umepata Mauzo!', `${tx.productName || 'Bidhaa'} imeuzwa. TZS ${sellerReceives.toLocaleString()} imewekwa escrow.`, { type: 'order', productId: tx.productId || '', transactionId: order_id, buyerPhone: tx.buyerPhone || '' });
          } catch (_) {}
        }

        // Notify buyer to confirm delivery
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
          try {
            await sendOneSignalNotification(tx.buyerId, 'Malipo Yamekamilika!', `Malipo ya ${tx.productName || 'Bidhaa'} yamepokelewa.`, { type: 'order', productId: tx.productId || '', transactionId: order_id });
          } catch (_) {}
        }
      }
    } else if (paymentStatus === 'failed' || paymentStatus === 'cancelled') {
      await txDoc.ref.update({ status: 'failed', failureReason: 'Payment failed via webhook' });
      if (tx.type === 'boost') {
        await notifyBoostPaymentFailed(tx, 'payment failed via webhook');
      } else if (tx.buyerId) {
        await db.collection('notifications').add({
          userId: tx.buyerId,
          title: 'Malipo Yameshindikana',
          body: `Malipo ya ${tx.productName || 'Bidhaa'} hayakukamilika. Jaribu tena kwenye app.`,
          isRead: false,
          type: 'payment_failed',
          transactionId: order_id,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        try {
          await sendOneSignalNotification(tx.buyerId, 'Malipo Yameshindikana', `Malipo ya ${tx.productName || 'Bidhaa'} hayakukamilika. Jaribu tena kwenye app.`, { type: 'payment_failed', productId: tx.productId || '', transactionId: order_id });
        } catch (_) {}
      }
    }

    res.status(200).json({ received: true });
  } catch (e) {
    console.error('Webhook error:', e);
    res.status(200).json({ received: true });
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
    const { userId, amount, phone } = req.body;
    if (!userId || !amount || !phone) {
      return res.status(400).json({ error: 'Missing userId, amount, or phone' });
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

    const admobSnap = await db.collection('admob_earnings').orderBy('month', 'desc').limit(1).get();
    let actualAdRevenue = 0;
    if (!admobSnap.empty) {
      actualAdRevenue = admobSnap.docs[0].data().amount || 0;
    }

    const revSnap = await db.collection('revenue_transactions').get();
    let totalCommissions = 0;
    revSnap.docs.forEach(doc => {
      totalCommissions += (doc.data().sokoLanguCommission || 0);
    });
    const totalAdminBalance = actualAdRevenue + totalCommissions;

    const withdrawnSnap = await db.collection('admin_withdrawals')
      .where('userId', '==', userId)
      .get();
    let totalWithdrawn = 0;
    withdrawnSnap.docs.forEach(doc => {
      const d = doc.data();
      if (d.status === 'completed') totalWithdrawn += d.amount || 0;
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
    const authHeader = req.headers.authorization || '';
    const token = authHeader.replace('Bearer ', '');
    if (!token) return res.status(401).json({ error: 'Unauthorized' });
    const decoded = await admin.auth().verifyIdToken(token).catch(() => null);
    if (!decoded) return res.status(403).json({ error: 'Invalid token' });

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
    const completedStatuses = new Set(['completed', 'delivered', 'delivery_confirmed']);
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
    const completedStatuses = new Set(['completed', 'delivered', 'delivery_confirmed']);
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

      if (completedStatuses.has(status)) {
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

    const paidStatuses = new Set(['completed', 'delivered', 'delivery_confirmed']);
    const entries = [];
    let runningBalance = 0;

    for (const doc of txDocs) {
      const d = doc.data();
      const status = d.status || '';
      const createdAt = d.createdAt ? (d.createdAt.toDate ? d.createdAt.toDate() : new Date(d.createdAt)) : null;
      const amount = d.totalAmount || 0;
      const commission = d.platformCommission || 0;
      const buyerName = d.buyerName || d.buyerPhone || 'Mnunuzi';
      const productName = d.productName || 'Bidhaa';

      if (paidStatuses.has(status)) {
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

    // 1. Estimated ad revenue (each ad view = 15 TZS)
    const adSnap = await db.collection('ad_views').count().get();
    const estimatedAdRevenue = (adSnap.data().count || 0) * 15;

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
    const paidStatuses = new Set(['completed', 'delivered', 'delivery_confirmed']);
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

    const availableBalance = totalAdminBalance - totalAdminPaidOut;

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
    const [userDoc, ordersSnap, withdrawalsSnap, txSnap] = await Promise.all([
      db.collection('users').doc(uid).get(),
      db.collection('orders').where('sellerId', '==', uid).orderBy('createdAt', 'desc').limit(50).get(),
      db.collection('withdrawals').where('userId', '==', uid).orderBy('createdAt', 'desc').limit(50).get(),
      db.collection('revenue_transactions').where('userId', '==', uid).orderBy('timestamp', 'desc').limit(50).get(),
    ]);

    if (!userDoc.exists) return res.status(404).json({ error: 'User not found' });

    res.json({
      user: { uid, ...userDoc.data() },
      orders: ordersSnap.docs.map(d => ({ id: d.id, ...d.data() })),
      withdrawals: withdrawalsSnap.docs.map(d => ({ id: d.id, ...d.data() })),
      revenueTransactions: txSnap.docs.map(d => ({ id: d.id, ...d.data() })),
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

    await db.collection('users').doc(uid).update(updates);
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
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const { productName, salePrice, discountPercent, sellerId, productImage } = req.body;

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
        const userIds = [];
        let lastPushId = null;
        while (true) {
          let query = db.collection('users');
          if (lastPushId) query = query.startAfter(lastPushId);
          query = query.limit(PAGE_SIZE);
          const usersSnap = await query.get();
          if (usersSnap.empty) break;
          for (const doc of usersSnap.docs) {
            if (doc.id) userIds.push(doc.id);
          }
          lastPushId = usersSnap.docs[usersSnap.docs.length - 1].id;
        }
        const osResult = await sendOneSignalBulk(userIds, `⚡ Flash Sale! -${discountPercent}%`, `${productName} sasa TSh ${salePrice} pekee!`, { type: 'flash_sale', productName: productName || '', image: productImage || '' });
        sentCount = osResult.successCount;
        await cooldownRef.set({ lastSentAt: admin.firestore.Timestamp.now() }, { merge: true });
        console.log(`[flash-sale] bulk push sent (sentCount=${sentCount})`);
      } catch (pushErr) {
        console.error('OneSignal push skipped for flash sale:', pushErr.message);
      }
    } else {
      console.log(`[flash-sale] push skipped — cooldown active (last sent ${lastSentAt.toISOString()})`);
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
    const { productId, tier, sellerId } = req.body;
    if (!productId || !tier) {
      return res.status(400).json({ error: 'Missing productId or tier' });
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

// Run every hour as fallback (cron-job.org can also call the endpoint)
setInterval(releaseExpiredEscrows, 60 * 60 * 1000);
setInterval(deactivateExpiredFlashSales, 60 * 60 * 1000);
setInterval(failStalePendingBoosts, 5 * 60 * 1000);
// Also run once on startup
setTimeout(releaseExpiredEscrows, 60 * 1000);
setTimeout(deactivateExpiredFlashSales, 60 * 1000);
setTimeout(failStalePendingBoosts, 60 * 1000);

// ============================================================
// 💰 CLICKPESA BALANCE — Check ClickPesa wallet balance
// ============================================================
app.get('/api/clickpesa/balance', async (req, res) => {
  try {
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

  const price = Number(productPrice);
  const processingFee = getUssdPushFee(price);
  const platformFee = price * 0.03;
  const totalAmount = price + processingFee + platformFee;
  const sellerReceives = price - platformFee;

  const txRef = await db.collection('transactions').doc();
  await txRef.set({
    buyerId, buyerName: buyerName || '', buyerPhone: buyerPhone || '',
    sellerId, sellerName: sellerName || '',
    productId, productName,
    productPrice: price, processingFee, platformFee,
    sokovibeCommission: platformFee,
    totalAmount, sellerReceives,
    status: 'completed',
    paymentMethod: 'ClickPesa',
    transactionReference: transactionReference || '',
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  await db.collection('users').doc(sellerId).set({
    sellerBalance: admin.firestore.FieldValue.increment(sellerReceives),
    totalSales: admin.firestore.FieldValue.increment(1),
    grossSalesVolume: admin.firestore.FieldValue.increment(price),
    lastSaleAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });

  await db.collection('revenue_transactions').add({
    userId: sellerId,
    amount: sellerReceives,
    type: 'sale',
    description: `Sale of ${productName}`,
    transactionId: txRef.id,
    productName,
    productPrice: price,
    sokovibeCommission: platformFee,
    buyerName: buyerName || '',
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
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
    const osResult = await sendOneSignalBulk(userIds, title, body || '', { ...(data || {}), type: (data && data.type) || 'general' });
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

    // Increment unread count for receiver
    try {
      const receiverDoc = await db.collection('users').doc(receiverId).get();
      if (receiverDoc.exists) {
        const receiverData = receiverDoc.data();
        const fieldName = receiverData.isBuyer === true ? 'unread_count_buyer' : 'unread_count_seller';
        await db.collection('chat_rooms').doc(roomId).update({
          [fieldName]: admin.firestore.FieldValue.increment(1),
        });
      }
    } catch (_) {}

    // Send OneSignal push to receiver
    const senderName = senderDoc.exists
      ? (senderDoc.data().displayName || senderDoc.data().name || 'Mtumiaji')
      : 'Mtumiaji';
    try {
      await sendOneSignalNotification(receiverId, senderName, text, { type: 'chat', senderId, senderName, roomId });
    } catch (_) {}

    // Create in-app notification doc for receiver
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
  const { methodId, amount } = req.body;
  if (!methodId || amount == null) {
    return res.status(400).json({ error: 'methodId and amount are required' });
  }
  const fee = calcGatewayFee(methodId, Number(amount));
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
    const { method, amount } = req.body;
    if (!method || !amount) {
      return res.status(400).json({ error: 'method and amount are required' });
    }
    const fee = calcGatewayFee(method, Math.round(amount));
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
      const gatewayFee = calcGatewayFee('billpay', Math.round(amount));
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
      const processingFee = getUssdPushFee(amount);
      const totalCharge = amount + processingFee;

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
        message: `USSD push sent to ${normalizedPhone}. Total charge: TZS ${totalCharge.toLocaleString()} (amount TZS ${amount.toLocaleString()} + fee TZS ${processingFee.toLocaleString()})`,
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
    if (!db) return res.status(503).json({ error: 'Database not configured' });
    const {
      buyerId, buyerName, productId, productName, productImage,
      productPrice, sellerId, sellerName, processingFee, serviceFeePercent,
      totalAmount, region, district, street, landmarks, deliveryType, orderId, shippingCost,
    } = req.body;

    if (!buyerId || !sellerId || !productId || !productName || productPrice == null) {
      return res.status(400).json({ error: 'Missing required fields' });
    }

    // Verify buyer has sufficient balance
    const buyerDoc = await db.collection('users').doc(buyerId).get();
    if (!buyerDoc.exists) return res.status(404).json({ error: 'Buyer not found' });
    const buyerData = buyerDoc.data();
    const balance = buyerData.walletBalance || 0;
    if (balance < totalAmount) {
      return res.status(400).json({ error: 'Insufficient wallet balance' });
    }

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

    const price = Number(productPrice);
    const fee = Number(processingFee) || 0;
    const commissionPercent = Number(serviceFeePercent) || 0.035;
    const commission = Math.round(price * commissionPercent);
    const shipping = Math.round(Number(shippingCost) || 0);
    // Buyer already pays commission in totalAmount (see order_detail_screen).
    // Seller receives the full product price + shipping reimbursement from escrow.
    const sellerReceives = price + shipping;

    // Deduct from buyer wallet
    await db.collection('users').doc(buyerId).set({
      walletBalance: admin.firestore.FieldValue.increment(-totalAmount),
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
      processingFee: fee,
      platformFee: commission,
      sokovibeCommission: commission,
      serviceFeePercent: commissionPercent,
      totalAmount: Number(totalAmount),
      sellerReceives,
      shippingCost: shipping,
      region, district, street,
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
app.post('/api/release-expired-escrows', async (req, res) => {
  try {
    const authHeader = req.headers.authorization || '';
    const token = authHeader.replace('Bearer ', '');
    if (!token) return res.status(401).json({ error: 'Unauthorized' });
    const decoded = await admin.auth().verifyIdToken(token).catch(() => null);
    if (!decoded) return res.status(403).json({ error: 'Invalid token' });
    const userDoc = await db.collection('users').doc(decoded.uid).get();
    if (!userDoc.exists || !userDoc.data().isAdmin) {
      return res.status(403).json({ error: 'Admin only' });
    }

    const now = admin.firestore.Timestamp.now();
    const expiredSnap = await db.collection('transactions')
      .where('status', '==', 'escrow_hold')
      .where('escrowExpiresAt', '<=', now)
      .get();

    let released = 0;
    let notified = 0;

    for (const doc of expiredSnap.docs) {
      const tx = doc.data();
      await doc.ref.update({ status: 'completed', completedAt: now });

      // Release funds to seller
      const sellerReceives = tx.sellerReceives || tx.productPrice || 0;
      if (sellerReceives > 0 && tx.sellerId) {
        await db.collection('users').doc(tx.sellerId).update({
          sellerBalance: admin.firestore.FieldValue.increment(sellerReceives),
          totalSales: admin.firestore.FieldValue.increment(1),
          grossSalesVolume: admin.firestore.FieldValue.increment(tx.productPrice || 0),
          lastSaleAt: now,
        });
      }

      // Notify buyer that escrow auto-released
      if (tx.buyerId) {
        await db.collection('notifications').add({
          userId: tx.buyerId,
          title: 'Escrow Imetolewa Kiotomatiki',
          body: `Malipo ya ${tx.productName || 'bidhaa'} yametolewa kwa muuzaji.`,
          type: 'order',
          transactionId: doc.id,
          isRead: false,
          createdAt: now,
        });
      }

      // Notify seller
      if (tx.sellerId) {
        await db.collection('notifications').add({
          userId: tx.sellerId,
          title: 'Malipo Yamekamilika',
          body: `Malipo ya ${tx.productName || 'bidhaa'} yamekutolewa. Angalia salio lako.`,
          type: 'order',
          transactionId: doc.id,
          isRead: false,
          createdAt: now,
        });
      }

      released++;
    }

    res.json({ released, notified: released * 2 });
  } catch (e) {
    console.error('Auto-release escrow error:', e);
    res.status(500).json({ error: e.message });
  }
});

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

    const { buyerId, buyerName, buyerPhone, sellerId, sellerName, productId, productName, productImage, productPrice, shippingCost, deliveryType, region, district, street, landmarks, phone, paymentMethod } = req.body;
    if (!buyerId || !sellerId || !productId || !productName || productPrice == null) {
      return res.status(400).json({ error: 'Missing required fields' });
    }
    if (decoded.uid !== buyerId) {
      return res.status(403).json({ error: 'Buyer ID mismatch' });
    }

    const platformFee = Math.round(Number(productPrice) * PLATFORM_COMMISSION_PERCENT);
    const totalAmount = Math.round(Number(productPrice)) + Math.round(Number(shippingCost) || 0) + platformFee;

    const result = await orderEngine.createOrder(db, {
      buyerId, buyerName: buyerName || '', buyerPhone: buyerPhone || '',
      sellerId, sellerName: sellerName || '',
      productId, productName, productImage: productImage || '',
      productPrice: Math.round(Number(productPrice)),
      shippingCost: Math.round(Number(shippingCost) || 0),
      platformFee,
      totalAmount,
      deliveryType: deliveryType || 'local',
      region: region || '', district: district || '', street: street || '',
      landmarks: landmarks || '',
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
        productPrice: Math.round(Number(productPrice)),
        shippingCost: Math.round(Number(shippingCost) || 0),
        platformFee,
        totalAmount,
        deliveryType: deliveryType || 'local',
        region: region || '', district: district || '', street: street || '',
        landmarks: landmarks || '',
        status: 'awaiting_shipping_quote',
        paymentMethod: paymentMethod || 'ussd_push',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    } catch (e) {
      console.error('order create tx mirror error:', e.message);
    }

    // Notify seller that a new order is pending — push + in-app + SMS so the
    // seller always hears about it even with the app closed
    try {
      await db.collection('notifications').add({
        userId: sellerId,
        title: 'Agizo Jipya Limewasilishwa!',
        body: `${buyerName || 'Mnunuzi'} ametuma agizo la ${productName}. Toa gharama ya usafirishaji sasa.`,
        type: 'order',
        data: { orderId: result.orderId, buyerId, productId },
        isRead: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      await sendOneSignalNotification(sellerId,
        'Agizo Jipya Limewasilishwa!',
        `${buyerName || 'Mnunuzi'} ametuma agizo la ${productName}. Toa gharama ya usafirishaji sasa.`,
        { type: 'order', orderId: result.orderId, buyerId, productId }
      );
      const sellerSnap = await db.collection('users').doc(sellerId).get();
      const sellerPhone = sellerSnap.data()?.phone;
      if (sellerPhone) {
        await sendSms(sellerPhone,
          `SOKO VIBE: Agizo JIPYA #${result.orderId}\n${buyerName || 'Mnunuzi'} ametuma agizo la ${productName} (TSh ${result.totalAmount || productPrice}). Fungua app na utoe gharama ya usafirishaji.`
        );
      }
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

    // Real-time status notifications: seller hears on payment, buyer on dispatch
    try {
      if (newStatus === 'paid' || newStatus === 'escrow_hold') {
        await db.collection('notifications').add({
          userId: order.sellerId,
          title: 'Malipo Yamekamilika!',
          body: `${order.buyerName || 'Mnunuzi'} amelipia agizo la ${order.productName || ''}. Escrow imeshikilia fedha.`,
          type: 'payment',
          data: { type: 'order', orderId, buyerId: order.buyerId },
          isRead: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        await sendOneSignalNotification(order.sellerId,
          'Malipo Yamekamilika!',
          `${order.buyerName || 'Mnunuzi'} amelipia agizo la ${order.productName || ''}. Escrow imeshikilia fedha.`,
          { type: 'order', orderId, buyerId: order.buyerId }
        );
      } else if (newStatus === 'quoted') {
        // Seller set the shipping cost — buyer must pay the updated bill
        let costLabel = '';
        try {
          const parsed = JSON.parse(note || '{}');
          const cost = Number(parsed.shippingCost || 0);
          if (cost > 0) costLabel = ` la TZS ${cost.toLocaleString()}`;
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

startProductListener();
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

// ─── Product listener: notify previous chat partners on new product ─────
function startProductListener() {
  if (!db) return;
  console.log('[PRODUCT] Starting product listener...');
  const MAX_KNOWN = 500;

  // Load recent product IDs on startup
  let knownProductIds = new Set();
  db.collection('products')
    .orderBy('createdAt', 'desc')
    .limit(200)
    .get()
    .then((snap) => {
      snap.docs.forEach((doc) => knownProductIds.add(doc.id));
      console.log(`[PRODUCT] Loaded ${snap.docs.length} recent products`);
    })
    .catch((err) => console.error('[PRODUCT] Failed to load recent products:', err.message));

  db.collection('products')
    .onSnapshot(
      (snapshot) => {
        snapshot.docChanges().forEach((change) => {
          if (change.type !== 'added') return;
          const productId = change.doc.id;
          if (knownProductIds.has(productId)) return;
          if (knownProductIds.size >= MAX_KNOWN) {
            const first = knownProductIds.values().next().value;
            if (first) knownProductIds.delete(first);
          }
          knownProductIds.add(productId);

          const product = change.doc.data();
          const sellerId = product.sellerId;
          if (!sellerId) return;
          const sellerName = product.sellerName || 'Mfanyabiashara';
          const productName = product.name || 'bidhaa mpya';

          db.collection('chat_rooms')
            .where('participants', 'array-contains', sellerId)
            .get()
            .then((roomsSnap) => {
              const notified = new Set();
              for (const roomDoc of roomsSnap.docs) {
                const room = roomDoc.data();
                const other = (room.participants || []).find((p) => p !== sellerId);
                if (!other || notified.has(other)) continue;
                notified.add(other);
                const title = sellerName;
                const body = `${sellerName} ameweka bidhaa mpya: ${productName}.`;
                db.collection('notifications').add({
                  userId: other,
                  title,
                  body,
                  data: { type: 'product', productId, sellerId },
                  isRead: false,
                  createdAt: admin.firestore.FieldValue.serverTimestamp(),
                }).catch(() => {});
                sendOneSignalNotification(other, title, body, { type: 'product', productId, sellerId, productName }).catch(() => {});
              }
              if (notified.size > 0) {
                console.log(`[PRODUCT] Notified ${notified.size} users about new product from ${sellerId}`);
              }
            })
            .catch((err) => console.error('[PRODUCT] Room lookup error:', err.message));
        });
      },
      (error) => console.error('[PRODUCT] Listener error:', error)
    );
}

// ============================================================
// 🔍 DIAGNOSTIC — Check legacy FCM token in user doc
app.get('/api/diag/fcm-token/:userId', async (req, res) => {
  try {
    const { userId } = req.params;
    if (!db) return res.status(503).json({ error: 'Database not configured' });
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
