const express = require('express');
const { getPayoutFee, clickpesaBalance } = require('../clickpesa');
const payoutHelpers = require('../helpers/payouts');

module.exports = function ({ commerceStore, requireUser, requireAdmin, isOwnerOrAdmin, sendOneSignalNotification, webhookIpWhitelist, verifyWebhook }) {
  const router = express.Router();
  const { generatePayoutReference, PAYOUT_STATUSES, processPayout, retryFailedPayout, updatePayoutStatus, auditLog } = payoutHelpers({ commerceStore });

  // RETIRED on wallet cutover (OWNERSHIP_MAP §6 item 3): seller money now lives
  // in the Postgres wallet and withdrawals go through POST /api/v1/wallet/
  // withdrawals. Both the Flutter app (kUseWalletApi) and the shop SPA read the
  // Postgres wallet. The legacy Firestore sellerBalance had 0 eligible TZS at
  // cutover, so this mutation can no longer be routed to Firestore money.
  router.post('/seller/withdraw', async (req, res) => {
    res.status(410).json({
      error: 'GONE',
      message: 'Legacy /api/payouts/seller/withdraw is retired. Use POST /api/v1/wallet/withdrawals.',
    });
  });

  router.post('/admin/withdraw', async (req, res) => {
    try {
      const auth = await requireAdmin(req, res);
      if (!auth.ok) return;

      let { userId, amount, phone } = req.body;
      if (!amount || !phone) {
        return res.status(400).json({ error: 'Missing amount or phone' });
      }
      if (!commerceStore) return res.status(503).json({ error: 'Database not configured' });

      if (auth.uid === 'admin-secret') {
        if (!userId) userId = 'admin-secret';
      } else {
        if (!userId) return res.status(400).json({ error: 'Missing userId' });
        if (auth.uid !== userId) {
          return res.status(403).json({ error: 'Token does not match userId' });
        }
        const user = await commerceStore.getDocument('users', userId);
        if (!user) return res.status(404).json({ error: 'User not found' });
        if (!user.isAdmin) return res.status(403).json({ error: 'Admin access required' });
        if (user.isSuspended) return res.status(403).json({ error: 'Account suspended' });
      }

      // Page through revenue_transactions instead of loading the whole
      // collection into memory (scalability). Sum platform revenue by type.
      let totalCommissions = 0, totalBoostRevenue = 0, totalKycRevenue = 0, totalOtherRevenue = 0;
      const PAGE = 500;
      for (let i = 0; i < 200; i++) {
        const batch = await commerceStore.listDocuments('revenue_transactions', { limit: PAGE, offset: i * PAGE });
        if (!batch || batch.length === 0) break;
        batch.forEach(d => {
          const amt = Number(d.sokoLanguCommission || d.amount || 0) || 0;
          const type = String(d.type || '').toLowerCase();
          if (type === 'boost') totalBoostRevenue += amt;
          else if (type === 'kyc_fee') totalKycRevenue += amt;
          else if (type === 'sale') { /* seller earnings, not platform revenue */ }
          else if (type === 'profanity_seizure') totalOtherRevenue += amt;
          else totalCommissions += amt;
        });
        if (batch.length < PAGE) break;
      }
      const totalPlatformRevenue = totalCommissions + totalBoostRevenue + totalKycRevenue + totalOtherRevenue;
      const totalAdminBalance = totalPlatformRevenue;

      const withdrawnDocs = await commerceStore.listDocuments('admin_withdrawals', { userId });
      let totalWithdrawn = 0;
      withdrawnDocs.forEach(d => {
        if (d.status === 'completed') totalWithdrawn += (d.netAmount || d.amount || 0);
      });
      const availableBalance = totalPlatformRevenue - totalWithdrawn;

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
        const result = await processPayout({
          userId, phone, amount, fee: payoutFee, netAmount,
          source: 'admin_panel',
          type: 'admin_withdrawal',
          metadata: { adminUid: auth.uid },
        });
        payoutId = result.payoutId;
        await auditLog({
          userId,
          type: 'withdrawal',
          amount,
          balanceBefore: availableBalance,
          balanceAfter: availableBalance - amount,
          reason: 'Admin payout',
          relatedId: payoutId,
        });
        res.status(200).json({ success: true, payoutId });
      } catch (e) {
        console.error('Payout processing error:', e);
        res.status(500).json({ error: 'Failed to process payout' });
      }

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

      if (!commerceStore) return res.status(200).json({ received: false });

      const payoutDoc = await commerceStore.getDocument('payouts', payoutRef);
      if (!payoutDoc) {
        console.warn(`ClickPesa payout webhook: payout ${payoutRef} not found`);
        return res.status(200).json({ received: false });
      }

      const payout = payoutDoc;
      if (payout.status === PAYOUT_STATUSES.SUCCESS || payout.status === PAYOUT_STATUSES.FAILED) {
        return res.status(200).json({ received: true });
      }

      const clickpesaTxId = payload.id || payload.transactionId || '';

      if (eventStatus === 'SUCCESS') {
        await updatePayoutStatus(payoutRef, PAYOUT_STATUSES.SUCCESS, { clickpesaReference: clickpesaTxId });

        try {
          await commerceStore.updateDocument('transactions', payoutRef, {
            status: 'completed',
            clickpesaReference: clickpesaTxId,
            completedAt: commerceStore.serverTimestamp,
          });
        } catch (_) {}

        if (payout.metadata?.sellerId) {
          const sellerId = payout.metadata.sellerId;
          await commerceStore.addDocument('notifications', {
            userId: sellerId,
            title: 'Payout imefanikiwa!',
            body: `TZS ${(payout.netAmount || payout.amount).toLocaleString()} zimetumwa kwenye mobile money yako.`,
            isRead: false,
            createdAt: commerceStore.serverTimestamp,
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
          await commerceStore.updateDocument('transactions', payoutRef, {
            status: 'failed',
            failureReason: payload.message || payload.error || 'payout failed',
            clickpesaReference: clickpesaTxId,
            completedAt: commerceStore.serverTimestamp,
          });
        } catch (_) {}

        if (payout.userId && payout.amount) {
          try {
            await commerceStore.runTransaction(async (tx, store) => {
              const userRef = store.collection('users').doc(payout.userId);
              const userSnap = await tx.get(userRef);
              if (!userSnap.exists) return;
              tx.update(userRef, {
                sellerBalance: commerceStore.increment(payout.amount),
              });
            });
            console.log(`ClickPesa payout reversed: ${payoutRef} — TZS ${payout.amount} returned to ${payout.userId}`);
          } catch (reverseErr) {
            console.error(`CRITICAL: Failed to reverse payout ${payoutRef} for user ${payout.userId}:`, reverseErr);
          }
        }

        if (payout.userId) {
          try {
            await commerceStore.addDocument('notifications', {
              userId: payout.userId,
              title: '❌ Utoaji wa Pesa Umeshindwa',
              body: `TZS ${(payout.netAmount || payout.amount).toLocaleString()} hazikutumwa. Pesa zimerudishwa kwenye pochi yako. Jaribu tena.`,
              isRead: false,
              createdAt: commerceStore.serverTimestamp,
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
