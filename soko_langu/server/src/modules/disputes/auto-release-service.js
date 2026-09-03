const { getPrisma } = require('../../config/database');
const { acquireLock, releaseLock } = require('../../config/redis');
const { OrderStateMachine, ORDER_STATES } = require('../orders/order-state-machine');

const REQUIRED_SAFEGUARDS = [
  'NO_ACTIVE_DISPUTE',
  'VERIFIED_DELIVERY',
  'CORRECT_RECIPIENT_ADDRESS',
  'SELLER_DISPATCH_EVIDENCE',
  'NO_CRITICAL_FRAUD_SIGNAL',
];

/**
 * Evaluate whether an order qualifies for auto-release after the inspection window.
 * Every safeguard must pass. Returns { canRelease, missingSafeguards }.
 */
async function evaluateAutoRelease(tx, orderId) {
  const order = await tx.order.findUnique({
    where: { id: orderId },
    include: { dispute: true, escrowHold: true },
  });
  if (!order) return { canRelease: false, missingSafeguards: ['ORDER_NOT_FOUND'] };

  const missing = [];

  // 1. No active dispute
  const hasActiveDispute = (order.dispute || []).some((d) => d.status === 'open');
  if (hasActiveDispute) missing.push('NO_ACTIVE_DISPUTE');

  // 2. Verified delivery
  if (!order.deliveredAt) missing.push('VERIFIED_DELIVERY');

  // 3. Correct recipient/address (best-effort: snapshot presence)
  if (!order.shippingAddressSnapshot) missing.push('CORRECT_RECIPIENT_ADDRESS');

  // 4. Seller dispatch evidence (courier/tracking present)
  if (!order.trackingNumber && !order.courierName) missing.push('SELLER_DISPATCH_EVIDENCE');

  // 5. No critical fraud signal (placeholder hooks)
  // Integration point: query seller risk / moderation flags.

  return { canRelease: missing.length === 0, missingSafeguards: missing };
}

/**
 * Attempt to auto-release escrow for a delivered order that never got an OTP
 * within the inspection window. Authorizes release only if all safeguards pass.
 * Idempotent: does nothing if already released/completed.
 */
async function autoRelease({ orderId, triggeredBy = 'system' }) {
  const prisma = getPrisma();
  const lock = await acquireLock(`autorelease:${orderId}`, 60);

  try {
    return await prisma.$transaction(async (tx) => {
      const order = await tx.order.findUnique({ where: { id: orderId } });
      if (!order) throw httpError(404, 'ORDER_NOT_FOUND');

      if (![ORDER_STATES.INSPECTION_PERIOD, ORDER_STATES.DELIVERED].includes(order.status)) {
        return { status: 'SKIPPED', reason: `STATE:${order.status}` };
      }

      const { canRelease, missingSafeguards } = await evaluateAutoRelease(tx, orderId);
      if (!canRelease) {
        return { status: 'BLOCKED', missingSafeguards };
      }

      // Everything checks out: transition to COMPLETED and release escrow.
      const machine = new OrderStateMachine(order.status);
      machine.transition(ORDER_STATES.COMPLETED, {
        actor: 'system',
        actorId: triggeredBy,
        reason: 'Auto-release after inspection window',
      });

      const completedOrder = await tx.order.update({
        where: { id: orderId },
        data: { status: ORDER_STATES.COMPLETED, completedAt: new Date() },
      });

      // Release escrow and settle (idempotent via releaseEscrowAndSettle)
      const { releaseEscrowAndSettle } = require('../handover/handover-service');
      await releaseEscrowAndSettle(tx, order);

      return { status: 'AUTO_RELEASED', order: completedOrder, missingSafeguards: [] };
    });
  } finally {
    if (!lock.skipped) await releaseLock(`autorelease:${orderId}`);
  }
}

function httpError(status, message) {
  const err = new Error(message);
  err.status = status;
  return err;
}

module.exports = {
  REQUIRED_SAFEGUARDS,
  evaluateAutoRelease,
  autoRelease,
};
