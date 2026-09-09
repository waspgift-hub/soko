const { getPrisma } = require('../../config/database');
const { acquireLock, releaseLock } = require('../../config/redis');
const { getProvider } = require('../payments/provider-factory');
const { OrderStateMachine, ORDER_STATES } = require('../orders/order-state-machine');
const { sendOneSignalNotification, notifyAdmins } = require('../legacy-compat/notify');

const REFUND_STATES = {
  PENDING: 'pending',
  PROCESSING: 'processing',
  COMPLETED: 'completed',
  FAILED: 'failed',
};

// Escrow-funded states from which a refund can be created/processed.
// READY_TO_DISPATCH, IN_TRANSIT, OUT_FOR_DELIVERY and DELIVERY_ATTEMPTED are
// intentionally excluded: the state machine routes those through DISPUTED.
const REFUNDABLE_ESCROW_STATES = [
  ORDER_STATES.IN_ESCROW,
  ORDER_STATES.DISPATCHED,
  ORDER_STATES.DELIVERED,
  ORDER_STATES.INSPECTION_PERIOD,
  ORDER_STATES.OTP_PENDING,
  ORDER_STATES.REFUND_PENDING,
];

// Extract mode + BigInt amount from a requested refund.
// Null amount, zero, or amount >= total => full refund of the total amount.
function computeRefundMode(totalAmount, requestedAmount) {
  const total = BigInt(totalAmount);
  if (requestedAmount === null || requestedAmount === undefined) {
    return { mode: 'full', amount: total };
  }
  const req = BigInt(requestedAmount);
  if (req <= 0n) {
    const err = new Error('INVALID_REFUND_AMOUNT');
    err.status = 400;
    throw err;
  }
  if (req >= total) {
    return { mode: 'full', amount: total };
  }
  return { mode: 'partial', amount: req };
}

function isRefundableEscrowState(status) {
  return REFUNDABLE_ESCROW_STATES.includes(status);
}

let _seq = 0;

function buildCorrelationId(orderNumber) {
  const ts = Date.now().toString(36);
  _seq = (_seq + 1) % 1296;
  return `refund_${orderNumber}_${ts}_${_seq.toString(36)}`;
}

// Create a Refund record for an order. Money stays put; the actual release is
// executed by processRefund (admin only). Buyer requests never move the order.
async function requestRefund({ orderId, requestedBy, role, reason, amount }) {
  const prisma = getPrisma();
  const lock = await acquireLock(`refundreq:${orderId}`, 60);

  try {
    return await prisma.$transaction(async (tx) => {
      const order = await tx.order.findUnique({ where: { id: orderId } });
      if (!order) throw httpError(404, 'ORDER_NOT_FOUND');

      if (role !== 'admin' && order.buyerId !== requestedBy) {
        throw httpError(403, 'FORBIDDEN');
      }

      if (!isRefundableEscrowState(order.status)) {
        throw httpError(409, `INELIGIBLE_REFUND_STATE:${order.status}`);
      }

      const escrowHold = await tx.escrowHold.findFirst({
        where: { orderId, status: { in: ['holding', 'disputed'] } },
      });
      if (!escrowHold) throw httpError(409, 'REFUND_ESCROW_UNAVAILABLE');

      const { mode, amount: refundAmount } = computeRefundMode(order.totalAmount, amount);
      const escrowAvailable = escrowHold.amount - escrowHold.releasedToBuyer;
      if (escrowAvailable < refundAmount) {
        throw httpError(400, 'INSUFFICIENT_ESCROW');
      }

      const existing = await tx.refund.findFirst({
        where: { orderId, status: { in: [REFUND_STATES.PENDING, REFUND_STATES.PROCESSING] } },
      });
      if (existing) return existing;

      const payment = await tx.payment.findFirst({
        where: { orderId, status: { in: ['completed', 'initiated', 'pending'] } },
        orderBy: { createdAt: 'desc' },
      });
      if (!payment) throw httpError(409, 'PAYMENT_NOT_FOUND');

      const refund = await tx.refund.create({
        data: {
          orderId,
          paymentId: payment.id,
          amount: refundAmount,
          mode,
          reason,
          correlationId: buildCorrelationId(order.orderNumber),
          requestedBy,
          status: REFUND_STATES.PENDING,
        },
      });

      return refund;
    });
  } finally {
    if (!lock.skipped) await releaseLock(`refundreq:${orderId}`);
  }
}

// Execute a refund: release escrow to the buyer per the Refund's mode, then
// disburse the money to the buyer's phone via the provider payout channel.
async function processRefund({ refundId, processedBy = 'system' }) {
  const prisma = getPrisma();
  const lock = await acquireLock(`refund:${refundId}`, 60);

  try {
    const { refund, order, escrowHold, finalState } = await prisma.$transaction(async (tx) => {
      const refundRecord = await tx.refund.findUnique({
        where: { id: refundId },
        include: { order: true },
      });
      if (!refundRecord) throw httpError(404, 'REFUND_NOT_FOUND');
      if (refundRecord.status === REFUND_STATES.COMPLETED) return { completed: true };
      if (refundRecord.status === REFUND_STATES.PROCESSING) {
        return { processing: true, refund: refundRecord, order: refundRecord.order };
      }
      if (refundRecord.status !== REFUND_STATES.PENDING && refundRecord.status !== REFUND_STATES.FAILED) {
        throw httpError(409, `INVALID_REFUND_STATE:${refundRecord.status}`);
      }

      const orderRecord = await tx.order.findUnique({ where: { id: refundRecord.orderId } });
      if (!orderRecord) throw httpError(404, 'ORDER_NOT_FOUND');
      if (!isRefundableEscrowState(orderRecord.status)) {
        throw httpError(409, `INELIGIBLE_REFUND_STATE:${orderRecord.status}`);
      }

      const escrowHoldRecord = await tx.escrowHold.findFirst({
        where: { orderId: orderRecord.id, status: { in: ['holding', 'disputed'] } },
      });
      if (!escrowHoldRecord) throw httpError(409, 'REFUND_ESCROW_UNAVAILABLE');

      const escrowAvailable = escrowHoldRecord.amount - escrowHoldRecord.releasedToBuyer;
      if (escrowAvailable < refundRecord.amount) {
        throw httpError(400, 'INSUFFICIENT_ESCROW');
      }

      const machine = new OrderStateMachine(orderRecord.status);
      if (orderRecord.status !== ORDER_STATES.REFUND_PENDING) {
        machine.transition(ORDER_STATES.REFUND_PENDING, {
          actor: 'admin',
          actorId: processedBy,
          reason: 'Refund initiated',
        });
      }
      const final = refundRecord.mode === 'full'
        ? ORDER_STATES.REFUNDED
        : ORDER_STATES.IN_ESCROW;
      machine.transition(final, { actor: 'admin', actorId: processedBy, reason: 'Refund processed' });

      if (refundRecord.mode === 'full') {
        await tx.escrowHold.update({
          where: { id: escrowHoldRecord.id },
          data: {
            status: 'released_to_buyer',
            releasedToBuyer: escrowHoldRecord.amount,
            releasedAt: new Date(),
          },
        });
      } else {
        await tx.escrowHold.update({
          where: { id: escrowHoldRecord.id },
          data: { releasedToBuyer: { increment: refundRecord.amount } },
        });
      }

      await tx.escrowTransaction.create({
        data: {
          escrowHoldId: escrowHoldRecord.id,
          type: 'REFUND_TO_BUYER',
          amount: refundRecord.amount,
          referenceId: refundId,
        },
      });

      await tx.order.update({
        where: { id: orderRecord.id },
        data: { status: final, statusChangedBy: processedBy },
      });

      const updatedRefund = await tx.refund.update({
        where: { id: refundId },
        data: {
          status: REFUND_STATES.PROCESSING,
          resolvedBy: processedBy,
          lastError: null,
          errorAt: null,
        },
      });

      return {
        refund: updatedRefund,
        order: { ...orderRecord, status: final },
        escrowHold: escrowHoldRecord,
        finalState: final,
      };
    });

    if (refund.completed) return { refund };
    if (refund.processing) {
      return { refund, processing: true };
    }

    await disburseRefund(refund);
    return { refund, order, escrowHold, finalState };
  } finally {
    if (!lock.skipped) await releaseLock(`refund:${refundId}`);
  }
}

// Push the refunded amount to the buyer's phone via the provider payout.
// Idempotent per refund: one PayoutTransaction row guards re-runs.
async function disburseRefund(refund) {
  const prisma = getPrisma();
  const existing = await prisma.payoutTransaction.findUnique({ where: { refundId: refund.id } });
  if (existing) return existing;

  const orderRecord = await prisma.order.findUnique({ where: { id: refund.orderId } });
  if (!orderRecord) return markRefundFailed(refund, 'ORDER_NOT_FOUND');

  const buyerUser = await prisma.user.findUnique({ where: { id: orderRecord.buyerId } });
  if (!buyerUser || !buyerUser.phone) {
    await markRefundFailed(refund, 'BUYER_NO_PHONE');
    await notifyRefundAdmin(`Refund ${refund.id} blocked: mnunuzi hana namba ya simu`, { refundId: refund.id, orderId: refund.orderId });
    return null;
  }

  try {
    const payment = await prisma.payment.findUnique({ where: { id: refund.paymentId } });
    const provider = getProvider((payment && payment.provider) || 'clickpesa');
    const payout = await provider.initiatePayout({
      amount: Number(refund.amount),
      orderReference: refund.correlationId,
      phoneNumber: buyerUser.phone,
    });

    await prisma.payoutTransaction.create({
      data: {
        refundId: refund.id,
        amount: refund.amount,
        providerResponse: payout,
        status: 'processing',
      },
    });

    const completed = await prisma.refund.update({
      where: { id: refund.id },
      data: { status: REFUND_STATES.COMPLETED, processedAt: new Date() },
    });

    await notifyBuyerRefund(orderRecord, completed);
    return completed;
  } catch (err) {
    await markRefundFailed(refund, err.message || 'PAYOUT_FAILED');
    await notifyRefundAdmin(`Refund ${refund.id} payout imeshindikana: ${err.message}`, { refundId: refund.id, orderId: refund.orderId });
    return null;
  }
}

async function markRefundFailed(refund, error) {
  const prisma = getPrisma();
  return prisma.refund.update({
    where: { id: refund.id },
    data: { status: REFUND_STATES.FAILED, lastError: String(error).slice(0, 500), errorAt: new Date() },
  });
}

async function notifyBuyerRefund(order, refund) {
  const prisma = getPrisma();
  const buyer = await prisma.user.findUnique({ where: { id: order.buyerId } });
  if (!buyer) return;

  const title = 'Pesa Zimerudishwa';
  const body = `TZS ${Number(refund.amount).toLocaleString()} zimerudishwa kwa ${order.orderNumber}.`;
  const data = { type: 'refund', orderId: order.id, refundId: refund.id };

  try {
    await prisma.notification.create({
      data: { userId: buyer.id, type: 'refund', title, body, data },
    });
  } catch (e) {
    console.error('[REFUND][NOTIFY-DB]', e.message);
  }
  try {
    await sendOneSignalNotification(buyer.firebaseUid, title, body, data);
  } catch (e) {
    console.error('[REFUND][NOTIFY-OS]', e.message);
  }
}

async function notifyRefundAdmin(body, data) {
  try {
    await notifyAdmins(`Refund Alert: ${body}`, data || {});
  } catch (e) {
    console.error('[REFUND][NOTIFY-ADMIN]', e.message);
  }
}

function listRefundsForOrder({ orderId, requesterId, role }) {
  const prisma = getPrisma();
  return prisma.$transaction(async (tx) => {
    const order = await tx.order.findUnique({ where: { id: orderId } });
    if (!order) throw httpError(404, 'ORDER_NOT_FOUND');
    if (role !== 'admin' && order.buyerId !== requesterId && order.sellerId !== requesterId) {
      throw httpError(403, 'FORBIDDEN');
    }
    return tx.refund.findMany({
      where: { orderId },
      orderBy: { createdAt: 'desc' },
    });
  });
}

function httpError(status, message) {
  const err = new Error(message);
  err.status = status;
  return err;
}

module.exports = {
  REFUND_STATES,
  REFUNDABLE_ESCROW_STATES,
  computeRefundMode,
  isRefundableEscrowState,
  buildCorrelationId,
  requestRefund,
  processRefund,
  markRefundFailed,
  listRefundsForOrder,
};