const { getPrisma } = require('../../config/database');
const { acquireLock, releaseLock } = require('../../config/redis');
const { validateShippingQuote } = require('./shipping-validation');
const { OrderStateMachine, ORDER_STATES } = require('../orders/order-state-machine');

const { toBigIntSafe } = require('../../utils/money');

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
      if (order.status !== ORDER_STATES.AWAITING_SELLER_SHIPPING) {
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
      const nextState = quoteStatus === 'blocked'
        ? ORDER_STATES.AWAITING_SELLER_SHIPPING
        : ORDER_STATES.AWAITING_PAYMENT;

      const machine = new OrderStateMachine(order.status);
      machine.transition(nextState, {
        actor: 'seller',
        actorId: sellerId,
        reason: `Quote submitted (${quoteStatus})`,
      });

      // The final payable goes live HERE, atomically, the moment the seller
      // sets shipping: total = product + shipping, commission computed
      // server-side on the product price. The buyer can only be charged this
      // exact figure (initiatePayment enforces it) and never before this step.
      const shippingFee = toBigIntSafe(amount);
      const platformCommission = calcCommission(order.productPrice);
      const totalAmount = toBigIntSafe(order.productPrice) + shippingFee;

      const quote = await tx.shippingQuote.create({
        data: {
          orderId,
          sellerId,
          amount: shippingFee,
          estimatedDays,
          notes,
          status: quoteStatus,
        },
      });

      await tx.order.update({
        where: { id: orderId },
        data: {
          status: nextState,
          shippingFee,
          platformCommission,
          totalAmount,
          shippingQuoteSnapshot: {
            id: quote.id,
            amount: shippingFee.toString(),
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

      if (order.status !== ORDER_STATES.AWAITING_PAYMENT) {
        throw httpError(409, `INVALID_ORDER_STATE:${order.status}`);
      }

      const machine = new OrderStateMachine(order.status);
      machine.transition(ORDER_STATES.AWAITING_PAYMENT, {
        actor: 'admin',
        actorId: approvedBy,
        reason: 'Quote approved',
      });

      const platformCommission = calcCommission(order.productPrice);

      const updatedOrder = await tx.order.update({
        where: { id: orderId },
        data: {
          status: ORDER_STATES.AWAITING_PAYMENT,
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
      if (order.status !== ORDER_STATES.AWAITING_PAYMENT) {
        throw httpError(409, `INVALID_ORDER_STATE:${order.status}`);
      }

      const machine = new OrderStateMachine(order.status);
      machine.transition(ORDER_STATES.AWAITING_SELLER_SHIPPING, {
        actor: 'admin',
        actorId: blockedBy,
        reason: reason || 'Quote blocked, awaiting revision',
      });

      const updatedOrder = await tx.order.update({
        where: { id: orderId },
        data: {
          status: ORDER_STATES.AWAITING_SELLER_SHIPPING,
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
  // PLATFORM_COMMISSION_PERCENT is a whole percent ("10" = 10%); the default is
  // 0 because Soko Vibe charges no platform fee.
  const percent = require('../../config').business.platformCommissionPercent;
  return Math.round((Number(toBigIntSafe(productPrice)) * percent) / 100);
}

function httpError(status, message) {
  const err = new Error(message);
  err.status = status;
  return err;
}

module.exports = { submitQuote, approveQuote, blockQuote };
