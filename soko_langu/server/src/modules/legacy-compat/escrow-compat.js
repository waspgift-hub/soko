// Compat escrow router: verbatim port of the proven old-server escrow
// handlers (dispatch, release, cancel, dispute) under original paths.
// Core logic migrated to EscrowService.
const express = require('express');
const admin = require('firebase-admin');
const { requireAdmin } = require('./auth-helpers');
const escrowService = require('../../services/escrow-service');
const commerceStore = require('../../services/commerce-store');
const { normalizePaymentMethod, isCod } = require('../../utils/payment-method');

const router = express.Router();

async function verifySeller(req, res, userId) {
  const authHeader = req.headers.authorization || '';
  const token = authHeader.replace('Bearer ', '');
  if (!token) return { ok: false, status: 401, error: 'Unauthorized' };
  try {
    const decodedToken = await admin.auth().verifyIdToken(token);
    if (decodedToken.uid !== userId) {
      return { ok: false, status: 403, error: 'Token does not match user' };
    }
    return { ok: true, uid: decodedToken.uid };
  } catch (_) {
    return { ok: false, status: 403, error: 'Invalid token' };
  }
}

async function assertEscrowOrder(orderId, res) {
  const doc = await commerceStore.getDocument('transactions', orderId).catch(() => null)
    || await commerceStore.getDocument('orders', orderId).catch(() => null);
  if (!doc) { res.status(404).json({ error: 'ORDER_NOT_FOUND' }); return null; }
  if (isCod(doc.paymentMethod)) { res.status(400).json({ error: 'INVALID_PAYMENT_METHOD', message: 'COD orders cannot use escrow endpoints' }); return null; }
  return doc;
}

router.post('/dispatch', async (req, res) => {
  try {
    const { orderId, userId, courierName, trackingNumber, driverPhone, notes, receiptUrl, photoUrl, note } = req.body;
    if (!orderId || !userId) return res.status(400).json({ error: 'Missing orderId or userId' });

    const auth = await verifySeller(req, res, userId);
    if (!auth.ok) return res.status(auth.status).json({ error: auth.error });

    const doc = await assertEscrowOrder(orderId, res);
    if (!doc) return;

    await escrowService.dispatchOrder({
      orderId,
      sellerId: userId,
      courierDetails: {
        courierName: courierName || '',
        trackingNumber: trackingNumber || '',
        driverPhone: driverPhone || '',
        receiptUrl: receiptUrl || '',
        photoUrl: photoUrl || '',
        note: note || notes || '',
      },
    });

    res.json({ success: true });
  } catch (e) {
    if (e.message.includes('FORBIDDEN')) return res.status(403).json({ error: e.message });
    if (e.message.includes('INVALID_STATE')) return res.status(400).json({ error: e.message });
    if (e.message === 'ORDER_NOT_FOUND') return res.status(404).json({ error: 'Transaction not found' });
    console.error('Escrow dispatch error:', e);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/release', async (req, res) => {
  try {
    const { orderId, userId } = req.body;
    if (!orderId || !userId) return res.status(400).json({ error: 'Missing orderId or userId' });

    const auth = await verifySeller(req, res, userId);
    if (!auth.ok) return res.status(auth.status).json({ error: auth.error });

    const doc = await assertEscrowOrder(orderId, res);
    if (!doc) return;

    const result = await escrowService.releaseEscrow({
      orderId,
      sellerId: userId,
      idempotencyKey: `release_${orderId}`,
    });

    res.json({ success: true, sellerReceives: result.sellerReceives });
  } catch (e) {
    console.error('Escrow release error:', e);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/cancel', async (req, res) => {
  try {
    const { orderId, userId } = req.body;
    if (!orderId || !userId) return res.status(400).json({ error: 'Missing orderId or userId' });

    const auth = await verifySeller(req, res, userId);
    if (!auth.ok) return res.status(auth.status).json({ error: auth.error });

    const doc = await assertEscrowOrder(orderId, res);
    if (!doc) return;

    const result = await escrowService.cancelOrder({
      orderId,
      buyerId: userId,
    });

    res.json({ success: true, refundAmount: result.refundAmount });
  } catch (e) {
    console.error('Escrow cancel error:', e);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/dispute', async (req, res) => {
  try {
    const { orderId, userId, reason } = req.body;
    if (!orderId || !userId) return res.status(400).json({ error: 'Missing orderId or userId' });

    const auth = await verifySeller(req, res, userId);
    if (!auth.ok) return res.status(auth.status).json({ error: auth.error });

    const doc = await assertEscrowOrder(orderId, res);
    if (!doc) return;

    await escrowService.openDispute({
      orderId,
      buyerId: userId,
      reason: reason || 'No reason provided',
    });

    res.json({ success: true });
  } catch (e) {
    console.error('Escrow dispute error:', e);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/admin-resolve-dispute', async (req, res) => {
  try {
    const auth = await requireAdmin(req, res);
    if (!auth.ok) return;

    const { orderId, resolution, amount, note } = req.body;
    await escrowService.resolveDispute({
      orderId,
      resolution,
      amount,
      note,
      adminId: auth.uid,
    });

    res.json({ success: true, message: `Dispute resolved: ${resolution}` });
  } catch (e) {
    console.error('Escrow admin-resolve-dispute error:', e);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/admin-transfer', async (req, res) => {
  try {
    const auth = await requireAdmin(req, res);
    if (!auth.ok) return;

    const { orderId, amount, phone, note } = req.body;
    await escrowService.adminTransfer({
      orderId,
      amount,
      phone,
      note,
      adminId: auth.uid,
    });

    res.json({ success: true, message: 'Admin transfer completed' });
  } catch (e) {
    console.error('Escrow admin-transfer error:', e);
    res.status(500).json({ error: 'Internal server error' });
  }
});

module.exports = router;
