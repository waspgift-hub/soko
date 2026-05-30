require('dotenv').config();
const express = require('express');
const cors = require('cors');
const crypto = require('crypto');
const admin = require('firebase-admin');
const nodemailer = require('nodemailer');

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
const PORT = process.env.PORT || 3000;
const WEBHOOK_SECRET = process.env.WEBHOOK_SECRET || '';
const ESCROW_AUTO_RELEASE_DAYS = parseInt(process.env.ESCROW_AUTO_RELEASE_DAYS) || 14;
const MAX_DAILY_SALE_AMOUNT = parseInt(process.env.MAX_DAILY_SALE_AMOUNT) || 5000000;

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
  if (!WEBHOOK_SECRET) return next(); // skip if not configured
  const secret = req.headers['x-webhook-secret'];
  if (secret !== WEBHOOK_SECRET) {
    console.warn(`Webhook secret mismatch from IP: ${req.ip}`);
    return res.status(200).json({ received: false });
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
async function checkDuplicatePayment(productId, buyerId) {
  if (!db) return false;
  try {
    const snap = await db.collection('transactions')
      .where('productId', '==', productId)
      .where('buyerId', '==', buyerId)
      .where('status', 'in', ['pending', 'escrow_hold'])
      .limit(1)
      .get();
    return snap.docs.length > 0;
  } catch { return false; }
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

// ============================================================
// ⭐ BOOST PRODUCT — TIER-BASED FEATURED LISTING
// ============================================================
const BOOST_TIERS = {
  bronze: { price: 1500, days: 3 },
  silver: { price: 3000, days: 7 },
  gold: { price: 10000, days: 30 },
};

const MONGIKE_TX_FEE = 180;          // Mongike charges TZS 180 per transaction
const MONGIKE_PAYOUT_FEE = 2000;     // Mongike charges TZS 2,000 per payout
const MONGIKE_BASE = 'https://mongike.com/api/v1';
const PLATFORM_COMMISSION_PERCENT = 0.04; // 4% platform commission
const MIN_WITHDRAWAL = 5000;          // Minimum withdrawal TZS 5,000

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
    const webhookUrl = process.env.WEBHOOK_URL || `https://sokolangu-production.up.railway.app/api/webhook`;

    const result = await callMongikePay({
      order_id,
      amount: tierConfig.price,
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
        tier: tier.toLowerCase(),
        amount: tierConfig.price,
        durationDays: tierConfig.days,
        userId: userId || '',
        buyerPhone: phone,
        status: 'pending',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    res.json({
      order_id,
      mongikeId: result.data?.id || '',
      message: 'Payment prompt sent to your phone. Check Mongike, Airtel Money, Mixx, or Halopesa and enter your PIN.',
    });
  } catch (e) {
    if (e.name === 'AbortError') {
      return res.status(504).json({ error: 'Mongike request timed out. Please try again.' });
    }
    res.status(500).json({ error: e.message || 'Internal server error' });
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
    const isChat = notifType === 'chat' || notifType === 'group_chat';

    const message = {
      token: fcmToken,
      notification: { title, body: body || '' },
      data: data || {},
      android: {
        priority: isChat ? 'high' : 'normal',
        notification: isChat ? {
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
      apns: isChat ? {
        payload: {
          aps: {
            sound: 'default',
            category: 'chat_message',
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
        subject: '🔐 Soko Langu — Reset Your Password',
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
                      <h1 style="color:#ffffff; margin:0; font-size:24px; font-weight:700; letter-spacing:1px;">SOKO LANGU</h1>
                      <p style="color:#95D5B2; margin:4px 0 0; font-size:13px;">Tanzania's Trusted Marketplace</p>
                    </td>
                  </tr>
                  <!-- Body -->
                  <tr>
                    <td style="padding:32px 24px;">
                      <h2 style="color:#1B4332; font-size:20px; margin:0 0 8px;">Password Reset Request</h2>
                      <p style="color:#555; font-size:14px; line-height:1.6; margin:0 0 20px;">
                        Someone requested to reset the password for your Soko Langu account. 
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
                        Soko Langu &bull; Tanzania<br>
                        Need help? Contact us through the app.
                      </p>
                    </td>
                  </tr>
                  <!-- Footer -->
                  <tr>
                    <td style="background:#1B4332; padding:16px 24px; text-align:center;">
                      <p style="color:#95D5B2; font-size:11px; margin:0;">
                        &copy; ${new Date().getFullYear()} Soko Langu. All rights reserved.
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
// 🔒 ESCROW — Release payment to seller (buyer confirms delivery)
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

    let sellerId, sellerReceives, productName, productPrice, escrowReleased, mongikeFee, platformFee;

    if (txDoc.exists) {
      const tx = txDoc.data();
      if (tx.buyerId !== userId) {
        return res.status(403).json({ error: 'Only the buyer can confirm delivery' });
      }
      if (tx.status !== 'escrow_hold') {
        return res.status(400).json({ error: `Cannot release escrow from status: ${tx.status}` });
      }
      if (tx.escrowReleased === true) {
        return res.status(400).json({ error: 'Escrow already released' });
      }
      sellerId = tx.sellerId;
      sellerReceives = tx.sellerReceives || 0;
      productName = tx.productName || 'Product';
      productPrice = tx.productPrice || 0;
      escrowReleased = tx.escrowReleased;
      mongikeFee = tx.mongikeFee || 0;
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
      mongikeFee = 0;
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

    // Move from pendingEscrow to sellerBalance
    await db.collection('users').doc(sellerId).update({
      sellerBalance: admin.firestore.FieldValue.increment(sellerReceives),
      pendingEscrow: admin.firestore.FieldValue.increment(-sellerReceives),
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

    // Try auto-payout to seller's phone now that escrow is released
    if (sellerReceives > 0) {
      try {
        const sellerUserDoc = await db.collection('users').doc(sellerId).get();
        const sellerPhone = sellerUserDoc.exists ? sellerUserDoc.data().phone : null;

        if (sellerPhone) {
          const payoutFee = MONGIKE_PAYOUT_FEE;
          const netPayout = sellerReceives - payoutFee;

          if (netPayout > 0) {
            const payoutResp = await fetch(`${MONGIKE_BASE}/payouts/withdraw`, {
              method: 'POST',
              headers: {
                'x-api-key': MONGIKE_API_KEY,
                'Content-Type': 'application/json',
              },
              body: JSON.stringify({
                amount: netPayout,
                recipient_phone: sellerPhone,
              }),
            });

            const payoutData = await payoutResp.json();

            if (payoutData.status === 'success') {
              await db.collection('withdrawals').add({
                userId: sellerId,
                type: 'seller',
                amount: sellerReceives,
                feeMongike: payoutFee,
                netAmount: netPayout,
                phone: sellerPhone,
                reference: payoutData.data?.id || orderId,
                status: 'completed',
                autoPayout: true,
                transactionId: orderId,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
              });

              // Deduct from seller balance (already credited above)
              // Actually keep in balance - this is a separate payout record
            }
          }
        }
      } catch (payoutErr) {
        console.error('Escrow auto-payout error:', payoutErr);
        // Funds already in sellerBalance — they can withdraw manually
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
      await db.collection('users').doc(sellerId).update({
        sellerBalance: admin.firestore.FieldValue.increment(sellerReceives),
        pendingEscrow: admin.firestore.FieldValue.increment(-sellerReceives),
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
    res.status(500).json({ error: e.message });
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
    res.status(500).json({ error: e.message });
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
    res.status(500).json({ error: e.message });
  }
});

// Admin KYC review
app.post('/api/admin/kyc/review', async (req, res) => {
  try {
    const secret = req.headers['x-admin-secret'];
    if (secret !== process.env.ADMIN_SECRET) return res.status(401).json({ error: 'Unauthorized' });
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

    await auditLog({
      userId,
      type: `kyc_${status}`,
      amount: 0,
      reason: `KYC ${status} by admin. Notes: ${notes || ''}`,
    });

    res.json({ success: true, message: `KYC ${status}` });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.get('/api/admin/kyc/pending', async (req, res) => {
  try {
    const secret = req.headers['x-admin-secret'];
    if (secret !== process.env.ADMIN_SECRET) return res.status(401).json({ error: 'Unauthorized' });
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
    res.status(500).json({ error: e.message });
  }
});

// ============================================================
// 🛒 MARKETPLACE — Initiate product purchase payment via Mongike
// ============================================================
app.post('/api/create-marketplace-payment-link', paymentRateLimit, async (req, res) => {
  try {
    const { productPrice, productName, productId, sellerId, sellerName, email, phone, buyerId } = req.body;
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

    const order_id = `order_${Date.now()}_${buyerId ? buyerId.substring(0, 8) : 'anon'}`;
    const webhookUrl = process.env.WEBHOOK_URL || `https://sokolangu-production.up.railway.app/api/webhook`;

    const result = await callMongikePay({
      order_id,
      amount: Math.round(productPrice),
      buyer_phone: phone,
      fee_payer: 'MERCHANT',
      webhook_url: webhookUrl,
    });

    if (result.status !== 'success') {
      return res.status(500).json({ error: result.message || 'Mongike error' });
    }

    if (db) {
      await db.collection('transactions').doc(order_id).set({
        type: 'purchase',
        productId,
        productName: sanitize(productName),
        sellerId,
        sellerName: sanitize(sellerName),
        buyerPhone: phone,
        buyerId: buyerId || '',
        productPrice: Math.round(productPrice),
        status: 'pending',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    res.json({
      order_id,
      mongikeId: result.data?.id || '',
      message: 'Payment prompt sent to your phone. Check Mongike, Airtel Money, Mixx, or Halopesa and enter your PIN.',
    });
  } catch (e) {
    if (e.name === 'AbortError') {
      return res.status(504).json({ error: 'Mongike request timed out. Please try again.' });
    }
    res.status(500).json({ error: e.message || 'Internal server error' });
  }
});

// ============================================================
// 🔔 MONGIKE WEBHOOK — Handle payment completion
// ============================================================
app.post('/api/webhook', verifyWebhook, async (req, res) => {
  try {
    const { order_id, status, amount, buyer_phone } = req.body;
    if (!order_id || !status) {
      return res.status(200).json({ received: false });
    }

    if (!db) return res.status(200).json({ received: false });

    const txDoc = await db.collection('transactions').doc(order_id).get();
    if (!txDoc.exists) return res.status(200).json({ received: false });

    const tx = txDoc.data();

    if (status === 'success' || status === 'completed') {
      await txDoc.ref.update({ status: 'completed' });

      if (tx.type === 'boost') {
        // Handle boost payment success
        const tier = tx.tier || 'bronze';
        const tierConfig = BOOST_TIERS[tier] || BOOST_TIERS.bronze;
        const now = new Date();
        const boostedUntil = new Date(now.getTime() + tierConfig.days * 24 * 60 * 60 * 1000);

        await db.collection('products').doc(tx.productId).update({
          isBoosted: true,
          boostedUntil: admin.firestore.Timestamp.fromDate(boostedUntil),
          boostTier: tier,
          // Backward compat
          isFeatured: true,
          featuredUntil: admin.firestore.Timestamp.fromDate(boostedUntil),
        });

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
              await admin.messaging().send({
                token,
                notification: { title: '✅ Boost imewashwa!', body: `Bidhaa yako imepandishwa kwa daraja la ${tier} kwa siku ${tierConfig.days}.` },
                data: { type: 'boost', productId: tx.productId || '' },
              });
            }
          } catch (_) {}
        }
      }

      if (tx.type === 'purchase') {
        const productPrice = tx.productPrice || 0;
        const platformFee = Math.round(productPrice * PLATFORM_COMMISSION_PERCENT);
        const mongikeFee = MONGIKE_TX_FEE;
        const payoutFee = MONGIKE_PAYOUT_FEE;
        const sellerReceives = productPrice - platformFee - mongikeFee - payoutFee;
        const escrowExpiry = new Date(Date.now() + ESCROW_AUTO_RELEASE_DAYS * 24 * 60 * 60 * 1000);

        // Update transaction — put in escrow instead of auto-paying
        await txDoc.ref.update({
          processingFee: mongikeFee,
          platformFee,
          mongikeFee,
          payoutFee,
          sokoLanguCommission: platformFee,
          totalAmount: productPrice,
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
          mongikeFee,
          payoutFee,
          sokoLanguCommission: platformFee,
          buyerName: tx.buyerName || '',
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
        });

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
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          // Send FCM push to seller
          try {
            const sellerSnap = await db.collection('users').doc(tx.sellerId).get();
            const sellerToken = sellerSnap.data()?.fcmToken;
            if (sellerToken) {
              await admin.messaging().send({
                token: sellerToken,
                notification: { title: 'Umepata Mauzo!', body: `${tx.productName || 'Bidhaa'} imeuzwa. TZS ${sellerReceives.toLocaleString()} imewekwa escrow.` },
                data: { type: 'order', productId: tx.productId || '', transactionId: order_id },
              });
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
              await admin.messaging().send({
                token: buyerToken,
                notification: { title: 'Malipo Yamekamilika!', body: `Malipo ya ${tx.productName || 'Bidhaa'} yamepokelewa.` },
                data: { type: 'order', productId: tx.productId || '', transactionId: order_id },
              });
            }
          } catch (_) {}
        }
      }
    } else if (status === 'failed' || status === 'cancelled') {
      await txDoc.ref.update({ status: 'failed' });
    }

    res.status(200).json({ received: true });
  } catch (e) {
    console.error('Webhook error:', e);
    res.status(200).json({ received: true });
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

    // Minimum withdrawal check
    if (amount < MIN_WITHDRAWAL) {
      return res.status(400).json({ error: `Minimum withdrawal is TZS ${MIN_WITHDRAWAL.toLocaleString()}` });
    }

    if (amount > sellerBalance) {
      return res.status(400).json({ error: 'Insufficient balance' });
    }

    const netAmount = amount - MONGIKE_PAYOUT_FEE;
    if (netAmount <= 0) {
      return res.status(400).json({ error: `Amount too small after TZS ${MONGIKE_PAYOUT_FEE.toLocaleString()} payout fee` });
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
      reason: `Seller withdrawal: TZS ${netAmount.toLocaleString()} to ${phone}`,
      relatedId: result.data?.id || '',
      metadata: { phone, netAmount, fee: MONGIKE_PAYOUT_FEE },
    });

    res.json({
      success: true,
      netAmount,
      fee: MONGIKE_PAYOUT_FEE,
      reference: result.data?.id || '',
      message: `TZS ${netAmount.toLocaleString()} sent to ${phone}`,
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
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const now = admin.firestore.Timestamp.now();
    const expired = await db.collection('transactions')
      .where('status', '==', 'escrow_hold')
      .where('escrowExpiresAt', '<=', now)
      .where('escrowReleased', '!=', true)
      .limit(20)
      .get();

    let released = 0;
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
        await db.collection('users').doc(sellerId).update({
          sellerBalance: admin.firestore.FieldValue.increment(sellerReceives),
          pendingEscrow: admin.firestore.FieldValue.increment(-sellerReceives),
        });

        await db.collection('notifications').add({
          userId: sellerId,
          title: 'Escrow Imefunguliwa Kiotomatiki',
          body: `${tx.productName || 'Bidhaa'} escrow imefunguliwa baada ya muda wake. TZS ${sellerReceives.toLocaleString()} zimewekwa kwenye salio lako.`,
          isRead: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      released++;
    }

    res.json({ success: true, released, total: expired.docs.length });
  } catch (e) {
    console.error('Cron release-escrows error:', e);
    res.status(500).json({ error: e.message });
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
    res.status(500).json({ error: e.message });
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
    res.status(500).json({ error: e.message });
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
    res.status(500).json({ error: e.message });
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
    res.status(500).json({ error: e.message });
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
    res.status(500).json({ error: e.message });
  }
}));

// Dismiss a fraud alert
app.patch('/api/fraud/alerts/:id/dismiss', asyncHandler(async (req, res) => {
  try {
    await db.collection('fraud_alerts').doc(req.params.id).update({ resolved: true });
    res.json({ success: true });
  } catch (e) {
    res.status(500).json({ error: e.message });
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
    res.status(500).json({ error: e.message });
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
    res.status(500).json({ error: e.message });
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
      if (!existing.empty) continue;

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
    res.status(500).json({ error: e.message });
  }
}));

// ─── FLASH SALE: NOTIFY USERS ──────────────────────────
app.post('/api/flash-sale/notify', asyncHandler(async (req, res) => {
  try {
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const { productName, salePrice, discountPercent, sellerId } = req.body;

    // Get all users with FCM tokens
    const usersSnap = await db.collection('users')
      .where('fcmToken', '!=', null)
      .limit(500)
      .get();

    const tokens = [];
    for (const doc of usersSnap.docs) {
      const token = doc.data().fcmToken;
      if (token) tokens.push(token);
    }

    let sentCount = 0;
    if (tokens.length > 0) {
      const message = {
        tokens,
        notification: {
          title: `⚡ Flash Sale! -${discountPercent}%`,
          body: `${productName} sasa TSh ${salePrice} pekee!`,
        },
        data: {
          type: 'flash_sale',
          productName: productName || '',
        },
        android: { priority: 'high' },
      };
      const resp = await admin.messaging().sendEachForMulticast(message);
      sentCount = resp.successCount;
    }

    // Write in-app notification for all users
    const usersForNotif = await db.collection('users').limit(500).get();
    const batch = db.batch();
    for (const doc of usersForNotif.docs) {
      if (doc.id === sellerId) continue;
      const notifRef = db.collection('notifications').doc();
      batch.set(notifRef, {
        userId: doc.id,
        title: `⚡ Flash Sale! -${discountPercent}%`,
        body: `${productName} sasa TSh ${salePrice} pekee!`,
        data: { type: 'flash_sale' },
        isRead: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();

    res.json({ success: true, pushSent: sentCount, inAppNotified: usersForNotif.size });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
}));

app.get('/health', (req, res) => res.json({ status: 'ok' }));

app.listen(PORT, () => console.log(`Server running on port ${PORT}`));
