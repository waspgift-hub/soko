const express = require('express');
const { getPayoutFee, clickpesaBalance } = require('../clickpesa');
const payoutHelpers = require('../helpers/payouts');

module.exports = function ({ admin, db, requireUser, requireAdmin, isOwnerOrAdmin, sendOneSignalNotification, webhookIpWhitelist, verifyWebhook }) {
  const router = express.Router();
  const { generatePayoutReference, PAYOUT_STATUSES, processPayout, retryFailedPayout, updatePayoutStatus, auditLog } = payoutHelpers({ admin, db });

  router.post('/seller/withdraw', async (req, res) => {
    try {
      const auth = await requireUser(req, res);
      if (!auth.ok) return;
      const { userId, amount, phone } = req.body;
      if (!userId || !amount || !phone) {
        return res.status(400).json({ error: 'Missing userId, amount, or phone' });
      }
      if (auth.uid !== userId) {
        return res.status(403).json({ error: 'Forbidden: cannot withdraw from another account' });
      }
      if (!db) return res.status(503).json({ error: 'Database not configured' });

      const withdrawAmount = Math.round(amount);
      if (withdrawAmount <= 0) {
        return res.status(400).json({ error: 'Withdrawal amount must be greater than zero' });
      }

      const payoutFee = getPayoutFee(withdrawAmount);
      const totalCost = withdrawAmount + payoutFee;

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

      const netAmount = withdrawAmount;
      let payoutResult;
      try {
        payoutResult = await processPayout({
          userId,
          phone,
          amount: totalCost,
          fee: payoutFee,
          netAmount,
          source: `seller_withdraw_${Date.now()}`,
          type: 'seller_withdrawal',
          metadata: { sellerName, balanceBefore: balanceSnapshot },
        });
      } catch (payoutErr) {
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

  router.post('/admin/withdraw', async (req, res) => {
    try {
      const auth = await requireAdmin(req, res);
      if (!auth.ok) return;

      let { userId, amount, phone } = req.body;
      if (!amount || !phone) {
        return res.status(400).json({ error: 'Missing amount or phone' });
      }
      if (!db) return res.status(503).json({ error: 'Database not configured' });

      if (auth.uid === 'admin-secret') {
        if (!userId) userId = 'admin-secret';
      } else {
        if (!userId) return res.status(400).json({ error: 'Missing userId' });
        if (auth.uid !== userId) {
          return res.status(403).json({ error: 'Token does not match userId' });
        }
        const userDoc = await db.collection('users').doc(userId).get();
        if (!userDoc.exists) return res.status(404).json({ error: 'User not found' });
        const user = userDoc.data();
        if (!user.isAdmin) return res.status(403).json({ error: 'Admin access required' });
        if (user.isSuspended) return res.status(403).json({ error: 'Account suspended' });
      }

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
      const totalAdminBalance = totalCommissions + totalBoostRevenue;

      const withdrawnSnap = await db.collection('admin_withdrawals')
        .where('userId', '==', userId)
        .get();
      let totalWithdrawn = 0;
      withdrawnSnap.docs.forEach(doc => {
        const d = doc.data();
        if (d.status === 'completed') totalWithdrawn += (d.netAmount || d.amount || 0);
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

  router.post('/create-payout', async (req, res) => {
    try {
      const auth = await requireAdmin(req, res);
      if (!auth.ok) return;

      const { userId, amount, phone, type, source } = req.body;
      if (!userId || !amount || !phone) {
        return res.status(400).json({ error: 'Missing userId, amount, or phone' });
      }
      if (!db) return res.status(503).json({ error: 'Database not configured' });

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

  router.get('/payout-status/:id', async (req, res) => {
    try {
      if (!db) return res.status(503).json({ error: 'Database not configured' });
      const doc = await db.collection('payouts').doc(req.params.id).get();
      if (!doc.exists) return res.status(404).json({ error: 'Payout not found' });
      if (!(await isOwnerOrAdmin(req, res, doc.data().userId || ''))) return;
      res.json({ id: doc.id, ...doc.data() });
    } catch (e) {
      res.status(500).json({ error: 'Internal server error' });
    }
  });

  router.get('/payouts', async (req, res) => {
    try {
      if (!db) return res.status(503).json({ error: 'Database not configured' });
      const { userId, limit: qLimit } = req.query;
      if (userId) {
        if (!(await isOwnerOrAdmin(req, res, userId))) return;
      } else {
        const adminAuth = await requireAdmin(req, res);
        if (!adminAuth.ok) return;
      }
      let query = db.collection('payouts').orderBy('createdAt', 'desc');
      if (userId) query = query.where('userId', '==', userId);
      const snap = await query.limit(parseInt(qLimit) || 50).get();
      const payouts = snap.docs.map(d => ({ id: d.id, ...d.data() }));
      res.json({ payouts });
    } catch (e) {
      res.status(500).json({ error: 'Internal server error' });
    }
  });

  router.post('/payout/retry/:id', async (req, res) => {
    try {
      const auth = await requireAdmin(req, res);
      if (!auth.ok) return;
      if (!db) return res.status(503).json({ error: 'Database not configured' });
      const result = await retryFailedPayout(req.params.id);
      res.json({ success: true, ...result });
    } catch (e) {
      res.status(500).json({ error: 'Internal server error' });
    }
  });

  router.get('/clickpesa/balance', async (req, res) => {
    try {
      const auth = await requireAdmin(req, res);
      if (!auth.ok) return;
      const balance = await clickpesaBalance();
      res.json({ success: true, balance });
    } catch (e) {
      res.status(500).json({ error: 'Internal server error' });
    }
  });

  router.post('/clickpesa/payout-preview', async (req, res) => {
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

  router.post('/clickpesa/payout-webhook', webhookIpWhitelist, verifyWebhook, async (req, res) => {
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

        try {
          await db.collection('transactions').doc(payoutRef).update({
            status: 'failed',
            failureReason: payload.message || payload.error || 'payout failed',
            clickpesaReference: clickpesaTxId,
            completedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        } catch (_) {}

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

  return { router };
};
