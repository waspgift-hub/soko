const { getStore } = require('../../config/database');
const { acquireLock, releaseLock } = require('../../config/redis');
const { OrderStateMachine, ORDER_STATES } = require('./order-state-machine');
const { computeSellerParity } = require('../../utils/commission-parity');
const { syncLegacyOrderStatus } = require('../legacy-compat/presentation-mirror');
const { refundOnCancel, isRefundableEscrowState } = require('../refunds/refund-service');
const { submitQuote, approveQuote } = require('../shipping/shipping-quote-service');
const { fileDispute } = require('../disputes/dispute-service');
const { releaseEscrowAndSettle } = require('../escrow/escrow-release');

// Default timers (configurable)
const DEFAULT_TIMERS = {
  SHIPPING_QUOTE_HOURS: 24,
  BUYER_PAYMENT_HOURS: 24,
  SELLER_DISPATCH_HOURS: 48,
  INSPECTION_MINUTES: 30,
  INSPECTION_MAX_HOURS: 24,
  AUTO_RELEASE_DAYS: 14,
};

function generateOrderNumber() {
  const date = new Date();
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, '0');
  const d = String(date.getDate()).padStart(2, '0');
  const random = Math.floor(1000 + Math.random() * 9000);
  return `SV${y}${m}${d}${random}`;
}

function httpError(status, message) {
  const err = new Error(message);
  err.status = status;
  return err;
}

async function audit(tx, data) {
  try {
    await tx.auditLog.create({
      data: {
        actorId: data.actorId,
        actorType: data.actorType || 'system',
        action: data.action,
        entityType: data.entityType,
        entityId: data.entityId,
        oldState: data.oldState,
        newState: data.newState,
        requestId: data.requestId,
      },
    });
  } catch (e) {
    console.error('[ORDER][AUDIT]', e.message);
  }
}

/**
 * Server-authoritative order creation. Totals come from the DB product row,
 * never the client payload; the order starts in PENDING_SHIPPING_FEE so the
 * seller quotes a price before any money moves.
 */
async function createOrder({ buyerId, productId, quantity = 1, addressId }) {
  const store = getStore();

  return store.$transaction(async (tx) => {
    const product = await tx.product.findUnique({ where: { id: productId } });
    if (!product) throw httpError(404, 'PRODUCT_NOT_FOUND');
    if (product.status !== 'published' || product.deletedAt) {
      throw httpError(409, 'PRODUCT_NOT_AVAILABLE');
    }
    if (product.stock < quantity) throw httpError(409, 'INSUFFICIENT_STOCK');

    // V1 createOrder compared address.userId too; v3 persists a snapshot so a
    // later address edit can never rewrite what a buyer agreed to.
    const address = await tx.address.findUnique({ where: { id: addressId } });
    if (!address || address.userId !== buyerId) throw httpError(400, 'INVALID_ADDRESS');

    const { commission, totalAmount } = computeSellerParity(product.price, 0n);

    const order = await tx.order.create({
      data: {
        orderNumber: generateOrderNumber(),
        buyerId,
        sellerId: product.sellerId,
        status: ORDER_STATES.PENDING_SHIPPING_FEE,
        productSnapshot: {
          productId: product.id,
          title: product.title,
          slug: product.slug,
          image: product.snapshot && product.snapshot.media ? (product.snapshot.media[0] || null) : null,
          quantity,
          unitPrice: Number(product.price),
        },
        shippingAddressSnapshot: {
          fullName: address.fullName || null,
          phone: address.phone || null,
          addressLine1: address.addressLine1 || null,
          addressLine2: address.addressLine2 || null,
          city: address.city || null,
          region: address.region || null,
          country: address.country || 'TZ',
        },
        shippingQuoteSnapshot: { amount: 0, source: 'v1_create_order' },
        productPrice: product.price,
        shippingFee: 0n,
        platformCommission: commission,
        totalAmount,
        currency: product.currency,
        paidAt: null,
        placedAt: new Date(),
      },
    });

    await tx.orderItem.create({
      data: {
        orderId: order.id,
        productId: product.id,
        quantity,
        unitPrice: product.price,
        totalPrice: product.price * BigInt(quantity),
        snapshot: {
          title: product.title,
          slug: product.slug,
          condition: product.condition || 'new',
        },
      },
    });

    await audit(tx, {
      actorId: buyerId,
      actorType: 'user',
      action: 'ORDER_CREATED',
      entityType: 'order',
      entityId: order.id,
      oldState: null,
      newState: { status: ORDER_STATES.PENDING_SHIPPING_FEE },
    });

    return tx.order.findUnique({ where: { id: order.id } });
  });
}

/**
 * Buyer approves the seller's shipping quote, locking the server-computed
 * totals (shipping + platform commission) and moving the order to
 * AWAITING_ESCROW_PAYMENT so the buyer can fund the escrow. The finance math
 * and state transitions live in shipping-quote-service; the buyer route only
 * overrides the recorded actor.
 */
async function approveShippingQuote({ orderId, approvedBy }) {
  return approveQuote({ orderId, approvedBy, actor: 'buyer' });
}

/**
 * Seller submits a shipping quote. Single implementation lives in
 * shipping-quote-service (validation + SHIPPING_FEE_* transitions); this is
 * the v1 orders alias so the controller keeps one call path.
 */
async function submitShippingQuote({ orderId, sellerId, amount, estimatedDays, notes }) {
  return submitQuote({ orderId, sellerId, amount, estimatedDays, notes });
}

/**
 * Seller dispatches the order: escrow-held -> SELLER_ACCEPTED ->
 * READY_TO_DISPATCH -> DISPATCHED with courier + tracking evidence. Seller
 * self-delivery stays at DISPATCHED; the logistics chain only advances when
 * the courier flow (or markDelivered) moves it.
 */
async function markDispatched({ orderId, sellerId, courierName, trackingNumber }) {
  const store = getStore();
  const lock = await acquireLock(`dispatch:${orderId}`, 60);

  try {
    return await store.$transaction(async (tx) => {
      const order = await tx.order.findUnique({ where: { id: orderId } });
      if (!order) throw httpError(404, 'ORDER_NOT_FOUND');
      if (order.sellerId !== sellerId) throw httpError(403, 'FORBIDDEN');

      if (![
        ORDER_STATES.ESCROW_HELD,
        ORDER_STATES.IN_ESCROW,
        ORDER_STATES.SELLER_ACCEPTED,
        ORDER_STATES.READY_TO_DISPATCH,
        ORDER_STATES.DISPATCH_READY,
      ].includes(order.status)) {
        throw httpError(409, `INVALID_DISPATCH_STATE:${order.status}`);
      }

      const machine = new OrderStateMachine(order.status);
      const visited = new Set([order.status]);
      const chain = [
        ORDER_STATES.SELLER_ACCEPTED,
        ORDER_STATES.READY_TO_DISPATCH,
        ORDER_STATES.DISPATCHED,
      ];
      for (const next of chain) {
        if (!visited.has(next) && machine.canTransition(next)) {
          machine.transition(next, { actor: 'seller', actorId: sellerId, reason: 'Seller dispatch' });
          visited.add(next);
        }
      }
      if (!visited.has(ORDER_STATES.DISPATCHED)) {
        throw httpError(409, `INVALID_DISPATCH_STATE:${order.status}`);
      }

      const updated = await tx.order.update({
        where: { id: orderId },
        data: {
          status: ORDER_STATES.DISPATCHED,
          courierName: courierName || null,
          trackingNumber: trackingNumber || null,
          dispatchedAt: new Date(),
          statusChangedBy: sellerId,
        },
      });

      await audit(tx, {
        actorId: sellerId,
        actorType: 'user',
        action: 'ORDER_DISPATCHED',
        entityType: 'order',
        entityId: orderId,
        oldState: { status: order.status },
        newState: { status: ORDER_STATES.DISPATCHED, courierName, trackingNumber },
      });

      return updated;
    });
  } finally {
    if (!lock.skipped) await releaseLock(`dispatch:${orderId}`);
  }
}

/**
 * Seller/courier/admin marks the order delivered (IN_TRANSIT -> DELIVERED).
 * Delivery is what arms the buyer's OTP/QR handover, so escrow stays held.
 */
async function markDelivered({ orderId, actorId }) {
  const store = getStore();
  const lock = await acquireLock(`deliver:${orderId}`, 60);

  try {
    return await store.$transaction(async (tx) => {
      const order = await tx.order.findUnique({ where: { id: orderId } });
      if (!order) throw httpError(404, 'ORDER_NOT_FOUND');

      if (![
        ORDER_STATES.DISPATCHED,
        ORDER_STATES.IN_TRANSIT,
        ORDER_STATES.ARRIVED,
        ORDER_STATES.DELIVERY_ATTEMPTED,
      ].includes(order.status)) {
        throw httpError(409, `INVALID_DELIVERY_STATE:${order.status}`);
      }

      const machine = new OrderStateMachine(order.status);
      const visited = new Set([order.status]);
      for (const next of [ORDER_STATES.IN_TRANSIT, ORDER_STATES.DELIVERED]) {
        if (!visited.has(next) && machine.canTransition(next)) {
          machine.transition(next, { actor: 'seller', actorId, reason: 'Seller delivered' });
          visited.add(next);
        }
      }
      if (!visited.has(ORDER_STATES.DELIVERED)) {
        throw httpError(409, `INVALID_DELIVERY_STATE:${order.status}`);
      }

      const updated = await tx.order.update({
        where: { id: orderId },
        data: { status: ORDER_STATES.DELIVERED, deliveredAt: new Date(), statusChangedBy: actorId },
      });

      await audit(tx, {
        actorId,
        actorType: 'user',
        action: 'ORDER_DELIVERED',
        entityType: 'order',
        entityId: orderId,
        oldState: { status: order.status },
        newState: { status: ORDER_STATES.DELIVERED },
      });

      return updated;
    });
  } finally {
    if (!lock.skipped) await releaseLock(`deliver:${orderId}`);
  }
}

/**
 * Finish an order whose settlement is authorized (DELIVERY_CONFIRMED, or a
 * delivered order past its inspection window): move to COMPLETED and release
 * escrow to the seller's wallet. Idempotent — a retry sees COMPLETED.
 */
async function completeOrder({ orderId, actorId = 'system', method = 'OTP_VERIFY' }) {
  const store = getStore();
  const lock = await acquireLock(`complete:${orderId}`, 60);

  try {
    const order = await store.$transaction(async (tx) => {
      const current = await tx.order.findUnique({ where: { id: orderId } });
      if (!current) throw httpError(404, 'ORDER_NOT_FOUND');

      if ([ORDER_STATES.COMPLETED, ORDER_STATES.WALLET_CREDITED].includes(current.status)) {
        return { status: 'ALREADY_COMPLETED', order: current };
      }
      if (![ORDER_STATES.DELIVERY_CONFIRMED, ORDER_STATES.DELIVERED, ORDER_STATES.INSPECTION_PERIOD].includes(current.status)) {
        throw httpError(409, `INVALID_ORDER_STATE:${current.status}`);
      }

      const started = new OrderStateMachine(current.status);
      const stateSteps = [];
      if (current.status !== ORDER_STATES.DELIVERY_CONFIRMED) {
        started.transition(ORDER_STATES.DELIVERY_CONFIRMED, { actor: 'system', actorId, reason: `Auto-release: ${method}` });
        stateSteps.push(ORDER_STATES.DELIVERY_CONFIRMED);
      }
      started.transition(ORDER_STATES.COMPLETED, { actor: 'system', actorId, reason: `Order completed: ${method}` });
      stateSteps.push(ORDER_STATES.COMPLETED);

      let updated = await tx.order.update({
        where: { id: orderId },
        data: { status: stateSteps[0], statusChangedBy: actorId },
      });

      await releaseEscrowAndSettle(tx, current);

      updated = await tx.order.update({
        where: { id: orderId },
        data: { status: ORDER_STATES.COMPLETED, completedAt: new Date(), statusChangedBy: actorId },
      });

      await audit(tx, {
        actorId,
        actorType: 'system',
        action: 'ORDER_COMPLETED',
        entityType: 'order',
        entityId: orderId,
        oldState: { status: current.status },
        newState: { status: ORDER_STATES.COMPLETED, method },
      });

      return { status: 'COMPLETED', order: updated };
    });

    await syncLegacyOrderStatus(order.order);
    return order;
  } finally {
    if (!lock.skipped) await releaseLock(`complete:${orderId}`);
  }
}

// Buyer-initiated cancel. Escrow-funded orders route through the full refund
// (money returns to the buyer); orders that never reached escrow simply move to
// CANCELLED through the state machine, no money moves.
async function cancelOrder({ orderId, actorId, reason }) {
  const store = getStore();

  const order = await store.order.findUnique({ where: { id: orderId } });
  if (!order) throw httpError(404, 'ORDER_NOT_FOUND');
  if (order.buyerId !== actorId) throw httpError(403, 'FORBIDDEN');

  if (isRefundableEscrowState(order.status)) {
    return refundOnCancel({
      orderId,
      actorId,
      role: 'buyer',
      reason: reason || 'Buyer cancelled order',
    });
  }

  return store.$transaction(async (tx) => {
    const fresh = await tx.order.findUnique({ where: { id: orderId } });
    const machine = new OrderStateMachine(fresh.status);
    if (!machine.canTransition(ORDER_STATES.CANCELLED)) {
      throw httpError(409, `INVALID_CANCEL_FROM_STATE:${fresh.status}`);
    }

    machine.transition(ORDER_STATES.CANCELLED, {
      actor: 'buyer',
      actorId,
      reason: reason || 'Buyer cancelled order',
    });

    const updated = await tx.order.update({
      where: { id: orderId },
      data: { status: ORDER_STATES.CANCELLED, statusChangedBy: actorId },
    });

    await syncLegacyOrderStatus(updated);
    return updated;
  });
}

/**
 * File a dispute (buyer or seller). Seller comparison resolves the acting
 * user to their SellerProfile because Order.sellerId is a profile id.
 */
async function disputeOrder({ orderId, filedBy, reason, description }) {
  const store = getStore();
  const profile = await store.sellerProfile.findUnique({ where: { userId: filedBy } });
  const role = profile ? 'seller' : 'buyer';

  const dispute = await fileDispute({ orderId, filedBy, reason, description, role });

  const order = await store.order.findUnique({ where: { id: orderId } });
  if (order) await syncLegacyOrderStatus(order);
  return dispute;
}

module.exports = {
  DEFAULT_TIMERS,
  createOrder,
  approveShippingQuote,
  submitShippingQuote,
  markDispatched,
  markDelivered,
  completeOrder,
  cancelOrder,
  disputeOrder,
  generateOrderNumber,
};