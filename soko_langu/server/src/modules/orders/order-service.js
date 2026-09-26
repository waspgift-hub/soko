const { getPrisma } = require('../../config/database');
const { OrderStateMachine, ORDER_STATES } = require('./order-state-machine');
const { computeSellerParity } = require('../../utils/commission-parity');
const shippingQuoteService = require('../shipping/shipping-quote-service');
const { syncLegacyOrderStatus } = require('../legacy-compat/presentation-mirror');

const DEFAULT_TIMERS = Object.freeze({
  SHIPPING_QUOTE_HOURS: 24,
  BUYER_PAYMENT_HOURS: 24,
  SELLER_DISPATCH_HOURS: 48,
  INSPECTION_MINUTES: 30,
  INSPECTION_MAX_HOURS: 24,
  AUTO_RELEASE_DAYS: 14,
  OTP_TTL_MS: 30 * 60 * 1000,
});

function generateOrderNumber() {
  const d = new Date();
  const random = Math.floor(1000 + Math.random() * 9000);
  return `SV${d.getFullYear()}${String(d.getMonth() + 1).padStart(2, '0')}${String(d.getDate()).padStart(2, '0')}${random}`;
}

function money(v) {
  const n = Number(v);
  if (!Number.isSafeInteger(n) || n < 0) throw new Error('INVALID_MONEY');
  return BigInt(n);
}

async function createOrder({ buyerId, productId, quantity = 1, addressId }) {
  const prisma = getPrisma();
  const order = await prisma.$transaction(async (tx) => {
    const product = await tx.product.findUnique({ where: { id: productId }, include: { seller: true } });
    if (!product) throw new Error('PRODUCT_NOT_FOUND');
    if (product.status !== 'ACTIVE') throw new Error('PRODUCT_NOT_AVAILABLE');
    if (!Number.isInteger(quantity) || quantity < 1 || product.stock < quantity) throw new Error('INSUFFICIENT_STOCK');
    if (product.sellerId === buyerId) throw new Error('CANNOT_BUY_OWN_PRODUCT');

    const address = await tx.address.findUnique({ where: { id: addressId } });
    if (!address || address.userId !== buyerId) throw new Error('INVALID_ADDRESS');

    const unitPrice = BigInt(product.price);
    const productTotal = unitPrice * BigInt(quantity);
    const order = await tx.order.create({
      data: {
        orderNumber: generateOrderNumber(),
        buyerId,
        sellerId: product.sellerId,
        status: ORDER_STATES.AWAITING_SELLER_SHIPPING,
        productSnapshot: {
          title: product.title,
          imageUrl: Array.isArray(product.snapshot?.images) ? product.snapshot.images[0] : (product.snapshot?.image || null),
          unitPrice: unitPrice.toString(),
          quantity,
        },
        shippingAddressSnapshot: {
          fullName: address.fullName,
          phone: address.phone,
          line1: address.addressLine1,
          line2: address.addressLine2,
          city: address.city,
          region: address.region,
          country: address.country,
          postalCode: address.postalCode,
          latitude: address.latitude?.toString?.(),
          longitude: address.longitude?.toString?.(),
        },
        productPrice: productTotal,
        shippingFee: 0n,
        platformCommission: 0n,
        totalAmount: productTotal,
        placedAt: new Date(),
        items: {
          create: {
            productId: product.id,
            quantity,
            unitPrice,
            totalPrice: productTotal,
            snapshot: { title: product.title, price: unitPrice.toString() },
          },
        },
      },
      include: { items: true, buyer: true, seller: true },
    });
    return order;
  });
  await syncLegacyOrderStatus(order);
  return order;
}

async function submitShippingQuote(args) {
  return shippingQuoteService.submitQuote(args).then(async (result) => {
    const prisma = getPrisma();
    const order = await prisma.order.findUnique({ where: { id: result.orderId } });
    if (order) await syncLegacyOrderStatus(order);
    return result;
  });
}

async function approveShippingQuote({ orderId, approvedBy }) {
  const result = await shippingQuoteService.approveQuote({ orderId, approvedBy });
  await syncLegacyOrderStatus(result);
  return result;
}

async function initiatePayment({ orderId, buyerId, provider, amount, phoneNumber }) {
  const paymentService = require('../payments/payment-service');
  return paymentService.initiatePayment({ orderId, buyerId, provider, amount, phoneNumber });
}

async function markDispatched({ orderId, sellerId, courierName, trackingNumber }) {
  const prisma = getPrisma();
  const order = await prisma.order.findUnique({ where: { id: orderId } });
  if (!order) throw new Error('ORDER_NOT_FOUND');
  if (order.sellerId !== sellerId) throw new Error('FORBIDDEN');

  const machine = new OrderStateMachine(order.status);
  machine.transition(ORDER_STATES.DISPATCHED, { actor: 'seller', reason: 'Seller dispatched order' });

  const updated = await prisma.order.update({
    where: { id: orderId },
    data: {
      status: ORDER_STATES.DISPATCHED,
      courierName,
      trackingNumber,
      dispatchedAt: new Date(),
      statusChangedBy: sellerId,
      statusChangedAt: new Date(),
    },
  });
  await syncLegacyOrderStatus(updated);
  return updated;
}

async function markDelivered({ orderId, actorId }) {
  const prisma = getPrisma();
  const order = await prisma.order.findUnique({ where: { id: orderId } });
  if (!order) throw new Error('ORDER_NOT_FOUND');

  const machine = new OrderStateMachine(order.status);
  machine.transition(ORDER_STATES.DELIVERED_PENDING_CONFIRMATION, {
    actor: 'courier',
    reason: 'Delivery recorded',
  });

  const updated = await prisma.order.update({
    where: { id: orderId },
    data: {
      status: ORDER_STATES.DELIVERED_PENDING_CONFIRMATION,
      deliveredAt: new Date(),
      statusChangedBy: actorId,
      statusChangedAt: new Date(),
    },
  });
  await syncLegacyOrderStatus(updated);
  return updated;
}

async function cancelOrder({ orderId, actorId, reason }) {
  const refundService = require('../refunds/refund-service');
  const prisma = getPrisma();
  const order = await prisma.order.findUnique({ where: { id: orderId } });
  if (!order) throw new Error('ORDER_NOT_FOUND');
  const isBuyer = order.buyerId === actorId;
  const profile = await prisma.sellerProfile.findUnique({ where: { userId: actorId } });
  const isSeller = profile?.id === order.sellerId;
  if (!isBuyer && !isSeller) throw new Error('FORBIDDEN');

  const canonicalStatus = OrderStateMachine.canonicalize(order.status);
  const escrowCancellationStates = new Set([
    ORDER_STATES.PAID_IN_ESCROW,
    ORDER_STATES.READY_FOR_DISPATCH,
  ]);
  if (escrowCancellationStates.has(canonicalStatus)) {
    if (!isBuyer) throw new Error('FORBIDDEN');
    return refundService.refundOnCancel({ orderId, actorId, role: 'buyer', reason });
  }

  const machine = new OrderStateMachine(order.status);
  machine.transition(ORDER_STATES.CANCELLED, { actor: isBuyer ? 'buyer' : 'seller', reason });
  const updated = await prisma.order.update({
    where: { id: orderId },
    data: { status: ORDER_STATES.CANCELLED, cancelledAt: new Date(), statusChangedBy: actorId, statusChangedAt: new Date() },
  });
  await syncLegacyOrderStatus(updated);
  return updated;
}

async function disputeOrder({ orderId, filedBy, reason, description }) {
  const prisma = getPrisma();
  const order = await prisma.order.findUnique({ where: { id: orderId } });
  if (!order) throw new Error('ORDER_NOT_FOUND');
  const profile = await prisma.sellerProfile.findUnique({ where: { userId: filedBy } });
  const isParty = order.buyerId === filedBy || profile?.id === order.sellerId;
  if (!isParty) throw new Error('FORBIDDEN');
  const machine = new OrderStateMachine(order.status);
  machine.transition(ORDER_STATES.DISPUTED, { actor: order.buyerId === filedBy ? 'buyer' : 'seller', reason });
  return prisma.$transaction(async (tx) => {
    const dispute = await tx.dispute.create({ data: { orderId, filedBy, reason, description, status: 'open' } });
    await tx.order.update({ where: { id: orderId }, data: { status: ORDER_STATES.DISPUTED, statusChangedBy: filedBy, statusChangedAt: new Date() } });
    return dispute;
  });
}

module.exports = {
  DEFAULT_TIMERS,
  createOrder,
  submitShippingQuote,
  approveShippingQuote,
  initiatePayment,
  markDispatched,
  markDelivered,
  cancelOrder,
  disputeOrder,
};
