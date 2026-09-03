const { getPrisma } = require('../../config/database');
const { acquireLock, releaseLock } = require('../../config/redis');
const { OrderStateMachine, ORDER_STATES } = require('../orders/order-state-machine');

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
 *  - FULL_TO_SELLER: release escrow to seller (order completes)
 *  - FULL_REFUND: release escrow to buyer (refund)
 *  - PARTIAL: split
 */
async function resolveDispute({ disputeId, resolvedBy, resolution, note }) {
  const prisma = getPrisma();
  const lock = await acquireLock(`dispute:${disputeId}`, 60);

  try {
    return await prisma.$transaction(async (tx) => {
      const dispute = await tx.dispute.findUnique({ where: { id: disputeId }, include: { order: true } });
      if (!dispute) throw httpError(404, 'DISPUTE_NOT_FOUND');
      if (dispute.status !== 'open') throw httpError(409, 'DISPUTE_NOT_OPEN');

      const valid = ['FULL_TO_SELLER', 'FULL_REFUND', 'PARTIAL'];
      if (!valid.includes(resolution)) throw httpError(400, 'INVALID_RESOLUTION');

      // Escrow release is delegated to the relevant service; here we mark resolution.
      const updated = await tx.dispute.update({
        where: { id: disputeId },
        data: {
          status: 'resolved',
          resolution,
          resolvedBy,
          resolvedAt: new Date(),
        },
      });

      // Move order to a terminal state per resolution outcome
      let nextState;
      if (resolution === 'FULL_TO_SELLER') nextState = ORDER_STATES.INSPECTION_PERIOD;
      else if (resolution === 'FULL_REFUND') nextState = ORDER_STATES.REFUND_PENDING;
      else nextState = ORDER_STATES.DISPUTED; // partial stays disputed for split handling

      const machine = new OrderStateMachine(dispute.order.status);
      machine.transition(nextState, {
        actor: 'admin',
        actorId: resolvedBy,
        reason: `Dispute resolved: ${resolution}`,
      });

      if (nextState !== ORDER_STATES.DISPUTED) {
        await tx.order.update({
          where: { id: dispute.orderId },
          data: { status: nextState, statusChangedBy: resolvedBy },
        });
      }

      return updated;
    });
  } finally {
    if (!lock.skipped) await releaseLock(`dispute:${disputeId}`);
  }
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
};
