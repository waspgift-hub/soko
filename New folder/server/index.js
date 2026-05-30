require('dotenv').config();
const express = require('express');
const cors = require('cors');
const crypto = require('crypto');
const admin = require('firebase-admin');
const nodemailer = require('nodemailer');
const { RtcTokenBuilder, RtcRole } = require('agora-access-token');

const app = express();

const REQUEST_TIMEOUT = 20000; // 20 seconds

app.use(cors());
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

const MONGIKE_API_KEY = process.env.MONGIKE_API_KEY;
const AGORA_APP_ID = process.env.AGORA_APP_ID;
const AGORA_CERT = process.env.AGORA_APP_CERTIFICATE;
const PORT = process.env.PORT || 3000;

// ─── Rate limiter (in-memory) ───
const rateHits = new Map();
const RATE_WINDOW = 60 * 1000;
const RATE_MAX = 30;

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

function sanitize(str) {
  if (typeof str !== 'string') return '';
  return str.replace(/<[^>]*>/g, '').trim().slice(0, 1000);
}

// ─── Email transporter (nodemailer) ───
const SMTP_HOST = process.env.SMTP_HOST || 'smtp.gmail.com';
const SMTP_PORT = process.env.SMTP_PORT || '587';
const SMTP_USER = process.env.SMTP_USER || 'waspgift@gmail.com';
const SMTP_PASS = process.env.SMTP_PASS || 'fgnd ylot wwmc grou';
const SMTP_FROM = process.env.SMTP_FROM || 'Soko Langu <waspgift@gmail.com>';
const SMTP_SECURE = process.env.SMTP_SECURE || 'false';

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

const TIER_PRICES_TZS = {
  premium: { monthly: 15000, yearly: 150000 },
  silver: { monthly: 35000, yearly: 350000 },
};

const MONGIKE_TX_FEE = 180;          // Mongike charges TZS 180 per transaction
const MONGIKE_PAYOUT_FEE = 2000;     // Mongike charges TZS 2,000 per payout
const MONGIKE_BASE = 'https://mongike.com/api/v1';

async function callMongikePay(body, retries = 2) {
  for (let attempt = 0; attempt <= retries; attempt++) {
    try {
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), 15000);

      const resp = await fetch(`${MONGIKE_BASE}/payments/mobile-money/tanzania`, {
        method: 'POST',
        headers: {
          'x-api-key': MONGIKE_API_KEY,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(body),
        signal: controller.signal,
      });
      clearTimeout(timeout);

      return await resp.json();
    } catch (err) {
      if (attempt === retries) throw err;
      await new Promise(r => setTimeout(r, 1000));
    }
  }
}

// --- Mongike payment link for subscriptions ---
app.post('/api/create-payment-link', async (req, res) => {
  try {
    const { tier, isYearly, email, phone, userId } = req.body;
    if (!tier || !['premium', 'silver'].includes(tier)) {
      return res.status(400).json({ error: 'Invalid tier' });
    }
    const prices = TIER_PRICES_TZS[tier];
    const amount = isYearly ? prices.yearly : prices.monthly;
    const order_id = `${tier}_${Date.now()}`;

    if (!phone) {
      return res.status(400).json({ error: 'Phone number required' });
    }

    const webhookUrl = process.env.WEBHOOK_URL || `https://sokolangu-production.up.railway.app/api/webhook`;

    const result = await callMongikePay({
      order_id,
      amount,
      buyer_phone: phone,
      buyer_email: email || '',
      fee_payer: 'MERCHANT',
      webhook_url: webhookUrl,
    });

    if (result.status !== 'success') {
      return res.status(500).json({ error: result.message || 'Mongike error' });
    }

    if (db) {
      const mongikeId = result.data?.id || '';
      await db.collection('transactions').doc(order_id).set({
        type: 'subscription',
        tier,
        amount,
        isYearly: isYearly ?? true,
        status: 'pending',
        mongikeId,
        buyerId: userId || email || '',
        buyerPhone: phone,
        buyerEmail: email || '',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    res.json({
      order_id,
      mongikeId: result.data?.id || '',
      message: 'Payment prompt sent to your phone. Check M-Pesa/Airtel Money and enter your PIN.',
    });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// --- Buy coins via Mongike ---
app.post('/api/buy-coins', async (req, res) => {
  try {
    const { coins, price, phone, userId } = req.body;
    if (!coins || !price || !phone) {
      return res.status(400).json({ error: 'Missing required fields' });
    }
    const order_id = `coins_${Date.now()}`;
    const webhookUrl = process.env.WEBHOOK_URL || `https://sokolangu-production.up.railway.app/api/webhook`;

    const result = await callMongikePay({
      order_id,
      amount: price,
      buyer_phone: phone,
      fee_payer: 'MERCHANT',
      webhook_url: webhookUrl,
    });

    if (result.status !== 'success') {
      return res.status(500).json({ error: result.message || 'Mongike error' });
    }

    if (db) {
      await db.collection('transactions').doc(order_id).set({
        type: 'coins',
        coins,
        amount: price,
        buyerId: userId || '',
        buyerPhone: phone,
        status: 'pending',
        mongikeId: result.data?.id || '',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    res.json({
      order_id,
      mongikeId: result.data?.id || '',
      message: 'Payment prompt sent to your phone.',
    });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// --- Monthly payout for all streamers (trigger via cron job) ---
// Cron schedule: "0 0 1 * *" (first day of every month)
// POST with x-admin-secret header
app.post('/api/process-monthly-payouts', async (req, res) => {
  try {
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const secret = req.headers['x-admin-secret'];
    if (secret !== process.env.ADMIN_SECRET) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const FEE_PLATFORM = 2000;
    const FEE_MONGIKE = 2000;
    const FEE_TOTAL = FEE_PLATFORM + FEE_MONGIKE;
    const now = new Date();
    const month = now.toLocaleString('default', { month: 'long' });
    const year = now.getFullYear();
    const monthLabel = `${month} ${year}`;
    let processed = 0;
    let skipped = 0;
    const errors = [];

    const usersSnap = await db.collection('users')
      .where('streamerEarnings', '>', 0)
      .get();

    for (const doc of usersSnap.docs) {
      const data = doc.data();
      const earnings = data.streamerEarnings || 0;
      const phone = data.phone || '';

      if (!phone || earnings <= FEE_TOTAL) {
        skipped++;
        continue;
      }

      const netAmount = earnings - FEE_TOTAL;

      try {
        const resp = await fetch(`${MONGIKE_BASE}/payouts/withdraw`, {
          method: 'POST',
          headers: {
            'x-api-key': MONGIKE_API_KEY,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            amount: netAmount,
            recipient_phone: phone,
          }),
        });

        const result = await resp.json();

        if (result.status !== 'success') {
          errors.push({ userId: doc.id, error: result.message || 'Payout failed' });
          continue;
        }

        await db.collection('users').doc(doc.id).update({
          streamerEarnings: 0,
        });

        await db.collection('withdrawals').add({
          userId: doc.id,
          earnings,
          feePlatform: FEE_PLATFORM,
          feeMongike: FEE_MONGIKE,
          netAmount,
          phone,
          month: monthLabel,
          status: 'completed',
          reference: result.reference || '',
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        processed++;
      } catch (e) {
        errors.push({ userId: doc.id, error: e.message });
      }
    }

    res.json({
      processed,
      skipped,
      errors,
      month: monthLabel,
      feePerPayout: FEE_TOTAL,
    });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// --- Process viewer payouts ---
app.post('/api/process-viewer-payouts', async (req, res) => {
  try {
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const secret = req.headers['x-admin-secret'];
    if (secret !== process.env.ADMIN_SECRET) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const FEE_PLATFORM = 2000;
    const FEE_MONGIKE = 2000;
    const FEE_TOTAL = FEE_PLATFORM + FEE_MONGIKE;
    const TZS_PER_COIN = 5;
    const now = new Date();
    const month = now.toLocaleString('default', { month: 'long' });
    const year = now.getFullYear();
    const monthLabel = `${month} ${year}`;
    let processed = 0;
    let skipped = 0;
    const errors = [];

    const usersSnap = await db.collection('users')
      .where('viewerCoins', '>', 0)
      .get();

    for (const doc of usersSnap.docs) {
      const data = doc.data();
      const coins = data.viewerCoins || 0;
      const tzsValue = coins * TZS_PER_COIN;
      const phone = data.phone || '';

      if (!phone || tzsValue <= FEE_TOTAL) {
        skipped++;
        continue;
      }

      const netAmount = tzsValue - FEE_TOTAL;

      try {
        const resp = await fetch(`${MONGIKE_BASE}/payouts/withdraw`, {
          method: 'POST',
          headers: {
            'x-api-key': MONGIKE_API_KEY,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            amount: netAmount,
            recipient_phone: phone,
          }),
        });

        const result = await resp.json();

        if (result.status !== 'success') {
          errors.push({ userId: doc.id, error: result.message || 'Payout failed' });
          continue;
        }

        await db.collection('users').doc(doc.id).update({
          viewerCoins: 0,
        });

        await db.collection('viewer_payouts').add({
          userId: doc.id,
          coins,
          tzsValue,
          feePlatform: FEE_PLATFORM,
          feeMongike: FEE_MONGIKE,
          netAmount,
          phone,
          month: monthLabel,
          status: 'completed',
          reference: result.reference || '',
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        processed++;
      } catch (e) {
        errors.push({ userId: doc.id, error: e.message });
      }
    }

    res.json({
      processed,
      skipped,
      errors,
      month: monthLabel,
      feePerPayout: FEE_TOTAL,
    });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// --- Process ad revenue for sellers (40% seller / 60% platform) ---
app.post('/api/process-ad-revenue', async (req, res) => {
  try {
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const secret = req.headers['x-admin-secret'];
    if (secret !== process.env.ADMIN_SECRET) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const MAX_VIEWS = 500;
    const REVENUE_PER_VIEW = 10;       // TZS per ad view
    const SELLER_SHARE = 0.40;          // 40% to seller
    const PLATFORM_SHARE = 0.60;        // 60% to platform
    const SELLER_PER_VIEW = Math.round(REVENUE_PER_VIEW * SELLER_SHARE); // TZS 4

    const viewsSnap = await db.collection('ad_views')
      .where('processed', '==', false)
      .limit(MAX_VIEWS)
      .get();

    if (viewsSnap.empty) {
      return res.json({ processed: 0, totalEarnings: 0, message: 'No unprocessed views' });
    }

    const sellerGroups = {};
    const batch = db.batch();

    for (const doc of viewsSnap.docs) {
      const data = doc.data();
      const sellerId = data.sellerId;
      if (!sellerId) continue;
      if (!sellerGroups[sellerId]) sellerGroups[sellerId] = 0;
      sellerGroups[sellerId]++;
      batch.update(doc.ref, { processed: true });
    }

    let totalEarnings = 0;
    let sellerCount = 0;

    for (const [sellerId, count] of Object.entries(sellerGroups)) {
      const earning = count * SELLER_PER_VIEW;
      totalEarnings += earning;
      sellerCount++;

      const walletRef = db.collection('wallets').doc(sellerId);
      const walletDoc = await walletRef.get();

      if (!walletDoc.exists) {
        batch.set(walletRef, {
          balance: earning,
          totalEarnings: earning,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      } else {
        batch.update(walletRef, {
          balance: admin.firestore.FieldValue.increment(earning),
          totalEarnings: admin.firestore.FieldValue.increment(earning),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      const txRef = db.collection('revenue_transactions').doc();
      batch.set(txRef, {
        userId: sellerId,
        type: 'ad_share',
        amount: earning,
        views: count,
        ratePerView: SELLER_PER_VIEW,
        description: `Ad revenue: ${count} views × TZS ${SELLER_PER_VIEW}`,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();

    res.json({
      processed: viewsSnap.docs.length,
      sellers: sellerCount,
      totalEarnings,
      perView: SELLER_PER_VIEW,
      platformShare: `${PLATFORM_SHARE * 100}%`,
    });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// --- Mongike payment link for marketplace ---
app.post('/api/create-marketplace-payment-link', async (req, res) => {
  try {
    const { productPrice, productName, productId, sellerId, sellerName, email, phone, userId } = req.body;

    if (!productPrice || productPrice <= 0) {
      return res.status(400).json({ error: 'Invalid price' });
    }
    if (!phone || phone.length < 10) {
      return res.status(400).json({ error: 'Valid phone number required (min 10 digits)' });
    }
    if (!productId) {
      return res.status(400).json({ error: 'Product ID is required' });
    }
    if (!sellerId) {
      return res.status(400).json({ error: 'Seller ID is required' });
    }

    const order_id = `mkt_${Date.now()}`;
    const amount = Math.round(productPrice);

    const webhookUrl = process.env.WEBHOOK_URL || `https://sokolangu-production.up.railway.app/api/webhook`;

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 15000);

    const result = await callMongikePay({
      order_id,
      amount,
      buyer_phone: phone,
      buyer_email: email || '',
      fee_payer: 'MERCHANT',
      webhook_url: webhookUrl,
    });
    clearTimeout(timeout);

    if (result.status !== 'success') {
      return res.status(500).json({ error: result.message || 'Mongike payment initiation failed' });
    }

    if (db) {
      const mongikeId = result.data?.id || '';
      await db.collection('transactions').doc(order_id).set({
        type: 'marketplace',
        buyerId: userId || '',
        buyerPhone: phone,
        buyerEmail: email || '',
        productId,
        sellerId,
        sellerName: sellerName || '',
        productName: productName || '',
        amount,
        mongikeId,
        status: 'pending',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    res.json({
      order_id,
      mongikeId: result.data?.id || '',
      message: 'Payment prompt sent to your phone. Check M-Pesa/Airtel Money and enter your PIN.',
    });
  } catch (e) {
    if (e.name === 'AbortError') {
      return res.status(504).json({ error: 'Mongike request timed out. Please try again.' });
    }
    res.status(500).json({ error: e.message || 'Internal server error' });
  }
});

// --- Verify transaction status ---
app.get('/api/verify-transaction', async (req, res) => {
  try {
    const { tx_ref } = req.query;
    if (!tx_ref) return res.status(400).json({ error: 'Missing tx_ref' });

    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const doc = await db.collection('transactions').doc(tx_ref).get();
    if (!doc.exists) return res.json({ status: 'not_found' });

    res.json({ status: doc.data().status || 'pending' });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// --- Mongike webhook ---
app.post('/api/webhook', async (req, res) => {
  const payload = req.body;
  const webhookKey = req.headers['x-api-key'];
  console.log('Mongike webhook received:', JSON.stringify(payload, null, 2));

  // Verify webhook authenticity
  if (webhookKey !== MONGIKE_API_KEY) {
    console.log('Webhook x-api-key mismatch — acknowledging anyway');
  }

  // Mongike webhook payload format:
  // { order_id, payment_status: "COMPLETED", reference, amount, metadata }
  const orderId = payload.order_id || '';
  const paymentStatus = payload.payment_status || '';
  const gatewayRef = payload.reference || '';

  if (!orderId) {
    console.log('No order_id in webhook payload — acknowledging');
    return res.status(200).send('OK');
  }

  try {
    if (!db) return res.status(200).send('OK');

    const txDoc = await db.collection('transactions').doc(orderId).get();

    if (!txDoc.exists) {
      console.log(`Transaction not found for order_id=${orderId}`);
      return res.status(200).send('OK');
    }

    const data = txDoc.data();
    if (data?.status === 'completed') {
      console.log(`Transaction ${orderId} already processed`);
      return res.status(200).send('Already processed');
    }

    if (paymentStatus === 'COMPLETED') {
      if (data?.type === 'marketplace') {
        await db.collection('transactions').doc(orderId).update({
          status: 'completed',
          gatewayRef,
          completedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        const item = {
          productId: data.productId || '',
          name: data.productName || 'Product',
          price: (data.amount || 0),
          quantity: 1,
          image: data.productImage || null,
          isReviewed: false,
        };

        await db.collection('orders').add({
          buyerId: data.buyerId || '',
          sellerId: data.sellerId || '',
          items: [item],
          totalAmount: data.amount || 0,
          status: 'pending',
          paymentMethod: 'Mongike',
          paymentMethodName: 'Mongike',
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          trackingNumber: null,
          escrowHold: true,
          escrowReleased: false,
        });

        if (data.productId) {
          try {
            await db.collection('products').doc(data.productId).update({
              soldCount: admin.firestore.FieldValue.increment(1),
            });
          } catch (_) {}
        }
      } else if (data?.type === 'coins') {
        const coinsAmount = data.coins || 0;
        const userId = data.buyerId || '';

        if (userId) {
          await db.collection('users').doc(userId).update({
            coins: admin.firestore.FieldValue.increment(coinsAmount),
          });
        }

        await db.collection('transactions').doc(orderId).update({
          status: 'completed',
          gatewayRef,
          completedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      } else if (data?.type === 'boost') {
        const productId = data.productId || '';
        if (productId) {
          const featuredUntil = new Date(Date.now() + 30 * 86400000);
          await db.collection('products').doc(productId).update({
            isFeatured: true,
            featuredUntil: admin.firestore.Timestamp.fromDate(featuredUntil),
          });
        }
        await db.collection('transactions').doc(orderId).update({
          status: 'completed',
          gatewayRef,
          completedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      } else {
        // subscription
        const userId = data.buyerId || data.buyerEmail || '';
        const tier = data.tier || 'premium';
        const isYearly = data.isYearly === true;

        if (userId) {
          const durationDays = isYearly ? 365 : 30;
          const premiumUntil = new Date(Date.now() + durationDays * 86400000);
          await db.collection('users').doc(userId).update({
            accountTier: tier,
            isPremium: true,
            premiumUntil: admin.firestore.Timestamp.fromDate(premiumUntil),
          });
        }

        await db.collection('transactions').doc(orderId).update({
          status: 'completed',
          gatewayRef,
          completedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      console.log(`Payment ${orderId} completed successfully`);
    } else {
      console.log(`Payment ${orderId} status: ${paymentStatus}`);
      await db.collection('transactions').doc(orderId).update({
        status: paymentStatus === 'FAILED' ? 'failed' : paymentStatus.toLowerCase(),
        gatewayRef,
      });
    }
  } catch (err) {
    console.error('Webhook error:', err);
  }

  res.status(200).send('OK');
});

// --- Agora token generation ---
app.post('/api/agora-token', (req, res) => {
  try {
    const { channelName, uid, role } = req.body;
    if (!channelName) return res.status(400).json({ error: 'Missing channelName' });

    const userUid = uid || 0;
    const userRole = role === 'broadcaster' ? RtcRole.PUBLISHER : RtcRole.SUBSCRIBER;
    const expireTime = 3600;

    const token = RtcTokenBuilder.buildTokenWithUid(
      AGORA_APP_ID, AGORA_CERT, channelName, userUid, userRole, expireTime, expireTime,
    );

    res.json({ token, appId: AGORA_APP_ID });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.get('/api/agora-token', (req, res) => {
  try {
    const channelName = req.query.channel;
    const uid = parseInt(req.query.uid) || 0;
    const role = req.query.role === 'broadcaster' ? RtcRole.PUBLISHER : RtcRole.SUBSCRIBER;
    if (!channelName) return res.status(400).json({ error: 'Missing channel query param' });

    const expireTime = 3600;
    const token = RtcTokenBuilder.buildTokenWithUid(
      AGORA_APP_ID, AGORA_CERT, channelName, uid, role, expireTime, expireTime,
    );

    res.json({ token, appId: AGORA_APP_ID });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// --- Webhook redirect handler (legacy — kept for Flutterwave backwards compatibility) ---
app.get('/api/webhook-redirect', (req, res) => {
  const txRef = req.query.tx_ref || req.query.txref || '';
  res.redirect(`sokolangu://payment-callback?tx_ref=${txRef}`);
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
    const isCall = notifType === 'call';
    const isChat = notifType === 'chat' || notifType === 'group_chat';

    const message = {
      token: fcmToken,
      notification: { title, body: body || '' },
      data: data || {},
      android: {
        priority: isCall || isChat ? 'high' : 'normal',
        notification: isCall ? {
          channelId: 'incoming_calls_v2',
          priority: 'high',
          visibility: 'public',
          sound: 'default',
          notificationPriority: 'max',
          vibrationPattern: [0, 500, 200, 500, 200, 1000],
          fullScreenIntent: true,
          tag: 'incoming_call',
        } : isChat ? {
          channelId: 'chat_messages_v2',
          priority: 'high',
          visibility: 'public',
          sound: 'default',
          notificationPriority: 'high',
          vibrationPattern: [0, 200, 100, 200],
          tag: notifType === 'group_chat' ? 'group_chat' : 'chat_message',
          color: '#40916C',
        } : undefined,
      },
      apns: isCall || isChat ? {
        payload: {
          aps: {
            sound: 'default',
            category: isCall ? 'incoming_call' : 'chat_message',
            'content-available': 1,
          },
        },
      } : undefined,
    };

    const response = await admin.messaging().send(message);

    // Also write in-app notification to Firestore
    await db.collection('notifications').add({
      userId,
      title,
      body: body || '',
      data: data || {},
      isRead: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    res.json({ sent: true, response });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ============================================================
// ⭐ BOOST PRODUCT — FEATURED LISTING (TZS 5,000 / 30 days)
// ============================================================
const BOOST_PRICE_TZS = 5000;

app.post('/api/boost-product', async (req, res) => {
  try {
    const { productId, phone, userId } = req.body;
    if (!productId || !phone) {
      return res.status(400).json({ error: 'Missing productId or phone' });
    }

    const order_id = `boost_${Date.now()}`;
    const webhookUrl = process.env.WEBHOOK_URL || `https://sokolangu-production.up.railway.app/api/webhook`;

    const result = await callMongikePay({
      order_id,
      amount: BOOST_PRICE_TZS,
      buyer_phone: phone,
      fee_payer: 'MERCHANT',
      webhook_url: webhookUrl,
    });

    if (result.status !== 'success') {
      return res.status(500).json({ error: result.message || 'Mongike error' });
    }

    if (db) {
      await db.collection('transactions').doc(order_id).set({
        type: 'boost',
        productId,
        amount: BOOST_PRICE_TZS,
        buyerId: userId || '',
        buyerPhone: phone,
        status: 'pending',
        mongikeId: result.data?.id || '',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    res.json({
      order_id,
      mongikeId: result.data?.id || '',
      message: 'Payment prompt sent to your phone.',
    });
  } catch (e) {
    res.status(500).json({ error: e.message });
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
    res.status(500).json({ error: e.message });
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
    res.status(500).json({ error: e.message });
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
    const allowed = ['accountTier', 'isAdmin', 'isSuspended', 'displayName', 'phone'];
    for (const field of allowed) {
      if (req.body[field] !== undefined) updates[field] = req.body[field];
    }
    if (Object.keys(updates).length === 0) {
      return res.status(400).json({ error: 'No valid fields to update' });
    }
    await db.collection('users').doc(uid).update(updates);
    res.json({ updated: true, uid, updates });
  } catch (e) {
    res.status(500).json({ error: e.message });
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
    res.status(500).json({ error: e.message });
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
    res.status(500).json({ error: e.message });
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
    res.status(500).json({ error: e.message });
  }
});

// ============================================================
// 🔐 FORGOT PASSWORD — SEND OTP
// ============================================================
app.post('/api/send-otp', async (req, res) => {
  try {
    const { email } = req.body;
    if (!email) return res.status(400).json({ error: 'Email is required' });
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
        subject: 'Soko Langu — Password Reset OTP',
        html: `
          <div style="font-family: Arial, sans-serif; max-width: 480px; margin: 0 auto;">
            <h2 style="color: #2D6A4F;">Soko Langu</h2>
            <p>Use the OTP below to reset your password:</p>
            <div style="font-size: 32px; font-weight: bold; color: #2D6A4F; text-align: center; 
                        padding: 20px; background: #F0F9F1; border-radius: 12px; letter-spacing: 8px;">
              ${otp}
            </div>
            <p style="color: #666;">This OTP expires in 10 minutes.</p>
            <p style="color: #999; font-size: 12px;">If you didn't request this, ignore this email.</p>
          </div>
        `,
      });
    } catch (mailErr) {
      return res.status(500).json({ error: 'Failed to send email. Try again.' });
    }

    res.json({ sent: true, message: 'OTP sent to your email' });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ============================================================
// 🔐 VERIFY OTP
// ============================================================
app.post('/api/verify-otp', async (req, res) => {
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
    res.status(500).json({ error: e.message });
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
    res.status(500).json({ error: e.message });
  }
});

// ============================================================
// 📲 FCM — SEND BULK PUSH NOTIFICATION (to multiple tokens)
// ============================================================
app.post('/api/send-bulk-notification', async (req, res) => {
  try {
    const { title, body, tokens, target } = req.body;
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
        const message = {
          tokens: batch,
          notification: { title, body: body || '' },
          android: { priority: 'high' },
          apns: {
            payload: {
              aps: { sound: 'default', 'content-available': 1 },
            },
          },
        };

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
    res.status(500).json({ error: e.message });
  }
});

// ============================================================
// 💸 WITHDRAW — Send money to user's M-Pesa via Mongike
// ============================================================
app.post('/api/withdraw', async (req, res) => {
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

    const totalCoinsBefore = (user.viewerCoins || 0) + (user.coins || 0);
    if (amount > totalCoinsBefore) {
      return res.status(400).json({ error: 'Insufficient balance' });
    }

    const FEE_MONGIKE = 2000;
    const netAmount = amount - FEE_MONGIKE;
    if (netAmount <= 0) {
      return res.status(400).json({ error: 'Amount too small after fee (min TZS 2001)' });
    }

    const resp = await fetch(`${MONGIKE_BASE}/payouts/withdraw`, {
      method: 'POST',
      headers: {
        'x-api-key': MONGIKE_API_KEY,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        amount: netAmount,
        recipient_phone: phone,
      }),
    });

    const result = await resp.json();

    if (result.status !== 'success') {
      await auditLog({
        userId, type: 'withdraw_failed', amount, balanceBefore: totalCoinsBefore, balanceAfter: totalCoinsBefore,
        reason: `Mongike payout failed: ${result.message || 'Unknown error'}`,
        metadata: { phone, netAmount, withdrawalType: 'viewer' },
      });
      return res.status(500).json({ error: result.message || 'Mongike payout failed' });
    }

    const viewerCoins = user.viewerCoins || 0;
    const regCoins = user.coins || 0;
    let remaining = amount;
    const deductions = {};
    if (viewerCoins > 0) {
      const take = Math.min(remaining, viewerCoins);
      deductions.viewerCoins = admin.firestore.FieldValue.increment(-take);
      remaining -= take;
    }
    if (remaining > 0 && regCoins > 0) {
      const take = Math.min(remaining, regCoins);
      deductions.coins = admin.firestore.FieldValue.increment(-take);
      remaining -= take;
    }
    await db.collection('users').doc(userId).update(deductions);

    await db.collection('withdrawals').add({
      userId,
      type: 'viewer',
      amount,
      feeMongike: FEE_MONGIKE,
      netAmount,
      phone,
      reference: result.data?.id || '',
      status: 'completed',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    await auditLog({
      userId, type: 'viewer_withdraw', amount: -amount,
      balanceBefore: totalCoinsBefore, balanceAfter: totalCoinsBefore - amount,
      reason: `Viewer withdrawal: TZS ${netAmount} to ${phone}`,
      relatedId: result.data?.id || '',
      metadata: { phone, netAmount, fee: FEE_MONGIKE },
    });

    res.json({
      success: true,
      netAmount,
      reference: result.data?.id || '',
      message: `TZS ${netAmount} sent to ${phone}`,
    });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ============================================================
// 🔒 ESCROW — Release payment to seller (buyer confirms delivery)
// ============================================================
app.post('/api/escrow/release', async (req, res) => {
  try {
    const { orderId, userId } = req.body;
    if (!orderId || !userId) {
      return res.status(400).json({ error: 'Missing orderId or userId' });
    }
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const orderDoc = await db.collection('orders').doc(orderId).get();
    if (!orderDoc.exists) return res.status(404).json({ error: 'Order not found' });

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

    await orderDoc.ref.update({
      status: 'delivered',
      escrowReleased: true,
      escrowReleasedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Credit seller's balance (full amount minus platform fee if any)
    const orderAmount = order.totalAmount || 0;
    const sellerPayout = orderAmount;

    const sellerDoc = await db.collection('users').doc(order.sellerId).get();
    const balanceBefore = sellerDoc.exists ? (sellerDoc.data().sellerBalance || 0) : 0;

    await db.collection('users').doc(order.sellerId).update({
      sellerBalance: admin.firestore.FieldValue.increment(sellerPayout),
    });

    // Record in revenue_transactions for seller
    await db.collection('revenue_transactions').add({
      userId: order.sellerId,
      type: 'sale',
      amount: sellerPayout,
      orderId,
      description: `Sale: ${order.items?.map(i => i.name).join(', ') || 'Product'} - TZS ${sellerPayout}`,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Audit log
    await auditLog({
      userId: order.sellerId,
      type: 'escrow_release',
      amount: sellerPayout,
      balanceBefore,
      balanceAfter: balanceBefore + sellerPayout,
      reason: `Escrow released for order ${orderId}`,
      relatedId: orderId,
      metadata: { buyerId: order.buyerId, items: order.items },
    });

    // Notify seller
    const notifRef = db.collection('notifications');
    await notifRef.add({
      userId: order.sellerId,
      title: 'Payment Released!',
      body: `Buyer confirmed delivery for order #${orderId.substring(0, 8)}. TZS ${sellerPayout} added to your balance.`,
      isRead: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    res.json({ success: true, message: 'Escrow released. Seller balance credited.' });
  } catch (e) {
    res.status(500).json({ error: e.message });
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

    const orderDoc = await db.collection('orders').doc(orderId).get();
    if (!orderDoc.exists) return res.status(404).json({ error: 'Order not found' });

    const order = orderDoc.data();
    const orderAmount = order.totalAmount || 0;
    const sellerPayout = orderAmount;

    await orderDoc.ref.update({
      status: 'delivered',
      escrowReleased: true,
      escrowReleasedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    if (order.sellerId) {
      await db.collection('users').doc(order.sellerId).update({
        sellerBalance: admin.firestore.FieldValue.increment(sellerPayout),
      });
      await db.collection('revenue_transactions').add({
        userId: order.sellerId,
        type: 'sale',
        amount: sellerPayout,
        orderId,
        description: `Sale (admin release): ${order.items?.map(i => i.name).join(', ') || 'Product'} - TZS ${sellerPayout}`,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    res.json({ success: true, message: 'Escrow force-released by admin' });
  } catch (e) {
    res.status(500).json({ error: e.message });
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
    if (amount > sellerBalance) {
      return res.status(400).json({ error: 'Insufficient balance' });
    }

    const netAmount = amount - MONGIKE_PAYOUT_FEE;
    if (netAmount <= 0) {
      return res.status(400).json({ error: `Amount too small after fee (min TZS ${MONGIKE_PAYOUT_FEE + 1})` });
    }

    const resp = await fetch(`${MONGIKE_BASE}/payouts/withdraw`, {
      method: 'POST',
      headers: {
        'x-api-key': MONGIKE_API_KEY,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        amount: netAmount,
        recipient_phone: phone,
      }),
    });

    const result = await resp.json();

    if (result.status !== 'success') {
      await auditLog({
        userId, type: 'withdraw_failed', amount, balanceBefore: sellerBalance, balanceAfter: sellerBalance,
        reason: `Mongike payout failed: ${result.message || 'Unknown error'}`,
        relatedId: '', metadata: { phone, netAmount },
      });
      return res.status(500).json({ error: result.message || 'Mongike payout failed' });
    }

    await db.collection('users').doc(userId).update({
      sellerBalance: admin.firestore.FieldValue.increment(-amount),
    });

    await db.collection('withdrawals').add({
      userId,
      type: 'seller',
      amount,
      feeMongike: MONGIKE_PAYOUT_FEE,
      netAmount,
      phone,
      reference: result.data?.id || '',
      status: 'completed',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    await auditLog({
      userId, type: 'seller_withdraw', amount: -amount,
      balanceBefore: sellerBalance, balanceAfter: sellerBalance - amount,
      reason: `Seller withdrawal: TZS ${netAmount} to ${phone}`,
      relatedId: result.data?.id || '',
      metadata: { phone, netAmount, fee: MONGIKE_PAYOUT_FEE },
    });

    res.json({
      success: true,
      netAmount,
      reference: result.data?.id || '',
      message: `TZS ${netAmount} sent to ${phone}`,
    });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ============================================================
// 🎬 STREAMER WITHDRAW — Send gift earnings to mobile money
// ============================================================
app.post('/api/streamer/withdraw', async (req, res) => {
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

    const streamerEarnings = user.streamerEarnings || 0;
    if (amount > streamerEarnings) {
      return res.status(400).json({ error: 'Insufficient gift earnings' });
    }

    const netAmount = amount - MONGIKE_PAYOUT_FEE;
    if (netAmount <= 0) {
      return res.status(400).json({ error: `Amount too small after fee (min TZS ${MONGIKE_PAYOUT_FEE + 1})` });
    }

    const resp = await fetch(`${MONGIKE_BASE}/payouts/withdraw`, {
      method: 'POST',
      headers: {
        'x-api-key': MONGIKE_API_KEY,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        amount: netAmount,
        recipient_phone: phone,
      }),
    });

    const result = await resp.json();

    if (result.status !== 'success') {
      await auditLog({
        userId, type: 'streamer_withdraw_failed', amount, balanceBefore: streamerEarnings, balanceAfter: streamerEarnings,
        reason: `Mongike payout failed: ${result.message || 'Unknown error'}`,
        metadata: { phone, netAmount },
      });
      return res.status(500).json({ error: result.message || 'Mongike payout failed' });
    }

    await db.collection('users').doc(userId).update({
      streamerEarnings: admin.firestore.FieldValue.increment(-amount),
    });

    await db.collection('streamer_withdrawals').add({
      userId,
      amount,
      fee: MONGIKE_PAYOUT_FEE,
      netAmount,
      phone,
      reference: result.data?.id || '',
      status: 'completed',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    await auditLog({
      userId, type: 'streamer_withdraw', amount: -amount,
      balanceBefore: streamerEarnings, balanceAfter: streamerEarnings - amount,
      reason: `Streamer withdrawal: TZS ${netAmount} to ${phone}`,
      relatedId: result.data?.id || '',
      metadata: { phone, netAmount, fee: MONGIKE_PAYOUT_FEE },
    });

    res.json({
      success: true,
      netAmount,
      reference: result.data?.id || '',
      message: `TZS ${netAmount} sent to ${phone}`,
    });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ============================================================
// 📊 ADMIN WITHDRAW — Send ad revenue to mobile money
// ============================================================
app.post('/api/admin/withdraw', async (req, res) => {
  try {
    const { userId, amount, phone } = req.body;
    if (!userId || !amount || !phone) {
      return res.status(400).json({ error: 'Missing userId, amount, or phone' });
    }
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const userDoc = await db.collection('users').doc(userId).get();
    if (!userDoc.exists) return res.status(404).json({ error: 'User not found' });

    const user = userDoc.data();
    if (!user.isAdmin) return res.status(403).json({ error: 'Admin access required' });
    if (user.isSuspended) return res.status(403).json({ error: 'Account suspended' });

    const netAmount = amount - MONGIKE_PAYOUT_FEE;
    if (netAmount <= 0) {
      return res.status(400).json({ error: `Amount too small after fee (min TZS ${MONGIKE_PAYOUT_FEE + 1})` });
    }

    const resp = await fetch(`${MONGIKE_BASE}/payouts/withdraw`, {
      method: 'POST',
      headers: {
        'x-api-key': MONGIKE_API_KEY,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        amount: netAmount,
        recipient_phone: phone,
      }),
    });

    const result = await resp.json();

    if (result.status !== 'success') {
      await auditLog({
        userId, type: 'admin_withdraw_failed', amount,
        reason: `Mongike payout failed: ${result.message || 'Unknown error'}`,
        metadata: { phone, netAmount },
      });
      return res.status(500).json({ error: result.message || 'Mongike payout failed' });
    }

    await db.collection('admin_withdrawals').add({
      userId,
      amount,
      fee: MONGIKE_PAYOUT_FEE,
      netAmount,
      phone,
      reference: result.data?.id || '',
      status: 'completed',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    await auditLog({
      userId, type: 'admin_withdraw', amount: -amount,
      reason: `Admin ad revenue withdrawal: TZS ${netAmount} to ${phone}`,
      relatedId: result.data?.id || '',
      metadata: { phone, netAmount, fee: MONGIKE_PAYOUT_FEE },
    });

    res.json({
      success: true,
      netAmount,
      reference: result.data?.id || '',
      message: `TZS ${netAmount} sent to ${phone}`,
    });
  } catch (e) {
    res.status(500).json({ error: e.message });
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
    let totalViewerCoins = 0;
    let totalCoins = 0;
    balanceSnap.docs.forEach(doc => {
      const d = doc.data();
      totalSellerBalance += d.sellerBalance || 0;
      totalViewerCoins += d.viewerCoins || 0;
      totalCoins += d.coins || 0;
    });

    res.json({
      totalUsers,
      totalOrders,
      totalWithdrawals,
      totalAdViews,
      totalSellerBalance,
      totalViewerCoins,
      totalCoins,
    });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ============================================================
// 📊 ADMIN — All transactions (Mongike payments)
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
    res.status(500).json({ error: e.message });
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
    res.status(500).json({ error: e.message });
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
    res.status(500).json({ error: e.message });
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
    res.status(500).json({ error: e.message });
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
    res.status(500).json({ error: e.message });
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
    res.status(500).json({ error: e.message });
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
    res.status(500).json({ error: e.message });
  }
});

// ============================================================
// 👑 ADMIN — Unsuspend user
// ============================================================
app.post('/api/admin/users/:uid/unsuspend', async (req, res) => {
  try {
    const secret = req.headers['x-admin-secret'];
    if (secret !== process.env.ADMIN_SECRET) return res.status(401).json({ error: 'Unauthorized' });
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const { uid } = req.params;
    await db.collection('users').doc(uid).update({
      isSuspended: false,
      suspendedAt: admin.firestore.FieldValue.delete(),
      suspendedBy: admin.firestore.FieldValue.delete(),
    });

    res.json({ success: true, message: 'User unsuspended' });
  } catch (e) {
    res.status(500).json({ error: e.message });
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
    res.status(500).json({ error: e.message });
  }
});

// ============================================================
// 👑 ADMIN — Delete product
// ============================================================
app.delete('/api/admin/products/:id', async (req, res) => {
  try {
    const secret = req.headers['x-admin-secret'];
    if (secret !== process.env.ADMIN_SECRET) return res.status(401).json({ error: 'Unauthorized' });
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const { id } = req.params;
    await db.collection('products').doc(id).delete();

    res.json({ success: true, message: 'Product deleted' });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ============================================================
// 👑 ADMIN — Delete user completely (all data)
// ============================================================
app.delete('/api/admin/users/:uid/full-delete', async (req, res) => {
  try {
    const secret = req.headers['x-admin-secret'];
    if (secret !== process.env.ADMIN_SECRET) return res.status(401).json({ error: 'Unauthorized' });
    if (!db) return res.status(503).json({ error: 'Database not configured' });

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
    res.status(500).json({ error: e.message });
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

    const allowed = ['transactions', 'withdrawals', 'revenue_transactions', 'ad_views', 'notifications', 'products', 'orders', 'reviews', 'audit_log', 'viewer_ad_views', 'viewer_payouts', 'viewer_soft_payouts'];
    if (!allowed.includes(collection)) return res.status(403).json({ error: 'Collection not allowed for deletion' });

    await db.collection(collection).doc(docId).delete();

    await auditLog({
      userId: 'admin', type: 'admin_delete', amount: 0,
      reason: `Admin deleted ${collection}/${docId}`,
      metadata: { collection, docId },
    });

    res.json({ success: true, message: `Document ${collection}/${docId} deleted` });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ---- Handle boost payment completion in webhook ----
// (Insert right after the 'coins' handler in the webhook)
// ============================================================

app.use((err, req, res, next) => {
  console.error('Unhandled error:', err);
  res.status(500).json({ error: err.message || 'Internal server error' });
});

app.get('/health', (req, res) => res.json({ status: 'ok' }));

app.listen(PORT, () => console.log(`Server running on port ${PORT}`));
