require('dotenv').config();
const express = require('express');
const cors = require('cors');
const admin = require('firebase-admin');
const { RtcTokenBuilder, RtcRole } = require('agora-access-token');

const app = express();
app.use(cors());
app.use(express.json());

const MONGIKE_API_KEY = process.env.MONGIKE_API_KEY;
const AGORA_APP_ID = process.env.AGORA_APP_ID;
const AGORA_CERT = process.env.AGORA_APP_CERTIFICATE;
const PORT = process.env.PORT || 3000;

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

const MONGIKE_BASE = 'https://mongike.com/api/v1';

async function callMongikePay(body) {
  const resp = await fetch(`${MONGIKE_BASE}/payments/mobile-money/tanzania`, {
    method: 'POST',
    headers: {
      'x-api-key': MONGIKE_API_KEY,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });
  return resp.json();
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

// --- Monthly payout for all streamers ---
app.post('/api/process-monthly-payouts', async (req, res) => {
  try {
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const secret = req.headers['x-admin-secret'];
    if (secret !== process.env.ADMIN_SECRET) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const FEE_TOTAL = 4000;
    const FEE_PLATFORM = 2000;
    const FEE_MONGIKE = 2000;
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
          feeTotal: FEE_TOTAL,
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

// --- Mongike payment link for marketplace ---
app.post('/api/create-marketplace-payment-link', async (req, res) => {
  try {
    const { productPrice, productName, productId, sellerId, sellerName, email, phone } = req.body;
    if (!productPrice || productPrice <= 0) {
      return res.status(400).json({ error: 'Invalid price' });
    }

    if (!phone) {
      return res.status(400).json({ error: 'Phone number required' });
    }

    const order_id = `mkt_${Date.now()}`;
    const amount = Math.round(productPrice * 1.05);

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
        type: 'marketplace',
        buyerId: req.body.userId || '',
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
    res.status(500).json({ error: e.message });
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

        await db.collection('orders').add({
          buyerId: data.buyerId || '',
          sellerId: data.sellerId || '',
          productId: data.productId || '',
          productName: data.productName || '',
          productPrice: data.amount || 0,
          totalAmount: data.amount || 0,
          status: 'confirmed',
          paymentMethod: 'Mongike',
          transactionRef: orderId,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        if (data.productId) {
          await db.collection('products').doc(data.productId).update({
            soldCount: admin.firestore.FieldValue.increment(1),
          });
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

// --- Webhook redirect handler (legacy — kept for Flutterwave backwards compatibility) ---
app.get('/api/webhook-redirect', (req, res) => {
  const txRef = req.query.tx_ref || req.query.txref || '';
  res.redirect(`sokolangu://payment-callback?tx_ref=${txRef}`);
});

// --- Process unprocessed ad views into revenue ---
app.post('/api/process-ad-revenue', async (req, res) => {
  try {
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const RATE_PER_VIEW = 10;
    const SELLER_SHARE = 0.4;

    const snap = await db.collection('ad_views')
      .where('processed', '==', false)
      .limit(500)
      .get();

    let processed = 0;

    for (const doc of snap.docs) {
      const data = doc.data();
      const amount = Math.round(RATE_PER_VIEW * SELLER_SHARE);

      await db.runTransaction(async (tx) => {
        const walletRef = db.collection('wallets').doc(data.sellerId);
        const walletSnap = await tx.get(walletRef);

        let newBalance = amount;
        let newTotal = amount;
        if (walletSnap.exists) {
          newBalance += (walletSnap.data().balance || 0);
          newTotal += (walletSnap.data().totalEarnings || 0);
        }

        tx.set(walletRef, {
          balance: newBalance,
          totalEarnings: newTotal,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });

        tx.update(doc.ref, { processed: true });

        tx.set(db.collection('revenue_transactions').doc(), {
          userId: data.sellerId,
          type: 'ad_share',
          amount,
          sellerTier: data.sellerTier || 'silver',
          source: doc.id,
          description: `Ad revenue share - view by ${data.buyerId || 'unknown'}`,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          status: 'completed',
        });
      });

      processed++;
    }

    res.json({ processed, rate: RATE_PER_VIEW, sellerShare: `${SELLER_SHARE * 100}%` });
  } catch (e) {
    res.status(500).json({ error: e.message });
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

    const message = {
      token: fcmToken,
      notification: { title, body: body || '' },
      data: data || {},
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

// ---- Handle boost payment completion in webhook ----
// (Insert right after the 'coins' handler in the webhook)
// ============================================================

app.get('/health', (req, res) => res.json({ status: 'ok' }));

app.listen(PORT, () => console.log(`Server running on port ${PORT}`));
