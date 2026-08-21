const express = require('express');
const bcrypt = require('bcryptjs');
const crypto = require('crypto');

const router = express.Router();

const OTP_LENGTH = 4;
const OTP_MAX_ATTEMPTS = 3;
const OTP_LOCKOUT_HOURS = 24;
const BCRYPT_ROUNDS = 10;

function generateOtp(length) {
  length = length || OTP_LENGTH;
  var max = Math.pow(10, length);
  var min = Math.pow(10, length - 1);
  return crypto.randomInt(min, max).toString();
}

async function hashOtp(otp) {
  return bcrypt.hash(otp, BCRYPT_ROUNDS);
}

async function verifyOtp(otp, hash) {
  return bcrypt.compare(otp, hash);
}

function log(tag, msg) {
  console.error('[' + tag + '] ' + msg);
}

router.post('/generate-delivery-otp', async function (req, res) {
  try {
    var orderId = req.body.orderId;
    if (!orderId) return res.status(400).json({ error: 'Missing orderId' });
    var locals = req.app.locals;
    var admin = locals.admin;
    var db = locals.db;
    var requireUser = locals.requireUser;
    var sendOneSignalNotification = locals.sendOneSignalNotification;
    if (!db) return res.status(503).json({ error: 'Database not configured' });
    var auth = await requireUser(req, res);
    if (!auth.ok) return;
    var txDoc = await db.collection('transactions').doc(orderId).get();
    var orderDoc = await db.collection('orders').doc(orderId).get();
    var tx = txDoc.exists ? txDoc.data() : null;
    var order = orderDoc.exists ? orderDoc.data() : null;
    if (!tx && !order) return res.status(404).json({ error: 'Order not found' });
    var sellerId = (tx && tx.sellerId) || (order && order.sellerId);
    if (sellerId !== auth.uid) return res.status(403).json({ error: 'Only the seller can generate delivery OTP' });
    var status = (tx && tx.status) || (order && order.status);
    if (status !== 'dispatched') return res.status(400).json({ error: 'OTP can only be generated after dispatch. Current: ' + status });
    var lockedUntil = (tx && tx.deliveryOtpLockedUntil) || (order && order.deliveryOtpLockedUntil);
    if (lockedUntil) {
      var lockDate = (lockedUntil && lockedUntil.toDate) ? lockedUntil.toDate() : new Date(lockedUntil);
      if (lockDate > new Date()) return res.status(423).json({ error: 'OTP is locked due to too many failed attempts' });
    }
    var plaintext = generateOtp();
    var hashed = await hashOtp(plaintext);
    var buyerId = (tx && tx.buyerId) || (order && order.buyerId);
    var otpData = {
      deliveryOtpHash: hashed,
      deliveryOtpAttempts: 0,
      deliveryOtpLockedUntil: null,
      deliveryOtpGeneratedAt: admin.firestore.FieldValue.serverTimestamp(),
      deliveryOtpBuyerVisible: plaintext,
    };
    if (txDoc.exists) await txDoc.ref.update(otpData);
    if (orderDoc.exists) await orderDoc.ref.update(otpData);
    var productName = (tx && tx.productName) || (order && order.productName) || 'Bidhaa';
    try {
      await db.collection('notifications').add({
        userId: buyerId,
        title: 'Nambari ya Uthibitisho',
        body: 'Nambari ya uthibitisho wa upokeaji wa ' + productName + ' imegenerezwa.',
        isRead: false,
        data: { type: 'delivery_otp_ready', transactionId: orderId },
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (_) {}
    try {
      await sendOneSignalNotification(buyerId, 'Nambari ya Uthibitisho', 'Nambari ya uthibitisho wa ' + productName + ' imegenerezwa.', { type: 'delivery_otp_ready', transactionId: orderId });
    } catch (_) {}
    res.json({ success: true, message: 'OTP imegenerezwa.' });
  } catch (e) {
    log('DELIVERY-OTP', 'generate error: ' + e.message);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/verify-delivery', async function (req, res) {
  try {
    var orderId = req.body.orderId;
    var otp = req.body.otp;
    if (!orderId || !otp) return res.status(400).json({ error: 'Missing orderId or otp' });
    if (!/^\d{4}$/.test(otp)) return res.status(400).json({ error: 'OTP must be exactly 4 digits' });
    var locals = req.app.locals;
    var admin = locals.admin;
    var db = locals.db;
    var requireUser = locals.requireUser;
    var redis = locals.redis;
    var sendOneSignalNotification = locals.sendOneSignalNotification;
    var clickpesaPayout = locals.clickpesaPayout;
    var getPayoutFee = locals.getPayoutFee;
    var generatePayoutReference = locals.generatePayoutReference;
    var PAYOUT_STATUSES = locals.PAYOUT_STATUSES;
    var auditLog = locals.auditLog;
    var checkSuspended = locals.checkSuspended;
    if (!db) return res.status(503).json({ error: 'Database not configured' });
    var auth = await requireUser(req, res);
    if (!auth.ok) return;
    var txDoc = await db.collection('transactions').doc(orderId).get();
    var orderDoc = await db.collection('orders').doc(orderId).get();
    var tx = txDoc.exists ? txDoc.data() : null;
    var order = orderDoc.exists ? orderDoc.data() : null;
    if (!tx && !order) return res.status(404).json({ error: 'Order not found' });
    var sellerId = (tx && tx.sellerId) || (order && order.sellerId);
    if (sellerId !== auth.uid) return res.status(403).json({ error: 'Only the seller can verify delivery OTP' });
    var status = (tx && tx.status) || (order && order.status);
    if (status !== 'dispatched') return res.status(400).json({ error: 'Order must be dispatched. Current: ' + status });
    if ((tx && tx.escrowReleased === true) || (order && order.escrowReleased === true)) return res.status(400).json({ error: 'Escrow already released' });
    if (status === 'disputed' || (tx && tx.disputeInfo && tx.disputeInfo.resolved === false)) return res.status(400).json({ error: 'Order is under dispute. Admin must resolve first.' });
    var otpHash = (tx && tx.deliveryOtpHash) || (order && order.deliveryOtpHash);
    if (!otpHash) return res.status(400).json({ error: 'Delivery OTP has not been generated yet.' });
    var lockedUntil = (tx && tx.deliveryOtpLockedUntil) || (order && order.deliveryOtpLockedUntil);
    if (lockedUntil) {
      var lockDate = (lockedUntil && lockedUntil.toDate) ? lockedUntil.toDate() : new Date(lockedUntil);
      if (lockDate > new Date()) {
        var remainingMin = Math.ceil((lockDate - new Date()) / 60000);
        return res.status(423).json({ error: 'OTP locked. Try again in ' + remainingMin + ' min.', lockedUntil: lockDate.toISOString() });
      }
    }
    var attempts = (tx && tx.deliveryOtpAttempts) || (order && order.deliveryOtpAttempts) || 0;
    if (attempts >= OTP_MAX_ATTEMPTS) {
      var lockUntil = new Date(Date.now() + OTP_LOCKOUT_HOURS * 60 * 60 * 1000);
      var lockData = { deliveryOtpLockedUntil: lockUntil, deliveryOtpAttempts: OTP_MAX_ATTEMPTS };
      if (txDoc.exists) await txDoc.ref.update(lockData);
      if (orderDoc.exists) await orderDoc.ref.update(lockData);
      return res.status(423).json({ error: 'Too many failed attempts. OTP locked for 24 hours.' });
    }
    var newAttempts = attempts + 1;
    var attemptUpdate = { deliveryOtpAttempts: newAttempts };
    if (txDoc.exists) await txDoc.ref.update(attemptUpdate);
    if (orderDoc.exists) await orderDoc.ref.update(attemptUpdate);
    var valid = await verifyOtp(otp, otpHash);
    if (!valid) {
      var remaining = OTP_MAX_ATTEMPTS - newAttempts;
      return res.status(400).json({ error: 'Invalid OTP. ' + remaining + ' attempt(s) remaining.', attemptsRemaining: remaining });
    }
    var lockKey = null;
    if (redis) {
      try {
        var lr = await redis.set('delivery:lock:' + orderId, auth.uid, 'EX', 30, 'NX');
        if (lr !== 'OK') return res.status(409).json({ error: 'Another request is processing this order. Try again.' });
        lockKey = 'delivery:lock:' + orderId;
      } catch (_) {}
    }
    try {
      var sellerReceives = (tx && tx.sellerReceives) || (tx && tx.totalAmount) || (order && order.totalAmount) || 0;
      var productName = (tx && tx.productName) || (order && order.productName) || 'Product';
      var buyerId = (tx && tx.buyerId) || (order && order.buyerId);
      var sellerPhone = (tx && tx.sellerPhone) || (order && order.sellerPhone) || '';
      var ref = txDoc.exists ? txDoc.ref : orderDoc.ref;
      await ref.update({
        status: 'completed',
        escrowReleased: true,
        escrowReleasedAt: admin.firestore.FieldValue.serverTimestamp(),
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
        confirmedBy: 'otp',
        deliveryOtpVerifiedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      var sellerDoc = await db.collection('users').doc(sellerId).get();
      var pendingBefore = sellerDoc.exists ? (sellerDoc.data().pendingEscrow || 0) : 0;
      var actualPending = Math.min(sellerReceives, pendingBefore);
      await db.collection('users').doc(sellerId).update({
        sellerBalance: admin.firestore.FieldValue.increment(sellerReceives),
        pendingEscrow: admin.firestore.FieldValue.increment(-actualPending),
      });
      await db.collection('revenue_transactions').add({
        userId: sellerId, type: 'sale', amount: sellerReceives, orderId: orderId,
        description: 'Escrow released (OTP): ' + productName + ' - TZS ' + sellerReceives,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });
      if (auditLog) {
        try {
          await auditLog({
            userId: sellerId, type: 'escrow_release', amount: sellerReceives, orderId: orderId,
            reason: 'Delivery OTP verified', relatedId: orderId,
          });
        } catch (_) {}
      }
      var autoPaidOut = false;
      var payoutRef = '';
      if (sellerDoc.exists && sellerDoc.data() && sellerDoc.data().autoPayout === true && sellerPhone) {
        var payoutFee = getPayoutFee(sellerReceives);
        if (sellerReceives > payoutFee) {
          var netPayout = sellerReceives - payoutFee;
          payoutRef = generatePayoutReference('otp');
          try {
            await clickpesaPayout({ amount: netPayout, phoneNumber: sellerPhone, orderReference: payoutRef });
            await db.collection('users').doc(sellerId).update({ sellerBalance: admin.firestore.FieldValue.increment(-sellerReceives) });
            await db.collection('payouts').doc(payoutRef).set({
              payoutId: payoutRef, userId: sellerId, userPhone: sellerPhone,
              type: 'otp_payout', amount: sellerReceives, fee: payoutFee,
              netAmount: netPayout, status: PAYOUT_STATUSES.PROCESSING,
              transactionId: orderId, createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            autoPaidOut = true;
          } catch (pe) {
            log('DELIVERY-OTP', 'payout failed for ' + orderId + ': ' + pe.message);
            try {
              await db.collection('payouts').doc(payoutRef).set({
                payoutId: payoutRef, userId: sellerId, userPhone: sellerPhone,
                type: 'otp_payout', amount: sellerReceives, fee: payoutFee,
                netAmount: netPayout, status: PAYOUT_STATUSES.FAILED,
                transactionId: orderId, failureReason: pe.message,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
              });
            } catch (_) {}
          }
        }
      }
      var sellerMsg = autoPaidOut
        ? 'Pesa TZS ' + sellerReceives.toLocaleString() + ' zimetolewa kwa ' + sellerPhone + '.'
        : 'Salio lako limeongezeka kwa TZS ' + sellerReceives.toLocaleString() + '.';
      try {
        await db.collection('notifications').add({
          userId: sellerId, title: 'Oda Imekamilika',
          body: productName + ' - ' + sellerMsg,
          isRead: false, data: { type: 'completed', transactionId: orderId },
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      } catch (_) {}
      try {
        await sendOneSignalNotification(sellerId, 'Oda Imekamilika', productName + ' - ' + sellerMsg, { type: 'completed', transactionId: orderId });
      } catch (_) {}
      try {
        await db.collection('notifications').add({
          userId: buyerId, title: 'Uthibitisho Umekubaliwa',
          body: productName + ' umekamilika. Asante kwa ununuzi!',
          isRead: false, data: { type: 'completed', transactionId: orderId },
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      } catch (_) {}
      try {
        await sendOneSignalNotification(buyerId, 'Uthibitisho Umekubaliwa', productName + ' umekamilika.', { type: 'completed', transactionId: orderId });
      } catch (_) {}
      res.json({ success: true, message: 'OTP imethibitishwa. Oda imekamilika.', autoPaidOut: autoPaidOut });
    } finally {
      if (lockKey && redis) {
        try { await redis.del(lockKey); } catch (_) {}
      }
    }
  } catch (e) {
    log('DELIVERY-OTP', 'verify error: ' + e.message);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/open-dispute', async function (req, res) {
  try {
    var orderId = req.body.orderId;
    var reason = req.body.reason;
    var evidenceUrls = req.body.evidenceUrls;
    if (!orderId) return res.status(400).json({ error: 'Missing orderId' });
    var locals = req.app.locals;
    var admin = locals.admin;
    var db = locals.db;
    var requireUser = locals.requireUser;
    var sendOneSignalNotification = locals.sendOneSignalNotification;
    var notifyAdmins = locals.notifyAdmins;
    if (!db) return res.status(503).json({ error: 'Database not configured' });
    var auth = await requireUser(req, res);
    if (!auth.ok) return;
    var txDoc = await db.collection('transactions').doc(orderId).get();
    var orderDoc = await db.collection('orders').doc(orderId).get();
    var tx = txDoc.exists ? txDoc.data() : null;
    var order = orderDoc.exists ? orderDoc.data() : null;
    if (!tx && !order) return res.status(404).json({ error: 'Order not found' });
    var buyerId = (tx && tx.buyerId) || (order && order.buyerId);
    if (buyerId !== auth.uid) return res.status(403).json({ error: 'Only the buyer can open a dispute' });
    var status = (tx && tx.status) || (order && order.status);
    var validStatuses = ['dispatched', 'escrow_hold', 'paid_escrow_hold'];
    if (validStatuses.indexOf(status) === -1) return res.status(400).json({ error: 'Cannot dispute from status: ' + status });
    if ((tx && tx.escrowReleased === true) || (order && order.escrowReleased === true)) return res.status(400).json({ error: 'Escrow already released, cannot dispute' });
    var disputeInfo = {
      reason: reason || 'Sijapata mzigo',
      evidenceUrls: evidenceUrls || [],
      raisedAt: admin.firestore.FieldValue.serverTimestamp(),
      resolved: false,
      raisedBy: auth.uid,
    };
    var updateData = { status: 'disputed', disputeInfo: disputeInfo, deliveryOtpLockedUntil: null };
    if (txDoc.exists) await txDoc.ref.update(updateData);
    if (orderDoc.exists) await orderDoc.ref.update(updateData);
    var productName = (tx && tx.productName) || (order && order.productName) || 'Bidhaa';
    var sellerId = (tx && tx.sellerId) || (order && order.sellerId);
    try {
      await db.collection('notifications').add({
        userId: sellerId, title: 'Mgogoro Umefunguliwa',
        body: 'Mnunuzi amefungua mgogoro kwa ' + productName + '. Tafadhali wasilisha ushahidi wako.',
        isRead: false, data: { type: 'disputed', transactionId: orderId },
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (_) {}
    try {
      await sendOneSignalNotification(sellerId, 'Mgogoro Umefunguliwa', 'Mnunuzi amefungua mgogoro kwa ' + productName + '.', { type: 'disputed', transactionId: orderId });
    } catch (_) {}
    try {
      await db.collection('notifications').add({
        userId: buyerId, title: 'Mgogoro Umefunguliwa',
        body: 'Tumepokea mgogoro wako kwa ' + productName + '. Admin atakagua na kutoa uamuzi.',
        isRead: false, data: { type: 'disputed', transactionId: orderId },
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (_) {}
    try {
      notifyAdmins('Mgogoro Mpya', 'Mgogoro kwa ' + productName + ' - ' + orderId + '. Pitia ushahidi na toa uamuzi.', { type: 'disputed', transactionId: orderId });
    } catch (_) {}
    res.json({ success: true, message: 'Dispute imefunguliwa. Admin atakagua na kutoa uamuzi.' });
  } catch (e) {
    log('DELIVERY-OTP', 'open-dispute error: ' + e.message);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/cron/auto-release', async function (req, res) {
  try {
    var locals = req.app.locals;
    var admin = locals.admin;
    var db = locals.db;
    var redis = locals.redis;
    var sendOneSignalNotification = locals.sendOneSignalNotification;
    var clickpesaPayout = locals.clickpesaPayout;
    var getPayoutFee = locals.getPayoutFee;
    var generatePayoutReference = locals.generatePayoutReference;
    var PAYOUT_STATUSES = locals.PAYOUT_STATUSES;
    if (!db) return res.status(503).json({ error: 'Database not configured' });
    var secret = req.headers['x-cron-secret'];
    var expectedSecret = process.env.CRON_SECRET;
    if (!expectedSecret || !secret) return res.status(401).json({ error: 'Unauthorized' });
    var secBuf = Buffer.from(expectedSecret, 'utf8');
    var hdrBuf = Buffer.from(secret, 'utf8');
    if (secBuf.length !== hdrBuf.length || !crypto.timingSafeEqual(secBuf, hdrBuf)) {
      return res.status(401).json({ error: 'Unauthorized' });
    }
    var AUTO_RELEASE_MS = 48 * 60 * 60 * 1000;
    var cutoff = new Date(Date.now() - AUTO_RELEASE_MS);
    var txSnap = await db.collection('transactions')
      .where('status', '==', 'dispatched')
      .where('escrowReleased', '==', false)
      .where('dispatchedAt', '<=', cutoff)
      .limit(50)
      .get();
    var results = [];
    for (var i = 0; i < txSnap.docs.length; i++) {
      var doc = txSnap.docs[i];
      var tx = doc.data();
      var orderId = doc.id;
      if (tx.disputeInfo && tx.disputeInfo.resolved === false) continue;
      if (!tx.buyerTransport && !tx.dispatchProof) continue;
      if (redis) {
        try {
          var lockResult = await redis.set('auto-release:lock:' + orderId, 'cron', 'EX', 60, 'NX');
          if (lockResult !== 'OK') continue;
        } catch (_) { continue; }
      }
      try {
        var sellerReceives = tx.sellerReceives || tx.totalAmount || 0;
        var sellerId = tx.sellerId;
        var productName = tx.productName || 'Product';
        var buyerId = tx.buyerId;
        await doc.ref.update({
          status: 'completed', escrowReleased: true,
          escrowReleasedAt: admin.firestore.FieldValue.serverTimestamp(),
          completedAt: admin.firestore.FieldValue.serverTimestamp(),
          confirmedBy: 'auto_release_48h',
        });
        var orderDoc = await db.collection('orders').doc(orderId).get();
        if (orderDoc.exists) {
          await orderDoc.ref.update({
            status: 'completed', escrowReleased: true,
            escrowReleasedAt: admin.firestore.FieldValue.serverTimestamp(),
            completedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        }
        var sellerDoc = await db.collection('users').doc(sellerId).get();
        var pendingBefore = sellerDoc.exists ? (sellerDoc.data().pendingEscrow || 0) : 0;
        var actualPending = Math.min(sellerReceives, pendingBefore);
        await db.collection('users').doc(sellerId).update({
          sellerBalance: admin.firestore.FieldValue.increment(sellerReceives),
          pendingEscrow: admin.firestore.FieldValue.increment(-actualPending),
        });
        await db.collection('revenue_transactions').add({
          userId: sellerId, type: 'sale', amount: sellerReceives, orderId: orderId,
          description: 'Auto-release 48h: ' + productName + ' - TZS ' + sellerReceives,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
        });
        var sellerPhone = tx.sellerPhone || '';
        if (sellerDoc.exists && sellerDoc.data() && sellerDoc.data().autoPayout === true && sellerPhone) {
          var payoutFee = getPayoutFee(sellerReceives);
          if (sellerReceives > payoutFee) {
            var netPayout = sellerReceives - payoutFee;
            var payoutRef = generatePayoutReference('ar');
            try {
              await clickpesaPayout({ amount: netPayout, phoneNumber: sellerPhone, orderReference: payoutRef });
              await db.collection('users').doc(sellerId).update({ sellerBalance: admin.firestore.FieldValue.increment(-sellerReceives) });
              await db.collection('payouts').doc(payoutRef).set({
                payoutId: payoutRef, userId: sellerId, userPhone: sellerPhone,
                type: 'auto_release_payout', amount: sellerReceives, fee: payoutFee,
                netAmount: netPayout, status: PAYOUT_STATUSES.PROCESSING,
                transactionId: orderId, createdAt: admin.firestore.FieldValue.serverTimestamp(),
              });
            } catch (_) {}
          }
        }
        try {
          await db.collection('notifications').add({
            userId: sellerId, title: 'Oda Imekamilika (Otomatiki)',
            body: productName + ' imekamilika automatically baada ya masaa 48.',
            isRead: false, data: { type: 'auto_release', transactionId: orderId },
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        } catch (_) {}
        try {
          await sendOneSignalNotification(sellerId, 'Oda Imekamilika', productName + ' imekamilika automatically baada ya masaa 48.', { type: 'auto_release', transactionId: orderId });
        } catch (_) {}
        try {
          await db.collection('notifications').add({
            userId: buyerId, title: 'Oda Imekamilika',
            body: productName + ' imekamilika automatically. Fedha zimetolewa kwa muuzaji.',
            isRead: false, data: { type: 'auto_release', transactionId: orderId },
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        } catch (_) {}
        try {
          await sendOneSignalNotification(buyerId, 'Oda Imekamilika', productName + ' imekamilika automatically.', { type: 'auto_release', transactionId: orderId });
        } catch (_) {}
        results.push({ orderId: orderId, status: 'released' });
      } catch (e) {
        log('AUTO-RELEASE', 'Error for ' + orderId + ': ' + e.message);
        results.push({ orderId: orderId, status: 'error', error: e.message });
      } finally {
        if (redis) {
          try { await redis.del('auto-release:lock:' + orderId); } catch (_) {}
        }
      }
    }
    res.json({ success: true, processed: results.length, results: results });
  } catch (e) {
    log('AUTO-RELEASE', 'Cron error: ' + e.message);
    res.status(500).json({ error: 'Internal server error' });
  }
});

module.exports = router;
