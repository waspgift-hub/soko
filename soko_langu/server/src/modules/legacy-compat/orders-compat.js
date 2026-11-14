// Compat orders/checkout router: verbatim port of proven old-server
// handlers (payment-link, statements, transaction-status, transactions
// create, gateway-fee, orders transition) under original /api paths.
const express = require('express');
const admin = require('firebase-admin');
const commerceStore = require('../../services/commerce-store');
const { requireUser, isOwnerOrAdmin } = require('./auth-helpers');
const { sendOneSignalNotification } = require('./notify');
const {
  clickpesaCollect,
  clickpesaCreateBillPayOrder,
  clickpesaUssdPushPreview,
  calcGatewayFee,
} = require('../../../clickpesa');
const { resolveEffectivePrice } = require('../../../money');
const { paymentLimiter } = require('../../middleware/rateLimiter');
const config = require('../../config');
const cache = require('../../../cache');
const { getRedis } = require('../../config/redis');
const { checkSuspended, ESCROW_REGIONAL_DAYS, ESCROW_LOCAL_DAYS } = require('./fraud-checks');
const escrowService = require('../../services/escrow-service');


try {
  cache.setRedisClient(getRedis());
} catch (e) {
  console.error('[COMPAT-ORDERS] cache wiring failed:', e.message);
}

const shippingValidation = require('../shipping/shipping-validation');
const MAX_DAILY_SALE_AMOUNT = config.business.maxDailySaleAmount;

function asyncHandler(fn) {
  return (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);
}

function sanitize(str) {
  if (typeof str !== 'string') return '';
  return str.replace(/<[^>]*>/g, '').trim().slice(0, 1000);
}

// Auto-release is owned by `finance.inspectionAutoRelease` and the canonical
// `autoRelease()` service (ESCROW_AUTO_RELEASE_DAYS, default 14). Do not add a
// second window here: the old 48h constant contradicted the approved policy.
// Historical spellings of "funds held" produced by the engine over time.
const ESCROW_STATES = ['pending', 'quoted', 'escrow_hold', 'paid_escrow_hold', 'paid_escrow_held', 'in_escrow', 'ready_to_dispatch'];
const DISPATCH_STATES = ['escrow_hold', 'paid_escrow_hold', 'paid_escrow_held', 'in_escrow', 'ready_to_dispatch'];
const TRANSIT_STATES = ['dispatched', 'in_transit', 'out_for_delivery', 'delivery_attempted'];

const router = express.Router();

router.get('/transactions', asyncHandler(async (req, res) => {
  const auth = await requireUser(req, res);
  if (!auth.ok) return;

  const { uid } = auth;
  const { status, from, to } = req.query;

  const where = [];
  if (status) where.push({ field: 'status', op: '==', value: status });
  if (uid) where.push({ field: 'userId', op: '==', value: uid });

  const snap = await commerceStore.listDocuments('transactions', { where, limit: 100 });
  res.json({ success: true, data: snap });
}));

router.get('/transaction/:id', asyncHandler(async (req, res) => {
  const auth = await requireUser(req, res);
  if (!auth.ok) return;

  const { id } = req.params;
  const doc = await commerceStore.getDocument('transactions', id);
  if (!doc) return res.status(404).json({ error: 'Transaction not found' });
  if (!(await isOwnerOrAdmin(auth, doc))) {
    return res.status(403).json({ error: 'Forbidden' });
  }
  res.json({ success: true, data: doc });
}));

router.post('/transactions/create', asyncHandler(async (req, res) => {
  const auth = await requireUser(req, res);
  if (!auth.ok) return;

  const { orderId, amount, currency = 'TZS', description } = req.body;
  if (!orderId || !amount) return res.status(400).json({ error: 'orderId and amount required' });

  const txData = {
    orderId,
    amount: Number(amount),
    currency,
    description: description || `Payment for order ${orderId}`,
    status: 'pending',
    userId: auth.uid,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  const txId = await commerceStore.addDocument('transactions', txData);
  res.json({ success: true, txId });
}));

router.get('/orders/:id', asyncHandler(async (req, res) => {
  const auth = await requireUser(req, res);
  if (!auth.ok) return;

  const { id } = req.params;
  const order = await commerceStore.getDocument('orders', id);
  if (!order) return res.status(404).json({ error: 'Order not found' });

  // Mask sensitive data
  const sanitizedOrder = { ...order };
  delete sanitizedOrder.internalNotes;

  res.json({ success: true, data: sanitizedOrder });
}));

router.patch('/orders/:id/transition', asyncHandler(async (req, res) => {
  const auth = await requireUser(req, res);
  if (!auth.ok) return;

  const { id: orderId } = req.params;
  const { newStatus, note } = req.body;

  if (!newStatus) return res.status(400).json({ error: 'newStatus required' });

  const order = await commerceStore.getDocument('orders', orderId);
  if (!order) return res.status(404).json({ error: 'Order not found' });

  // Security check: must be owner or admin
  if (!isOwnerOrAdmin(auth, order)) {
    return res.status(403).json({ error: 'Unauthorized to transition this order' });
  }

  const result = await escrowService.transitionOrder({
    orderId,
    newStatus,
    note,
    uid: auth.uid,
  });

  // Real-time status notifications: buyer on quote, buyer on dispatch
  try {
    if (newStatus === 'quoted') {
      let costLabel = '';
      let shippingCost = 0;
      try {
        const parsed = JSON.parse(note || '{}');
        shippingCost = Number(parsed.shippingCost || 0);
        if (shippingCost > 0) costLabel = ` la TZS ${shippingCost.toLocaleString()}`;
      } catch (_) {}
      await commerceStore.addDocument('notifications', {
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
      const sellerConfirmBody = `Quote yako ya usafirishaji ya TZS ${shippingCost.toLocaleString()} imetumwa kwa ${order.buyerName || 'mnunuzi'}.`;
      await commerceStore.addDocument('notifications', {
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
      await commerceStore.addDocument('notifications', {
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
}));

module.exports = router;
