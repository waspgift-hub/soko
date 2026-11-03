const admin = require('firebase-admin');
const ORDER_STATUS = {
  PENDING: 'pending',
  QUOTED: 'quoted',
  PAID: 'paid',
  ESCROW_HOLD: 'escrow_hold',
  DISPATCHED: 'dispatched',
  CONFIRMED: 'confirmed',
  COMPLETED: 'completed',
  CANCELLED: 'cancelled',
  DISPUTED: 'disputed',
  REFUNDED: 'refunded',
  FAILED: 'failed',
};

const ESCROW_STATUS = {
  HELD: 'held',
  RELEASED: 'released',
  DISPUTED: 'disputed',
};

const STATUS_COLORS = {
  pending: '#2196F3',
  quoted: '#00BCD4',
  paid: '#4CAF50',
  escrow_hold: '#FF9800',
  dispatched: '#FF5722',
  confirmed: '#9C27B0',
  completed: '#E91E63',
  cancelled: '#F44336',
  disputed: '#FFC107',
  refunded: '#9E9E9E',
  failed: '#F44336',
};

function isValidTransition(from, to) {
  const transitions = {
    [ORDER_STATUS.PENDING]: [ORDER_STATUS.QUOTED, ORDER_STATUS.CANCELLED],
    [ORDER_STATUS.QUOTED]: [ORDER_STATUS.PAID, ORDER_STATUS.CANCELLED],
    [ORDER_STATUS.PAID]: [ORDER_STATUS.ESCROW_HOLD, ORDER_STATUS.FAILED],
    [ORDER_STATUS.ESCROW_HOLD]: [ORDER_STATUS.DISPATCHED, ORDER_STATUS.DISPUTED, ORDER_STATUS.CANCELLED],
    [ORDER_STATUS.DISPATCHED]: [ORDER_STATUS.CONFIRMED, ORDER_STATUS.DISPUTED],
    [ORDER_STATUS.CONFIRMED]: [ORDER_STATUS.COMPLETED, ORDER_STATUS.DISPUTED],
    [ORDER_STATUS.DISPUTED]: [ORDER_STATUS.REFUNDED, ORDER_STATUS.COMPLETED],
    [ORDER_STATUS.COMPLETED]: [],
    [ORDER_STATUS.CANCELLED]: [],
    [ORDER_STATUS.REFUNDED]: [],
    [ORDER_STATUS.FAILED]: [ORDER_STATUS.PAID],
  };
  return transitions[from]?.includes(to) ?? false;
}

// Role-based transition enforcement: only certain actors can trigger certain transitions.
// 'system' is used by webhooks/listeners (paid→escrow_hold, paid→failed).
const ROLE_ALLOWED_TRANSITIONS = {
  seller: [ORDER_STATUS.QUOTED, ORDER_STATUS.DISPATCHED, ORDER_STATUS.CANCELLED],
  buyer:  [ORDER_STATUS.PAID, ORDER_STATUS.DISPUTED, ORDER_STATUS.CONFIRMED, ORDER_STATUS.CANCELLED],
  admin:  [ORDER_STATUS.REFUNDED, ORDER_STATUS.COMPLETED, ORDER_STATUS.CANCELLED],
  system: [ORDER_STATUS.ESCROW_HOLD, ORDER_STATUS.FAILED],
};

function canActorTransition(actorRole, newStatus) {
  const allowed = ROLE_ALLOWED_TRANSITIONS[actorRole];
  if (!allowed) return false;
  return allowed.includes(newStatus);
}

function getOrderStepNumber(status) {
  const steps = [
    ORDER_STATUS.PENDING, ORDER_STATUS.QUOTED, ORDER_STATUS.PAID,
    ORDER_STATUS.ESCROW_HOLD, ORDER_STATUS.DISPATCHED,
    ORDER_STATUS.CONFIRMED, ORDER_STATUS.COMPLETED,
  ];
  const idx = steps.indexOf(status);
  return idx >= 0 ? idx + 1 : 0;
}

async function addTimelineEntry(db, orderId, entry) {
  await db.collection('orderTimeline').add({
    orderId,
    ...entry,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

async function createOrder(db, data) {
  const orderRef = db.collection('orders').doc();
  const order = {
    orderId: orderRef.id,
    ...data,
    status: ORDER_STATUS.PENDING,
    statusHistory: [{ status: ORDER_STATUS.PENDING, at: new Date().toISOString() }],
    escrowStatus: null,
    escrowReleased: false,
    disputeInfo: null,
    dispatchProof: null,
    confirmReceiptAt: null,
    completedAt: null,
    cancelledAt: null,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  await orderRef.set(order);
  await addTimelineEntry(db, orderRef.id, { status: ORDER_STATUS.PENDING, title: 'Order Placed', description: 'Buyer placed an order' });
  return { orderId: orderRef.id, ...order };
}

async function transitionOrder(db, orderId, newStatus, actorId, meta = {}) {
  const doc = await db.collection('orders').doc(orderId).get();
  if (!doc.exists) throw new Error('Order not found');
  const order = doc.data();
  if (!isValidTransition(order.status, newStatus)) {
    throw new Error(`Cannot transition from ${order.status} to ${newStatus}`);
  }
  const updates = { status: newStatus, updatedAt: admin.firestore.FieldValue.serverTimestamp() };
  if (newStatus === ORDER_STATUS.QUOTED) {
    let parsedNote = {};
    try { parsedNote = typeof meta.note === 'string' ? JSON.parse(meta.note) : (meta.note || {}); } catch (_) {}
    const shippingCost = Number(parsedNote.shippingCost || 0);
    updates.shippingCost = shippingCost;
    updates.busName = parsedNote.busName || '';
    updates.plateNumber = parsedNote.plateNumber || '';
  }
  if (newStatus === ORDER_STATUS.CANCELLED) updates.cancelledAt = admin.firestore.FieldValue.serverTimestamp();
  if (newStatus === ORDER_STATUS.COMPLETED) updates.completedAt = admin.firestore.FieldValue.serverTimestamp();
  if (newStatus === ORDER_STATUS.CONFIRMED) updates.confirmReceiptAt = admin.firestore.FieldValue.serverTimestamp();
  if (newStatus === ORDER_STATUS.DISPATCHED) updates.dispatchedAt = admin.firestore.FieldValue.serverTimestamp();
  if (newStatus === ORDER_STATUS.DISPUTED) updates.disputeInfo = { reason: meta.reason || '', evidenceUrls: meta.evidenceUrls || [], raisedAt: admin.firestore.FieldValue.serverTimestamp(), resolved: false };
  if (newStatus === ORDER_STATUS.ESCROW_HOLD) { updates.escrowStatus = ESCROW_STATUS.HELD; updates.escrowHeldAt = admin.firestore.FieldValue.serverTimestamp(); }
  if (newStatus === ORDER_STATUS.COMPLETED || newStatus === ORDER_STATUS.REFUNDED) { updates.escrowStatus = ESCROW_STATUS.RELEASED; updates.escrowReleased = true; updates.escrowReleasedAt = admin.firestore.FieldValue.serverTimestamp(); }
  await doc.ref.update(updates);
  await doc.ref.update({ statusHistory: admin.firestore.FieldValue.arrayUnion({ status: newStatus, at: new Date().toISOString(), by: actorId, ...meta }) });

  // Keep the transactions mirror doc (buyer's payment source of truth) in sync
  // server-side so a failed client-side manual write can't leave the docs
  // divergent. The transaction is created with the orderId as its doc id.
  try {
    const txRef = db.collection('transactions').doc(orderId);
    const txDoc = await txRef.get();
    if (newStatus === ORDER_STATUS.QUOTED) {
      let parsedNote = {};
      try { parsedNote = typeof meta.note === 'string' ? JSON.parse(meta.note) : (meta.note || {}); } catch (_) {}
      const shippingCost = Number(parsedNote.shippingCost || 0);
      await txRef.set({
        status: newStatus,
        shippingCost,
        busName: parsedNote.busName || '',
        plateNumber: parsedNote.plateNumber || '',
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      if (txDoc.exists) {
        await txRef.update({ totalAmount: admin.firestore.FieldValue.increment(shippingCost) });
      }
    } else if (txDoc.exists) {
      await txRef.update({ status: newStatus, updatedAt: admin.firestore.FieldValue.serverTimestamp() });
    }
  } catch (e) {
    console.error('transitionOrder mirror-sync error:', e.message);
  }
  const titles = {
    [ORDER_STATUS.PENDING]: 'Order Placed',
    [ORDER_STATUS.QUOTED]: 'Shipping Quote Provided',
    [ORDER_STATUS.PAID]: 'Payment Completed',
    [ORDER_STATUS.ESCROW_HOLD]: 'Funds in Escrow',
    [ORDER_STATUS.DISPATCHED]: 'Order Dispatched',
    [ORDER_STATUS.CONFIRMED]: 'Delivery Confirmed',
    [ORDER_STATUS.COMPLETED]: 'Order Completed',
    [ORDER_STATUS.CANCELLED]: 'Order Cancelled',
    [ORDER_STATUS.DISPUTED]: 'Dispute Opened',
    [ORDER_STATUS.REFUNDED]: 'Refunded',
    [ORDER_STATUS.FAILED]: 'Payment Failed',
  };
  await addTimelineEntry(db, orderId, { status: newStatus, title: titles[newStatus] || newStatus, description: meta.note || '', actorId });
  return { ...order, ...updates };
}

module.exports = {
  ORDER_STATUS,
  ESCROW_STATUS,
  STATUS_COLORS,
  isValidTransition,
  canActorTransition,
  getOrderStepNumber,
  addTimelineEntry,
  createOrder,
  transitionOrder,
};
