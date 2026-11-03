const { getPrisma } = require('../../config/database');
const { acquireLock, releaseLock } = require('../../config/redis');
const { OrderStateMachine, ORDER_STATES } = require('../orders/order-state-machine');
const { releaseEscrowAndSettle } = require('../handover/handover-service');

const DISPUTE_REASONS = [
  'WRONG_ITEM',
  'DAMAGED_ITEM',
  'FAKE_ITEM',
  'NOT_RECEIVED',
  'QUALITY_ISSUE',
  'BUYER_FRAUD',
];

// Reason groups: some reasons are for buyer-filed, some for seller-filed.
const BUYER_REASONS = ['WRONG_ITEM', 'DAMAGED_ITEM', 'FAKE_ITEM', 'NOT_RECEIVED', 'QUALITY_ISSUE'];
const SELLER_REASONS = ['BUYER_FRAUD'];

/**
 * File a dispute on an order.
 * Moves order to DISPUTED and freezes the escrow hold.
 */
async function fileDispute({ orderId, filedBy, reason, description, role }) {
  const prisma = getPrisma();
  const lock = await acquireLock(`dispute:${orderId}`, 60);

  try {
    return await prisma.$transaction(async (tx) => {
      const order = await tx.order.findUnique({ where: { id: orderId } });
      if (!order) throw httpError(404, 'ORDER_NOT_FOUND');

      const isBuyer = order.buyerId === filedBy;
      const isSeller = order.sellerId === filedBy;
      if (!isBuyer && !isSeller) throw httpError(403, 'FORBIDDEN');

      // Validate reason belongs to the filer's allowed list
      const allowed = role === 'seller' ? SELLER_REASONS : BUYER_REASONS;
      if (!DISPUTE_REASONS.includes(reason)) throw httpError(400, 'INVALID_REASON');
      if (role !== 'admin' && !allowed.includes(reason)) {
        throw httpError(400, `REASON_NOT_ALLOWED_FOR_ROLE:${role}`);
      }

      // Dispute window: only disputable states
      if (!isDisputableState(order.status)) {
        throw httpError(409, `CANNOT_DISPUTE_IN_STATE:${order.status}`);
      }

      const machine = new OrderStateMachine(order.status);
      machine.transition(ORDER_STATES.DISPUTED, {
        actor: role || (isBuyer ? 'buyer' : 'seller'),
        actorId: filedBy,
        reason: `Dispute filed: ${reason}`,
      });

      const dispute = await tx.dispute.create({
        data: {
          orderId,
          filedBy,
          reason,
          description,
          status: 'open',
        },
      });

      // Freeze escrow
      const escrowHold = await tx.escrowHold.findFirst({
        where: { orderId, status: 'holding' },
      });
      if (escrowHold) {
        await tx.escrowHold.update({
          where: { id: escrowHold.id },
          data: { status: 'disputed' },
        });
      }

      await tx.order.update({
        where: { id: orderId },
        data: { status: ORDER_STATES.DISPUTED, statusChangedBy: filedBy },
      });

      return dispute;
    });
  } finally {
    if (!lock.skipped) await releaseLock(`dispute:${orderId}`);
  }
}

/**
 * Resolve a dispute. Resolution decides fund outcome:
 *  - FULL_TO_SELLER: release escrow to seller (order completes immediately)
 *  - FULL_REFUND: release escrow to buyer (opens a pending refund record)
 *  - PARTIAL: split escrow — buyer gets buyerAmount back, seller keeps the
 *    remainder in escrow until delivery/OTP completes
 */
async function resolveDispute({ disputeId, resolvedBy, resolution, note, buyerAmount, sellerAmount }) {
  const prisma = getPrisma();
  const lock = await acquireLock(`dispute:${disputeId}`, 60);

  try {
    return await prisma.$transaction(async (tx) => {
      const dispute = await tx.dispute.findUnique({ where: { id: disputeId }, include: { order: true } });
      if (!dispute) throw httpError(404, 'DISPUTE_NOT_FOUND');
      if (dispute.status !== 'open') throw httpError(409, 'DISPUTE_NOT_OPEN');

      const valid = ['FULL_TO_SELLER', 'FULL_REFUND', 'PARTIAL'];
      if (!valid.includes(resolution)) throw httpError(400, 'INVALID_RESOLUTION');

      const escrowHold = await tx.escrowHold.findFirst({
        where: { orderId: dispute.orderId, status: { in: ['holding', 'disputed'] } },
      });
      if (!escrowHold) throw httpError(409, 'DISPUTE_ESCROW_UNAVAILABLE');
      const escrowAvailable = escrowHold.amount - escrowHold.releasedToBuyer;

      let split = null;
      if (resolution === 'PARTIAL') {
        split = validateDisputeSplit(escrowAvailable, buyerAmount, sellerAmount);
      }

      let nextState;
      if (resolution === 'FULL_TO_SELLER') nextState = ORDER_STATES.COMPLETED;
      else if (resolution === 'FULL_REFUND') nextState = ORDER_STATES.REFUND_PENDING;
      else nextState = ORDER_STATES.REFUND_PENDING;

      const machine = new OrderStateMachine(dispute.order.status);
      machine.transition(nextState, {
        actor: resolution === 'FULL_TO_SELLER' ? 'system' : 'admin',
        actorId: resolvedBy,
        reason: `Dispute resolved: ${resolution}`,
      });

      const updated = await tx.dispute.update({
        where: { id: disputeId },
        data: {
          status: 'resolved',
          resolution,
          resolutionDetails: split || null,
          resolvedBy,
          resolvedAt: new Date(),
        },
      });

      await tx.order.update({
        where: { id: dispute.orderId },
        data: { status: nextState, statusChangedBy: resolvedBy },
      });

      if (resolution === 'FULL_TO_SELLER') {
        // Admin ruled for the seller: settle immediately. Idempotent via the
        // `settlement_<orderId>` ledger key — a later OTP verify is a no-op.
        await releaseEscrowAndSettle(tx, dispute.order);
      } else if (resolution === 'FULL_REFUND') {
        await openRefundForOrder(tx, dispute, resolvedBy, null);
      } else {
        await openRefundForOrder(tx, dispute, resolvedBy, split.buyerAmount);
      }

      return updated;
    });
  } finally {
    if (!lock.skipped) await releaseLock(`dispute:${disputeId}`);
  }
}

// Validate a PARTIAL split: no floats, no leftover money, no over-draw.
// The split must use up the escrow exactly (buyer part + seller part).
function validateDisputeSplit(escrowAvailable, buyerAmount, sellerAmount) {
  const total = BigInt(escrowAvailable);
  if (buyerAmount === undefined || buyerAmount === null || sellerAmount === undefined || sellerAmount === null) {
    const err = httpError(400, 'PARTIAL_SPLIT_AMOUNTS_REQUIRED');
    throw err;
  }
  const buyer = BigInt(buyerAmount);
  const seller = BigInt(sellerAmount);
  if (buyer <= 0n || seller <= 0n) throw httpError(400, 'INVALID_SPLIT_AMOUNTS');
  if (buyer > total || seller > total) throw httpError(400, 'SPLIT_EXCEEDS_ESCROW');
  if (buyer + seller !== total) throw httpError(400, 'SPLIT_MUST_COVER_ESCROW');
  return { buyerAmount: buyer.toString(), sellerAmount: seller.toString() };
}

// Record the refund obligation a resolution creates so the admin money
// movement (processRefund) can act on it afterwards.
async function openRefundForOrder(tx, dispute, resolvedBy, buyerAmount) {
  const existing = await tx.refund.findFirst({
    where: { orderId: dispute.orderId, status: { in: ['pending', 'processing'] } },
  });
  if (existing) return existing;

  const payment = await tx.payment.findFirst({
    where: { orderId: dispute.orderId, status: { in: ['completed', 'initiated', 'pending'] } },
    orderBy: { createdAt: 'desc' },
  });
  if (!payment) return null;

  const isPartial = buyerAmount !== null && buyerAmount !== undefined;
  return tx.refund.create({
    data: {
      orderId: dispute.orderId,
      paymentId: payment.id,
      amount: isPartial ? BigInt(buyerAmount) : dispute.order.totalAmount,
      mode: isPartial ? 'partial' : 'full',
      reason: `Dispute resolved: ${dispute.resolution}`,
      status: 'pending',
      correlationId: `refund_${dispute.order.orderNumber}_${Date.now().toString(36)}`,
      requestedBy: dispute.filedBy || resolvedBy,
    },
  });
}

function isDisputableState(status) {
  return [
    ORDER_STATES.IN_ESCROW,
    ORDER_STATES.READY_TO_DISPATCH,
    ORDER_STATES.DISPATCHED,
    ORDER_STATES.IN_TRANSIT,
    ORDER_STATES.OUT_FOR_DELIVERY,
    ORDER_STATES.DELIVERED,
    ORDER_STATES.INSPECTION_PERIOD,
    ORDER_STATES.OTP_PENDING,
    ORDER_STATES.COMPLETED,
  ].includes(status);
}

function httpError(status, message) {
  const err = new Error(message);
  err.status = status;
  return err;
}

module.exports = {
  DISPUTE_REASONS,
  BUYER_REASONS,
  SELLER_REASONS,
  fileDispute,
  resolveDispute,
  validateDisputeSplit,
};
