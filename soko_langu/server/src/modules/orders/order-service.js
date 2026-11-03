const crypto = require('crypto');
const { getPrisma } = require('../../config/database');
const { OrderStateMachine, ORDER_STATES } = require('./order-state-machine');
const { releaseEscrowAndSettle } = require('../handover/handover-service');
const { submitQuote } = require('../shipping/shipping-quote-service');
const { computeSellerParity } = require('../../utils/commission-parity');
const { syncLegacyOrderStatus } = require('../legacy-compat/presentation-mirror');

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
  const random = crypto.randomBytes(4).toString('hex').toUpperCase();
  return `SV${y}${m}${d}${random}`;
}

function httpError(status, message) {
  const error = new Error(message);
  error.status = status;
  return error;
}

/**
 * Phase 2: Server-Authoritative Order Creation
 * Logic: Calculate totals based on DB product price, not client-provided amount.
 */
async function createOrder({ buyerId, productId, quantity = 1, addressId }) {
  const prisma = getPrisma();
  
  return prisma.$transaction(async (tx) => {
    const product = await tx.product.findUnique({
      where: { id: productId },
      include: {
        seller: { select: { id: true, userId: true, storeName: true, sellerStatus: true } },
        category: { select: { id: true, name: true, isActive: true } },
        media: { select: { r2Key: true, thumbnailR2Key: true, type: true }, orderBy: { sortOrder: 'asc' }, take: 4 },
      },
    });

    if (!product) throw new Error('PRODUCT_NOT_FOUND');
    if (product.status !== 'published' || product.deletedAt) throw new Error('PRODUCT_NOT_AVAILABLE');
    if (!product.category?.isActive) throw new Error('CATEGORY_INACTIVE');
    if (product.seller?.sellerStatus && product.seller.sellerStatus !== 'active') throw new Error('SELLER_NOT_ACTIVE');
    const qty = Number(quantity);
    if (!Number.isInteger(qty) || qty < 1 || qty > 1000) throw new Error('INVALID_QUANTITY');
    if (product.stock < qty) throw new Error('INSUFFICIENT_STOCK');
    if (product.seller?.userId === buyerId) throw new Error('CANNOT_BUY_OWN_PRODUCT');

    const address = await tx.address.findUnique({
      where: { id: addressId },
    });

    if (!address || address.userId !== buyerId) throw new Error('INVALID_ADDRESS');

    // Server-authoritative calculation
    const order = await tx.order.create({
      data: {
        orderNumber: generateOrderNumber(),
        buyerId,
        sellerId: product.sellerId,
        status: ORDER_STATES.PENDING_SHIPPING_FEE,
        productSnapshot: {
          productId: product.id,
          title: product.title,
          unitPrice: String(product.price),
          quantity: qty,
          currency: product.currency,
          condition: product.condition,
          media: product.media.map((m) => ({ r2Key: m.r2Key, thumbnailR2Key: m.thumbnailR2Key, type: m.type })),
        },
        shippingAddressSnapshot: {
          fullName: address.fullName || '',
          phone: address.phone || '',
          addressLine1: address.addressLine1,
          addressLine2: address.addressLine2 || '',
          city: address.city || '',
          region: address.region || '',
          country: address.country || 'TZ',
        },
        productPrice: BigInt(product.price) * BigInt(qty),
        shippingFee: 0n,
        platformCommission: 0n,
        totalAmount: BigInt(product.price) * BigInt(qty),
        currency: product.currency,
        placedAt: new Date(),
        statusChangedBy: buyerId,
      },
    });

    // V3 Transition: DRAFT -> PENDING_PAYMENT (if no shipping quote needed) 
    // or keep as DRAFT until shipping is sorted.
    return order;
  });
}

/**
 * Server-Authoritative Total Calculation
 * Logic: Final amount = subtotal + shipping + platformFee - discount
 */
async function approveShippingQuote({ orderId, approvedBy, actorType = 'admin' }) {
  const prisma = getPrisma();
  
  return prisma.$transaction(async (tx) => {
    const order = await tx.order.findUnique({ where: { id: orderId } });
    if (!order) throw new Error('ORDER_NOT_FOUND');

    // V3 Guard: Enforce State Transition
    const osm = new OrderStateMachine(order.status);
    if (!osm.canTransition(ORDER_STATES.AWAITING_ESCROW_PAYMENT)) {
      throw new Error(`INVALID_STATE_TRANSITION: Cannot approve quote for order in state ${order.status}`);
    }

    const shippingFee = order.shippingFee || 0n;
    
    // V3 Rule: Platform commission is calculated server-side
    const { commission, totalAmount } = computeSellerParity(order.productPrice, shippingFee);

    const updated = await tx.order.update({
      where: { id: orderId },
      data: {
        status: ORDER_STATES.AWAITING_ESCROW_PAYMENT,
        shippingFee: BigInt(shippingFee),
        platformCommission: BigInt(commission),
        totalAmount: BigInt(totalAmount),
      },
    });

    return updated;
  });
}

async function initiatePayment({ orderId, buyerId, provider }) {
  const prisma = getPrisma();
  
  return prisma.$transaction(async (tx) => {
    const order = await tx.order.findUnique({ where: { id: orderId } });
    if (!order) throw new Error('ORDER_NOT_FOUND');
    if (order.buyerId !== buyerId) throw new Error('FORBIDDEN');

    // V3 Guard: Enforce State Transition
    const osm = new OrderStateMachine(order.status);
    if (!osm.canTransition(ORDER_STATES.PAYMENT_PROCESSING)) {
      throw new Error(`INVALID_STATE_TRANSITION: Cannot pay for order in state ${order.status}`);
    }

    const payment = await tx.payment.create({
      data: {
        orderId,
        provider,
        amount: order.totalAmount, // Strictly use server-calculated total
        currency: order.currency,
        status: 'pending',
        idempotencyKey: `pay_${orderId}`,
      },
    });

    await tx.order.update({
      where: { id: orderId },
      data: { status: ORDER_STATES.PAYMENT_PROCESSING, statusChangedBy: buyerId },
    });

    return payment;
  });
}

/**
 * V3 Webhook Handler with Ledger Writes
 * Logic: Payment success -> Ledger Entry -> Order state: ESCROW_HELD
 */
async function verifyPayment({ paymentId, providerPaymentId, orderReference }) {
  const { confirmCollection } = require('../payments/payment-service');
  return confirmCollection({
    paymentId,
    providerPaymentId,
    orderReference,
    force: false,
  });
}

async function completeOrder({ orderId, actorId = 'system', method = 'AUTO_RELEASE' }) {
  const prisma = getPrisma();
  return prisma.$transaction(async (tx) => {
    const order = await tx.order.findUnique({ where: { id: orderId } });
    if (!order) throw new Error('ORDER_NOT_FOUND');

    if ([ORDER_STATES.COMPLETED, ORDER_STATES.WALLET_CREDITED, ORDER_STATES.PAYOUT_PENDING, ORDER_STATES.PAYOUT_COMPLETE].includes(order.status)) {
      return order;
    }

    const eligible = method === 'AUTO_RELEASE'
      ? [ORDER_STATES.DELIVERED, ORDER_STATES.INSPECTION_PERIOD, ORDER_STATES.OTP_PENDING, ORDER_STATES.DELIVERY_CONFIRMED]
      : [ORDER_STATES.OTP_PENDING, ORDER_STATES.INSPECTION_PERIOD, ORDER_STATES.DELIVERY_CONFIRMED];

    if (!eligible.includes(order.status)) throw new Error('INVALID_STATE_FOR_COMPLETION');

    if (method === 'AUTO_RELEASE') {
      const { evaluateAutoRelease } = require('../disputes/auto-release-service');
      const guard = await evaluateAutoRelease(tx, orderId);
      if (!guard.canRelease) {
        return {
          status: 'BLOCKED',
          missingSafeguards: guard.missingSafeguards,
          order,
        };
      }
    }

    const updated = await tx.order.update({
      where: { id: orderId },
      data: {
        status: ORDER_STATES.COMPLETED,
        completedAt: new Date(),
        statusChangedBy: actorId,
      },
    });

    await releaseEscrowAndSettle(tx, order);
    await syncLegacyOrderStatus({ ...order, ...updated });
    return updated;
  });
}

async function submitShippingQuote(args) {
  return submitQuote(args);
}

async function markDispatched({ orderId, actorId, sellerId, shippingMethod, courierName, trackingNumber, estimatedDelivery }) {
  actorId = sellerId || actorId;
  const prisma = getPrisma();
  return prisma.$transaction(async (tx) => {
    const order = await tx.order.findUnique({ where: { id: orderId } });
    if (!order) throw httpError(404, 'ORDER_NOT_FOUND');
    if (order.sellerId !== actorId) throw httpError(403, 'FORBIDDEN');

    const machine = new OrderStateMachine(order.status);
    machine.transition(ORDER_STATES.DISPATCHED, {
      actor: 'seller',
      actorId,
      reason: 'Seller dispatched order',
    });

    return tx.order.update({
      where: { id: orderId },
      data: {
        status: ORDER_STATES.DISPATCHED,
        shippingMethod: shippingMethod || null,
        courierName: courierName || null,
        trackingNumber: trackingNumber || null,
        estimatedDelivery: estimatedDelivery ? new Date(estimatedDelivery) : null,
        dispatchedAt: new Date(),
        statusChangedBy: actorId,
      },
    });
  });
}

async function markDelivered({ orderId, actorId, role = 'seller' }) {
  const prisma = getPrisma();
  return prisma.$transaction(async (tx) => {
    const order = await tx.order.findUnique({ where: { id: orderId } });
    if (!order) throw httpError(404, 'ORDER_NOT_FOUND');
    const isSeller = role === 'seller' && order.sellerId === actorId;
    const isPrivileged = role === 'admin' || role === 'courier';
    if (!isSeller && !isPrivileged) throw httpError(403, 'FORBIDDEN');

    const actor = role === 'courier' ? 'courier' : role === 'admin' ? 'admin' : 'seller';
    const machine = new OrderStateMachine(order.status);
    machine.transition(ORDER_STATES.INSPECTION_PERIOD, {
      actor,
      actorId,
      reason: 'Delivery marked delivered',
    });

    return tx.order.update({
      where: { id: orderId },
      data: {
        status: ORDER_STATES.INSPECTION_PERIOD,
        deliveredAt: new Date(),
        statusChangedBy: actorId,
      },
    });
  });
}

async function cancelOrder({ orderId, actorId, role = 'buyer', reason }) {
  const { refundOnCancel } = require('../refunds/refund-service');
  return refundOnCancel({ orderId, actorId, role, reason });
}

async function disputeOrder({ orderId, filedBy, role, reason, description }) {
  const { fileDispute } = require('../disputes/dispute-service');
  return fileDispute({ orderId, filedBy, role, reason, description });
}

module.exports = {
  DEFAULT_TIMERS: { ...DEFAULT_TIMERS, OTP_TTL_MS: 30 * 60 * 1000 },
  createOrder,
  approveShippingQuote,
  initiatePayment,
  verifyPayment,
  completeOrder,
  submitShippingQuote,
  markDispatched,
  markDelivered,
  cancelOrder,
  disputeOrder,
};
