// Compat orders/checkout router: verbatim port of proven old-server
// handlers (payment-link, statements, transaction-status, transactions
// create, gateway-fee, orders transition) under original /api paths.
const express = require('express');
const admin = require('firebase-admin');
const { getFirebaseFirestore } = require('../../config/firebase');
const { requireUser, isOwnerOrAdmin } = require('./auth-helpers');
const { sendOneSignalNotification } = require('./notify');
const { clickpesaCollect, calcGatewayFee } = require('../../../clickpesa');
const { resolveEffectivePrice } = require('../../../money');
const { paymentLimiter } = require('../../middleware/rateLimiter');
const config = require('../../config');
const cache = require('../../../cache');
const { getRedis } = require('../../config/redis');

try {
  cache.setRedisClient(getRedis());
} catch (e) {
  console.error('[COMPAT-ORDERS] cache wiring failed:', e.message);
}

const db = getFirebaseFirestore();
const MAX_DAILY_SALE_AMOUNT = config.business.maxDailySaleAmount;
const PLATFORM_COMMISSION_PERCENT = config.business.platformCommissionPercent;

function asyncHandler(fn) {
  return (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);
}

function sanitize(str) {
  if (typeof str !== 'string') return '';
  return str.replace(/<[^>]*>/g, '').trim().slice(0, 1000);
}

async function verifyAuthToken(req) {
  const { getFirebaseAuth } = require('../../config/firebase');
  const authHeader = req.headers.authorization || req.headers['Authorization'] || '';
  const token = authHeader.replace('Bearer ', '');
  if (!token) return null;
  try {
    const auth = getFirebaseAuth();
    if (!auth) return null;
    return await auth.verifyIdToken(token);
  } catch {
    return null;
  }
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

const router = express.Router();
router.post('/create-marketplace-payment-link', paymentLimiter, async (req, res) => {
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
        billDescription: `${sanitize(productName || 'Product')}`,
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
router.get('/transaction-status/:orderId', async (req, res) => {
  try {
    const { orderId } = req.params;
    if (!orderId) return res.status(400).json({ error: 'Missing orderId' });
    // Auth FIRST — a 404 before auth would let anyone probe which transaction
    // IDs exist in the database.
    if (!(await requireUser(req, res))) return;
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const cacheKey = `tx-status:${orderId}`;
    const cached = await cache.get(cacheKey);
    if (cached) return res.json(cached);

    const doc = await db.collection('transactions').doc(orderId).get();
    if (!doc.exists) return res.status(404).json({ error: 'Transaction not found' });

    const data = doc.data();
    if (!(await isOwnerOrAdmin(req, res, data.buyerId || data.userId || ''))) return;
    const result = {
      success: true,
      status: data.status || 'pending',
      failureReason: data.failureReason || null,
      completedAt: data.completedAt || null,
    };
    // 3s TTL — this endpoint is polled rapidly during USSD payment confirmation
    await cache.set(cacheKey, result, 3_000);
    res.json(result);
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});
router.post('/transactions/create', asyncHandler(async (req, res) => {
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

router.post('/gateway-fee', (req, res) => {
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
router.post('/orders/transition', async (req, res) => {
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

    // Role-based transition enforcement: buyer can't dispatch, seller can't confirm, etc.
    const actorRole = isAdmin ? 'admin' : isSeller ? 'seller' : 'buyer';
    if (!orderEngine.canActorTransition(actorRole, newStatus)) {
      return res.status(403).json({ error: `Role '${actorRole}' cannot transition order to '${newStatus}'` });
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

module.exports = router;
