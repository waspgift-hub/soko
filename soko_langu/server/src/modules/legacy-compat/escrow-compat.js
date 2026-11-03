// Compat escrow router: verbatim port of the proven old-server escrow
// handlers (dispatch, buyer-transport, release, cancel, dispute) under
// their original paths. Firestore is the same project.
const express = require('express');
const admin = require('firebase-admin');
const { getFirebaseFirestore } = require('../../config/firebase');
const { requireUser, requireAdmin, checkSuspended } = require('./auth-helpers');
const { sendOneSignalNotification, notifyAdmins } = require('./notify');
const { sendSms } = require('../../services/sms-service');
const { clickpesaPayout, getPayoutFee } = require('../../../clickpesa');
const payoutHelpers = require('../../../helpers/payouts');

const db = getFirebaseFirestore();
const { generatePayoutReference, PAYOUT_STATUSES, PAYOUT_RETRY_MAX, auditLog } = payoutHelpers({ admin, db });

// SMS language preference lookup is a refinement; compat sends as-is.
async function sendLocalizedSms(phone, message) {
  return sendSms(phone, message);
}

const router = express.Router();
router.post('/dispatch', async (req, res) => {
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
    // Accept every spelling of "funds held" the engine has produced over time.
    const dispatchableStates = ['escrow_hold', 'paid_escrow_hold', 'paid_escrow_held', 'in_escrow', 'ready_to_dispatch'];
    if (dispatchableStates.indexOf(tx.status) === -1) {
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
      flowStage: 'in_transit',
      dispatchProof,
      busName: req.body.busName || '',
      plateNumber: req.body.plateNumber || '',
      dispatchedAt: admin.firestore.FieldValue.serverTimestamp(),
      autoReleaseDeadline: new Date(Date.now() + 48 * 60 * 60 * 1000),
      escrowHeldAt: tx.escrowHeldAt || tx.completedAt || null,
    });
    const dispatchMirror = await db.collection('orders').doc(orderId).get();
    if (dispatchMirror.exists) {
      await dispatchMirror.ref.update({
        status: 'dispatched',
        flowStage: 'in_transit',
        dispatchProof,
        busName: req.body.busName || '',
        plateNumber: req.body.plateNumber || '',
        dispatchedAt: admin.firestore.FieldValue.serverTimestamp(),
        autoReleaseDeadline: new Date(Date.now() + 48 * 60 * 60 * 1000),
      });
    }

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
router.post('/buyer-transport', async (req, res) => {
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
router.post('/release', async (req, res) => {
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
      // Money must still be in escrow; any post-dispatch stage is releasable.
      const releasableStates = ['dispatched', 'in_transit', 'out_for_delivery', 'delivery_attempted', 'delivered', 'inspection_period', 'otp_pending'];
      if (releasableStates.indexOf(tx.status) === -1) {
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
      confirmedBy: 'buyer_release',
      flowStage: 'wallet_credited',
      walletCreditedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    if (orderDoc && orderDoc.exists && txDoc.exists) {
      await orderDoc.ref.update({
        status: 'delivered',
        escrowReleased: true,
        escrowReleasedAt: admin.firestore.FieldValue.serverTimestamp(),
        confirmedBy: 'buyer_release',
        flowStage: 'wallet_credited',
      });
    }

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
    // Status is set to PENDING/PROCESSING — only the ClickPesa payout webhook
    // marks it SUCCESS. Marking 'completed' here would falsely claim money was
    // sent before the provider confirms it.
    let autoPaidOut = false;
    let payoutRef = '';
    if (sellerDoc.exists && sellerDoc.data()?.autoPayout === true && !payoutMethod) {
      const sellerData = sellerDoc.data();
      const sellerPhone = sellerData?.phone;
      const payoutFee = getPayoutFee(sellerReceives);
      if (sellerPhone && sellerReceives > payoutFee) {
        const netPayout = sellerReceives - payoutFee;
        payoutRef = generatePayoutReference('ap');
        try {
          const mRef = await clickpesaPayout({
            amount: netPayout,
            phoneNumber: sellerPhone,
            orderReference: payoutRef,
          });
          // ClickPesa accepted the payout request — now move the money out of
          // the seller's wallet. If the API call threw, nothing was deducted
          // and the seller keeps their balance (no money is lost).
          await db.collection('users').doc(sellerId).update({
            sellerBalance: admin.firestore.FieldValue.increment(-sellerReceives),
          });
          await db.collection('payouts').doc(payoutRef).set({
            payoutId: payoutRef,
            userId: sellerId, userPhone: sellerPhone,
            type: 'auto_payout', amount: sellerReceives, fee: payoutFee,
            netAmount: netPayout, clickpesaReference: mRef.id || mRef.orderReference || '',
            status: PAYOUT_STATUSES.PROCESSING,
            retryCount: 0,
            maxRetries: PAYOUT_RETRY_MAX,
            transactionId: orderId,
            metadata: { orderId, autoRelease: true },
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          await ref.update({ payoutMethod: 'auto' });
          autoPaidOut = true;
        } catch (payoutErr) {
          // Payout request rejected — seller keeps their balance. Record the
          // failure and notify so they can fix their phone or retry manually.
          console.error(`[AUTO-PAYOUT] ClickPesa rejected payout for ${sellerId} (${payoutRef}): ${payoutErr.message}`);
          try {
            await db.collection('payouts').doc(payoutRef).set({
              payoutId: payoutRef,
              userId: sellerId, userPhone: sellerPhone,
              type: 'auto_payout', amount: sellerReceives, fee: payoutFee,
              netAmount: netPayout, clickpesaReference: '',
              status: PAYOUT_STATUSES.FAILED,
              retryCount: 0,
              maxRetries: PAYOUT_RETRY_MAX,
              transactionId: orderId,
              failureReason: payoutErr.message || 'payout rejected',
              metadata: { orderId, autoRelease: true },
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
          } catch (_) {}
          try {
            await db.collection('notifications').add({
              userId: sellerId,
              title: '⚠️ Utoaji wa Pesa Umeshindwa',
              body: `Pesa zimefunguliwa kwenye salio lako bali kutumwa kwa simu kumeshindwa (${productName}). Angalia namba yako ya simu kisha utoe mwenyewe.`,
              isRead: false,
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
              data: { type: 'auto_payout', status: 'failed', transactionId: orderId },
            });
          } catch (_) {}
        }
      }
    }

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
          ? `TZS ${(sellerReceives - getPayoutFee(sellerReceives)).toLocaleString()} zimetumwa kwa simu yako kwa mauzo ya ${productName} (fee TZS ${getPayoutFee(sellerReceives).toLocaleString()}).`
          : `Mteja amethibitisha kupokea mzigo #${orderId}. TZS ${sellerReceives.toLocaleString()} zimetolewa Escrow na kuwekwa kwenye pochi yako.`;
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
router.post('/cancel', async (req, res) => {
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
    const cancelableStates = ['escrow_hold', 'paid_escrow_hold', 'paid_escrow_held', 'in_escrow'];
    if (cancelableStates.indexOf(tx.status) === -1) {
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

    const grossRefund = productPrice + shippingCost;
    const cancelPayoutFee = getPayoutFee(grossRefund);

    if (grossRefund <= cancelPayoutFee) {
      return res.status(400).json({ error: `Refund amount must exceed fee of TZS ${cancelPayoutFee.toLocaleString()}` });
    }

    // Refund includes the shipping cost the buyer paid, minus the actual ClickPesa payout fee
    const refundAmount = grossRefund - cancelPayoutFee;

    // Refund minus payout fee to buyer via ClickPesa
    try {
      await clickpesaPayout({
        amount: refundAmount,
        phoneNumber: buyerPhone,
        orderReference: `refund${orderId}`.replace(/[^a-zA-Z0-9]/g, ''),
      });
    } catch (payoutErr) {
      return res.status(500).json({ error: `Refund failed: ${payoutErr.message}` });
    }

    // Update transaction
    await txDoc.ref.update({
      status: 'refunded',
      escrowReleased: true,
      cancellationType: 'buyer_cancel',
      refundFee: cancelPayoutFee,
      cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    const cancelMirror = await db.collection('orders').doc(orderId).get();
    if (cancelMirror.exists) {
      await cancelMirror.ref.update({
        status: 'refunded',
        escrowReleased: true,
        cancellationType: 'buyer_cancel',
        refundFee: cancelPayoutFee,
        cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

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
      fee: cancelPayoutFee,
      description: `Buyer cancel: ${productName} - TZS ${refundAmount} (fee TZS ${cancelPayoutFee})`,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Notify buyer
    await db.collection('notifications').add({
      userId: tx.buyerId,
      title: '💰 Pesa Zimerudishwa',
      body: `TZS ${refundAmount.toLocaleString()} zimerudishwa kwa ${productName}. Ada ya TZS ${cancelPayoutFee.toLocaleString()} imekatwa kwa gharama za payout.`,
      isRead: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      data: { type: 'refund', orderId },
    });
    try {
      await sendOneSignalNotification(tx.buyerId, '💰 Pesa Zimerudishwa', `TZS ${refundAmount.toLocaleString()} zimerudishwa kwa ${productName}. Ada ya TZS ${cancelPayoutFee.toLocaleString()} imekatwa kwa gharama za payout.`, { type: 'refund', orderId });
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

    res.json({ success: true, refundAmount, fee: cancelPayoutFee, message: `Oda imeghairiwa. TZS ${refundAmount.toLocaleString()} zimerudishwa kwa simu yako (ada TZS ${cancelPayoutFee.toLocaleString()}).` });
  } catch (e) {
    console.error('Escrow cancel error:', e);
    res.status(500).json({ error: 'Internal server error' });
  }
});
router.post('/dispute', async (req, res) => {
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
    const disputeValidStates = [
      'dispatched', 'in_transit', 'out_for_delivery', 'delivery_attempted',
      'delivered', 'inspection_period',
      'escrow_hold', 'paid_escrow_hold', 'paid_escrow_held', 'in_escrow',
    ];
    if (disputeValidStates.indexOf(tx.status) === -1) {
      return res.status(400).json({ error: `Cannot dispute from status: ${tx.status}` });
    }
    if (tx.escrowReleased === true) {
      return res.status(400).json({ error: 'Escrow already released, cannot dispute' });
    }

    const disputeInfo = {
      reason: reason || 'Sijapata mzigo',
      evidenceUrls: evidenceUrls || [],
      raisedBy: userId,
      raisedAt: admin.firestore.FieldValue.serverTimestamp(),
      resolved: false,
    };
    const batch = db.batch();
    batch.set(txDoc.ref, { status: 'disputed', disputeInfo }, { merge: true });
    const orderRef = db.collection('orders').doc(orderId);
    const orderSnap = await orderRef.get();
    if (orderSnap.exists) {
      batch.set(orderRef, { status: 'disputed', disputeInfo }, { merge: true });
    }
    await batch.commit();

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
// 🛡 ADMIN — Force release escrow to the seller (x-admin-secret or admin token)
// ============================================================
router.post('/admin-release', async (req, res) => {
  try {
    const auth = await requireAdmin(req, res);
    if (!auth.ok) return;
    const { orderId } = req.body;
    if (!orderId) return res.status(400).json({ error: 'Missing orderId' });
    if (!db) return res.status(503).json({ error: 'Database not configured' });

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
      if (tx.escrowReleased) return res.status(400).json({ error: 'Escrow already released' });
      await txDoc.ref.update({
        status: 'delivered',
        escrowReleased: true,
        escrowReleasedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } else {
      const order = orderDoc.data();
      sellerId = order.sellerId;
      sellerReceives = order.totalAmount || 0;
      productName = order.items?.map((i) => i.name).join(', ') || 'Product';
      if (order.escrowReleased) return res.status(400).json({ error: 'Escrow already released' });
      await orderDoc.ref.update({
        status: 'delivered',
        escrowReleased: true,
        escrowReleasedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    if (sellerId) {
      const sellerDoc = await db.collection('users').doc(sellerId).get();
      const pending = sellerDoc.exists ? (sellerDoc.data().pendingEscrow || 0) : 0;
      const actualPending = Math.min(sellerReceives, pending);
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
      await db.collection('notifications').add({
        userId: sellerId,
        title: 'Admin Amefungua Escrow!',
        body: `${productName} — TZS ${sellerReceives.toLocaleString()} zimewekwa salio lako.`,
        type: 'escrow_release',
        data: { orderId, adminRelease: true },
        isRead: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      try {
        await sendOneSignalNotification(sellerId, 'Admin Amefungua Escrow!', `${productName} — TZS ${sellerReceives.toLocaleString()} zimewekwa salio lako.`, { type: 'escrow_release', orderId, adminRelease: true });
      } catch (_) {}
    }

    res.json({ success: true, message: 'Escrow force-released by admin' });
  } catch (e) {
    console.error('Escrow admin-release error:', e);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// ⚖️ ADMIN — Resolve a dispute: 'release' funds to seller OR 'refund'
// the buyer in full via ClickPesa payout.
// ============================================================
router.post('/admin-resolve-dispute', async (req, res) => {
  try {
    const auth = await requireAdmin(req, res);
    if (!auth.ok) return;

    const { orderId, resolution, note } = req.body;
    if (!orderId || !resolution) return res.status(400).json({ error: 'Missing orderId or resolution' });
    if (!['release', 'refund'].includes(resolution)) {
      return res.status(400).json({ error: 'Resolution must be "release" or "refund"' });
    }
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const txDoc = await db.collection('transactions').doc(orderId).get();
    if (!txDoc.exists) return res.status(404).json({ error: 'Transaction not found' });
    const tx = txDoc.data();
    if (tx.status !== 'disputed') {
      return res.status(400).json({ error: `Cannot resolve from status: ${tx.status}` });
    }

    if (resolution === 'release') {
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
        'disputeInfo.adminNote': note || '',
      });
      const resolveOrder = await db.collection('orders').doc(orderId).get();
      if (resolveOrder.exists) {
        await resolveOrder.ref.update({
          status: 'delivered',
          escrowReleased: true,
          escrowReleasedAt: admin.firestore.FieldValue.serverTimestamp(),
          'disputeInfo.resolved': true,
          'disputeInfo.resolution': 'released_to_seller',
          'disputeInfo.adminNote': note || '',
        });
      }

      if (sellerId && sellerReceives > 0) {
        await db.collection('users').doc(sellerId).update({
          sellerBalance: admin.firestore.FieldValue.increment(sellerReceives),
          pendingEscrow: admin.firestore.FieldValue.increment(-actualPending),
        });
      }

      const notifyBody = `Admin ameamua pesa zitolewe kwa muuzaji. ${note || ''}`;
      await db.collection('notifications').add({
        userId: tx.buyerId,
        title: '⚖️ Uamuzi wa Mgogoro',
        body: notifyBody,
        isRead: false,
        data: { type: 'dispute_resolved', transactionId: orderId },
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      try { await sendOneSignalNotification(tx.buyerId, '⚖️ Uamuzi wa Mgogoro', notifyBody, { type: 'dispute_resolved', transactionId: orderId }); } catch (_) {}
      if (sellerId) {
        await db.collection('notifications').add({
          userId: sellerId,
          title: '⚖️ Uamuzi wa Mgogoro',
          body: `Admin ameamua pesa zikutolee. ${note || ''}`,
          isRead: false,
          data: { type: 'dispute_resolved', transactionId: orderId },
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        try { await sendOneSignalNotification(sellerId, '⚖️ Uamuzi wa Mgogoro', `Admin ameamua pesa zikutolee. ${note || ''}`, { type: 'dispute_resolved', transactionId: orderId }); } catch (_) {}
      }
      return res.json({ success: true, message: 'Dispute resolved: funds released to seller' });
    }

    // resolution === 'refund' → FULL refund to buyer (ClickPesa payout)
    const productPrice = tx.productPrice || 0;
    const sellerReceives = tx.sellerReceives || 0;
    const sellerId = tx.sellerId;
    const buyerPhone = tx.buyerPhone || '';
    const productName = tx.productName || 'Product';

    if (!buyerPhone) return res.status(400).json({ error: 'Buyer phone number not found for refund' });

    const refundAmount = productPrice;
    try {
      await clickpesaPayout({
        amount: refundAmount,
        phoneNumber: buyerPhone,
        orderReference: `disputerefund${orderId}`.replace(/[^a-zA-Z0-9]/g, ''),
      });
    } catch (payoutErr) {
      return res.status(502).json({ error: `Refund payment failed: ${payoutErr.message}` });
    }

    await txDoc.ref.update({
      status: 'refunded',
      escrowReleased: true,
      escrowReleasedAt: admin.firestore.FieldValue.serverTimestamp(),
      'disputeInfo.resolved': true,
      'disputeInfo.resolution': 'refunded_to_buyer',
      'disputeInfo.refundedAmount': refundAmount,
      'disputeInfo.adminNote': note || '',
    });
    const resolveOrderRefund = await db.collection('orders').doc(orderId).get();
    if (resolveOrderRefund.exists) {
      await resolveOrderRefund.ref.update({
        status: 'refunded',
        escrowReleased: true,
        escrowReleasedAt: admin.firestore.FieldValue.serverTimestamp(),
        'disputeInfo.resolved': true,
        'disputeInfo.resolution': 'refunded_to_buyer',
        'disputeInfo.refundedAmount': refundAmount,
        'disputeInfo.adminNote': note || '',
      });
    }

    if (sellerId && sellerReceives > 0) {
      const sellerDoc = await db.collection('users').doc(sellerId).get();
      const refundPending = sellerDoc.exists ? (sellerDoc.data().pendingEscrow || 0) : 0;
      const actualPending = Math.min(sellerReceives, refundPending);
      const currentBalance = sellerDoc.exists ? (sellerDoc.data().sellerBalance || 0) : 0;
      const gatewayFee = getPayoutFee(refundAmount);
      const sellerPenalty = Math.min(gatewayFee, sellerReceives, Math.max(0, currentBalance));
      const updateBlock = {
        pendingEscrow: admin.firestore.FieldValue.increment(-actualPending),
        totalSales: admin.firestore.FieldValue.increment(-1),
        grossSalesVolume: admin.firestore.FieldValue.increment(-productPrice),
      };
      if (sellerPenalty > 0) updateBlock.sellerBalance = admin.firestore.FieldValue.increment(-sellerPenalty);
      await db.collection('users').doc(sellerId).update(updateBlock);
    }

    await db.collection('revenue_transactions').add({
      userId: 'platform',
      amount: -productPrice,
      type: 'refund',
      orderId,
      description: `Refund (dispute): ${productName} - TZS ${productPrice}`,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });

    const refundBody = `Refund kamili ya TZS ${refundAmount.toLocaleString()} kwa ${productName} imetumwa kwa namba yako.`;
    await db.collection('notifications').add({
      userId: tx.buyerId,
      title: '💸 Pesa Zimerudishwa Kamili',
      body: refundBody,
      isRead: false,
      data: { type: 'refund', orderId },
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    try { await sendOneSignalNotification(tx.buyerId, '💸 Pesa Zimerudishwa Kamili', refundBody, { type: 'refund', orderId }); } catch (_) {}

    if (sellerId) {
      await db.collection('notifications').add({
        userId: sellerId,
        title: '❌ Mgogoro Umekamilika',
        body: `${productName} imerefundiwa mnunuzi. Pesa zimetolewa kwenye pendingEscrow yako.`,
        isRead: false,
        data: { type: 'refund', orderId },
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      try { await sendOneSignalNotification(sellerId, '❌ Mgogoro Umekamilika', `${productName} imerefundiwa mnunuzi. Pesa zimetolewa kwenye pendingEscrow yako.`, { type: 'refund', orderId }); } catch (_) {}
    }

    res.json({ success: true, message: 'Dispute resolved: refund sent to buyer' });
  } catch (e) {
    console.error('Escrow admin-resolve-dispute error:', e);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 💸 ADMIN — Transaction transfer: cancel the order and pay an
// arbitrary amount to whichever phone the admin decides. Any part
// not transferred is credited back to the seller so money never
// vanishes from the platform.
// ============================================================
router.post('/admin-transfer', async (req, res) => {
  try {
    const auth = await requireAdmin(req, res);
    if (!auth.ok) return;

    const { orderId, amount, phone, note } = req.body;
    if (!orderId || !phone) return res.status(400).json({ error: 'Missing orderId or phone' });
    if (!amount || Number(amount) <= 0) return res.status(400).json({ error: 'Invalid amount' });
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const txDoc = await db.collection('transactions').doc(orderId).get();
    if (!txDoc.exists) return res.status(404).json({ error: 'Transaction not found' });
    const tx = txDoc.data();
    if (tx.escrowReleased === true) return res.status(400).json({ error: 'Escrow already released/resolved' });

    const escrowTotal = tx.sellerReceives || tx.productPrice || 0;
    if (escrowTotal <= 0) return res.status(400).json({ error: 'No escrow funds on this transaction' });
    const transferAmount = Math.min(Number(amount), escrowTotal);

    // ClickPesa payout to the admin's chosen recipient
    try {
      await clickpesaPayout({
        amount: transferAmount,
        phoneNumber: String(phone),
        orderReference: `admintransfer${orderId}`.replace(/[^a-zA-Z0-9]/g, ''),
      });
    } catch (payoutErr) {
      return res.status(502).json({ error: `Transfer payment failed: ${payoutErr.message}` });
    }

    await txDoc.ref.update({
      status: 'refunded',
      escrowReleased: true,
      escrowReleasedAt: admin.firestore.FieldValue.serverTimestamp(),
      adminTransfer: true,
      transferAmount,
      transferPhone: String(phone),
      transferNote: note || '',
      transferredAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    const sellerId = tx.sellerId;
    if (sellerId) {
      const sellerDoc = await db.collection('users').doc(sellerId).get();
      const pending = sellerDoc.exists ? (sellerDoc.data().pendingEscrow || 0) : 0;
      const actualPending = Math.min(escrowTotal, pending);
      const remainder = escrowTotal - transferAmount;
      const updateBlock = {
        pendingEscrow: admin.firestore.FieldValue.increment(-actualPending),
      };
      if (remainder > 0) {
        updateBlock.sellerBalance = admin.firestore.FieldValue.increment(remainder);
      }
      await db.collection('users').doc(sellerId).update(updateBlock);

      await db.collection('revenue_transactions').add({
        userId: 'platform',
        amount: -escrowTotal,
        type: 'admin_transfer',
        orderId,
        description: `Admin transfer: TZS ${transferAmount} kwa ${phone} (${tx.productName || 'Product'}). Salio TZS ${remainder} limewekwa kwa muuzaji.`,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });

      await db.collection('notifications').add({
        userId: sellerId,
        title: '⚠️ Order Inerejeshwa na Admin',
        body: `${tx.productName || 'Bidhaa'} order imefutwa na admin. Pesa imehamishwa na salio limewekwa. ${note || ''}`,
        isRead: false,
        data: { type: 'admin_transfer', orderId },
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    await db.collection('notifications').add({
      userId: tx.buyerId,
      title: '⚠️ Order Ineresolved by Admin',
      body: `Admin amekamilisha mgogoro wa ${tx.productName || 'Bidhaa'}. ${note || ''}`,
      isRead: false,
      data: { type: 'admin_transfer', orderId },
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    notifyAdmins(
      '💰 Admin Transfer Imetumwa',
      `TZS ${transferAmount.toLocaleString()} → ${phone} kwa order ${orderId}.`,
      { type: 'admin_transfer', orderId },
    );

    res.json({
      success: true,
      message: `Transfer TZS ${transferAmount.toLocaleString()} kwa ${phone} imetumwa. Salio limewekwa kwa muuzaji.`,
      transferred: transferAmount,
    });
  } catch (e) {
    console.error('Escrow admin-transfer error:', e);
    res.status(500).json({ error: 'Internal server error' });
  }
});

module.exports = router;
