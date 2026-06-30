require('dotenv').config();
const express = require('express');
const cors = require('cors');
const crypto = require('crypto');
const admin = require('firebase-admin');
const nodemailer = require('nodemailer');
const helmet = require('helmet');

const app = express();

const REQUEST_TIMEOUT = 20000; // 20 seconds

// Security headers
app.use(helmet());

// Tight CORS — only allow the Flutter app origins
const ALLOWED_ORIGINS = [
  'https://soko-langu-server-production.up.railway.app',
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

function buildFcmApns(title, body) {
  return {
    headers: { 'apns-priority': '10' },
    payload: {
      aps: {
        alert: { title: title || '', body: body || '' },
        sound: 'soko_notification.wav',
        badge: 1,
        'content-available': 1,
      },
    },
  };
}

/**
 * Builds a standard FCM message with a `notification` payload to ensure
 * the OS displays it in the system tray when the app is in the background or killed.
 * The `data` payload carries additional info for the app to handle when opened.
 */
function buildFcmMessage({ token, tokens, title, body, data = {} }) {
  const msg = {
    notification: {
      title: title || 'Soko Vibe',
      body: body || '',
    },
    data: buildFcmDataPayload(title, body, data),
    android: { 
      priority: 'high',
    },
    apns: buildFcmApns(title, body), // iOS can still use the custom APNS payload
  };
  if (token) msg.token = token;
  if (tokens && tokens.length) msg.tokens = tokens;
  return msg;
}

async function sendFcmToToken(message, userIdForCleanup = null) {
  try {
    return await admin.messaging().send(message);
  } catch (e) {
    if (userIdForCleanup && db &&
        (e.code === 'messaging/registration-token-not-registered' ||
         e.code === 'messaging/invalid-registration-token')) {
      await db.collection('users').doc(userIdForCleanup).update({ fcmToken: null });
    }
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

// OTP brute force protection — max 3 attempts per email per 15 minutes
const otpHits = new Map();
const OTP_WINDOW = 15 * 60 * 1000;
const OTP_MAX = 3;

function otpRateLimit(req, res, next) {
  const email = (req.body?.email || '').toLowerCase().trim();
  if (!email) return next();
  const now = Date.now();
  if (!otpHits.has(email)) otpHits.set(email, []);
  const hits = otpHits.get(email).filter(t => now - t < OTP_WINDOW);
  hits.push(now);
  otpHits.set(email, hits);
  if (hits.length > OTP_MAX) {
    return res.status(429).json({ error: 'Too many attempts. Try again later.' });
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
    if (secret) {
      console.warn(`Webhook secret mismatch from IP: ${req.ip}`);
      return res.status(200).json({ received: false });
    }
    console.warn(`Webhook called without secret from IP: ${req.ip} — accepting anyway`);
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

function isValidEmail(email) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
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
      if (email === 'admin@soko-langu.com' || email === 'admin@soko-vibe.com') {
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

// ─── Email transporter (nodemailer) ───
const SMTP_HOST = process.env.SMTP_HOST || '';
const SMTP_PORT = process.env.SMTP_PORT || '';
const SMTP_USER = process.env.SMTP_USER || '';
const SMTP_PASS = process.env.SMTP_PASS || '';
const SMTP_FROM = process.env.SMTP_FROM || '';
const SMTP_SECURE = process.env.SMTP_SECURE || '';

let transporter;
if (SMTP_HOST && SMTP_USER && SMTP_PASS) {
  transporter = nodemailer.createTransport({
    host: SMTP_HOST,
    port: parseInt(SMTP_PORT),
    secure: SMTP_SECURE === 'true',
    auth: { user: SMTP_USER, pass: SMTP_PASS },
  });
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

const PLATFORM_COMMISSION_PERCENT = 0.04; // 4% platform commission
const MIN_WITHDRAWAL = 5000;          // Minimum withdrawal TZS 5,000

// ─── ClickPesa Fees ───
const CLICKPESA_PAYOUT_FEE_TIERS = [
  { min: 100, max: 999, fee: 52 },
  { min: 1000, max: 1999, fee: 72 },
  { min: 2000, max: 2999, fee: 104 },
  { min: 3000, max: 3999, fee: 116 },
  { min: 4000, max: 4999, fee: 168 },
  { min: 5000, max: 6999, fee: 234 },
  { min: 7000, max: 7999, fee: 360 },
  { min: 8000, max: 9999, fee: 430 },
  { min: 10000, max: 14999, fee: 642 },
  { min: 15000, max: 19999, fee: 680 },
  { min: 20000, max: 29999, fee: 700 },
  { min: 30000, max: 39999, fee: 980 },
  { min: 40000, max: 49999, fee: 1038 },
  { min: 50000, max: 99999, fee: 1460 },
  { min: 100000, max: 199999, fee: 1868 },
  { min: 200000, max: 299999, fee: 2220 },
  { min: 300000, max: 399999, fee: 3180 },
  { min: 400000, max: 499999, fee: 3764 },
  { min: 500000, max: 599999, fee: 4672 },
  { min: 600000, max: 699999, fee: 5712 },
  { min: 700000, max: 799999, fee: 6560 },
  { min: 800000, max: 899999, fee: 7800 },
  { min: 900000, max: 1000000, fee: 8508 },
  { min: 1000001, max: 3000000, fee: 9346 },
  { min: 3000001, max: 5000000, fee: 9890 },
];

const CLICKPESA_USSD_PUSH_FEE_TIERS = [
  { min: 500, max: 999, fee: 54 },
  { min: 1000, max: 1999, fee: 92 },
  { min: 2000, max: 2999, fee: 124 },
  { min: 3000, max: 3999, fee: 230 },
  { min: 4000, max: 4999, fee: 380 },
  { min: 5000, max: 9999, fee: 580 },
  { min: 10000, max: 19999, fee: 920 },
  { min: 20000, max: 39999, fee: 1150 },
  { min: 40000, max: 49999, fee: 1572 },
  { min: 50000, max: 99999, fee: 2136 },
  { min: 100000, max: 199999, fee: 3240 },
  { min: 200000, max: 299999, fee: 3660 },
  { min: 300000, max: 399999, fee: 4080 },
  { min: 400000, max: 499999, fee: 4340 },
  { min: 500000, max: 599999, fee: 4820 },
  { min: 600000, max: 799999, fee: 5230 },
  { min: 800000, max: 999999, fee: 6146 },
  { min: 1000000, max: 1999999, fee: 7210 },
  { min: 2000000, max: 3000000, fee: 7960 },
];

function getClickPesaUssdPushFee(amount) {
  const tier = CLICKPESA_USSD_PUSH_FEE_TIERS.find(t => amount >= t.min && amount <= t.max);
  return tier ? tier.fee : 7960;
}

function getClickPesaPayoutFee(amount) {
  const tier = CLICKPESA_PAYOUT_FEE_TIERS.find(t => amount >= t.min && amount <= t.max);
  return tier ? tier.fee : 9890;
}

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
  const extId = payoutId.replace(/[^a-zA-Z0-9]/g, '').slice(0, 20);

  const available = await getClickPesaBalance();
  if (netAmount > available) {
    await updatePayoutStatus(payoutId, PAYOUT_STATUSES.FAILED, {
      failureReason: `Insufficient ClickPesa balance: TZS ${available} available, need TZS ${netAmount}`,
      clickpesaReference: '',
    });
    throw new Error(`Insufficient ClickPesa balance: TZS ${available} available, need TZS ${netAmount}`);
  }

  const result = await clickPesaDisburse({ amount: netAmount, phone, externalId: extId });

  const clickpesaRef = result.id || result.transactionId || result.data?.transactionId || '';
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

// ─── ClickPesa Configuration ───
const CLICKPESA_BASE_URL = 'https://api.clickpesa.com/third-parties';
const CLICKPESA_CLIENT_ID = process.env.CLICKPESA_CLIENT_ID || '';
const CLICKPESA_API_KEY = process.env.CLICKPESA_API_KEY || '';
const CLICKPESA_CHECKSUM_KEY = process.env.CLICKPESA_CHECKSUM_KEY || '';

let clickpesaToken = null;
let clickpesaTokenExpiry = 0;

/** Canonicalize object: sort keys recursively */
function canonicalize(obj) {
  if (obj === null || typeof obj !== 'object') return obj;
  if (Array.isArray(obj)) return obj.map(canonicalize);
  return Object.keys(obj).sort().reduce((acc, k) => { acc[k] = canonicalize(obj[k]); return acc; }, {});
}

/** HMAC-SHA256 checksum for ClickPesa payloads */
function createClickPesaChecksum(payload) {
  const canonical = canonicalize(payload);
  const json = JSON.stringify(canonical);
  const hmac = crypto.createHmac('sha256', CLICKPESA_CHECKSUM_KEY);
  hmac.update(json);
  return hmac.digest('hex');
}

/** Get ClickPesa JWT token (cached, auto-refresh) */
async function getClickPesaToken() {
  if (clickpesaToken && Date.now() < clickpesaTokenExpiry) return clickpesaToken;

  const resp = await fetch(`${CLICKPESA_BASE_URL}/generate-token`, {
    method: 'POST',
    headers: {
      'client-id': CLICKPESA_CLIENT_ID,
      'api-key': CLICKPESA_API_KEY,
    },
  });

  if (!resp.ok) {
    const errText = await resp.text();
    throw new Error(`ClickPesa auth failed (${resp.status}): ${errText}`);
  }

  const data = await resp.json();
  clickpesaToken = data.token;
  const expiresIn = 55 * 60 * 1000; // 55 min cache (token valid 1 hr)
  clickpesaTokenExpiry = Date.now() + expiresIn;
  return clickpesaToken;
}

/** Format phone to 2557XXXXXXXX (ClickPesa format) */
function toClickPesaPhone(phone) {
  return '255' + phone.replace(/[^0-9]/g, '').slice(-9);
}

/** USSD Push — send payment prompt to customer's phone */
async function clickPesaMobileCheckout({ amount, phone, externalId }) {
  const token = await getClickPesaToken();
  const phoneNumber = toClickPesaPhone(phone);
  let orderReference = externalId.replace(/[^a-zA-Z0-9]/g, '').slice(0, 20);
  const payload = { amount: String(Math.round(amount)), orderReference, phoneNumber, currency: 'TZS' };
  payload.checksum = createClickPesaChecksum(payload);

  const resp = await fetch(`${CLICKPESA_BASE_URL}/payments/initiate-ussd-push-request`, {
    method: 'POST',
    headers: { 'Authorization': token, 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  });

  const text = await resp.text();
  let data = {};
  try { data = JSON.parse(text); } catch (_) {}
  if (!resp.ok) {
    throw new Error(data.message || data.error || 'ClickPesa checkout failed');
  }
  return data;
}

/** Mobile money payout — disburse funds to recipient */
async function clickPesaDisburse({ amount, phone, externalId }) {
  const token = await getClickPesaToken();
  const phoneNumber = toClickPesaPhone(phone);
  const payload = { amount: Math.round(amount), orderReference: externalId.replace(/[^a-zA-Z0-9]/g, ''), phoneNumber, currency: 'TZS' };
  payload.checksum = createClickPesaChecksum(payload);

  const resp = await fetch(`${CLICKPESA_BASE_URL}/payouts/create-mobile-money-payout`, {
    method: 'POST',
    headers: { 'Authorization': token, 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  });

  const text = await resp.text();
  let data = {};
  try { data = JSON.parse(text); } catch (_) {}
  if (!resp.ok) {
    throw new Error(data.message || data.error || 'ClickPesa disbursement failed');
  }
  return data;
}

/** Get ClickPesa account balance — returns TZS available balance (number) */
async function getClickPesaBalance() {
  const token = await getClickPesaToken();
  const resp = await fetch(`${CLICKPESA_BASE_URL}/account/balance`, {
    method: 'GET',
    headers: { 'Authorization': token, 'Content-Type': 'application/json' },
  });
  const text = await resp.text();
  let data = {};
  try { data = JSON.parse(text); } catch (_) {}
  if (!resp.ok) throw new Error(data.message || data.error || 'Failed to fetch balance');
  // Response format: { balances: [{ currency: "TZS", balance: 0 }, ...] }
  const tzsBalance = (data.balances || []).find(b => b.currency === 'TZS');
  return tzsBalance ? tzsBalance.balance : 0;
}

/** Preview/validate a mobile money payout before sending */
async function clickPesaPayoutPreview({ amount, phone, externalId }) {
  const token = await getClickPesaToken();
  const phoneNumber = toClickPesaPhone(phone);
  const payload = { amount: Math.round(amount), orderReference: externalId.replace(/[^a-zA-Z0-9]/g, ''), phoneNumber, currency: 'TZS' };
  payload.checksum = createClickPesaChecksum(payload);

  const resp = await fetch(`${CLICKPESA_BASE_URL}/payouts/preview-mobile-money-payout`, {
    method: 'POST',
    headers: { 'Authorization': token, 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  });

  const text = await resp.text();
  let data = {};
  try { data = JSON.parse(text); } catch (_) {}
  if (!resp.ok) throw new Error(data.message || data.error || 'Payout preview failed');
  return data;
}

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
    const { productId, tier, amount, durationDays, phone, userId } = req.body;
    if (!productId || !tier || !phone) {
      return res.status(400).json({ error: 'Missing required fields (productId, tier, phone)' });
    }

    const tierConfig = BOOST_TIERS[tier];
    if (!tierConfig) {
      return res.status(400).json({ error: 'Invalid boost tier' });
    }

    const order_id = `boost_${Date.now()}`;

    const result = await clickPesaMobileCheckout({
      amount: tierConfig.price,
      phone,
      provider: 'Mpesa',
      externalId: order_id,
    });

    if (db) {
      await db.collection('transactions').doc(order_id).set({
        type: 'boost',
        productId,
        tier: tier.toLowerCase(),
        amount: tierConfig.price,
        durationDays: tierConfig.days,
        userId: userId || '',
        buyerPhone: phone,
        clickpesaTransactionId: result.id || result.transactionId || result.data?.transactionId || '',
        status: 'pending',
        paymentMethod: 'ClickPesa',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    res.json({
      order_id,
      clickpesaTransactionId: result.id || result.transactionId || result.data?.transactionId || '',
      message: 'Tuma PIN yako kwenye simu ili kukamilisha malipo.',
    });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
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

    const fcmToken = userDoc.data().fcmToken;
    if (!fcmToken) return res.json({ sent: false, reason: 'No FCM token' });

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
      if (e.code === 'messaging/registration-token-not-registered' ||
          e.code === 'messaging/invalid-registration-token') {
        return res.json({ sent: false, reason: 'Stale token cleaned up' });
      }
      throw e;
    }

    // Also write in-app notification to Firestore
    await db.collection('notifications').add({
      userId,
      title,
      body: body || '',
      data: data || {},
      isRead: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

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
// 🔐 FORGOT PASSWORD — SEND OTP
// ============================================================
app.post('/api/send-otp', otpRateLimit, async (req, res) => {
  try {
    const { email } = req.body;
    if (!email) return res.status(400).json({ error: 'Email is required' });
    if (!isValidEmail(email)) return res.status(400).json({ error: 'Invalid email format' });
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    // Check if user exists in Firebase Auth
    let userRecord;
    try {
      userRecord = await admin.auth().getUserByEmail(email);
    } catch {
      return res.status(404).json({ error: 'No account found with this email' });
    }

    if (!transporter) {
      return res.status(503).json({ error: 'Email service not configured. Contact admin.' });
    }

    // Generate 6-digit OTP
    const otp = Math.floor(100000 + Math.random() * 900000).toString();
    const hashed = crypto.createHash('sha256').update(otp).digest('hex');
    const expiresAt = Date.now() + 10 * 60 * 1000; // 10 minutes

    // Save to Firestore
    await db.collection('password_resets').doc(email.toLowerCase()).set({
      otpHash: hashed,
      expiresAt,
      used: false,
      uid: userRecord.uid,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Send email
    try {
      await transporter.sendMail({
        from: SMTP_FROM,
        to: email,
        subject: '🔐 Soko Vibe — Reset Your Password',
        html: `
          <!DOCTYPE html>
          <html>
          <head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"></head>
          <body style="margin:0; padding:0; background-color:#f4f7f6; font-family: 'Segoe UI', Arial, sans-serif;">
            <table width="100%" cellpadding="0" cellspacing="0" style="background-color:#f4f7f6; padding:20px 0;">
              <tr><td align="center">
                <table width="480" cellpadding="0" cellspacing="0" style="background-color:#ffffff; border-radius:16px; overflow:hidden; box-shadow:0 4px 24px rgba(0,0,0,0.08);">
                  <!-- Header -->
                  <tr>
                    <td style="background: linear-gradient(135deg, #1B4332 0%, #2D6A4F 50%, #40916C 100%); padding:32px 24px; text-align:center;">
                      <div style="font-size:36px; margin-bottom:8px;">🏪</div>
                      <h1 style="color:#ffffff; margin:0; font-size:24px; font-weight:700; letter-spacing:1px;">SOKO VIBE</h1>
                      <p style="color:#95D5B2; margin:4px 0 0; font-size:13px;">Tanzania's Trusted Marketplace</p>
                    </td>
                  </tr>
                  <!-- Body -->
                  <tr>
                    <td style="padding:32px 24px;">
                      <h2 style="color:#1B4332; font-size:20px; margin:0 0 8px;">Password Reset Request</h2>
                      <p style="color:#555; font-size:14px; line-height:1.6; margin:0 0 20px;">
                        Someone requested to reset the password for your Soko Vibe account. 
                        Use the One-Time Password (OTP) below to proceed.
                      </p>
                      <!-- OTP Box -->
                      <div style="background:#F0F9F1; border:2px dashed #2D6A4F; border-radius:12px; padding:20px; text-align:center; margin-bottom:20px;">
                        <p style="color:#2D6A4F; font-size:13px; font-weight:600; margin:0 0 10px; text-transform:uppercase; letter-spacing:1px;">Your OTP</p>
                        <div style="font-size:36px; font-weight:800; color:#1B4332; letter-spacing:12px; font-family:'Courier New', monospace;">
                          ${otp}
                        </div>
                        <p style="color:#888; font-size:12px; margin:12px 0 0;">Valid for 10 minutes</p>
                      </div>
                      <!-- Instructions -->
                      <div style="background:#FFF8E1; border-left:4px solid #FFA000; padding:12px 16px; border-radius:8px; margin-bottom:20px;">
                        <p style="color:#795548; font-size:13px; margin:0; line-height:1.5;">
                          <strong>⚡ Didn't request this?</strong> Ignore this email. Your password will not be changed.
                        </p>
                      </div>
                      <p style="color:#999; font-size:12px; line-height:1.5; margin:0; text-align:center;">
                        Soko Vibe &bull; Tanzania<br>
                        Need help? Contact us through the app.
                      </p>
                    </td>
                  </tr>
                  <!-- Footer -->
                  <tr>
                    <td style="background:#1B4332; padding:16px 24px; text-align:center;">
                      <p style="color:#95D5B2; font-size:11px; margin:0;">
                        &copy; ${new Date().getFullYear()} Soko Vibe. All rights reserved.
                      </p>
                    </td>
                  </tr>
                </table>
              </td></tr>
            </table>
          </body>
          </html>
        `,
      });
    } catch (mailErr) {
      return res.status(500).json({ error: 'Failed to send email. Try again.' });
    }

    res.json({ sent: true, message: 'OTP sent to your email' });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 🔐 VERIFY OTP
// ============================================================
app.post('/api/verify-otp', otpRateLimit, async (req, res) => {
  try {
    const { email, otp } = req.body;
    if (!email || !otp) return res.status(400).json({ error: 'Email and OTP are required' });
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const doc = await db.collection('password_resets').doc(email.toLowerCase()).get();
    if (!doc.exists) return res.status(400).json({ error: 'No OTP found. Request a new one.' });

    const data = doc.data();
    if (data.used) return res.status(400).json({ error: 'OTP already used' });
    if (Date.now() > data.expiresAt) return res.status(400).json({ error: 'OTP expired. Request a new one.' });

    const hashed = crypto.createHash('sha256').update(otp).digest('hex');
    if (hashed !== data.otpHash) return res.status(400).json({ error: 'Invalid OTP' });

    // Mark as used
    await doc.ref.update({ used: true });

    res.json({ valid: true, uid: data.uid });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 🔐 RESET PASSWORD AFTER OTP
// ============================================================
app.post('/api/reset-password-after-otp', async (req, res) => {
  try {
    const { email, newPassword } = req.body;
    if (!email || !newPassword) {
      return res.status(400).json({ error: 'Email and new password are required' });
    }
    if (newPassword.length < 6) {
      return res.status(400).json({ error: 'Password must be at least 6 characters' });
    }
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const doc = await db.collection('password_resets').doc(email.toLowerCase()).get();
    if (!doc.exists) return res.status(400).json({ error: 'No verified OTP found' });

    const data = doc.data();
    if (!data.used) return res.status(400).json({ error: 'OTP not yet verified' });

    // Update password via Firebase Admin SDK
    await admin.auth().updateUser(data.uid, { password: newPassword });

    // Generate a custom token so user can sign in automatically
    const customToken = await admin.auth().createCustomToken(data.uid);

    // Clean up the OTP doc
    await doc.ref.delete();

    res.json({ success: true, customToken });
  } catch (e) {
    if (e.code === 'auth/claims-too-large') {
      return res.status(400).json({ error: 'Token claims too large' });
    }
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

    let sellerId, sellerReceives, productName, productPrice, escrowReleased, platformFee;

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

    // Auto-payout to seller's phone (only if autoPayout is enabled)
    if (sellerReceives > 0) {
      try {
        const sellerUserDoc = await db.collection('users').doc(sellerId).get();
        if (!sellerUserDoc.exists) return;
        const sellerData = sellerUserDoc.data();
        const autoPayout = sellerData.autoPayout !== false; // default true

        if (!autoPayout) {
          console.log(`Auto-payout skipped for seller ${sellerId}: manual mode`);
          return;
        }

        const sellerPhone = sellerData.phone;
        if (!sellerPhone) return;

        const clickPesaFee = getClickPesaPayoutFee(sellerReceives);
        const netPayout = sellerReceives - clickPesaFee;
        if (netPayout <= 0) return;

        try {
          const payout = await processPayout({
            userId: sellerId, phone: sellerPhone,
            amount: sellerReceives, fee: clickPesaFee, netAmount: netPayout,
            source: `escrow_${orderId}`,
            type: 'escrow_release',
            metadata: { orderId, sellerId, productName },
          });

          await db.collection('users').doc(sellerId).update({
            sellerBalance: admin.firestore.FieldValue.increment(-sellerReceives),
          });
        } catch (payoutErr) {
          // If ClickPesa payout fails, set status to failed_retry and alert admin
          console.error('ClickPesa escrow auto-payout failed:', payoutErr);
          await ref.update({
            payoutStatus: 'failed_retry',
            payoutError: payoutErr.message || 'ClickPesa API error',
            payoutFailedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          // Alert admin
          await db.collection('notifications').add({
            userId: 'admin',
            title: '⚠️ Auto-payout Imeshindwa',
            body: `Escrow ${orderId} — TZS ${sellerReceives.toLocaleString()} kwa ${sellerId}. ClickPesa error. Pesa zipo kwenye sellerBalance.`,
            isRead: false,
            data: { type: 'failed_retry', transactionId: orderId },
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        }
      } catch (payoutErr) {
        console.error('Escrow auto-payout error:', payoutErr);
      }
    }

    // Notify seller
    await db.collection('notifications').add({
      userId: sellerId,
      title: 'Escrow Imefunguliwa!',
      body: `Mnunuzi amethibitisha upokeaji wa ${productName}. TZS ${sellerReceives.toLocaleString()} zimewekwa kwenye salio lako.`,
      isRead: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    // Send FCM to seller
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

    res.json({ success: true, message: 'Escrow released. Seller balance credited.' });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});
// ============================================================
// 🔒 ESCROW — Admin force release
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

    // Notify seller
    await db.collection('notifications').add({
      userId: tx.sellerId,
      title: '\u2696\uFE0F Mgogoro Umefunguliwa',
      body: `Mnunuzi amefungua mgogoro kwa ${tx.productName || 'Bidhaa'}. Tafadhali wasilisha ushahidi wako.`,
      isRead: false,
      data: { type: 'disputed', transactionId: orderId },
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Notify buyer
    await db.collection('notifications').add({
      userId,
      title: '\u2696\uFE0F Mgogoro Umefunguliwa',
      body: `Tumepokea mgogoro wako kwa ${tx.productName || 'Bidhaa'}. Admin atakagua na kutoa uamuzi.`,
      isRead: false,
      data: { type: 'disputed', transactionId: orderId },
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Alert admin
    await db.collection('notifications').add({
      userId: 'admin',
      title: '\u2696\uFE0F Mgogoro Mpya Unahitaji Uamuzi',
      body: `Mgogoro kwa ${tx.productName || 'Bidhaa'} \u2014 ${orderId}. Pitia ushahidi na toa uamuzi.`,
      isRead: false,
      data: { type: 'disputed', transactionId: orderId },
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

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
      await db.collection('notifications').add({
        userId: sellerId,
        title: '\u2696\uFE0F Uamuzi wa Mgogoro',
        body: `Admin ameamua pesa zikutolee. ${note || ''}`,
        isRead: false,
        data: { type: 'dispute_resolved', transactionId: orderId },
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

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
      let gatewayFee = 0;
      try { gatewayFee = getClickPesaPayoutFee(refundAmount); } catch (_) {}

      // Send full refund to buyer
      try {
        await clickPesaDisburse({ amount: refundAmount, phone: buyerPhone, externalId: `refund_${orderId}` });
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
          // If seller has balance, deduct the gateway fee from it
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
    const clickPesaFee = getClickPesaPayoutFee(sellerReceives);
    const netPayout = sellerReceives - clickPesaFee;

    if (netPayout <= 0) {
      // Nothing to pay out — just clear the flag
      await txDoc.ref.update({
        payoutStatus: admin.firestore.FieldValue.delete(),
        payoutError: admin.firestore.FieldValue.delete(),
        payoutFailedAt: admin.firestore.FieldValue.delete(),
        payoutRetriedAt: admin.firestore.FieldValue.serverTimestamp(),
        payoutRetryNote: 'Net payout was zero, skipped ClickPesa',
      });
      return res.json({ success: true, message: 'Payout skipped: net amount <= 0. Flag cleared.' });
    }

    await processPayout({
      userId: sellerId, phone: sellerPhone,
      amount: sellerReceives, fee: clickPesaFee, netAmount: netPayout,
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
// 🛒 MARKETPLACE — Initiate product purchase payment via ClickPesa
// ============================================================
app.post('/api/create-marketplace-payment-link', paymentRateLimit, async (req, res) => {
  try {
    const { productPrice, productName, productId, sellerId, sellerName, email, phone, buyerId, deliveryType } = req.body;
    if (!productPrice || !productId || !sellerId || !phone) {
      return res.status(400).json({ error: 'Missing required fields' });
    }

    // Fraud checks
    if (buyerId) {
      const suspended = await checkSuspended(buyerId);
      if (suspended) return res.status(403).json({ error: 'Account suspended' });

      const isDuplicate = await checkDuplicatePayment(productId, buyerId);
      if (isDuplicate) return res.status(400).json({ error: 'A pending payment already exists for this product' });

      const withinLimit = await checkDailyLimit(buyerId, productPrice);
      if (!withinLimit) return res.status(400).json({ error: `Daily purchase limit of TZS ${MAX_DAILY_SALE_AMOUNT.toLocaleString()} exceeded` });
    }

    const order_id = `p${Date.now().toString(36)}${buyerId ? buyerId.substring(0, 4) : 'x'}`;

    const result = await clickPesaMobileCheckout({
      amount: productPrice,
      phone,
      provider: 'Mpesa',
      externalId: order_id,
    });

    if (db) {
      let buyerName = '';
      if (buyerId) {
        try {
          const buyerDoc = await db.collection('users').doc(buyerId).get();
          buyerName = buyerDoc.data()?.name || buyerDoc.data()?.displayName || '';
        } catch (_) {}
      }
      await db.collection('transactions').doc(order_id).set({
        type: 'purchase',
        productId,
        productName: sanitize(productName),
        sellerId,
        sellerName: sanitize(sellerName),
        buyerPhone: phone,
        buyerId: buyerId || '',
        buyerName,
        productPrice: Math.round(productPrice),
        status: 'pending',
        paymentMethod: 'ClickPesa',
        deliveryType: deliveryType || 'local',
        autoReleaseDays: deliveryType === 'regional' ? ESCROW_REGIONAL_DAYS : ESCROW_LOCAL_DAYS,
        clickpesaTransactionId: result.id || result.transactionId || result.data?.transactionId || '',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    res.json({
      order_id,
      clickpesaTransactionId: result.id || result.transactionId || result.data?.transactionId || '',
      message: 'Tuma PIN yako kwenye simu ili kukamilisha malipo.',
    });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
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
        const payoutFee = getClickPesaPayoutFee(productPrice);
        const processingFee = tx.clickPesaFee || 0;
        const sellerReceives = productPrice - platformFee - processingFee;
        const deliveryType = tx.deliveryType || 'local';
        const autoReleaseDays = tx.autoReleaseDays || (deliveryType === 'regional' ? ESCROW_REGIONAL_DAYS : ESCROW_LOCAL_DAYS);
        const escrowExpiry = new Date(Date.now() + autoReleaseDays * 24 * 60 * 60 * 1000);

        // Update transaction — put in escrow instead of auto-paying
        await txDoc.ref.update({
          processingFee,
          platformFee,
          clickPesaFee: processingFee,
          payoutFee,
          sokoLanguCommission: platformFee,
          totalAmount: productPrice,
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
          clickPesaFee: processingFee,
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
      const payoutFee = getClickPesaPayoutFee(productPrice);
      const processingFee = tx.clickPesaFee || 0;
      const sellerReceives = productPrice - platformFee - processingFee;
      const deliveryType = tx.deliveryType || 'local';
      const autoReleaseDays = tx.autoReleaseDays || (deliveryType === 'regional' ? ESCROW_REGIONAL_DAYS : ESCROW_LOCAL_DAYS);
      const escrowExpiry = new Date(Date.now() + autoReleaseDays * 24 * 60 * 60 * 1000);

      await txDoc.ref.update({
        processingFee,
        platformFee,
        clickPesaFee: processingFee,
        payoutFee,
        sokoLanguCommission: platformFee,
        totalAmount: productPrice,
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
        clickPesaFee: processingFee,
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
app.post('/api/seller/withdraw', async (req, res) => {
  try {
    const { userId, amount, phone } = req.body;
    if (!userId || !amount || !phone) {
      return res.status(400).json({ error: 'Missing userId, amount, or phone' });
    }
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const userDoc = await db.collection('users').doc(userId).get();
    if (!userDoc.exists) return res.status(404).json({ error: 'User not found' });

    const user = userDoc.data();
    if (user.isSuspended) return res.status(403).json({ error: 'Account suspended' });

    const sellerBalance = user.sellerBalance || 0;

    if (amount < MIN_WITHDRAWAL) {
      return res.status(400).json({ error: `Minimum withdrawal is TZS ${MIN_WITHDRAWAL.toLocaleString()}` });
    }

    if (amount > sellerBalance) {
      return res.status(400).json({ error: 'Insufficient balance' });
    }

    const clickPesaFee = getClickPesaPayoutFee(amount);
    const netAmount = amount - clickPesaFee;
    if (netAmount <= 0) {
      return res.status(400).json({ error: `Amount too small after TZS ${clickPesaFee.toLocaleString()} payout fee` });
    }

    let payoutId;
    try {
      const payout = await processPayout({
        userId, phone, amount, fee: clickPesaFee, netAmount,
        source: `seller_withdraw_${Date.now()}`,
        type: 'seller_withdrawal',
        metadata: { balanceBefore: sellerBalance },
      });
      payoutId = payout.payoutId;
    } catch (payoutErr) {
      return res.status(502).json({ error: `Payout failed: ${payoutErr.message}` });
    }

    await db.collection('users').doc(userId).update({
      sellerBalance: admin.firestore.FieldValue.increment(-amount),
    });

    await auditLog({
      userId, type: 'seller_withdraw', amount: -amount,
      balanceBefore: sellerBalance, balanceAfter: sellerBalance - amount,
      reason: `Seller withdrawal: TZS ${netAmount.toLocaleString()} to ${phone}`,
      relatedId: payoutId,
      metadata: { phone, netAmount, fee: clickPesaFee, payoutId },
    });

    res.json({
      success: true,
      netAmount,
      fee: clickPesaFee,
      payoutId,
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

    const clickPesaFee = getClickPesaPayoutFee(amount);
    const netAmount = amount - clickPesaFee;
    if (netAmount <= 0) {
      return res.status(400).json({ error: `Amount too small after fee (min TZS ${clickPesaFee + 1})` });
    }

    let payoutId;
    try {
      const payout = await processPayout({
        userId, phone, amount, fee: clickPesaFee, netAmount,
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
      fee: clickPesaFee,
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
      metadata: { phone, netAmount, fee: clickPesaFee, payoutId },
    });

    res.json({
      success: true,
      netAmount,
      fee: clickPesaFee,
      payoutId,
      message: `TZS ${netAmount.toLocaleString()} zimetumwa kwa ${phone}`,
    });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 💰 CLICKPESA BALANCE — Check merchant wallet balance
// ============================================================
app.get('/api/clickpesa/balance', async (req, res) => {
  try {
    const balance = await getClickPesaBalance();
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

    const preview = await clickPesaPayoutPreview({
      amount, phone,
      externalId: 'preview_' + Date.now().toString(36),
    });
    res.json({ success: true, preview });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 💰 CREATE PAYOUT — Admin-initiated payout
// ============================================================
app.post('/api/create-payout', async (req, res) => {
  try {
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

    const clickPesaFee = getClickPesaPayoutFee(amount);
    const netAmount = amount - clickPesaFee;
    if (netAmount <= 0) {
      return res.status(400).json({ error: `Amount too small after fee (min TZS ${clickPesaFee + 1})` });
    }

    const payoutResult = await processPayout({
      userId, phone, amount, fee: clickPesaFee, netAmount,
      source: source || generatePayoutReference('src'),
      type: type || 'manual',
    });

    await auditLog({
      userId, type: 'admin_create_payout', amount: -amount,
      reason: `Admin-created payout: TZS ${netAmount} to ${phone}`,
      relatedId: payoutResult.payoutId,
      metadata: { phone, netAmount, fee: clickPesaFee, source },
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
// 📊 ADMIN — All transactions (ClickPesa payments)
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

    // 4. Total money ever processed
    const txSnap = await db.collection('transactions').get();
    let totalProcessed = 0;
    txSnap.docs.forEach(doc => {
      const d = doc.data();
      totalProcessed += (d.totalAmount || 0);
    });

    // 5. Total payouts sent
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

    // 6. Admin withdrawal history
    let totalAdminWithdrawn = 0;
    adminWithdrawSnap.docs.forEach(doc => {
      const d = doc.data();
      if (d.status === 'completed') totalAdminWithdrawn += (d.amount || 0);
    });

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
      paymentProcessor: 'ClickPesa',
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
// 👑 ADMIN — Delete user (suspend + remove data)
// ============================================================
app.delete('/api/admin/users/:uid', async (req, res) => {
  try {
    const secret = req.headers['x-admin-secret'];
    if (secret !== process.env.ADMIN_SECRET) return res.status(401).json({ error: 'Unauthorized' });
    if (!db) return res.status(503).json({ error: 'Database not configured' });

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

    res.json({ success: true, message: 'User suspended' });
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
    const productSnap = await db.collection('products').doc(productId).get();
    const productData = productSnap.data() || {};
    const productName = productData.name || 'Bidhaa';
    const productImage = (productData.images && productData.images.length > 0) ? productData.images[0] : '';
    const tierLabel = tier.charAt(0).toUpperCase() + tier.slice(1);
    const title = `🚀 ${tierLabel} Boost!`;
    const body = `${productName} imepandishwa daraja! Angalia sasa.`;

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
              image: productImage || '',
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
          data: { type: 'boost', productId: productId || '', image: productImage || '' },
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

        // Auto-payout seller with failed_retry protection
        try {
          const sellerData = autoSellerDoc.data();
          const autoPayout = sellerData.autoPayout !== false;
          if (autoPayout && sellerData.phone) {
            const clickPesaFee = getClickPesaPayoutFee(sellerReceives);
            const netPayout = sellerReceives - clickPesaFee;
            if (netPayout > 0) {
              await processPayout({
                userId: sellerId, phone: sellerData.phone,
                amount: sellerReceives, fee: clickPesaFee, netAmount: netPayout,
                source: `auto_escrow_${doc.id}`,
                type: 'escrow_auto_release',
                metadata: { orderId: doc.id, sellerId, productName: tx.productName },
              });
              await db.collection('users').doc(sellerId).update({
                sellerBalance: admin.firestore.FieldValue.increment(-sellerReceives),
              });
            }
          }
        } catch (payoutErr) {
          console.error(`Auto-payout failed for escrow ${doc.id}:`, payoutErr.message);
          await doc.ref.update({
            payoutStatus: 'failed_retry',
            payoutError: payoutErr.message || 'ClickPesa API error',
            payoutFailedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          await db.collection('notifications').add({
            userId: 'admin',
            title: '⚠️ Auto-payout Imeshindwa',
            body: `Escrow ${doc.id} — TZS ${sellerReceives.toLocaleString()} kwa ${sellerId}. Pesa zipo kwenye sellerBalance.`,
            isRead: false,
            data: { type: 'failed_retry', transactionId: doc.id },
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        }

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
// ClickPesa — Callback (webhook)
// ============================================================
app.post('/api/clickpesa-callback', async (req, res) => {
  try {
    let payload = req.body;
    console.log('ClickPesa callback received:', JSON.stringify(payload));

    // ClickPesa sends { event: "PAYMENT RECEIVED", data: { id, status, orderReference, ... } }
    if (payload.data && payload.data.orderReference) {
      payload = payload.data;
    }

    const txStatus = (payload.status || '').toLowerCase();
    const externalId = payload.orderReference || '';
    const reference = payload.id || '';

    if (!externalId || !txStatus) {
      return res.status(200).json({ received: false });
    }

    if (!db) return res.status(200).json({ received: false });

    // Check if this is a payout callback (reference starts with po_)
    if (externalId.startsWith('po_')) {
      const payoutDoc = await db.collection('payouts').doc(externalId).get();
      if (!payoutDoc.exists) {
        console.warn(`ClickPesa callback: payout ${externalId} not found`);
        return res.status(200).json({ received: false });
      }

      if (txStatus === 'success') {
        await updatePayoutStatus(externalId, PAYOUT_STATUSES.SUCCESS, { clickpesaReference: reference });

        const payout = payoutDoc.data();
        if (payout.type === 'escrow_release' && payout.metadata?.sellerId) {
          await db.collection('notifications').add({
            userId: payout.metadata.sellerId,
            title: '✅ Payout imefanikiwa!',
            body: `TZS ${payout.netAmount?.toLocaleString() || payout.amount} zimetumwa kwenye mobile money yako.`,
            isRead: false,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        }
      } else if (txStatus === 'failed') {
        await updatePayoutStatus(externalId, PAYOUT_STATUSES.FAILED, {
          failureReason: payload.message || payload.error || 'Payout failed',
        });
        // Auto-retry if under max retries
        try {
          await retryFailedPayout(externalId);
        } catch (_) {}
      } else if (txStatus === 'refunded') {
        await updatePayoutStatus(externalId, PAYOUT_STATUSES.REFUNDED);
      } else if (txStatus === 'reversed') {
        await updatePayoutStatus(externalId, PAYOUT_STATUSES.REVERSED);
        // Refund the user's balance since payout was reversed
        const payout = payoutDoc.data();
        if (payout && payout.userId && payout.type === 'seller_withdrawal') {
          await db.collection('users').doc(payout.userId).update({
            sellerBalance: admin.firestore.FieldValue.increment(payout.amount || 0),
          });
        }
      }

      return res.status(200).json({ received: true });
    }

    const txDoc = await db.collection('transactions').doc(externalId).get();
    if (!txDoc.exists) {
      console.warn(`ClickPesa callback: transaction ${externalId} not found`);
      return res.status(200).json({ received: false });
    }

    const tx = txDoc.data();

    if (txStatus === 'success') {
      if (tx.type === 'boost') {
        const tier = tx.tier || 'bronze';
        const tierConfig = BOOST_TIERS[tier] || BOOST_TIERS.bronze;
        const boostedUntil = new Date(Date.now() + tierConfig.days * 24 * 60 * 60 * 1000);

        try {
          await db.collection('products').doc(tx.productId).update({
            isBoosted: true,
            boostedUntil: admin.firestore.Timestamp.fromDate(boostedUntil),
            boostTier: tier,
            isFeatured: true,
            featuredUntil: admin.firestore.Timestamp.fromDate(boostedUntil),
          });
        } catch (productErr) {
          console.error(`ClickPesa: Failed to boost product ${tx.productId}:`, productErr);
          await txDoc.ref.update({ status: 'failed', failureReason: `Product update failed: ${productErr.message}` });
          return res.status(200).json({ received: true });
        }

        await txDoc.ref.update({ status: 'completed', clickpesaReference: reference });

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

        await db.collection('revenue_transactions').add({
          userId: 'platform',
          amount: tx.amount || tierConfig.price,
          sokoLanguCommission: tx.amount || tierConfig.price,
          type: 'boost',
          subType: tier,
          productId: tx.productId,
          transactionId: externalId,
          paymentMethod: 'ClickPesa',
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      } else {
        const productPrice = tx.productPrice || 0;
        const platformFee = Math.round(productPrice * PLATFORM_COMMISSION_PERCENT);
        const sellerReceives = productPrice - platformFee;
        const deliveryType = tx.deliveryType || 'local';
        const autoReleaseDays = tx.autoReleaseDays || (deliveryType === 'regional' ? ESCROW_REGIONAL_DAYS : ESCROW_LOCAL_DAYS);
        const escrowExpiry = new Date(Date.now() + autoReleaseDays * 24 * 60 * 60 * 1000);

        await txDoc.ref.update({
          processingFee: 0,
          platformFee,
          totalAmount: productPrice,
          sellerReceives,
          status: 'escrow_hold',
          paymentMethod: 'ClickPesa',
          transactionReference: reference,
          clickpesaReference: reference,
          escrowStatus: 'held',
          escrowHeldAt: admin.firestore.FieldValue.serverTimestamp(),
          escrowExpiresAt: admin.firestore.Timestamp.fromDate(escrowExpiry),
        });

        await db.collection('revenue_transactions').add({
          userId: 'platform',
          amount: platformFee,
          type: 'commission',
          description: `Commission for ${tx.productName || 'Product'} (escrow)`,
          transactionId: externalId,
          productName: tx.productName || '',
          productPrice,
          sokoLanguCommission: platformFee,
          paymentMethod: 'ClickPesa',
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
        });

        try {
          const fsSnap = await db.collection('flash_sales')
            .where('productId', '==', tx.productId)
            .where('isActive', '==', true)
            .limit(5).get();
          const payNow = new Date();
          const activeDoc = fsSnap.docs.find(d => isFlashSaleStillActive(d.data(), payNow));
          if (activeDoc) {
            const fsData = activeDoc.data();
            const newStock = Math.max(0, (fsData.stock || 0) - 1);
            const newSold = (fsData.soldCount || 0) + 1;
            await activeDoc.ref.update({ stock: newStock, soldCount: newSold, isActive: newStock > 0 });
          }
        } catch (_) {}

        if (sellerReceives > 0 && tx.sellerId) {
          await db.collection('users').doc(tx.sellerId).set({
            pendingEscrow: admin.firestore.FieldValue.increment(sellerReceives),
            totalSales: admin.firestore.FieldValue.increment(1),
            grossSalesVolume: admin.firestore.FieldValue.increment(productPrice),
            lastSaleAt: admin.firestore.FieldValue.serverTimestamp(),
          }, { merge: true });

          await db.collection('notifications').add({
            userId: tx.sellerId,
            title: 'Umepata Mauzo!',
            body: `${tx.productName || 'Bidhaa'} imeuzwa. TZS ${sellerReceives.toLocaleString()} imewekwa escrow.`,
            isRead: false,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });

          try {
            const sellerSnap = await db.collection('users').doc(tx.sellerId).get();
            const sellerToken = sellerSnap.data()?.fcmToken;
            if (sellerToken) {
              await sendFcmToToken(buildFcmMessage({
                token: sellerToken,
                title: 'Umepata Mauzo!',
                body: `${tx.productName || 'Bidhaa'} imeuzwa. TZS ${sellerReceives.toLocaleString()} imewekwa escrow.`,
                data: { type: 'payment', transactionId: externalId },
              }), tx.sellerId);
            }
          } catch (_) {}
        }

        // Notify buyer that payment was successful
        if (tx.userId && tx.userId !== tx.sellerId) {
          await db.collection('notifications').add({
            userId: tx.userId,
            title: 'Malipo Yamekamilika!',
            body: `Malipo ya ${tx.productName || 'bidhaa'} yamekamilika. Tumeshika TZS ${productPrice.toLocaleString()} hadi muuzaji atakapotoa.`,
            isRead: false,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });

          try {
            const buyerSnap = await db.collection('users').doc(tx.userId).get();
            const buyerToken = buyerSnap.data()?.fcmToken;
            if (buyerToken) {
              await sendFcmToToken(buildFcmMessage({
                token: buyerToken,
                title: 'Malipo Yamekamilika!',
                body: `Malipo ya ${tx.productName || 'bidhaa'} yamekamilika kwa mafanikio.`,
                data: { type: 'payment', transactionId: externalId },
              }), tx.userId);
            }
          } catch (_) {}
        }
      }
    } else if (txStatus === 'failed') {
      await txDoc.ref.update({
        status: 'failed',
        failureReason: `ClickPesa: ${payload.message || payload.error || 'Payment failed'}`,
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    res.status(200).json({ received: true });
  } catch (e) {
    console.error('ClickPesa callback error:', e);
    res.status(200).json({ received: false });
  }
});

// ─── Global error handler (catches unhandled errors, never leaks internals) ───
app.use((err, req, res, _next) => {
  console.error('Unhandled error:', err?.stack || err?.message || err);
  res.status(500).json({ error: 'Internal server error' });
});

app.listen(PORT, () => console.log(`Server running on port ${PORT}`));
