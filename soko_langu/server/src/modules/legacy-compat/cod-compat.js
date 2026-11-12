// COD (cash on delivery) compat router.
//
// COD is a fulfilment/payment method that NEVER touches ClickPesa, escrow or
// seller wallet balances. Money is collected physically by the seller; this
// module only records delivery + cash-collection confirmations and guards
// against fake completion.
const express = require('express');
const admin = require('firebase-admin');
const commerceStore = require('../../services/commerce-store');
const { requireUser, isOwnerOrAdmin } = require('./auth-helpers');
const { normalizePaymentMethod, isCod } = require('../../utils/payment-method');

const router = express.Router();

function asyncHandler(fn) {
  return (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);
}

async function loadOrderDoc(orderId) {
  let doc = await commerceStore.getDocument('transactions', orderId).catch(() => null);
  if (!doc) doc = await commerceStore.getDocument('orders', orderId).catch(() => null);
  return doc;
}

function assertCod(doc) {
  if (!doc) {
    const e = new Error('ORDER_NOT_FOUND'); e.status = 404; throw e;
  }
  const pm = normalizePaymentMethod(doc.paymentMethod);
  if (pm !== 'cod') {
    const e = new Error('INVALID_PAYMENT_METHOD'); e.status = 400; throw e;
  }
  return doc;
}

// Seller dispatches a COD order. Requires buyer quote acceptance.
router.post('/:orderId/dispatch', asyncHandler(async (req, res) => {
  const auth = await requireUser(req, res);
  if (!auth.ok) return;
  const orderId = req.params.orderId;
  const doc = await loadOrderDoc(orderId);
  assertCod(doc);
  if (doc.sellerId !== auth.uid && !(await isOwnerOrAdmin(auth, doc))) {
    return res.status(403).json({ error: 'FORBIDDEN' });
  }
  if (!doc.quoteAcceptedByBuyer) {
    return res.status(409).json({ error: 'BUYER_QUOTE_NOT_ACCEPTED' });
  }
  const { courierName, trackingNumber, driverPhone, notes, receiptUrl, photoUrl } = req.body || {};
  const patch = {
    status: 'DISPATCHED',
    dispatchProof: { courierName: courierName || '', trackingNumber: trackingNumber || '', driverPhone: driverPhone || '', receiptUrl: receiptUrl || '', photoUrl: photoUrl || '', note: notes || '', dispatchedAt: new Date() },
    dispatchedAt: commerceStore.serverTimestamp(),
    updatedAt: commerceStore.serverTimestamp(),
  };
  await commerceStore.upsertDocument('orders', orderId, patch);
  await commerceStore.upsertDocument('transactions', orderId, patch);
  return res.json({ success: true, orderId });
}));

// Two-party confirmation: buyer confirms physical receipt.
router.post('/:orderId/confirm-delivery', asyncHandler(async (req, res) => {
  const auth = await requireUser(req, res);
  if (!auth.ok) return;
  const orderId = req.params.orderId;
  const doc = await loadOrderDoc(orderId);
  assertCod(doc);
  if (doc.buyerId !== auth.uid) return res.status(403).json({ error: 'FORBIDDEN' });

  const status = String(doc.status || '').toLowerCase();
  if (!['dispatched', 'in_transit', 'out_for_delivery', 'delivered'].includes(status)) {
    return res.status(409).json({ error: 'INVALID_ORDER_STATE' });
  }

  const patch = {
    buyerConfirmedDeliveryAt: commerceStore.serverTimestamp(),
    fulfillmentStatus: 'delivered',
    updatedAt: commerceStore.serverTimestamp(),
  };
  await commerceStore.upsertDocument('orders', orderId, patch);
  await commerceStore.upsertDocument('transactions', orderId, patch);

  return res.json({ success: true, orderId });
}));

// Seller records cash collection. Requires buyer delivery confirmation first.
router.post('/:orderId/confirm-cash-collected', asyncHandler(async (req, res) => {
  const auth = await requireUser(req, res);
  if (!auth.ok) return;
  const orderId = req.params.orderId;
  const doc = await loadOrderDoc(orderId);
  assertCod(doc);
  if (doc.sellerId !== auth.uid && !(await isOwnerOrAdmin(auth, doc))) {
    return res.status(403).json({ error: 'FORBIDDEN' });
  }
  if (!doc.buyerConfirmedDeliveryAt) {
    return res.status(409).json({ error: 'DELIVERY_NOT_CONFIRMED' });
  }
  if (doc.codCashCollectedAt) {
    return res.json({ success: true, alreadyRecorded: true, orderId });
  }

  const patch = {
    codCashCollectedAt: commerceStore.serverTimestamp(),
    codCashCollectionConfirmedBy: auth.uid,
    paymentStatus: 'cash_collected',
    status: 'COMPLETED',
    completedAt: commerceStore.serverTimestamp(),
    updatedAt: commerceStore.serverTimestamp(),
  };
  await commerceStore.upsertDocument('orders', orderId, patch);
  await commerceStore.upsertDocument('transactions', orderId, patch);

  return res.json({ success: true, orderId });
}));

router.post('/:orderId/report-delivery-issue', asyncHandler(async (req, res) => {
  const auth = await requireUser(req, res);
  if (!auth.ok) return;
  const orderId = req.params.orderId;
  const doc = await loadOrderDoc(orderId);
  assertCod(doc);
  const { reason } = req.body || {};
  const patch = {
    fulfillmentStatus: 'delivery_issue',
    codDeliveryIssue: reason || 'unspecified',
    updatedAt: commerceStore.serverTimestamp(),
  };
  await commerceStore.upsertDocument('orders', orderId, patch);
  await commerceStore.upsertDocument('transactions', orderId, patch);
  return res.json({ success: true, orderId });
}));

router.post('/:orderId/report-payment-issue', asyncHandler(async (req, res) => {
  const auth = await requireUser(req, res);
  if (!auth.ok) return;
  const orderId = req.params.orderId;
  const doc = await loadOrderDoc(orderId);
  assertCod(doc);
  const { reason } = req.body || {};
  const patch = {
    paymentStatus: 'cash_collection_disputed',
    codPaymentIssue: reason || 'unspecified',
    updatedAt: commerceStore.serverTimestamp(),
  };
  await commerceStore.upsertDocument('orders', orderId, patch);
  await commerceStore.upsertDocument('transactions', orderId, patch);
  return res.json({ success: true, orderId });
}));

module.exports = router;