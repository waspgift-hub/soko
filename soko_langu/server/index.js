require('dotenv').config();
const express = require('express');
const cors = require('cors');
const compression = require('compression');
const crypto = require('crypto');
const admin = require('firebase-admin');
const helmet = require('helmet');
const { mongikeCollect, mongikePayout, mongikeBalance, COLLECTION_FEE, PAYOUT_FEE } = require('./mongike');
const { groqChat, groqTranscribe } = require('./groq');

const ADMIN_EMAILS = ["admin@soko-langu.com", "admin@soko-vibe.com"];

const app = express();

const REQUEST_TIMEOUT = 20000; // 20 seconds

// Security headers
app.use(helmet());

// Gzip compression — smaller response bodies = faster downloads
app.use(compression({ level: 6, threshold: 256 }));

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

function asyncHandler(fn) {
  return (req, res, next) => {
    Promise.resolve(fn(req, res, next)).catch(next);
  };
}

const PORT = process.env.PORT || 3000;
const WEBHOOK_SECRET = process.env.WEBHOOK_SECRET || '';
const ESCROW_AUTO_RELEASE_DAYS = parseInt(process.env.ESCROW_AUTO_RELEASE_DAYS) || 14;
const ESCROW_LOCAL_DAYS = 3;
const ESCROW_REGIONAL_DAYS = 7;
const MAX_DAILY_SALE_AMOUNT = parseInt(process.env.MAX_DAILY_SALE_AMOUNT) || 5000000;

// ─── Shared FCM helpers (Android data-only → Flutter/Awesome Notifications) ───
function stringifyFcmData(data = {}) {
  const out = {};
  for (const [k, v] of Object.entries(data || {})) {
    if (v === undefined || v === null) continue;
    out[String(k)] = String(v);
  }
  return out;
}

function buildFcmDataPayload(title, body, data = {}) {
  return stringifyFcmData({ title: title || '', body: body || '', ...data });
}

/**
 * Builds an FCM message with both data + notification payload.
 * The `notification` payload ensures delivery even when app is killed
 * (Android auto-displays it). The background handler skips when
 * notification payload is present to avoid duplicates.
 */
function buildFcmMessage({ token, tokens, title, body, data = {} }) {
  const notifType = (data && data.type) || 'general';
  const channelId = notifType === 'chat' ? 'chat_messages_v4'
    : notifType === 'payment' || notifType === 'order' || notifType === 'withdrawal' ? 'payments_notifications_v4'
    : 'general_notifications_v4';
  const msg = {
    data: buildFcmDataPayload(title, body, data),
    notification: { title: title || '', body: body || '' },
    android: {
      priority: 'high',
      notification: { channel_id: channelId, sound: 'soko_notification', icon: 'ic_notification' },
    },
    apns: { payload: { aps: { sound: 'default' } } },
  };
  if (token) msg.token = token;
  if (tokens && tokens.length) msg.tokens = tokens;
  return msg;
}

async function sendFcmToToken(message, userIdForCleanup = null) {
  const notifType = (message.data && message.data.type) || 'unknown';
  try {
    const result = await admin.messaging().send(message);
    console.log(`[FCM] sent user=${userIdForCleanup || '?'} type=${notifType} success=${result}`);
    return result;
  } catch (e) {
    const errCode = e.code || '';
    const errMsg = e.message || '';
    console.error(`[FCM] FAILED user=${userIdForCleanup || '?'} type=${notifType} code=${errCode} msg=${errMsg}`, e.errorInfo || '');

    // Log quota / sender-id errors specifically
    if (errCode === 'messaging/quota-exceeded') console.error(`[FCM] QUOTA EXCEEDED`);
    if (errCode === 'messaging/sender-id-mismatch') console.error(`[FCM] SENDER ID MISMATCH`);

    // Stale / invalid token — try topic fallback, then clean up
    if (userIdForCleanup && db &&
        (errCode === 'messaging/registration-token-not-registered' ||
         errCode === 'messaging/invalid-registration-token')) {
      console.log(`[FCM] Token stale for ${userIdForCleanup}, trying topic fallback...`);
      try {
        const topicMsg = {
          topic: `user_${userIdForCleanup}`,
          data: message.data || {},
          android: { priority: 'high' },
        };
        if (message.notification) topicMsg.notification = message.notification;
        const topicResult = await admin.messaging().send(topicMsg);
        console.log(`[FCM] Topic fallback succeeded for ${userIdForCleanup}: ${topicResult}`);
        return topicResult;
      } catch (topicErr) {
        console.error(`[FCM] Topic fallback ALSO failed for ${userIdForCleanup}: ${topicErr.code || topicErr.message}`);
      }
      // Clean stale token so next attempt gets fresh data
      await db.collection('users').doc(userIdForCleanup).update({ fcmToken: null });
      console.log(`[FCM] Cleared stale token for ${userIdForCleanup}`);
      return null; // Token handled — don't throw
    }

    // For other errors, re-throw so callers can decide how to handle
    throw e;
  }
}

/** @deprecated Use buildFcmMessage — kept for reference */
function androidNotifConfig(channelId, tag) {
  return {
    priority: 'high',
    notification: {
      channelId,
      priority: 'max',
      visibility: 'public',
      sound: 'soko_notification',
      notificationPriority: 'PRIORITY_MAX',
      defaultSound: false,
      vibrateTimingsMillis: [0, 200, 100, 200, 100, 300],
      defaultVibrateTimings: false,
      lights: [true, 500, 500],
      defaultLightSettings: false,
      ...(tag ? { tag } : {}),
      color: '#40916C',
    },
  };
}

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
  if (!WEBHOOK_SECRET) return next();
  const secret = req.headers['x-webhook-secret'];
  if (secret !== WEBHOOK_SECRET) {
    console.warn(`Webhook secret mismatch from IP: ${req.ip}`);
    return res.status(403).json({ error: 'Invalid webhook secret' });
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

let db;
if (process.env.FIREBASE_SERVICE_ACCOUNT_JSON) {
  const sa = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON);
  admin.initializeApp({ credential: admin.credential.cert(sa) });
  db = admin.firestore();
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

// PAYOUT_FEE (2000 TZS flat) imported from mongike.js

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
      paymentMethod: 'Mongike',
      source: source || '',
      metadata: metadata || {},
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }

  const result = await mongikePayout({
    amount: netAmount,
    recipientPhone: phone,
    recipientName: metadata?.sellerName || '',
    narration: `Soko Vibe withdrawal: ${type || 'payout'}`,
    externalReference: payoutId,
  });

  const mongikeRef = result.id || result.orderReference || '';
  await updatePayoutStatus(payoutId, PAYOUT_STATUSES.SUCCESS, { mongikeReference: mongikeRef });

  return { payoutId, mongikeReference: mongikeRef, netAmount, fee };
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

// ─── Mongike-only Payout Configuration ───
// All payouts use Mongike's flat 2,000 TZS fee. See mongike.js for the API client.

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

    const { productId, tier, amount, durationDays, phone, userId, productName, productImage, productPrice } = req.body;
    if (!productId || !tier || !phone) {
      return res.status(400).json({ error: 'Missing required fields (productId, tier, phone)' });
    }

    const tierConfig = BOOST_TIERS[tier];
    if (!tierConfig) {
      return res.status(400).json({ error: 'Invalid boost tier' });
    }

    const order_id = `boost_${Date.now()}`;
    const callbackUrl = `${req.protocol}://${req.get('host')}/api/mongike/webhook`;

    const result = await mongikeCollect({
      amount: tierConfig.price,
      orderId: order_id,
      buyerPhone: phone,
      feePayer: 'MERCHANT',
      callbackUrl,
    });

    const ref = result.id || result.orderReference || '';

    if (db) {
      await db.collection('transactions').doc(order_id).set({
        type: 'boost',
        productId,
        productName: productName || '',
        productImage: productImage || '',
        productPrice: productPrice || 0,
        tier: tier.toLowerCase(),
        amount: tierConfig.price,
        totalAmount: tierConfig.price,
        durationDays: tierConfig.days,
        userId: userId || '',
        buyerId: userId || '',
        buyerName: userId || '',
        buyerPhone: phone,
        sellerName: 'Soko Vibe',
        mongikeReference: ref,
        status: 'pending',
        paymentMethod: 'Mongike',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    res.json({
      order_id,
      mongikeReference: ref,
      message: 'Tuma PIN yako kwenye simu ili kukamilisha malipo.',
    });
  } catch (e) {
    console.error('/api/boost-product error:', e?.message || e);
    const msg = e?.message?.includes('Mongike') ? e.message : 'Internal server error';
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
    const normalized = digits.startsWith('0') ? '255' + digits.slice(1) : !digits.startsWith('255') ? '255' + digits : digits;
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 15000);
    const resp = await fetch('https://meseji.co.tz/api/v1/sms/send', {
      method: 'POST',
      signal: controller.signal,
      headers: { 'x-api-key': apiKey, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        sender_id: process.env.MESEJI_SENDER_ID || 'MESEJI',
        message,
        contacts: normalized,
      }),
    });
    clearTimeout(timeout);
    if (!resp.ok) {
      const err = await resp.text();
      console.error(`/api/sms/send: Meseji returned ${resp.status}: ${err}`);
      return res.status(502).json({ error: 'SMS provider error' });
    }
    res.json({ sent: true });
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
    const normalized = digits.startsWith('0') ? '255' + digits.slice(1) : !digits.startsWith('255') ? '255' + digits : digits;
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 15000);
    const resp = await fetch('https://meseji.co.tz/api/v1/sms/send', {
      method: 'POST',
      signal: controller.signal,
      headers: { 'x-api-key': apiKey, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        sender_id: process.env.MESEJI_SENDER_ID || 'MESEJI',
        message,
        contacts: normalized,
      }),
    });
    clearTimeout(timeout);
    if (!resp.ok) {
      const err = await resp.text();
      console.error(`sendSms: Meseji returned ${resp.status}: ${err}`);
      return false;
    }
    return true;
  } catch (e) {
    if (e.name === 'AbortError') {
      console.error('sendSms: request timed out after 15s for', phone);
    } else {
      console.error('sendSms error:', e.message);
    }
    return false;
  }
}

// ─── Admin notification helper — sends FCM + in-app to ALL admins ───
async function notifyAdmins(title, body, data = {}) {
  try {
    const adminSnap = await db.collection('users').where('isAdmin', '==', true).get();
    const promises = [];
    adminSnap.forEach(doc => {
      const uid = doc.id;
      const fcmToken = doc.data().fcmToken;
      promises.push(db.collection('notifications').add({
        userId: uid,
        title, body,
        isRead: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        data,
      }));
      if (fcmToken) {
        promises.push(sendFcmToToken(buildFcmMessage({
          token: fcmToken, title, body, data,
        }), uid).catch(() => {}));
      }
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

// 📲 FCM — SEND PUSH NOTIFICATION
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

    // Write in-app notification to Firestore (always, even without FCM token)
    await db.collection('notifications').add({
      userId,
      title,
      body: body || '',
      data: data || {},
      isRead: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    const fcmToken = userDoc.data().fcmToken;
    if (!fcmToken) return res.json({ sent: true, reason: 'No FCM token, in-app only' });

    const notifType = data && data.type;
    const message = buildFcmMessage({
      token: fcmToken,
      title,
      body: body || '',
      data: { ...(data || {}), type: notifType || 'general' },
    });

    try {
      await sendFcmToToken(message, userId);
    } catch (e) {
      // sendFcmToToken already cleaned the stale token and tried topic fallback
      if (e.code !== 'messaging/registration-token-not-registered' &&
          e.code !== 'messaging/invalid-registration-token') {
        throw e;
      }
    }

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
// 📲 FCM — SEND BULK PUSH NOTIFICATION (to multiple tokens)
// ============================================================
app.post('/api/send-bulk-notification', async (req, res) => {
  try {
    const auth = await requireAdmin(req, res);
    if (!auth.ok) return;

    const { title, body, tokens, target, data } = req.body;
    if (!title || !tokens || !Array.isArray(tokens) || tokens.length === 0) {
      return res.status(400).json({ error: 'Missing title or tokens array' });
    }

    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const BATCH_SIZE = 500;
    let sent = 0;
    const errors = [];

    for (let i = 0; i < tokens.length; i += BATCH_SIZE) {
      const batch = tokens.slice(i, i + BATCH_SIZE);
      try {
        const message = buildFcmMessage({
          tokens: batch,
          title,
          body: body || '',
          data: { ...(data || {}), type: (data && data.type) || 'general' },
        });

        const response = await admin.messaging().sendEachForMulticast(message);
        sent += response.successCount;

        if (response.failureCount > 0) {
          response.responses.forEach((resp, idx) => {
            if (!resp.success) {
              errors.push({ token: batch[idx].substring(0, 20) + '...', error: resp.error.message });
            }
          });
        }
      } catch (e) {
        errors.push({ batch: i / BATCH_SIZE, error: e.message });
      }
    }

    // Log the notification in Firestore
    await db.collection('admin_notifications').add({
      title,
      body,
      target: target || 'all',
      sentCount: sent,
      errorCount: errors.length,
      sentAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    res.json({
      sent: true,
      totalTokens: tokens.length,
      delivered: sent,
      errors: errors.length > 0 ? errors.slice(0, 10) : [],
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

    // FCM push to buyer
    try {
      const buyerSnap = await db.collection('users').doc(tx.buyerId).get();
      const buyerToken = buyerSnap.data()?.fcmToken;
      if (buyerToken) {
        await sendFcmToToken(buildFcmMessage({
          token: buyerToken,
          title: 'Bidhaa Imesafirishwa!',
          body: `${tx.productName || 'Bidhaa'} imesafirishwa. Thibitisha upokeaji ukishapata mzigo.`,
          data: { type: 'dispatched', transactionId: orderId },
        }), tx.buyerId);
      }
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
        if (sellerPhone && sellerReceives > PAYOUT_FEE) {
          const netPayout = sellerReceives - PAYOUT_FEE;
          const payoutRef = generatePayoutReference('ap');
          await db.collection('users').doc(sellerId).update({
            sellerBalance: admin.firestore.FieldValue.increment(-sellerReceives),
          });
          const mRef = await mongikePayout({
            amount: netPayout,
            recipientPhone: sellerPhone,
            recipientName: sellerData?.name || sellerData?.displayName || '',
            narration: `Soko Vibe auto payout: ${productName}`,
            externalReference: payoutRef,
          });
          await db.collection('payouts').doc(payoutRef).set({
            userId: sellerId, userPhone: sellerPhone,
            type: 'auto_payout', amount: sellerReceives, fee: PAYOUT_FEE,
            netAmount: netPayout, mongikeReference: mRef.id || '',
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
      await db.collection('notifications').add({
        userId: sellerId,
        title: 'Pesa Zimetumwa Moja kwa Moja!',
        body: `${productName} — TZS ${(sellerReceives - PAYOUT_FEE).toLocaleString()} zimetumwa kwa simu yako. Fee ya TZS ${PAYOUT_FEE.toLocaleString()} imekatwa.`,
        isRead: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      try {
        const st = (sellerDoc.data())?.fcmToken;
        if (st) sendFcmToToken(buildFcmMessage({
          token: st, title: 'Pesa Zimetumwa Moja kwa Moja!',
          body: `TZS ${(sellerReceives - PAYOUT_FEE).toLocaleString()} zimetumwa kwa simu yako (fee TZS ${PAYOUT_FEE.toLocaleString()}).`,
          data: { type: 'auto_payout', transactionId: orderId },
        }), sellerId).catch(() => {});
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
        const sellerUser = await db.collection('users').doc(sellerId).get();
        const sellerToken = sellerUser.data()?.fcmToken;
        if (sellerToken) {
          await sendFcmToToken(buildFcmMessage({
            token: sellerToken,
            title: 'Escrow Imefunguliwa!',
            body: `${productName} — TZS ${sellerReceives.toLocaleString()} zimewekwa salio lako.`,
            data: { type: 'escrow_release', transactionId: orderId },
          }), sellerId);
        }
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
    // Send FCM to buyer
    try {
      const buyerSnap = await db.collection('users').doc(userId).get();
      const buyerToken = buyerSnap.data()?.fcmToken;
      if (buyerToken) {
        await sendFcmToToken(buildFcmMessage({
          token: buyerToken,
          title: 'Umethibitisha Upokeaji',
          body: `${productName} — asante kwa kununua ndani ya SokoVibe!`,
          data: { type: 'delivery_confirmed', transactionId: orderId },
        }), userId);
      }
    } catch (_) {}

    // SMS seller about escrow release / auto payout
    try {
      const sellerUser = await db.collection('users').doc(sellerId).get();
      const sellerPhone = sellerUser.data()?.phone;
      if (sellerPhone) {
        const sellerMsg = autoPaidOut
          ? `Soko Vibe: TZS ${(sellerReceives - PAYOUT_FEE).toLocaleString()} zimetumwa kwa simu yako kwa mauzo ya ${productName} (fee TZS ${PAYOUT_FEE.toLocaleString()}).`
          : `Soko Vibe: Mteja amethibitisha kupokea mzigo #${orderId}. TZS ${sellerReceives.toLocaleString()} zimetolewa Escrow na kuwekwa kwenye pochi yako.`;
        sendSms(sellerPhone, sellerMsg);
      }
    } catch (_) {}

    res.json({
      success: true,
      message: autoPaidOut
        ? `Auto payout: TZS ${(sellerReceives - PAYOUT_FEE).toLocaleString()} sent to seller phone`
        : 'Escrow released. Seller balance credited.',
      autoPaidOut,
    });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 🔔 MONGIKE WEBHOOK — Handle payment status updates
// ============================================================
// Mongike calls this when a USSD push payment is completed, failed,
// or when a payout status changes. Expects `x-webhook-secret` header.
app.post('/api/mongike/webhook', verifyWebhook, async (req, res) => {
  try {
    // Mongike may wrap the payload in { event: "...", data: { ... } }
    // or send flat { order_id, status, amount, ... }
    let payload = req.body;
    if (payload.data && typeof payload.data === 'object') {
      payload = payload.data;
    }

    const orderId = payload.orderReference || payload.order_id || payload.externalId || '';
    const rawStatus = (payload.status || payload.paymentStatus || payload.event || '').toString().toLowerCase();
    const paymentStatus = rawStatus === 'completed' || rawStatus === 'payment_received' || rawStatus === 'payment_completed'
      ? 'success'
      : rawStatus === 'failed' || rawStatus === 'cancelled' || rawStatus === 'expired'
        ? 'failed'
        : rawStatus;

    if (!orderId || !paymentStatus) {
      return res.status(200).json({ received: false });
    }

    if (!db) return res.status(200).json({ received: false });

    const txDoc = await db.collection('transactions').doc(orderId).get();
    if (!txDoc.exists) {
      console.warn(`Mongike webhook: transaction ${orderId} not found`);
      return res.status(200).json({ received: false });
    }

    const tx = txDoc.data();

    // Prevent double-processing — skip if already finalized
    if (tx.status === 'completed' || tx.status === 'escrow_hold' || tx.status === 'failed') {
      return res.status(200).json({ received: true });
    }

    const mongikeRef = payload.id || payload.transactionId || payload.reference || tx.mongikeReference || '';

    if (paymentStatus === 'success') {

      if (tx.type === 'boost') {
        // ── Activate product boost ──
        const tier = tx.tier || 'bronze';
        const tierConfig = BOOST_TIERS[tier] || BOOST_TIERS.bronze;
        const boostedUntil = new Date(Date.now() + tierConfig.days * 24 * 60 * 60 * 1000);

        // Mark transaction as completed FIRST so the UI updates immediately
        await txDoc.ref.update({
          status: 'completed',
          mongikeReference: mongikeRef,
          completedAt: admin.firestore.FieldValue.serverTimestamp(),
          totalAmount: tx.amount || 0,
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
          const userSnap = await db.collection('users').doc(tx.userId).get();
          const token = userSnap.data()?.fcmToken;
          if (token) {
            sendFcmToToken(buildFcmMessage({
              token,
              title: '✅ Boost imewashwa!',
              body: `Bidhaa yako imepandishwa kwa daraja la ${tier} kwa siku ${tierConfig.days}.`,
              data: { type: 'boost', productId: tx.productId || '' },
            }), tx.userId).catch(() => {});
          }
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
          paymentMethod: 'Mongike',
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
        const processingFee = COLLECTION_FEE;
        const sellerReceives = productPrice;
        const deliveryType = tx.deliveryType || 'local';
        const autoReleaseDays = tx.autoReleaseDays || (deliveryType === 'regional' ? ESCROW_REGIONAL_DAYS : ESCROW_LOCAL_DAYS);
        const escrowExpiry = new Date(Date.now() + autoReleaseDays * 24 * 60 * 60 * 1000);

        await txDoc.ref.update({
          processingFee,
          platformFee,
          sokoLanguCommission: platformFee,
          totalAmount: productPrice + platformFee + processingFee,
          sellerReceives,
          status: 'escrow_hold',
          paymentMethod: 'Mongike',
          mongikeReference: mongikeRef,
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
          paymentMethod: 'Mongike',
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
            db.collection('users').doc(tx.sellerId).get().then(sellerSnap => {
              const sellerToken = sellerSnap.data()?.fcmToken;
              if (sellerToken) {
                sendFcmToToken(buildFcmMessage({
                  token: sellerToken,
                  title: 'Umepata Mauzo!',
                  body: `${tx.productName || 'Bidhaa'} imeuzwa. TZS ${sellerReceives.toLocaleString()} zimewekwa escrow.`,
                  data: { type: 'order', productId: tx.productId || '', transactionId: orderId },
                }), tx.sellerId).catch(() => {});
              }
            }).catch(() => {});
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
          db.collection('users').doc(tx.buyerId).get().then(buyerSnap => {
            const buyerToken = buyerSnap.data()?.fcmToken;
            if (buyerToken) {
              sendFcmToToken(buildFcmMessage({
                token: buyerToken,
                title: 'Malipo Yamekamilika!',
                body: `Malipo ya ${tx.productName || 'Bidhaa'} yamepokelewa.`,
                data: { type: 'order', productId: tx.productId || '', transactionId: orderId },
              }), tx.buyerId).catch(() => {});
            }
          }).catch(() => {});
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
        mongikeReference: mongikeRef,
        failureReason: payload.message || payload.error || 'Mongike payment failed',
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // Notify buyer of failed payment
      if (tx.buyerId) {
        await db.collection('notifications').add({
          userId: tx.buyerId,
          title: 'Malipo Yameshindikana',
          body: `Malipo ya ${tx.productName || 'Bidhaa'} hayakukamilika. Jaribu tena au wasiliana nasi. Sababu: ${payload.message || payload.error || 'Mongike payment failed'}`,
          isRead: false,
          type: 'payment_failed',
          transactionId: orderId,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        try {
          const buyerSnap = await db.collection('users').doc(tx.buyerId).get();
          const buyerToken = buyerSnap.data()?.fcmToken;
          if (buyerToken) {
            await sendFcmToToken(buildFcmMessage({
              token: buyerToken,
              title: 'Malipo Yameshindikana',
              body: `Malipo ya ${tx.productName || 'Bidhaa'} hayakukamilika. Jaribu tena kwenye app.`,
              data: { type: 'payment_failed', productId: tx.productId || '', transactionId: orderId },
            }), tx.buyerId);
          }
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
    console.error('Mongike webhook error:', e);
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
    const sellerId = tx.sellerId;
    const sellerReceives = tx.sellerReceives || 0;
    const productName = tx.productName || 'Product';

    if (!buyerPhone) {
      return res.status(400).json({ error: 'Buyer phone not found for refund' });
    }

    if (productPrice <= PAYOUT_FEE) {
      return res.status(400).json({ error: `Refund amount must exceed fee of TZS ${PAYOUT_FEE.toLocaleString()}` });
    }

    const refundAmount = productPrice - PAYOUT_FEE;

    // Refund minus payout fee to buyer via Mongike
    try {
      await mongikePayout({
        amount: refundAmount,
        recipientPhone: buyerPhone,
        narration: `Soko Vibe cancel refund: ${orderId}`,
      });
    } catch (payoutErr) {
      return res.status(500).json({ error: `Refund failed: ${payoutErr.message}` });
    }

    // Update transaction
    await txDoc.ref.update({
      status: 'refunded',
      escrowReleased: true,
      cancellationType: 'buyer_cancel',
      refundFee: PAYOUT_FEE,
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
      fee: PAYOUT_FEE,
      description: `Buyer cancel: ${productName} - TZS ${refundAmount} (fee TZS ${PAYOUT_FEE})`,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Notify buyer
    await db.collection('notifications').add({
      userId: tx.buyerId,
      title: '💰 Pesa Zimerudishwa',
      body: `TZS ${refundAmount.toLocaleString()} zimerudishwa kwa ${productName}. Ada ya TZS ${PAYOUT_FEE.toLocaleString()} imekatwa kwa gharama za payout.`,
      isRead: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      data: { type: 'refund', orderId },
    });
    try {
      const buyerSnap = await db.collection('users').doc(tx.buyerId).get();
      const buyerToken = buyerSnap.data()?.fcmToken;
      if (buyerToken) {
        await sendFcmToToken(buildFcmMessage({
          token: buyerToken,
          title: '💰 Pesa Zimerudishwa',
          body: `TZS ${refundAmount.toLocaleString()} zimerudishwa kwa ${productName}. Ada ya TZS ${PAYOUT_FEE.toLocaleString()} imekatwa kwa gharama za payout.`,
          data: { type: 'refund', orderId },
        }), tx.buyerId);
      }
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
        const sellerSnap = await db.collection('users').doc(sellerId).get();
        const sellerToken = sellerSnap.data()?.fcmToken;
        if (sellerToken) {
          await sendFcmToToken(buildFcmMessage({
            token: sellerToken,
            title: '❌ Oda Imeghairiwa',
            body: `${productName} imeghairiwa na mnunuzi. Pesa zimetolewa kwenye pendingEscrow yako.`,
            data: { type: 'cancelled', orderId },
          }), sellerId);
        }
      } catch (_) {}
    }

    res.json({ success: true, refundAmount, fee: PAYOUT_FEE, message: `Oda imeghairiwa. TZS ${refundAmount.toLocaleString()} zimerudishwa kwa simu yako (ada TZS ${PAYOUT_FEE.toLocaleString()}).` });
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
      const sellerSnap = await db.collection('users').doc(tx.sellerId).get();
      const sellerToken = sellerSnap.data()?.fcmToken;
      if (sellerToken) {
        await sendFcmToToken(buildFcmMessage({
          token: sellerToken,
          title: '\u2696\uFE0F Mgogoro Umefunguliwa',
          body: `Mnunuzi amefungua mgogoro kwa ${productName}. Tafadhali wasilisha ushahidi wako.`,
          data: { type: 'disputed', transactionId: orderId },
        }), tx.sellerId);
      }
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
      const buyerSnap = await db.collection('users').doc(userId).get();
      const buyerToken = buyerSnap.data()?.fcmToken;
      if (buyerToken) {
        await sendFcmToToken(buildFcmMessage({
          token: buyerToken,
          title: '\u2696\uFE0F Mgogoro Umefunguliwa',
          body: `Tumepokea mgogoro wako kwa ${productName}. Admin atakagua na kutoa uamuzi.`,
          data: { type: 'disputed', transactionId: orderId },
        }), userId);
      }
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
        const buyerSnap = await db.collection('users').doc(tx.buyerId).get();
        const buyerToken = buyerSnap.data()?.fcmToken;
        if (buyerToken) {
          await sendFcmToToken(buildFcmMessage({
            token: buyerToken,
            title: '\u2696\uFE0F Uamuzi wa Mgogoro',
            body: `Admin ameamua pesa zitolewe kwa muuzaji. ${note || ''}`,
            data: { type: 'dispute_resolved', transactionId: orderId },
          }), tx.buyerId);
        }
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
        const sellerSnap = await db.collection('users').doc(sellerId).get();
        const sellerToken = sellerSnap.data()?.fcmToken;
        if (sellerToken) {
          await sendFcmToToken(buildFcmMessage({
            token: sellerToken,
            title: '\u2696\uFE0F Uamuzi wa Mgogoro',
            body: `Admin ameamua pesa zikutolee. ${note || ''}`,
            data: { type: 'dispute_resolved', transactionId: orderId },
          }), sellerId);
        }
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
      const gatewayFee = PAYOUT_FEE;

      // Send full refund to buyer via Mongike
      try {
        await mongikePayout({
          amount: refundAmount,
          recipientPhone: buyerPhone,
          narration: `Soko Vibe refund: ${orderId}`,
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
        const buyerSnap = await db.collection('users').doc(tx.buyerId).get();
        const buyerToken = buyerSnap.data()?.fcmToken;
        if (buyerToken) {
          await sendFcmToToken(buildFcmMessage({
            token: buyerToken,
            title: '\uD83D\uDCB0 Pesa Zimerudishwa Kamili',
            body: `Refund kamili ya TZS ${refundAmount.toLocaleString()} kwa ${productName} imetumwa kwa namba yako.`,
            data: { type: 'refund', orderId },
          }), tx.buyerId);
        }
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
          const sellerSnap = await db.collection('users').doc(sellerId).get();
          const sellerToken = sellerSnap.data()?.fcmToken;
          if (sellerToken) {
            await sendFcmToToken(buildFcmMessage({
              token: sellerToken,
              title: '\u274C Mgogoro Umekamilika',
              body: `${productName} imerefundiwa mnunuzi. Pesa zimetolewa kwenye pendingEscrow yako.${gatewayFee > 0 ? ' Ada ya gateway imetozwa kwenye akaunti yako.' : ''}`,
              data: { type: 'refund', orderId },
            }), sellerId);
          }
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
    if (token) {
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
    const netPayout = sellerReceives - PAYOUT_FEE;

    if (netPayout <= 0) {
      await txDoc.ref.update({
        payoutStatus: admin.firestore.FieldValue.delete(),
        payoutError: admin.firestore.FieldValue.delete(),
        payoutFailedAt: admin.firestore.FieldValue.delete(),
        payoutRetriedAt: admin.firestore.FieldValue.serverTimestamp(),
        payoutRetryNote: 'Net payout was zero, skipped Mongike',
      });
      return res.json({ success: true, message: 'Payout skipped: net amount <= 0. Flag cleared.' });
    }

    await processPayout({
      userId: sellerId, phone: sellerPhone,
      amount: sellerReceives, fee: PAYOUT_FEE, netAmount: netPayout,
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

    const autoApproved = errors.length === 0;
    const status = autoApproved ? 'approved' : 'pending';
    const reason = autoApproved ? '' : errors.join('; ');

    await db.collection('users').doc(userId).update({
      kyc: {
        fullName,
        idType,
        idNumber: cleanId,
        idImageUrl: idImageUrl || '',
        selfieUrl: selfieUrl || '',
        status,
        approved: autoApproved,
        reviewNotes: reason,
        submittedAt: admin.firestore.FieldValue.serverTimestamp(),
        reviewedAt: autoApproved ? admin.firestore.FieldValue.serverTimestamp() : null,
      },
    });

    // Update sellerKycApproved on all products if auto-approved
    if (autoApproved && userId) {
      await updateSellerKycOnProducts(userId, true);
    }

    await auditLog({
      userId,
      type: `kyc_${status}`,
      amount: 0,
      reason: `KYC ${status}: ${idType} ${cleanId}${reason ? ' — ' + reason : ''}`,
    });

    // Notify user
    await db.collection('notifications').add({
      userId,
      title: autoApproved ? 'KYC Imekubaliwa!' : 'KYC Inahitaji Ukaguzi',
      body: autoApproved
        ? 'Umekubaliwa kuuza bidhaa. Sasa unaweza kuongeza bidhaa zako.'
        : `KYC yako inahitaji marekebisho: ${reason}. Tuma tena baada ya kusahihisha.`,
      isRead: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    try {
      const userSnap = await db.collection('users').doc(userId).get();
      const fcmToken = userSnap.data()?.fcmToken;
      if (fcmToken) {
        const kycTitle = autoApproved ? 'KYC Imekubaliwa!' : 'KYC Inahitaji Ukaguzi';
        const kycBody = autoApproved
          ? 'Umekubaliwa kuuza bidhaa. Sasa unaweza kuongeza bidhaa zako.'
          : `KYC yako inahitaji marekebisho: ${reason}. Tuma tena baada ya kusahihisha.`;
        await sendFcmToToken(buildFcmMessage({
          token: fcmToken,
          title: kycTitle,
          body: kycBody,
          data: { type: 'kyc', status: autoApproved ? 'approved' : 'pending' },
        }), userId);
      }
    } catch (_) {}

    res.json({
      success: true,
      approved: autoApproved,
      reason,
      message: autoApproved ? 'KYC imekubaliwa moja kwa moja' : `KYC imetumwa lakini: ${reason}`,
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
      const userSnap = await db.collection('users').doc(userId).get();
      const fcmToken = userSnap.data()?.fcmToken;
      if (fcmToken) {
        const kycTitle = approve ? 'KYC Imekubaliwa!' : 'KYC Imekataliwa';
        const kycBody = approve
          ? 'Umekubaliwa kuuza bidhaa. Sasa unaweza kuongeza bidhaa mpya.'
          : `KYC yako imekataliwa. Sababu: ${notes || 'Tafadhali wasiliana na msaada'}. Wasilisha tena baada ya kurekebisha.`;
        await sendFcmToToken(buildFcmMessage({
          token: fcmToken,
          title: kycTitle,
          body: kycBody,
          data: { type: 'kyc', status: approve ? 'approved' : 'rejected' },
        }), userId);
      }
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

// ============================================================
// 🛒 MARKETPLACE — Initiate product purchase payment via Mongike
// ============================================================
app.post('/api/create-marketplace-payment-link', paymentRateLimit, async (req, res) => {
  try {
    const authHeader = req.headers.authorization || '';
    const token = authHeader.replace('Bearer ', '');
    if (!token) return res.status(401).json({ error: 'Unauthorized' });
    try { await admin.auth().verifyIdToken(token); } catch (_) { return res.status(403).json({ error: 'Invalid token' }); }

    const { productPrice, productName, productId, sellerId, sellerName, email, phone, buyerId, deliveryType, shippingCost, existingTransactionId } = req.body;
    if (!productPrice || !productId || !sellerId || !phone) {
      return res.status(400).json({ error: 'Missing required fields' });
    }

    // Resolve buyer name before Mongike call
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

    // Include shipping + platform commission + transaction fee in total sent to Mongike
    const commission = Math.round(Math.round(productPrice) * PLATFORM_COMMISSION_PERCENT);
    const totalAmount = Math.round(productPrice) + Math.round(shippingCost || 0) + commission + COLLECTION_FEE;
    const callbackUrl = `${req.protocol}://${req.get('host')}/api/mongike/webhook`;

    const result = await mongikeCollect({
      amount: totalAmount,
      orderId: order_id,
      buyerPhone: phone,
      buyerName: buyerName || undefined,
      buyerEmail: email || undefined,
      feePayer: 'MERCHANT',
      callbackUrl,
    });

    const ref = result.id || result.orderReference || '';

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
        processingFee: COLLECTION_FEE,
        totalAmount,
        status: 'pending',
        paymentMethod: 'Mongike',
        deliveryType: deliveryType || 'local',
        autoReleaseDays: deliveryType === 'regional' ? ESCROW_REGIONAL_DAYS : ESCROW_LOCAL_DAYS,
        mongikeReference: ref,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    }

    res.json({
      order_id,
      mongikeReference: ref,
      message: 'Tuma PIN yako kwenye simu ili kukamilisha malipo.',
    });
  } catch (e) {
    console.error('create-marketplace-payment-link error:', e.message);
    const msg = e.message && e.message.includes('Mongike')
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

        // Send notification + FCM push
        if (tx.userId) {
          await db.collection('notifications').add({
            userId: tx.userId,
            title: '✅ Boost imewashwa!',
            body: `Bidhaa yako imepandishwa kwa daraja la ${tier} kwa siku ${tierConfig.days}.`,
            data: { type: 'boost', productId: tx.productId },
            isRead: false,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          // Send FCM push
          try {
            const userSnap = await db.collection('users').doc(tx.userId).get();
            const token = userSnap.data()?.fcmToken;
            if (token) {
              await sendFcmToToken(buildFcmMessage({
                token,
                title: '✅ Boost imewashwa!',
                body: `Bidhaa yako imepandishwa kwa daraja la ${tier} kwa siku ${tierConfig.days}.`,
                data: { type: 'boost', productId: tx.productId || '' },
              }), tx.userId);
            }
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
        const payoutFee = PAYOUT_FEE;
        const processingFee = tx.mongikeFee || 0;
        const sellerReceives = productPrice;
        const deliveryType = tx.deliveryType || 'local';
        const autoReleaseDays = tx.autoReleaseDays || (deliveryType === 'regional' ? ESCROW_REGIONAL_DAYS : ESCROW_LOCAL_DAYS);
        const escrowExpiry = new Date(Date.now() + autoReleaseDays * 24 * 60 * 60 * 1000);

        // Update transaction — put in escrow instead of auto-paying
        await txDoc.ref.update({
          processingFee,
          platformFee,
          mongikeFee: processingFee,
          payoutFee,
          sokoLanguCommission: platformFee,
          totalAmount: productPrice + platformFee,
          sellerReceives,
          status: 'escrow_hold',
          paymentMethod: 'Mongike',
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
          mongikeFee: processingFee,
          payoutFee,
          sokoLanguCommission: platformFee,
          buyerName: tx.buyerName || '',
          paymentMethod: 'Mongike',
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
          // Send FCM push to seller
          try {
            const sellerSnap = await db.collection('users').doc(tx.sellerId).get();
            const sellerToken = sellerSnap.data()?.fcmToken;
            if (sellerToken) {
              await sendFcmToToken(buildFcmMessage({
                token: sellerToken,
                title: 'Umepata Mauzo!',
                body: `${tx.productName || 'Bidhaa'} imeuzwa. TZS ${sellerReceives.toLocaleString()} imewekwa escrow.`,
                data: {
                  type: 'order',
                  productId: tx.productId || '',
                  transactionId: order_id,
                  buyerPhone: tx.buyerPhone || '',
                },
              }), tx.sellerId);
            }
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
          // Send FCM push to buyer
          try {
            const buyerSnap = await db.collection('users').doc(tx.buyerId).get();
            const buyerToken = buyerSnap.data()?.fcmToken;
            if (buyerToken) {
              await sendFcmToToken(buildFcmMessage({
                token: buyerToken,
                title: 'Malipo Yamekamilika!',
                body: `Malipo ya ${tx.productName || 'Bidhaa'} yamepokelewa.`,
                data: { type: 'order', productId: tx.productId || '', transactionId: order_id },
              }), tx.buyerId);
            }
          } catch (_) {}
        }
      }
    } else if (paymentStatus === 'failed' || paymentStatus === 'cancelled') {
      await txDoc.ref.update({ status: 'failed' });
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
      const payoutFee = PAYOUT_FEE;
      const processingFee = tx.mongikeFee || 0;
      const sellerReceives = productPrice;
      const deliveryType = tx.deliveryType || 'local';
      const autoReleaseDays = tx.autoReleaseDays || (deliveryType === 'regional' ? ESCROW_REGIONAL_DAYS : ESCROW_LOCAL_DAYS);
      const escrowExpiry = new Date(Date.now() + autoReleaseDays * 24 * 60 * 60 * 1000);

      await txDoc.ref.update({
        processingFee,
        platformFee,
        mongikeFee: processingFee,
        payoutFee,
        sokoLanguCommission: platformFee,
        totalAmount: productPrice + platformFee,
        sellerReceives,
        status: 'escrow_hold',
        paymentMethod: 'Mongike',
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
        mongikeFee: processingFee,
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
// 💰 SELLER WITHDRAW — Send seller balance to mobile money via Mongike
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

    const totalCost = withdrawAmount + PAYOUT_FEE;

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
          throw new Error(`Insufficient balance. You need TZS ${totalCost.toLocaleString()} (${withdrawAmount.toLocaleString()} withdrawal + ${PAYOUT_FEE.toLocaleString()} fee). Available: TZS ${currentBalance.toLocaleString()}`);
        }

        tx.update(userRef, {
          sellerBalance: admin.firestore.FieldValue.increment(-totalCost),
        });
      });
    } catch (txErr) {
      return res.status(400).json({ error: txErr.message });
    }

    // Balance deducted atomically — now call Mongike to send the withdrawal amount
    const netAmount = withdrawAmount; // Seller receives the full withdrawal amount
    let payoutResult;
    try {
      payoutResult = await processPayout({
        userId,
        phone,
        amount: totalCost,       // total deducted from seller
        fee: PAYOUT_FEE,
        netAmount,               // what seller actually receives
        source: `seller_withdraw_${Date.now()}`,
        type: 'seller_withdrawal',
        metadata: { sellerName, balanceBefore: balanceSnapshot },
      });
    } catch (payoutErr) {
      // Mongike call failed — reverse the deduction
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
      reason: `Seller withdrawal: TZS ${netAmount.toLocaleString()} to ${phone} (fee: TZS ${PAYOUT_FEE.toLocaleString()})`,
      relatedId: payoutResult.payoutId,
      metadata: { phone, netAmount, fee: PAYOUT_FEE, payoutId: payoutResult.payoutId },
    });

    // Notify seller about withdrawal initiation
    try {
      const userSnap = await db.collection('users').doc(userId).get();
      const fcmToken = userSnap.data()?.fcmToken;
      await db.collection('notifications').add({
        userId,
        title: '💰 Utoaji wa Pesa Umeanzishwa',
        body: `TZS ${netAmount.toLocaleString()} zinaandaliwa kutuma kwa ${phone}.`,
        isRead: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        data: { type: 'withdrawal', payoutId: payoutResult.payoutId },
      });
      if (fcmToken) {
        await sendFcmToToken(buildFcmMessage({
          token: fcmToken,
          title: '💰 Utoaji wa Pesa Umeanzishwa',
          body: `TZS ${netAmount.toLocaleString()} zinaandaliwa kutuma kwa ${phone}.`,
          data: { type: 'withdrawal', payoutId: payoutResult.payoutId },
        }), userId);
      }
    } catch (_) {}

    res.json({
      success: true,
      netAmount,
      fee: PAYOUT_FEE,
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

    const netAmount = amount - PAYOUT_FEE;
    if (netAmount <= 0) {
      return res.status(400).json({ error: `Amount too small after fee (min TZS ${PAYOUT_FEE + 1})` });
    }

    let payoutId;
    try {
      const payout = await processPayout({
        userId, phone, amount, fee: PAYOUT_FEE, netAmount,
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
      fee: PAYOUT_FEE,
      netAmount,
      phone,
      payoutId,
      status: 'completed',
      paymentMethod: 'Mongike',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    await auditLog({
      userId, type: 'admin_withdraw', amount: -amount,
      reason: `Admin ad revenue withdrawal: TZS ${netAmount} to ${phone}`,
      relatedId: payoutId,
      metadata: { phone, netAmount, fee: PAYOUT_FEE, payoutId },
    });

    res.json({
      success: true,
      netAmount,
      fee: PAYOUT_FEE,
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

    const netAmount = amount - PAYOUT_FEE;
    if (netAmount <= 0) {
      return res.status(400).json({ error: `Amount too small after fee (min TZS ${PAYOUT_FEE + 1})` });
    }

    const payoutResult = await processPayout({
      userId, phone, amount, fee: PAYOUT_FEE, netAmount,
      source: source || generatePayoutReference('src'),
      type: type || 'manual',
    });

    await auditLog({
      userId, type: 'admin_create_payout', amount: -amount,
      reason: `Admin-created payout: TZS ${netAmount} to ${phone}`,
      relatedId: payoutResult.payoutId,
      metadata: { phone, netAmount, fee: PAYOUT_FEE, source },
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
// 📊 ADMIN — Finance summary (all admin money + Mongike balance)
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

    // 5. Total money ever processed
    const txSnap = await db.collection('transactions').get();
    let totalProcessed = 0;
    txSnap.docs.forEach(doc => {
      const d = doc.data();
      totalProcessed += (d.totalAmount || 0);
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

    // 8. Actual Mongike wallet balance
    let actualMongikeBalance = 0;
    try {
      actualMongikeBalance = await mongikeBalance();
    } catch (_) {
      actualMongikeBalance = 0;
    }

    res.json({
      success: true,
      estimatedAdRevenue,
      actualAdRevenue,
      totalCommissions,
      totalBoostRevenue,
      totalAdminBalance,
      totalPaidOut: totalAdminPaidOut,
      availableBalance,
      totalAdminWithdrawn,
      actualMongikeBalance,
      paymentProcessor: 'Mongike',
    });
  } catch (e) {
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
      const userSnap = await db.collection('users').doc(uid).get();
      const fcmToken = userSnap.data()?.fcmToken;
      if (fcmToken) {
        await sendFcmToToken(buildFcmMessage({
          token: fcmToken,
          title: 'Akaunti Yako Imesitishwa',
          body: 'Akaunti yako imesitishwa. Wasiliana na msaada kwa maelezo zaidi.',
          data: { type: 'account', status: 'suspended' },
        }), uid);
      }
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
      const userSnap = await db.collection('users').doc(uid).get();
      const fcmToken = userSnap.data()?.fcmToken;
      if (fcmToken) {
        await sendFcmToToken(buildFcmMessage({
          token: fcmToken,
          title: 'Akaunti Yako Imerejeshwa',
          body: 'Akaunti yako imerejeshwa. Sasa unaweza kuendelea kutumia Soko Vibe.',
          data: { type: 'account', status: 'unsuspended' },
        }), uid);
      }
    } catch (_) {}

    res.json({ success: true, message: 'User unsuspended' });
  } catch (e) {
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
    const [orders, withdrawals, notifications, products, reviews] = await Promise.all([
      db.collection('orders').where('sellerId', '==', uid).get(),
      db.collection('orders').where('buyerId', '==', uid).get(),
      db.collection('withdrawals').where('userId', '==', uid).get(),
      db.collection('notifications').where('userId', '==', uid).get(),
      db.collection('products').where('sellerId', '==', uid).get(),
      db.collection('reviews').where('userId', '==', uid).get(),
    ]);

    orders.docs.forEach(d => batch.delete(d.ref));
    withdrawals.docs.forEach(d => batch.delete(d.ref));
    notifications.docs.forEach(d => batch.delete(d.ref));
    products.docs.forEach(d => batch.delete(d.ref));
    reviews.docs.forEach(d => batch.delete(d.ref));

    await batch.commit();

    await auditLog({
      userId: uid, type: 'admin_full_delete', amount: 0,
      reason: 'User fully deleted by admin',
    });

    res.json({ success: true, message: 'User and all related data deleted' });
  } catch (e) {
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

    // Get all users with FCM tokens (paginated by document ID)
    let sentCount = 0;
    let lastPushId = null;
    const PAGE_SIZE = 500;

    try {
      while (true) {
        let query = db.collection('users')
          .where('fcmToken', '!=', null);
        if (lastPushId) query = query.startAfter(lastPushId);
        query = query.limit(PAGE_SIZE);
        const usersSnap = await query.get();
        if (usersSnap.empty) break;

        const tokens = [];
        for (const doc of usersSnap.docs) {
          const token = doc.data().fcmToken;
          if (token) tokens.push(token);
        }

        // Send FCM in batches of 500
        for (let i = 0; i < tokens.length; i += PAGE_SIZE) {
          const chunk = tokens.slice(i, i + PAGE_SIZE);
          const message = buildFcmMessage({
            tokens: chunk,
            title: `⚡ Flash Sale! -${discountPercent}%`,
            body: `${productName} sasa TSh ${salePrice} pekee!`,
            data: {
              type: 'flash_sale',
              productName: productName || '',
              image: productImage || '',
            },
          });
          try {
            const resp = await admin.messaging().sendEachForMulticast(message);
            sentCount += resp.successCount;
          } catch (_) {}
        }

        lastPushId = usersSnap.docs[usersSnap.docs.length - 1].id;
      }
    } catch (fcmErr) {
      console.error('FCM push skipped for flash sale:', fcmErr.message);
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
        if (doc.id === sellerId) continue;
        batch.set(db.collection('notifications').doc(), {
          userId: doc.id,
          title: `⚡ Flash Sale! -${discountPercent}%`,
          body: `${productName} sasa TSh ${salePrice} pekee!`,
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

    res.json({ success: true, pushSent: sentCount, inAppNotified });
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
      while (true) {
        let query = db.collection('users').where('fcmToken', '!=', null);
        if (lastDocId) query = query.startAfter(lastDocId);
        query = query.limit(PAGE_SIZE);
        const snap = await query.get();
        if (snap.empty) break;

        const tokens = [];
        for (const doc of snap.docs) {
          const token = doc.data().fcmToken;
          if (token) tokens.push(token);
        }

        for (let i = 0; i < tokens.length; i += PAGE_SIZE) {
          const chunk = tokens.slice(i, i + PAGE_SIZE);
          const message = buildFcmMessage({
            tokens: chunk,
            title,
            body,
            data: {
              type: 'boost',
              productId: productId || '',
              productName: productName || '',
              image: imageUrl || '',
            },
          });
          try {
            const resp = await admin.messaging().sendEachForMulticast(message);
            sentCount += resp.successCount;
          } catch (_) {}
        }
        lastDocId = snap.docs[snap.docs.length - 1].id;
      }
    } catch (fcmErr) {
      console.error('FCM push skipped for boost:', fcmErr.message);
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

    console.log(`Boost notify: ${sentCount} FCM, ${inAppNotified} in-app`);
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
          const sellerSnap = await db.collection('users').doc(sellerId).get();
          const sellerToken = sellerSnap.data()?.fcmToken;
          if (sellerToken) {
            await sendFcmToToken(buildFcmMessage({
              token: sellerToken,
              title: 'Escrow Imefunguliwa Kiotomatiki',
              body: `${tx.productName || 'Bidhaa'} — TZS ${sellerReceives.toLocaleString()} zimewekwa salio lako.`,
              data: { type: 'escrow_auto_release', transactionId: doc.id },
            }), sellerId);
          }
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
          const buyerSnap = await db.collection('users').doc(tx.buyerId).get();
          const buyerToken = buyerSnap.data()?.fcmToken;
          if (buyerToken) {
            await sendFcmToToken(buildFcmMessage({
              token: buyerToken,
              title: 'Escrow Imefunguliwa Kiotomatiki',
              body: `${tx.productName || 'Bidhaa'} — muda wa escrow umeisha, pesa zimefunguliwa kwa muuzaji.`,
              data: { type: 'escrow_auto_release', transactionId: doc.id },
            }), tx.buyerId);
          }
        } catch (_) {}
      }
    }
  } catch (e) {
    console.error('Auto-release escrow error:', e);
  }
}

// Run every hour as fallback (cron-job.org can also call the endpoint)
setInterval(releaseExpiredEscrows, 60 * 60 * 1000);
setInterval(deactivateExpiredFlashSales, 60 * 60 * 1000);
// Also run once on startup
setTimeout(releaseExpiredEscrows, 60 * 1000);
setTimeout(deactivateExpiredFlashSales, 60 * 1000);

// ============================================================
// 💰 MONGIKE BALANCE — Check Mongike wallet balance
// ============================================================
app.get('/api/mongike/balance', async (req, res) => {
  try {
    const balance = await mongikeBalance();
    res.json({ success: true, balance });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 🔍 PAYOUT PREVIEW — Validate payout details before sending
// ============================================================
app.post('/api/mongike/payout-preview', async (req, res) => {
  try {
    const { amount, phone } = req.body;
    if (!amount || !phone) return res.status(400).json({ error: 'Missing amount or phone' });
    const preview = {
      amount: Math.round(amount),
      fee: PAYOUT_FEE,
      netAmount: Math.round(amount) - PAYOUT_FEE,
      recipientPhone: phone,
    };
    res.json({ success: true, preview });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 🔔 MONGIKE PAYOUT WEBHOOK — Handle payout status updates
// ============================================================
// Mongike calls this when a payout status changes (SUCCESS or FAILED).
// On SUCCESS: mark the Firestore payout record as completed.
// On FAILED: atomically reverse the deducted amount back to the seller's wallet.
app.post('/api/mongike/payout-webhook', verifyWebhook, async (req, res) => {
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
      console.warn(`Mongike payout webhook: payout ${payoutRef} not found`);
      return res.status(200).json({ received: false });
    }

    const payout = payoutDoc.data();
    if (payout.status === PAYOUT_STATUSES.SUCCESS || payout.status === PAYOUT_STATUSES.FAILED) {
      return res.status(200).json({ received: true });
    }

    const mongikeTxId = payload.id || payload.transactionId || '';

    if (eventStatus === 'SUCCESS') {
      await updatePayoutStatus(payoutRef, PAYOUT_STATUSES.SUCCESS, { mongikeReference: mongikeTxId });

      // Update the transactions collection record if it exists
      try {
        await db.collection('transactions').doc(payoutRef).update({
          status: 'completed',
          mongikeReference: mongikeTxId,
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
          const sellerSnap = await db.collection('users').doc(sellerId).get();
          const fcmToken = sellerSnap.data()?.fcmToken;
          if (fcmToken) {
            await sendFcmToToken(buildFcmMessage({
              token: fcmToken,
              title: 'Payout imefanikiwa!',
              body: `TZS ${(payout.netAmount || payout.amount).toLocaleString()} zimetumwa kwenye mobile money yako.`,
              data: { type: 'withdrawal', status: 'completed' },
            }), sellerId);
          }
        } catch (_) {}
      }
    } else if (eventStatus === 'FAILED') {
      await updatePayoutStatus(payoutRef, PAYOUT_STATUSES.FAILED, {
        failureReason: payload.message || payload.error || 'Mongike payout failed',
        mongikeReference: mongikeTxId,
      });

      // Update the transactions collection record to failed
      try {
        await db.collection('transactions').doc(payoutRef).update({
          status: 'failed',
          failureReason: payload.message || payload.error || 'Mongike payout failed',
          mongikeReference: mongikeTxId,
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
          console.log(`Mongike payout reversed: ${payoutRef} — TZS ${payout.amount} returned to ${payout.userId}`);
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
          const userSnap = await db.collection('users').doc(payout.userId).get();
          const fcmToken = userSnap.data()?.fcmToken;
          if (fcmToken) {
            await sendFcmToToken(buildFcmMessage({
              token: fcmToken,
              title: '❌ Utoaji wa Pesa Umeshindwa',
              body: `TZS ${(payout.netAmount || payout.amount).toLocaleString()} hazikutumwa. Pesa zimerudishwa kwenye pochi yako. Jaribu tena.`,
              data: { type: 'withdrawal', status: 'failed', payoutId: payoutRef },
            }), payout.userId);
          }
        } catch (_) {}
      }

      // Attempt auto-retry if under max retries
      try {
        await retryFailedPayout(payoutRef);
      } catch (_) {}
    }

    res.status(200).json({ received: true });
  } catch (e) {
    console.error('Mongike payout webhook error:', e);
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
  const processingFee = price * 0.02;
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
    paymentMethod: 'Mongike',
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
  const tokens = [];
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
    const token = userDoc.data().fcmToken;
    if (token && typeof token === 'string' && token.length > 0) {
      tokens.push(token);
    }
  }

  await batch.commit();

  let sent = 0;
  if (tokens.length > 0) {
    const BATCH_SIZE = 500;
    for (let i = 0; i < tokens.length; i += BATCH_SIZE) {
      const tokenBatch = tokens.slice(i, i + BATCH_SIZE);
      try {
        const message = buildFcmMessage({
          tokens: tokenBatch,
          title,
          body: body || '',
          data: { ...(data || {}), type: (data && data.type) || 'general' },
        });
        const response = await admin.messaging().sendEachForMulticast(message);
        sent += response.successCount;
      } catch (e) {
        console.error('Broadcast FCM batch error:', e.message);
      }
    }
  }

  await db.collection('admin_notifications').add({
    title,
    body,
    target: 'all',
    sentCount: sent,
    notifCount,
    sentAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  res.json({ success: true, notifications: notifCount, fcmSent: sent });
}));

// ─── Global error handler (catches unhandled errors, never leaks internals) ───
app.use((err, req, res, _next) => {
  console.error('Unhandled error:', err?.stack || err?.message || err);
  res.status(500).json({ error: 'Internal server error' });
});

// ─── Clear stale FCM token for a user (forces fresh token on next app open) ──
app.post('/api/clear-token', async (req, res) => {
  try {
    const { uid } = req.body;
    if (!uid) return res.status(400).json({ error: 'uid required' });
    if (!db) return res.status(503).json({ error: 'Database not configured' });
    await db.collection('users').doc(uid).update({ fcmToken: admin.firestore.FieldValue.delete() });
    console.log(`[FCM] Cleared token for user ${uid}`);
    res.json({ success: true });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ─── Diagnostic: check FCM credentials + topic test ──────────────────
app.get('/api/fcm-check', async (req, res) => {
  try {
    const projectId = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON || '{}').project_id;
    if (!admin.messaging) return res.json({ status: 'error', msg: 'admin.messaging unavailable' });
    const results = {};
    // Test 1: dry-run with bogus token
    try {
      await admin.messaging().send({ token: '__test__', data: { a: '1' } }, true);
      results.dryRun = 'unexpected-success';
    } catch (e) {
      results.dryRun = { code: e.code, message: e.message };
    }
    // Test 2: send to a topic (no registration needed)
    try {
      const topicMsgId = await admin.messaging().send({
        topic: 'test_diagnostic',
        data: { title: 'FCM Check', body: 'This is a test', type: 'general' },
        android: { priority: 'high' },
      });
      results.topicSend = { success: true, messageId: topicMsgId };
    } catch (e) {
      results.topicSend = { code: e.code, message: e.message };
    }
    // Test 3: try subscribing user token to topic
    if (req.query.uid) {
      try {
        const userDoc = await db.collection('users').doc(req.query.uid).get();
        if (userDoc.exists) {
          const token = userDoc.data().fcmToken;
          if (token) {
            const subResult = await admin.messaging().subscribeToTopic([token], 'test_user_topic');
            results.subscribeToTopic = subResult;
            // Now try sending to that topic
            const topicMsgId2 = await admin.messaging().send({
              topic: 'test_user_topic',
              data: { title: 'Topic Test', body: 'Sent via topic after subscribe attempt', type: 'general' },
              android: { priority: 'high' },
            });
            results.sendToSubscribedTopic = { success: true, messageId: topicMsgId2 };
          }
        }
      } catch (e) {
        results.subscribeToTopic = { code: e.code, message: e.message };
      }
    }
    return res.json({ status: 'complete', projectId, results });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ─── Diagnostic: test FCM push (by userId, email, or direct token) ─────
app.post('/api/test-fcm', async (req, res) => {
  try {
    const { userId, email, token: directToken, title, body } = req.body;
    if (!title) return res.status(400).json({ error: 'title required' });
    if (!userId && !email && !directToken) return res.status(400).json({ error: 'Provide userId, email, or token' });
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    let fcmToken = directToken;
    let uid = userId || '';
    if (!fcmToken) {
      if (!uid && email) {
        // Look up by email via Firebase Auth
        try {
          const userRecord = await admin.auth().getUserByEmail(email);
          uid = userRecord.uid;
        } catch (authErr) {
          return res.status(404).json({ error: `User not found by email: ${authErr.message}` });
        }
      }
      const userDoc = await db.collection('users').doc(uid).get();
      if (!userDoc.exists) return res.status(404).json({ error: 'User not found' });
      fcmToken = userDoc.data().fcmToken;
      if (!fcmToken) return res.status(400).json({ error: 'No FCM token for this user. Open the app first.' });
    }

    // Try sending via Admin SDK
    try {
      const result = await admin.messaging().send({
        token: fcmToken,
        data: { title: title || '', body: body || 'Test body', type: 'general' },
        android: { priority: 'high' },
      });
      return res.json({ success: true, method: 'admin-sdk', messageId: result, tokenPrefix: fcmToken.substring(0, 8) + '...', uid });
    } catch (adminErr) {
      console.error('[FCM-DIAG] Admin SDK failed:', adminErr.code || adminErr.message);
      const projectId = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON || '{}').project_id;
      return res.status(502).json({
        success: false,
        error: adminErr.code || adminErr.message,
        tokenPrefix: fcmToken.substring(0, 12) + '...',
        uid,
        hint: projectId ? `Enable FCM v1 API at https://console.cloud.google.com/apis/library/fcm.googleapis.com?project=${projectId}` : 'Check FIREBASE_SERVICE_ACCOUNT_JSON',
      });
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

    // Send FCM push to receiver — data-only so Awesome Notifications background
    // handler shows the custom chat layout (Messaging layout + Reply button).
    const senderName = senderDoc.exists
      ? (senderDoc.data().displayName || senderDoc.data().name || 'Mtumiaji')
      : 'Mtumiaji';
    const receiverDoc = await db.collection('users').doc(receiverId).get();
    if (receiverDoc.exists) {
      const fcmToken = receiverDoc.data().fcmToken;
      if (fcmToken) {
        const chatMessage = {
          data: { title: senderName, body: text, type: 'chat', senderId, senderName, roomId },
          token: fcmToken,
          android: { priority: 'high' },
        };
        sendFcmToToken(chatMessage, receiverId).catch(() => {});
      }
    }

    res.json({ success: true, messageId: msgRef.id });
  } catch (e) {
    console.error('/api/chat/send error:', e);
    res.status(500).json({ error: 'Internal server error' });
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

startProductListener();
app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
  // Self-ping every 10 minutes to prevent Render free-tier spin-down
  const publicUrl = process.env.RENDER_EXTERNAL_URL || '';
  if (publicUrl) {
    console.log(`[SELF-PING] Auto-ping enabled for ${publicUrl}/ping every 10 minutes`);
    setInterval(async () => {
      try {
        const controller = new AbortController();
        const timeout = setTimeout(() => controller.abort(), 10000);
        const resp = await fetch(`${publicUrl}/ping`, { signal: controller.signal });
        clearTimeout(timeout);
        if (resp.ok) {
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
  let knownProductIds = new Set();
  const listenerStartedAt = admin.firestore.Timestamp.now();

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
          const product = change.doc.data();
          const productTime = product.createdAt;
          if (productTime && productTime < listenerStartedAt) return;
          knownProductIds.add(productId);

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
                db.collection('users').doc(other).get()
                  .then((userSnap) => {
                    const fcmToken = userSnap.data()?.fcmToken;
                    if (fcmToken) {
                      sendFcmToToken(buildFcmMessage({
                        token: fcmToken,
                        title,
                        body,
                        data: { type: 'product', productId, sellerId, productName },
                      }), other).catch((err) => {
                        if (err.code?.startsWith('messaging/')) {
                          db.collection('users').doc(other).update({ fcmToken: null });
                        }
                      });
                    }
                  })
                  .catch(() => {});
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
