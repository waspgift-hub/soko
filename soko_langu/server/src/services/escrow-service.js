const { getFirebaseFirestore } = require('../config/firebase');
const { OrderStateMachine, ORDER_STATES, canonicalStatusOf } = require('../modules/orders/order-state-machine');
const commerceStore = require('./commerce-store');
const { sendOneSignalNotification } = require('../modules/legacy-compat/notify');
const { sendSms } = require('./sms-service');
const shippingValidation = require('../modules/shipping/shipping-validation');

/**
 * Escrow Service
 * Orchestrates the movement of funds and order state during the fulfillment phase.
 */

async function setShippingQuote({ orderId, shippingCost, uid, db }) {
  const store = db || getFirebaseFirestore();
  const txDoc = await store.collection('transactions').doc(orderId).get();
  if (!txDoc.exists) throw new Error('ORDER_NOT_FOUND');

  const tx = txDoc.data();
  const currentStatus = canonicalStatusOf(tx.status);
  const machine = new OrderStateMachine(currentStatus);

  const buyerAddrMap = tx.deliveryAddress && typeof tx.deliveryAddress === 'object' ? tx.deliveryAddress : {};
  const validation = shippingValidation.validateShippingQuote({
    amount: shippingCost,
    shippingAddress: {
      region: tx.region || buyerAddrMap.region || '',
      city: tx.district || buyerAddrMap.district || '',
    },
    sellerRegion: tx.sellerRegion || '',
  });

  const totalAmount = (tx.productPrice || 0) + shippingCost;

  await txDoc.ref.update({
    updatedAt: new Date(),
    status: ORDER_STATES.PENDING_SHIPPING_FEE,
    shippingCost,
    totalAmount,
    shippingQuote: {
      amount: shippingCost,
      setAt: new Date(),
      setBy: uid,
      verdict: validation.verdict,
      distanceTier: validation.distanceTier,
      reason: validation.reason || null,
      baseline: validation.baseline,
    },
  });

  return { status: 'quoted', shippingCost, totalAmount };
}

async function updateLogisticsStatus({ orderId, status, uid, note, db }) {
  const store = db || getFirebaseFirestore();
  const txDoc = await store.collection('transactions').doc(orderId).get();
  if (!txDoc.exists) throw new Error('ORDER_NOT_FOUND');

  const tx = txDoc.data();
  const currentStatus = canonicalStatusOf(tx.status);
  const machine = new OrderStateMachine(currentStatus);

  const targetStatus = canonicalStatusOf(status);
  if (!machine.canTransition(targetStatus)) {
    throw new Error(`Invalid order transition: ${machine.state} -> ${targetStatus}`);
  }

  const timestamp = new Date();
  let update = { updatedAt: timestamp, status: targetStatus };

  switch (targetStatus) {
    case ORDER_STATES.DISPATCHED:
      update = {
        ...update,
        dispatchedAt: timestamp,
        flowStage: 'in_transit',
        autoReleaseDeadline: new Date(Date.now() + 48 * 60 * 60 * 1000),
        dispatchProof: { note: note || '', dispatchedAt: timestamp },
      };
      break;
    case ORDER_STATES.IN_TRANSIT:
      update = { ...update, flowStage: 'in_transit', inTransitAt: timestamp };
      break;
    case ORDER_STATES.OUT_FOR_DELIVERY:
      update = { ...update, flowStage: 'out_for_delivery', outForDeliveryAt: timestamp };
      break;
    case ORDER_STATES.DELIVERED:
      update = {
        ...update,
        deliveredAt: timestamp,
        flowStage: 'inspection_period',
        inspectionMinutes: 30,
        inspectionDeadline: new Date(Date.now() + 30 * 60 * 1000),
        arrivalConfirmedBy: uid,
      };
      break;
    case ORDER_STATES.DISPUTED:
      update = {
        ...update,
        disputeInfo: {
          reason: note || 'Sijapata mzigo',
          evidenceUrls: [],
          raisedAt: timestamp,
          resolved: false,
          raisedBy: uid,
        },
      };
      break;
  }

  await txDoc.ref.update(update);
  return { success: true, status: targetStatus };
}

async function confirmDelivery({ orderId, uid, db }) {
  const store = db || getFirebaseFirestore();
  const txDoc = await store.collection('transactions').doc(orderId).get();
  if (!txDoc.exists) throw new Error('ORDER_NOT_FOUND');

  await txDoc.ref.update({
    updatedAt: new Date(),
    confirmedBy: uid,
    deliveryConfirmedAt: new Date(),
  });

  return { success: true };
}

async function dispatchOrder({ orderId, sellerId, courierDetails, db }) {
  const store = db || getFirebaseFirestore();
  const txDoc = await store.collection('transactions').doc(orderId).get();
  if (!txDoc.exists) throw new Error('ORDER_NOT_FOUND');

  const tx = txDoc.data();
  if (tx.sellerId !== sellerId) throw new Error('FORBIDDEN_SELLER');

  const currentStatus = canonicalStatusOf(tx.status);
  const machine = new OrderStateMachine(currentStatus);
  
  // Dispatch is allowed from several "held" states
  const dispatchable = [ORDER_STATES.ESCROW_HELD, ORDER_STATES.IN_ESCROW, ORDER_STATES.READY_TO_DISPATCH];
  if (!dispatchable.includes(machine.state)) {
    throw new Error(`INVALID_STATE_FOR_DISPATCH:${machine.state}`);
  }

  const dispatchProof = {
    ...courierDetails,
    dispatchedAt: new Date(), // Simplified for service layer, controller can use serverTimestamp
  };

  await txDoc.ref.update({
    status: ORDER_STATES.DISPATCHED,
    flowStage: 'in_transit',
    dispatchProof,
    dispatchedAt: new Date(),
    autoReleaseDeadline: new Date(Date.now() + 48 * 60 * 60 * 1000),
  });

  return { success: true };
}

async function releaseEscrow({ orderId, sellerId, idempotencyKey, db }) {
  const store = db || getFirebaseFirestore();
  const txDoc = await store.collection('transactions').doc(orderId).get();
  if (!txDoc.exists) throw new Error('ORDER_NOT_FOUND');

  const tx = txDoc.data();
  const amount = tx.amount || 0;
  const commission = tx.commission || 0;

  // Use CommerceStore for the atomic balance transfer
  const result = await commerceStore.settleEscrowToSeller({
    orderId,
    sellerId,
    amount,
    commission,
    idempotencyKey,
    db: store,
  });

  if (result.alreadySettled) {
    return { success: true, alreadySettled: true };
  }

  await txDoc.ref.update({
    status: ORDER_STATES.COMPLETED,
    completedAt: new Date(),
    escrowReleased: true,
  });

  return { success: true, sellerReceives: result.sellerReceives };
}

async function cancelOrder({ orderId, buyerId, db }) {
  const store = db || getFirebaseFirestore();
  const txDoc = await store.collection('transactions').doc(orderId).get();
  if (!txDoc.exists) throw new Error('ORDER_NOT_FOUND');

  const tx = txDoc.data();
  
  // Refund buyer logic
  const refundAmount = tx.amount || 0;
  
  // 1. Mark order as cancelled
  await txDoc.ref.update({
    status: ORDER_STATES.CANCELLED,
    cancelledAt: new Date(),
    escrowReleased: true,
  });

  // 2. In a real production system, we would trigger a ClickPesa refund here.
  // For now, we assume the funds are held in the platform's escrow account 
  // and we just need to update the transaction state.
  
  return { success: true, refundAmount };
}

async function openDispute({ orderId, buyerId, reason, db }) {
  const store = db || getFirebaseFirestore();
  const txDoc = await store.collection('transactions').doc(orderId).get();
  if (!txDoc.exists) throw new Error('ORDER_NOT_FOUND');

  await txDoc.ref.update({
    status: ORDER_STATES.DISPUTED,
    disputeOpenedAt: new Date(),
    disputeReason: reason,
    'disputeInfo.status': 'open',
  });

  return { success: true };
}

async function resolveDispute({ orderId, resolution, amount, note, adminId, db }) {
  const store = db || getFirebaseFirestore();

async function adminTransfer({ orderId, amount, phone, note, adminId, db }) {
  const store = db || getFirebaseFirestore();
  const txDoc = await store.collection('transactions').doc(orderId).get();
  if (!txDoc.exists) throw new Error('ORDER_NOT_FOUND');

  const tx = txDoc.data();
  const sellerId = tx.sellerId;

  // 1. Cancel the order
  await txDoc.ref.update({
    status: ORDER_STATES.CANCELLED,
    cancelledBy: 'admin',
    cancelledAt: new Date(),
    adminNote: note,
    escrowReleased: true,
  });

  // 2. Payout to arbitrary phone
  // In a real system, we'd call the payout provider here.
  // For now, we record the transfer.
  await store.collection('payouts').add({
    orderId,
    amount,
    phone,
    note,
    adminId,
    status: 'completed',
    createdAt: new Date(),
  });

  return { success: true };
}

  const txDoc = await store.collection('transactions').doc(orderId).get();
  if (!txDoc.exists) throw new Error('ORDER_NOT_FOUND');

  const tx = txDoc.data();
  const sellerId = tx.sellerId;
  const buyerId = tx.buyerId;

  if (resolution === 'refund_to_buyer') {
    // Refund buyer
    await txDoc.ref.update({
      status: ORDER_STATES.REFUNDED,
      'disputeInfo.resolved': true,
      'disputeInfo.resolution': 'refunded_to_buyer',
      'disputeInfo.refundedAmount': amount,
      'disputeInfo.adminNote': note,
    });
    
    // If there was a partial release to seller, we might need to penalize them
    // (matching the logic in escrow-compat.js)
  } else if (resolution === 'release_to_seller') {
    await releaseEscrow({ orderId, sellerId, db: store });
    await txDoc.ref.update({
      status: ORDER_STATES.COMPLETED,
      'disputeInfo.resolved': true,
      'disputeInfo.resolution': 'released_to_seller',
      'disputeInfo.adminNote': note,
    });
  }

  return { success: true };
}

async function getTransaction(orderId, db) {
  const store = db || getFirebaseFirestore();
  const txDoc = await store.collection('transactions').doc(orderId).get();
  return txDoc.exists ? { id: txDoc.id, ...txDoc.data() } : null;
}

async function createTransaction({ orderId, data, db }) {
  const store = db || getFirebaseFirestore();
  const ref = orderId ? store.collection('transactions').doc(orderId) : store.collection('transactions').doc();
  await ref.set(data, { merge: true });
  return { id: ref.id, ...data };
}

async function listTransactionsBySeller(sellerId, limit = 300, db) {
  const store = db || getFirebaseFirestore();
  const snap = await store.collection('transactions')
    .where('sellerId', '==', sellerId)
    .limit(limit)
    .get();
  return snap.docs.map(doc => ({ id: doc.id, ...doc.data() }));
}

module.exports = {
  setShippingQuote,
  updateLogisticsStatus,
  confirmDelivery,
  dispatchOrder,
  releaseEscrow,
  cancelOrder,
  openDispute,
  resolveDispute,
  adminTransfer,
  getTransaction,
  createTransaction,
  listTransactionsBySeller,
};
