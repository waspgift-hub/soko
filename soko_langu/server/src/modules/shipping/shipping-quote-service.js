const { getStore } = require('../../config/database');
const { acquireLock, releaseLock } = require('../../config/redis');
const { validateShippingQuote } = require('./shipping-validation');
const { OrderStateMachine, ORDER_STATES } = require('../orders/order-state-machine');

// Seller submits a shipping quote for an order.
// Runs platform validation to decide NORMAL / REVIEW_REQUIRED / BLOCKED.
async function submitQuote({ orderId, sellerId, amount, estimatedDays, notes, shippingAddress, sellerRegion }) {
  const store = getStore();
  const lock = await acquireLock(`shipping:${orderId}`, 60);

  try {
    return await store.$transaction(async (tx) => {
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

      // NORMAL quotes auto-approve so the buyer can pay immediately after the
      // seller quotes (matches the app's quote→pay UX); REVIEW_REQUIRED/BLOCKED
      // still need human action. The two-step chain keeps the canonical machine
      // honest: the seller hands off, then the system moves the order to
      // payment-readiness.
      const autoApproved = quoteStatus === 'submitted';

      const machine = new OrderStateMachine(order.status);
      machine.transition(ORDER_STATES.SHIPPING_FEE_SUBMITTED, {
        actor: 'seller',
        actorId: sellerId,
        reason: `Quote submitted (${quoteStatus})`,
      });
      if (autoApproved) {
        machine.transition(ORDER_STATES.AWAITING_ESCROW_PAYMENT, {
          actor: 'system',
          actorId: sellerId,
          reason: 'NORMAL quote auto-approved',
        });
      }

      const nextState = autoApproved
        ? ORDER_STATES.AWAITING_ESCROW_PAYMENT
        : quoteStatus === 'review_required'
          ? ORDER_STATES.SHIPPING_FEE_REVIEW
          : ORDER_STATES.PENDING_SHIPPING_FEE;

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

      // Lock the server-computed totals the moment a NORMAL quote lands so the
      // payment step charges price + shipping exactly (never client-inflated).
      const updatedOrder = await tx.order.update({
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
          ...(autoApproved
            ? {
                platformCommission: calcCommission(order.productPrice),
                totalAmount: BigInt(order.productPrice) + BigInt(Math.round(amount)),
              }
            : {}),
          statusChangedBy: sellerId,
        },
      });

      if (autoApproved) {
        await tx.shippingQuote.updateMany({
          where: { orderId, status: 'submitted' },
          data: { status: 'approved', reviewedBy: 'system', reviewedAt: new Date() },
        });
      }

      return { orderId, quote, validation, updatedOrder };
    });
  } finally {
    if (lock.acquired) await releaseLock(`shipping:${orderId}`, lock.token);
  }
}

// Buyer or admin approves a validated/queued quote, moving order toward payment.
// actor defaults to 'admin' for the admin route; the buyer route overrides it.
async function approveQuote({ orderId, approvedBy, actor = 'admin' }) {
  const store = getStore();
  const lock = await acquireLock(`shipping:${orderId}`, 60);

  try {
    return await store.$transaction(async (tx) => {
      const order = await tx.order.findUnique({ where: { id: orderId } });
      if (!order) throw httpError(404, 'ORDER_NOT_FOUND');

      if (![ORDER_STATES.SHIPPING_FEE_SUBMITTED, ORDER_STATES.SHIPPING_FEE_REVIEW].includes(order.status)) {
        throw httpError(409, `INVALID_ORDER_STATE:${order.status}`);
      }

      const machine = new OrderStateMachine(order.status);
      machine.transition(ORDER_STATES.AWAITING_ESCROW_PAYMENT, {
        actor,
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
    if (lock.acquired) await releaseLock(`shipping:${orderId}`, lock.token);
  }
}

// Admin blocks a quote, returning order to PENDING_SHIPPING_FEE for revision.
async function blockQuote({ orderId, blockedBy, reason }) {
  const store = getStore();
  const lock = await acquireLock(`shipping:${orderId}`, 60);

  try {
    return await store.$transaction(async (tx) => {
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
    if (lock.acquired) await releaseLock(`shipping:${orderId}`, lock.token);
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
