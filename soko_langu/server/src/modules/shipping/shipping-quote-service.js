const { getPrisma } = require('../../config/database');
const { acquireLock, releaseLock } = require('../../config/redis');
const { validateShippingQuote } = require('./shipping-validation');
const { OrderStateMachine, ORDER_STATES } = require('../orders/order-state-machine');

// Seller submits a shipping quote for an order.
// Runs platform validation to decide NORMAL / REVIEW_REQUIRED / BLOCKED.
async function submitQuote({ orderId, sellerId, amount, estimatedDays, notes, shippingAddress, sellerRegion }) {
  const prisma = getPrisma();
  const lock = await acquireLock(`shipping:${orderId}`, 60);

  try {
    return await prisma.$transaction(async (tx) => {
      const order = await tx.order.findUnique({ where: { id: orderId }, include: { seller: true } });
      if (!order) throw httpError(404, 'ORDER_NOT_FOUND');
      if (order.sellerId !== sellerId) throw httpError(403, 'FORBIDDEN');
      if (order.status !== ORDER_STATES.PENDING_SHIPPING_FEE) {
        throw httpError(409, `INVALID_ORDER_STATE:${order.status}`);
      }

      const addr = shippingAddress || order.shippingAddressSnapshot || {};
      const region = sellerRegion || order.seller?.region || null;

      const validation = validateShippingQuote({
        amount,
        shippingAddress: addr,
        sellerRegion: region,
        sellerRiskScore: Number(order.seller?.reliabilityScore || 0) * 100,
      });

      const quoteStatus = validation.verdict === 'BLOCKED' ? 'blocked'
        : validation.verdict === 'REVIEW_REQUIRED' ? 'review_required'
        : 'submitted';

      // If in review, the order moves to SHIPPING_FEE_REVIEW so admin must act.
      const nextState = quoteStatus === 'review_required'
        ? ORDER_STATES.SHIPPING_FEE_REVIEW
        : quoteStatus === 'blocked'
          ? ORDER_STATES.PENDING_SHIPPING_FEE // stays put; seller must revise
          : ORDER_STATES.SHIPPING_FEE_SUBMITTED;

      const machine = new OrderStateMachine(order.status);
      machine.transition(nextState, {
        actor: 'seller',
        actorId: sellerId,
        reason: `Quote submitted (${quoteStatus})`,
      });

      const quote = await tx.shippingQuote.create({
        data: {
          orderId,
          sellerId,
          amount,
          estimatedDays,
          notes,
          status: quoteStatus,
        },
      });

      await tx.order.update({
        where: { id: orderId },
        data: {
          status: nextState,
          shippingFee: amount,
          shippingQuoteSnapshot: {
            id: quote.id,
            amount: amount.toString(),
            estimatedDays,
            verdict: validation.verdict,
          },
          statusChangedBy: sellerId,
        },
      });

      return { orderId, quote, validation };
    });
  } finally {
    if (!lock.skipped) await releaseLock(`shipping:${orderId}`);
  }
}

// Admin approves a validated/queued quote, moving order toward payment.
async function approveQuote({ orderId, approvedBy }) {
  const prisma = getPrisma();
  const lock = await acquireLock(`shipping:${orderId}`, 60);

  try {
    return await prisma.$transaction(async (tx) => {
      const order = await tx.order.findUnique({ where: { id: orderId } });
      if (!order) throw httpError(404, 'ORDER_NOT_FOUND');

      if (![ORDER_STATES.SHIPPING_FEE_SUBMITTED, ORDER_STATES.SHIPPING_FEE_REVIEW].includes(order.status)) {
        throw httpError(409, `INVALID_ORDER_STATE:${order.status}`);
      }

      const machine = new OrderStateMachine(order.status);
      machine.transition(ORDER_STATES.AWAITING_ESCROW_PAYMENT, {
        actor: 'admin',
        actorId: approvedBy,
        reason: 'Quote approved',
      });

      const platformCommission = calcCommission(order.productPrice);

      const updatedOrder = await tx.order.update({
        where: { id: orderId },
        data: {
          status: ORDER_STATES.AWAITING_ESCROW_PAYMENT,
          platformCommission,
          totalAmount: order.productPrice + order.shippingFee,
          statusChangedBy: approvedBy,
        },
      });

      await tx.shippingQuote.updateMany({
        where: { orderId, status: { in: ['submitted', 'review_required'] } },
        data: { status: 'approved', reviewedBy: approvedBy, reviewedAt: new Date() },
      });

      return updatedOrder;
    });
  } finally {
    if (!lock.skipped) await releaseLock(`shipping:${orderId}`);
  }
}

// Admin blocks a quote, returning order to PENDING_SHIPPING_FEE for revision.
async function blockQuote({ orderId, blockedBy, reason }) {
  const prisma = getPrisma();
  const lock = await acquireLock(`shipping:${orderId}`, 60);

  try {
    return await prisma.$transaction(async (tx) => {
      const order = await tx.order.findUnique({ where: { id: orderId } });
      if (!order) throw httpError(404, 'ORDER_NOT_FOUND');
      if (order.status !== ORDER_STATES.SHIPPING_FEE_REVIEW) {
        throw httpError(409, `INVALID_ORDER_STATE:${order.status}`);
      }

      const machine = new OrderStateMachine(order.status);
      machine.transition(ORDER_STATES.PENDING_SHIPPING_FEE, {
        actor: 'admin',
        actorId: blockedBy,
        reason: reason || 'Quote blocked, awaiting revision',
      });

      const updatedOrder = await tx.order.update({
        where: { id: orderId },
        data: {
          status: ORDER_STATES.PENDING_SHIPPING_FEE,
          statusChangedBy: blockedBy,
        },
      });

      await tx.shippingQuote.updateMany({
        where: { orderId, status: { in: ['submitted', 'review_required'] } },
        data: { status: 'blocked', reviewedBy: blockedBy, reviewedAt: new Date() },
      });

      return updatedOrder;
    });
  } finally {
    if (!lock.skipped) await releaseLock(`shipping:${orderId}`);
  }
}

function calcCommission(productPrice) {
  const percent = require('../../config').business.platformCommissionPercent;
  return Math.round(Number(productPrice) * percent);
}

function httpError(status, message) {
  const err = new Error(message);
  err.status = status;
  return err;
}

module.exports = { submitQuote, approveQuote, blockQuote };
