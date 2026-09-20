const { getPrisma } = require('../../config/database');
const { OrderStateMachine, ORDER_STATES } = require('./order-state-machine');
const { updateWalletBalance, settleEscrowToSeller } = require('../wallet/ledger-service');
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
  const random = Math.floor(1000 + Math.random() * 9000);
  return `SV${y}${m}${d}${random}`;
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
      include: { seller: true },
    });

    if (!product) throw new Error('PRODUCT_NOT_FOUND');
    if (product.status !== 'ACTIVE') throw new Error('PRODUCT_NOT_AVAILABLE');
    if (product.stock < quantity) throw new Error('INSUFFICIENT_STOCK');

    const address = await tx.address.findUnique({
      where: { id: addressId },
    });

    if (!address || address.userId !== buyerId) throw new Error('INVALID_ADDRESS');

    // Server-authoritative calculation
    const subtotal = Number(product.price) * quantity;

    const order = await tx.order.create({
      data: {
        id: generateOrderNumber(), // Using as ID for simplicity if mapped to String @id
        buyerId,
        sellerId: product.sellerId,
        status: ORDER_STATES.DRAFT,
        subtotal,
        total: subtotal, // Initial total; will be updated with shipping/fees
        currency: product.currency,
        shippingAddress: {
          fullName: address.fullName,
          phone: address.phone,
          line1: address.addressLine1,
          city: address.city,
        },
        items: {
          create: {
            productId: product.id,
            sellerId: product.sellerId,
            titleSnapshot: product.title,
            priceSnapshot: product.price,
            quantity,
          },
        },
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

    const shippingFee = order.shippingCost || 0;
    const subtotal = Number(order.subtotal);
    
    // V3 Rule: Platform commission is calculated server-side
    const { commission, totalAmount } = computeSellerParity(subtotal, shippingFee);

    const updated = await tx.order.update({
      where: { id: orderId },
      data: {
        status: ORDER_STATES.PENDING_PAYMENT,
        shippingCost: shippingFee,
        platformFee: commission,
        total: totalAmount,
        escrowAmount: totalAmount, // Full amount held in escrow
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
    if (order.status !== ORDER_STATES.PENDING_PAYMENT) {
      throw new Error(`INVALID_STATE: ${order.status}`);
    }

    const payment = await tx.payment.create({
      data: {
        orderId,
        provider,
        amount: order.total,
        currency: order.currency,
        status: 'pending',
        idempotencyKey: `pay_${orderId}_${Date.now()}`,
      },
    });

    await tx.order.update({
      where: { id: orderId },
      data: { status: ORDER_STATES.PAYMENT_PROCESSING },
    });

    return payment;
  });
}

/**
 * V3 Webhook Handler with Ledger Writes
 * Logic: Payment success -> Ledger Entry -> Order state: ESCROW_HELD
 */
async function verifyPayment({ paymentId, providerPaymentId }) {
  const prisma = getPrisma();
  
  return prisma.$transaction(async (tx) => {
    const payment = await tx.payment.findUnique({
      where: { id: paymentId },
      include: { order: true },
    });

    if (!payment || payment.status !== 'pending') {
      throw new Error('PAYMENT_NOT_FOUND_OR_PROCESSED');
    }

    // 1. Update Payment status
    const updatedPayment = await tx.payment.update({
      where: { id: paymentId },
      data: { status: 'completed', providerTransId: providerPaymentId, confirmedAt: new Date() },
    });

    // 2. Move Order to ESCROW_HELD
    const updatedOrder = await tx.order.update({
      where: { id: payment.orderId },
      data: { status: ORDER_STATES.ESCROW_HELD },
    });

    // 3. Financial Truth: Create Ledger Entry for the Escrow Pool
    // We assume an internal account 'ESCROW_POOL' exists
    const escrowAccount = await tx.ledgerAccount.findFirst({
      where: { accountName: 'ESCROW_POOL' },
    });

    if (escrowAccount) {
      await tx.ledgerEntry.create({
        data: {
          accountId: escrowAccount.id,
          transactionId: payment.id,
          direction: 'CREDIT',
          amount: payment.amount,
          referenceType: 'ORDER_PAYMENT',
          referenceId: payment.orderId,
        },
      });
    }

    return { payment: updatedPayment, order: updatedOrder };
  });
}

async function completeOrder({ orderId, actorId, method }) {
  const prisma = getPrisma();
  
  return prisma.$transaction(async (tx) => {
    const order = await tx.order.findUnique({ where: { id: orderId } });
    if (!order) throw new Error('ORDER_NOT_FOUND');

    if (![ORDER_STATES.DELIVERY_CONFIRMED, ORDER_STATES.OTP_PENDING].includes(order.status)) {
      throw new Error('INVALID_STATE_FOR_COMPLETION');
    }

    // 1. Update Order to COMPLETED
    const updatedOrder = await tx.order.update({
      where: { id: orderId },
      data: { status: ORDER_STATES.COMPLETED, updatedAt: new Date() },
    });

    // 2. Ledger Settlement: Escrow Pool -> Seller Wallet
    const sellerEntitlement = Number(order.total) - Number(order.platformFee);
    
    // Use the new ledger-service for atomic update
    await settleEscrowToSeller({
      orderId: order.id,
      sellerId: order.sellerId,
      amount: sellerEntitlement,
      idempotencyKey: `settle_${order.id}`,
    });

    return updatedOrder;
  });
}

module.exports = {
  DEFAULT_TIMERS,
  createOrder,
  approveShippingQuote,
  initiatePayment,
  verifyPayment,
  completeOrder,
};
