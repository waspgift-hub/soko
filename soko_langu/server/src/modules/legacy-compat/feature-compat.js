// Feature-compat router: verbatim ports of the old-server endpoints the Flutter
// app still calls (KYC, chat send, boost, flash sales, cloudinary signing, SMS,
// statements, analytics, misc wallet/auth helpers) under their ORIGINAL /api
// paths. Firestore is the same project, so data continues where it left off.
//
// Any money-affecting logic here is copied 1:1 from the proven legacy monolith
// (server/index.js); nothing is invented. Deviations are limited to:
//   - sendOneSignalBulk skips per-user preference gating (compat philosophy:
//     delivery only, gating lives in the old server);
//   - failStalePendingBoosts applies the LEGACY success path only for `boost`
//     transactions (mark completed + activate product) instead of the full
//     applyClickPesaPayment router, which is already served by the deployed v1
//     webhook handlers. The pending transaction stays recoverable on the next
//     run if ClickPesa later confirms success.
// eslint-disable-next-line global-require
const express = require('express');
const crypto = require('crypto');
const axios = require('axios');
const admin = require('firebase-admin');

const { requireUser, requireAdmin, isOwnerOrAdmin } = require('./auth-helpers');
const { sendOneSignalNotification, notifyAdmins } = require('./notify');
const { verifyAdminSecret } = require('../../../middlewares/security');
const {
  clickpesaCollect,
  clickpesaPaymentStatus,
  clickpesaCreateBillPayOrder,
  calcGatewayFee,
  ALL_PAYMENT_METHODS,
} = require('../../../clickpesa');
const { localizeNotif, localizeDefaultReason, smsSafeForGateway } = require('../../../notif_lang');
const { parseFlashSaleEndTime, isFlashSaleStillActive } = require('../../../money');
const cache = require('../../../cache');
const config = require('../../config');

// ─── Legacy constants (server/index.js) ─────────────────────────────────
const BOOST_TIERS = {
  bronze: { price: 1500, days: 3 },
  silver: { price: 3000, days: 7 },
  gold: { price: 10000, days: 30 },
};

// Statuses where money really came in (single source of truth for every
// place a transaction is counted as a payment).
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

// Statuses where the escrow has actually been released to the seller. Escrow
// hold statuses are NOT credits: money is still in pendingEscrow until release.
const SELLER_CREDIT_STATUSES = new Set(['delivered', 'delivery_confirmed', 'completed']);

const NOTIF_LANG_TTL_MS = 5 * 60 * 1000;
const notifLangCache = new Map();

// ─── Notification helpers (ported from server/index.js) ────────────────
async function getUserNotifLang(db, userId) {
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

// SMS language is a SEPARATE preference (smsLangCode) from the in-app language.
async function getUserSmsLang(db, userId) {
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

const NOTIFY_SMS_BASE = 'https://api.notify.africa';

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

async function sendSms(phone, message) {
  try {
    const apiKey = process.env.MESEJI_API_KEY;
    if (apiKey) {
      const digits = phone.replace(/\D/g, '');
      // Meseji expects `contacts` as a single local-format STRING; the array
      // form fails with `finalContacts.split is not a function` (verified live).
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

// Resolves the recipient's language and localizes the Swahili SMS template.
async function sendLocalizedSms(db, phone, swMessage, userId) {
  const lang = userId ? await getUserSmsLang(db, userId) : 'sw';
  return sendSms(phone, smsSafeForGateway(lang, swMessage));
}

async function notifyBoostPaymentFailed(db, tx, reason = '') {
  try {
    if (!tx || !tx.userId) return;
    // The gateway may pass an English default; project it to the user's
    // language so the boost-failure message stays a single language.
    const reasonLang = await getUserNotifLang(db, tx.userId);
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
      const msg = `Malipo ya Boost ya TZS ${amount.toLocaleString()} hayakukamilika${reasonText}. Jaribu tena kwenye app.`;
      await sendLocalizedSms(db, phone, msg, tx.userId);
    } else {
      console.error(`notifyBoostPaymentFailed: no phone for user ${tx.userId} (tx ${tx.buyerPhone || 'none'}) — SMS skipped`);
    }
  } catch (e) {
    console.error('notifyBoostPaymentFailed error:', e.message);
  }
}

function notifTypeToChannel(type) {
  switch (type) {
    case 'chat': return 'soko_chat';
    case 'order': return 'soko_orders';
    case 'payment': return 'soko_orders';
    case 'boost': return 'soko_boost';
    case 'flash_sale': return 'soko_general';
    case 'escrow_auto_release': return 'soko_orders';
    case 'kyc': return 'soko_general';
    default: return 'soko_general';
  }
}

async function sendOneSignalBulk(db, userIds, title, body, data = {}) {
  if (!userIds || userIds.length === 0) return { successCount: 0 };
  const appId = config.onesignal.appId;
  const apiKey = config.onesignal.apiKey;
  if (!appId || !apiKey) {
    console.error('[OS] Missing config');
    return { successCount: 0 };
  }
  const notifType = (data && data.type) || 'general';
  let successCount = 0;
  const batchSize = 2000;
  for (let i = 0; i < userIds.length; i += batchSize) {
    const chunk = userIds.slice(i, i + batchSize);
    try {
      const resp = await axios.post('https://onesignal.com/api/v1/notifications', {
        app_id: appId,
        include_external_user_ids: chunk,
        channel_for_external_user_ids: 'push',
        headings: { en: title || '', sw: title || '' },
        contents: { en: body || '', sw: body || '' },
        data: { ...(data || {}), type: notifType },
        priority: 10, android_priority: 'high', android_visibility: 1,
        existing_android_channel_id: notifTypeToChannel(notifType),
        android_sound: 'soko_notification',
        android_icon: 'ic_notification',
      }, {
        headers: { Authorization: `Basic ${apiKey}`, 'Content-Type': 'application/json' },
        timeout: 20000,
      });
      const result = resp.data || {};
      if (result.id) {
        successCount += result.recipients || chunk.length;
        console.log(`[OS] bulk sent — id=${result.id} recipients=${result.recipients ?? chunk.length}`);
      } else {
        console.error('[OS] bulk send failed:', JSON.stringify(result));
      }
    } catch (err) {
      console.error('[OS] bulk send error:', err.response?.data ? JSON.stringify(err.response.data) : err.message);
    }
  }
  return { successCount };
}

// ─── Cron helpers (ported from server/index.js) ────────────────────────
async function releaseExpiredEscrows(db) {
  if (!db) return;
  try {
    const now = admin.firestore.Timestamp.now();
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

// Maps raw ClickPesa status rows (GET /payments/{orderReference}) to
// 'success' | 'failed' | '' (still pending/unknown).
function clickPesaStatusFrom(resp, orderId) {
  let rows = [];
  if (resp && Array.isArray(resp.data)) rows = resp.data;
  else if (Array.isArray(resp)) rows = resp;
  else if (resp && resp.data && Array.isArray(resp.data.rows)) rows = resp.data.rows;
  const match = rows.find((r) => (r.orderReference || r.order_id || r.externalId || '') === orderId) || rows[0] || {};
  const raw = String(match.status || match.paymentStatus || resp?.status || '').toLowerCase();
  if (/success|settled|completed|payment_received|paid/.test(raw)) return 'success';
  if (/fail|cancel|expire|reject|declin|error/.test(raw)) return 'failed';
  return '';
}

// Extracts the human-readable failure reason from GET /payments/{orderReference}.
function clickPesaFailureReasonFrom(resp, orderId) {
  let rows = [];
  if (resp && Array.isArray(resp.data)) rows = resp.data;
  else if (Array.isArray(resp)) rows = resp;
  else if (resp && resp.data && Array.isArray(resp.data.rows)) rows = resp.data.rows;
  const match = rows.find((r) => (r.orderReference || r.order_id || r.externalId || '') === orderId) || rows[0] || {};
  return String(match.message || match.failureMessage || match.error || resp?.message || '').trim();
}

// Legacy success path for a CONFIRMED boost payment: skip if already
// finalized, otherwise atomically mark the transaction completed AND activate
// the product boost (the exact applyClickPesaPayment boost branch). On a batch
// failure the transaction stays pending so the next run can retry — the same
// recovery the poller gives the full router.
async function boostPaymentSuccess(db, orderId) {
  const txDoc = await db.collection('transactions').doc(orderId).get();
  if (!txDoc.exists) return;
  const tx = txDoc.data();
  if (tx.status === 'completed' || tx.status === 'escrow_hold') return;

  const tier = tx.tier || 'bronze';
  const tierConfig = BOOST_TIERS[tier] || BOOST_TIERS.bronze;
  const boostedUntil = new Date(Date.now() + tierConfig.days * 24 * 60 * 60 * 1000);

  const batch = db.batch();
  batch.update(txDoc.ref, {
    status: 'completed',
    completedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  if (tx.productId) {
    batch.update(db.collection('products').doc(tx.productId), {
      isBoosted: true,
      boostedUntil: admin.firestore.Timestamp.fromDate(boostedUntil),
      boostTier: tier,
      isFeatured: true,
      featuredUntil: admin.firestore.Timestamp.fromDate(boostedUntil),
    });
  }
  try {
    await batch.commit();
    console.log(`[Boost] Atomic batch committed for ${orderId}`);
  } catch (batchErr) {
    console.error(`[Boost] Batch commit failed for ${orderId}:`, batchErr.message);
  }
}

async function failStalePendingBoosts(db) {
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
        await boostPaymentSuccess(db, doc.id);
        continue;
      }
      if (cpStatus === 'failed') {
        const reason = cpFailureReason || 'Malipo ya ussd yameshindikana';
        await doc.ref.update({
          status: 'failed',
          failureReason: reason,
          completedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        await notifyBoostPaymentFailed(db, tx, reason);
        continue;
      }

      // Still unresolved (pending/unknown) and past the session window → timeout.
      const reason = 'muda wa malipo umeisha';
      await doc.ref.update({
        status: 'failed',
        failureReason: reason,
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      await notifyBoostPaymentFailed(db, tx, reason);
    }
  } catch (e) {
    console.error('failStalePendingBoosts error:', e.message);
  }
}

// ─── Router ─────────────────────────────────────────────────────────────
module.exports = function ({ admin: fbAdmin, db }) {
  const A = fbAdmin || admin;

  function verifyToken(header) {
    return A.auth().verifyIdToken(String(header || '').replace('Bearer ', '').trim());
  }

  const router = express.Router();

  // ─── AUTH — check-phone / check-email (Firestore semantics, not Prisma) ─
  router.post('/auth/check-phone', async (req, res) => {
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

  router.post('/auth/check-email', async (req, res) => {
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
          await A.auth().getUserByEmail(email.trim().toLowerCase());
          exists = true;
        } catch (_) {}
      }

      res.json({ exists });
    } catch (e) {
      console.error('/api/auth/check-email error:', e.message);
      res.status(500).json({ error: 'Internal server error' });
    }
  });

  // ─── SMS — send via Meseji (falls back to Notify Africa) ──────────────
  router.post('/sms/send', async (req, res) => {
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

  // ─── NOTIFICATIONS — send one-off (in-app + push) ─────────────────────
  router.post('/send-notification', async (req, res) => {
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

      await db.collection('notifications').add({
        userId,
        title,
        body: body || '',
        data: data || {},
        isRead: false,
        createdAt: A.firestore.FieldValue.serverTimestamp(),
      });

      const notifType = data && data.type;
      await sendOneSignalNotification(userId, title, body || '', { ...(data || {}), type: notifType || 'general' });

      res.json({ sent: true });
    } catch (e) {
      res.status(500).json({ error: 'Internal server error' });
    }
  });

  // ─── KYC — submit / status ────────────────────────────────────────────
  router.post('/kyc/submit', async (req, res) => {
    try {
      // Auth FIRST — never reveal field requirements to anonymous callers.
      const { userId, fullName, idType, idNumber, idImageUrl, selfieUrl } = req.body || {};
      if (!(await isOwnerOrAdmin(req, res, userId || ''))) return;
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
      // TODO: Integrate Face Matching microservice (e.g. AWS Rekognition)

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
          submittedAt: A.firestore.FieldValue.serverTimestamp(),
          reviewedAt: null,
        },
      });

      // Notify admin about new KYC submission
      const adminSnap = await db.collection('users').where('isAdmin', '==', true).limit(5).get();
      for (const adminDoc of adminSnap.docs) {
        await db.collection('notifications').add({
          userId: adminDoc.id,
          title: 'KYC Mpya Imewasilishwa',
          body: `${fullName} ametuma KYC yake. Tafadhali kagua.`,
          isRead: false,
          createdAt: A.firestore.FieldValue.serverTimestamp(),
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
        createdAt: A.firestore.FieldValue.serverTimestamp(),
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

  router.get('/kyc/status/:userId', async (req, res) => {
    try {
      const auth = await requireUser(req, res);
      if (!auth.ok) return;
      const { userId } = req.params;
      if (!db) return res.status(503).json({ error: 'Database not configured' });

      // Only the owner (or an admin) may read KYC documents.
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

  // ─── CHAT — send message via REST ─────────────────────────────────────
  router.post('/chat/send', async (req, res) => {
    try {
      const { senderId, receiverId, roomId, text, productId, productName, replyTo, replyToContent, replyToSender } = req.body;
      if (!senderId || !receiverId || !roomId || !text) {
        return res.status(400).json({ error: 'Missing required fields (senderId, receiverId, roomId, text)' });
      }
      if (!db) return res.status(503).json({ error: 'Database not configured' });

      const authHeader = req.headers['authorization'];
      if (!authHeader || !authHeader.startsWith('Bearer ')) {
        return res.status(401).json({ error: 'Unauthorized' });
      }
      let decoded;
      try {
        decoded = await A.auth().verifyIdToken(authHeader.slice(7));
      } catch {
        return res.status(401).json({ error: 'Invalid token' });
      }
      if (decoded.uid !== senderId) {
        return res.status(403).json({ error: 'Sender ID mismatch' });
      }

      const senderDoc = await db.collection('users').doc(senderId).get();
      if (senderDoc.exists && senderDoc.data().isSuspended === true) {
        return res.status(403).json({ error: 'Account suspended' });
      }

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
        timestamp: A.firestore.FieldValue.serverTimestamp(),
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
        last_timestamp: A.firestore.FieldValue.serverTimestamp(),
      });

      // Presence-aware delivery: a recipient currently viewing this exact
      // conversation (activeChatRoom === roomId) sees the message live, so we
      // skip the unread bump, push, and in-app banner. If they are in the app
      // elsewhere (fresh lastActive) we still bump unread + in-app badge but
      // skip the disruptive heads-up push.
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
      receiverActiveHere = receiverRoomId === roomId && receiverFresh;

      if (!receiverActiveHere) {
        try {
          await db.collection('chat_rooms').doc(roomId).update({
            [`unread_counts.${receiverId}`]: A.firestore.FieldValue.increment(1),
          });
          const legacyField = receiverData?.isBuyer === true ? 'unread_count_buyer' : 'unread_count_seller';
          await db.collection('chat_rooms').doc(roomId).update({
            [legacyField]: A.firestore.FieldValue.increment(1),
          });
        } catch (_) {}
      }

      if (!receiverActiveHere && !receiverFresh) {
        try {
          await sendOneSignalNotification(receiverId, senderName, text, { type: 'chat', senderId, senderName, roomId });
        } catch (_) {}
      }

      if (!receiverActiveHere) {
        try {
          await db.collection('notifications').add({
            userId: receiverId,
            title: senderName,
            body: text,
            type: 'chat',
            data: { senderId, senderName, roomId },
            isRead: false,
            createdAt: A.firestore.FieldValue.serverTimestamp(),
          });
        } catch (_) {}
      }

      res.json({ success: true, messageId: msgRef.id });
    } catch (e) {
      console.error('/api/chat/send error:', e);
      res.status(500).json({ error: 'Internal server error' });
    }
  });

  // ─── BOOST — hyped product placement (ClickPesa flow) ─────────────────
  router.post('/boost-product', async (req, res) => {
    try {
      const authHeader = req.headers.authorization || '';
      const token = authHeader.replace('Bearer ', '');
      if (!token) return res.status(401).json({ error: 'Unauthorized' });
      let decoded;
      try { decoded = await A.auth().verifyIdToken(token); } catch (_) { return res.status(403).json({ error: 'Invalid token' }); }

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
              cancelledAt: A.firestore.FieldValue.serverTimestamp(),
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

      // BillPay fee (1%) is deducted from the collected amount, so we add it on top.
      // USSD Push fee is charged to the customer by ClickPesa on top, so we send the
      // real tier price (never pre-added) to avoid charging the processing fee twice.
      const isBillPay = (paymentMethod || 'ussd_push') === 'billpay';
      const gatewayFee = calcGatewayFee(isBillPay ? 'billpay' : 'ussd_push', tierConfig.price, req.body.provider);
      const totalToCollect = isBillPay ? tierConfig.price + gatewayFee : tierConfig.price;

      const order_id = `boost${Date.now()}`;

      if (isBillPay) {
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
            createdAt: A.firestore.FieldValue.serverTimestamp(),
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
        // USSD Push flow (async — return immediately)
        if (db) {
          await db.collection('transactions').doc(order_id).set({
            type: 'boost', productId, productName: productName || '',
            productImage: productImage || '', productPrice: productPrice || 0,
            tier: tier.toLowerCase(), amount: tierConfig.price, gatewayFee,
            totalAmount: totalToCollect, durationDays: tierConfig.days,
            userId: userId || '', buyerId: userId || '', buyerName: userId || '',
            buyerPhone: normalizedPhone, sellerName: 'Soko Vibe',
            status: 'pending', paymentMethod: paymentMethod || 'ussd_push',
            createdAt: A.firestore.FieldValue.serverTimestamp(),
          });
        }

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
                completedAt: A.firestore.FieldValue.serverTimestamp(),
              }).then(() => notifyBoostPaymentFailed(db, txData, reason));
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

  // ─── SELLER — balance ─────────────────────────────────────────────────
  router.get('/seller/balance', async (req, res) => {
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

  // ─── SELLER — analytics ───────────────────────────────────────────────
  router.get('/seller-analytics/:sellerId', async (req, res) => {
    try {
      const { sellerId } = req.params;
      if (!sellerId) return res.status(400).json({ error: 'sellerId required' });

      const authHeader = req.headers['authorization'];
      if (!authHeader || !authHeader.startsWith('Bearer ')) {
        return res.status(401).json({ error: 'Unauthorized' });
      }
      let decoded;
      try {
        decoded = await A.auth().verifyIdToken(authHeader.slice(7));
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

      const analyticsCacheKey = `seller-analytics:${sellerId}`;
      const cachedAnalytics = await cache.get(analyticsCacheKey);
      if (cachedAnalytics) return res.json(cachedAnalytics);

      const now = new Date();
      const monthStart = new Date(now.getFullYear(), now.getMonth(), 1);

      // Products & Views
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

      // Transactions & Order Stats
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

      // Reviews
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

      const analyticsResult = {
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
      };
      await cache.set(analyticsCacheKey, analyticsResult, 60_000);
      res.json(analyticsResult);
    } catch (e) {
      res.status(500).json({ error: 'Internal server error' });
    }
  });

  // ─── SELLER STATEMENT — bank-statement-style financial report ─────────
  router.get('/seller-statement/:sellerId', async (req, res) => {
    try {
      const { sellerId } = req.params;
      if (!sellerId) return res.status(400).json({ error: 'sellerId required' });

      const authHeader = req.headers['authorization'];
      if (!authHeader || !authHeader.startsWith('Bearer ')) {
        return res.status(401).json({ error: 'Unauthorized' });
      }
      let decoded;
      try {
        decoded = await A.auth().verifyIdToken(authHeader.slice(7));
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
        // seller. escrow_hold / dispatched are still held in pendingEscrow.
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

  // ─── BUYER STATEMENT — buyer's payments + refunds, running balance ────
  router.get('/buyer-statement/:buyerId', async (req, res) => {
    try {
      const { buyerId } = req.params;
      if (!buyerId) return res.status(400).json({ error: 'buyerId required' });

      const authHeader = req.headers['authorization'];
      if (!authHeader || !authHeader.startsWith('Bearer ')) {
        return res.status(401).json({ error: 'Unauthorized' });
      }
      let decoded;
      try {
        decoded = await A.auth().verifyIdToken(authHeader.slice(7));
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

      // Payments made by the buyer (money out). 'paid' is intentionally
      // excluded: it is set client-side the moment a USSD push is sent, BEFORE
      // payment is actually confirmed.
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

      // Wallet deposits (money added to the buyer's wallet) — money IN, so they
      // are credits. Only counted once ClickPesa confirms ('completed').
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

  // ─── CLOUDINARY — upload signing + delete (server-only auth) ──────────
  router.post('/cloudinary/sign', async (req, res) => {
    try {
      const authHeader = req.headers.authorization;
      if (!authHeader || !authHeader.startsWith('Bearer ')) {
        return res.status(401).json({ error: 'Missing or invalid token' });
      }
      const token = authHeader.split(' ')[1];
      try {
        await A.auth().verifyIdToken(token);
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

  router.post('/cloudinary/delete', async (req, res) => {
    try {
      const authHeader = req.headers.authorization;
      if (!authHeader || !authHeader.startsWith('Bearer ')) {
        return res.status(401).json({ error: 'Missing or invalid token' });
      }
      try {
        await A.auth().verifyIdToken(authHeader.split(' ')[1]);
      } catch {
        return res.status(401).json({ error: 'Invalid token' });
      }

      const apiKey = process.env.CLOUDINARY_API_KEY;
      const apiSecret = process.env.CLOUDINARY_API_SECRET;
      if (!apiKey || !apiSecret) {
        return res.status(500).json({ error: 'Cloudinary not configured on server' });
      }

      const { imageUrl } = req.body;
      if (!imageUrl || !/res\.cloudinary\.com/.test(imageUrl)) {
        return res.json({ success: false, skipped: true });
      }
      const match = imageUrl.match(/\/v\d+\/(.+)\.\w+$/);
      if (!match) return res.json({ success: false, skipped: true });
      const publicId = match[1];

      const resp = await axios.post(
        'https://api.cloudinary.com/v1_1/dgbsohnl4/image/destroy',
        new URLSearchParams({
          public_id: publicId,
          timestamp: String(Math.floor(Date.now() / 1000)),
        }),
        {
          auth: { username: apiKey, password: apiSecret },
          headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
          timeout: 15000,
        },
      );
      const result = resp.data || {};
      if (result.result === 'ok' || result.result === 'not found') {
        res.json({ success: true, publicId, result: result.result });
      } else {
        res.status(502).json({ error: `Cloudinary delete failed: ${result.result}` });
      }
    } catch (e) {
      console.error('Cloudinary delete error:', e.message);
      res.status(500).json({ error: 'Internal server error' });
    }
  });

  // ─── ADMIN — one-off broadcast to all users (in-app + OneSignal) ──────
  router.post('/admin/broadcast-notification', async (req, res) => {
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

      // Admin broadcast always delivers (compat bulk sender has no prefs gate).
      const pushResult = await sendOneSignalBulk(db, userIds, title, body || '', {
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
            createdAt: A.firestore.FieldValue.serverTimestamp(),
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

  // ─── CRON — release expired escrows + fail stale boosts ───────────────
  router.post('/cron/release-escrows', async (req, res) => {
    try {
      const secret = req.headers['x-cron-secret'];
      if (!verifyAdminSecret(secret)) {
        return res.status(401).json({ error: 'Unauthorized' });
      }
      await releaseExpiredEscrows(db);
      await failStalePendingBoosts(db);
      res.json({ success: true, message: 'Escrow release triggered' });
    } catch (e) {
      console.error('Cron release-escrows error:', e);
      res.status(500).json({ error: 'Internal server error' });
    }
  });

  // ─── STATS — monitoring snapshot (admin) ──────────────────────────────
  router.get('/stats', async (req, res) => {
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

  // ─── FLASH SALES — create / scan / notify / deactivate / delete ───────
  router.post('/flash-sale/create', async (req, res) => {
    try {
      const authHeader = req.headers['authorization'];
      if (!authHeader || !authHeader.startsWith('Bearer ')) {
        return res.status(401).json({ error: 'Unauthorized' });
      }
      let decoded;
      try {
        decoded = await A.auth().verifyIdToken(authHeader.slice(7));
      } catch {
        return res.status(401).json({ error: 'Invalid token' });
      }

      const {
        productId, productName, productImage, originalPrice, salePrice,
        discountPercent, sellerId, sellerName, sellerPhone, location,
        stock, startTime, endTime,
      } = req.body;

      if (!productId || !sellerId || !productName) {
        return res.status(400).json({ error: 'Missing required fields' });
      }
      if (decoded.uid !== sellerId) {
        return res.status(403).json({ error: 'Seller ID does not match authenticated user' });
      }

      if (!db) return res.status(503).json({ error: 'Database not configured' });

      // Check if user is suspended
      const userDoc = await db.collection('users').doc(sellerId).get();
      if (userDoc.exists && userDoc.data().isSuspended === true) {
        return res.status(403).json({ error: 'Account suspended' });
      }

      // Prevent duplicate active flash sales for the same product.
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
        startTime: startTime ? new Date(startTime) : A.firestore.FieldValue.serverTimestamp(),
        endTime: endTime ? new Date(endTime) : new Date(Date.now() + 24 * 3600000),
        createdAt: A.firestore.FieldValue.serverTimestamp(),
      });

      res.json({ success: true, flashSaleId: ref.id });
    } catch (e) {
      res.status(500).json({ error: 'Internal server error' });
    }
  });

  router.post('/flash-sale/scan', async (req, res) => {
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
          startTime: A.firestore.FieldValue.serverTimestamp(),
          endTime: new Date(now.getTime() + 24 * 3600000),
          createdAt: A.firestore.FieldValue.serverTimestamp(),
        });
        created++;
      }

      res.json({ success: true, flashSalesCreated: created });
    } catch (e) {
      res.status(500).json({ error: 'Internal server error' });
    }
  });

  router.post('/flash-sale/notify', async (req, res) => {
    try {
      const auth = await requireUser(req, res);
      if (!auth.ok) return;
      const { productName, salePrice, discountPercent, sellerId, productImage } = req.body;
      if (!sellerId || auth.uid !== sellerId) {
        return res.status(403).json({ error: 'Seller ID mismatch' });
      }
      if (!db) return res.status(503).json({ error: 'Database not configured' });

      let sentCount = 0;
      const PAGE_SIZE = 500;

      // Dedup: full-audience push at most once per 24h. In-app rows still go out.
      const cooldownRef = db.collection('app_settings').doc('flash_sale_push_cooldown');
      const cooldownSnap = await cooldownRef.get();
      const lastSentAt = cooldownSnap.exists && cooldownSnap.data()?.lastSentAt
        ? cooldownSnap.data().lastSentAt.toDate()
        : null;
      const cooldownMs = 24 * 60 * 60 * 1000;
      const pushSkipped = lastSentAt != null && Date.now() - lastSentAt.getTime() < cooldownMs;

      if (!pushSkipped) {
        try {
          // Group recipients by in-app language and send a localized bulk push
          // per group (a Swahili template would otherwise reach en/zh users).
          const langBuckets = new Map();
          let lastPushId = null;
          while (true) {
            let query = db.collection('users');
            if (lastPushId) query = query.startAfter(lastPushId);
            query = query.limit(PAGE_SIZE);
            const usersSnap = await query.get();
            if (usersSnap.empty) break;
            for (const doc of usersSnap.docs) {
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
            const osResult = await sendOneSignalBulk(db, ids, loc.title, loc.body, { type: 'flash_sale', productName: productName || '', image: productImage || '' });
            sentCount += osResult.successCount;
            console.log(`[flash-sale] bulk push sent lang=${lang} users=${ids.length} sent=${osResult.successCount}`);
          }
          await cooldownRef.set({ lastSentAt: A.firestore.Timestamp.now() }, { merge: true });
          console.log(`[flash-sale] bulk push total sentCount=${sentCount}`);
        } catch (pushErr) {
          console.error('OneSignal push skipped for flash sale:', pushErr.message);
        }
      } else {
        console.log(`[flash-sale] push skipped — cooldown active (last sent ${lastSentAt.toISOString()})`);
      }

      // Always confirm to the flash-sale creator that the sale is live.
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
            createdAt: A.firestore.FieldValue.serverTimestamp(),
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
  });

  router.post('/flash-sales/deactivate-expired', async (req, res) => {
    if (!db) return res.status(503).json({ error: 'Database not configured' });
    const authHeader = req.headers['authorization'];
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({ error: 'Unauthorized' });
    }
    try {
      await A.auth().verifyIdToken(authHeader.slice(7));
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
  });

  router.post('/flash-sales/delete', async (req, res) => {
    if (!db) return res.status(503).json({ error: 'Database not configured' });
    const auth = await requireAdmin(req, res);
    if (!auth.ok) return;
    const { flashSaleId } = req.body;
    if (!flashSaleId) return res.status(400).json({ error: 'flashSaleId required' });
    await db.collection('flash_sales').doc(flashSaleId).delete();
    res.json({ success: true });
  });

  // ─── PAYMENT METHODS / fees / wallet deposit methods ──────────────────
  router.get('/payment-methods', (req, res) => {
    res.json({ success: true, methods: ALL_PAYMENT_METHODS });
  });

  router.post('/payment-methods/calc-fee', (req, res) => {
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

  router.get('/wallet/deposit/methods', (req, res) => {
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

  return router;
};