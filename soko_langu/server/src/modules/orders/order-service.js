const { getPrisma } = require('../../config/database');
const { acquireLock, releaseLock } = require('../../config/redis');
const { OrderStateMachine, ORDER_STATES } = require('./order-state-machine');

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

// Create a new order from a product
async function createOrder({ buyerId, productId, quantity = 1, addressId }) {
  const prisma = getPrisma();
  
  return prisma.$transaction(async (tx) => {
    // Load product with seller
    const product = await tx.product.findUnique({
      where: { id: productId },
      include: { seller: true },
    });

    if (!product) {
      throw new Error('PRODUCT_NOT_FOUND');
    }

    if (product.status !== 'published') {
      throw new Error('PRODUCT_NOT_AVAILABLE');
    }

    if (product.stock < quantity) {
      throw new Error('INSUFFICIENT_STOCK');
    }

    // Load address
    const address = await tx.address.findUnique({
      where: { id: addressId },
    });

    if (!address || address.userId !== buyerId) {
      throw new Error('INVALID_ADDRESS');
    }

    // Create immutable product snapshot
    const productSnapshot = {
      id: product.id,
      title: product.title,
      description: product.description,
      price: product.price.toString(),
      imageUrl: product.media?.[0]?.r2Key || null,
      condition: product.condition,
      snapshotAt: new Date().toISOString(),
    };

    // Create immutable address snapshot
    const addressSnapshot = {
      fullName: address.fullName,
      phone: address.phone,
      line1: address.addressLine1,
      line2: address.addressLine2,
      city: address.city,
      region: address.region,
      country: address.country,
    };

    // Create order
    const order = await tx.order.create({
      data: {
        orderNumber: generateOrderNumber(),
        buyerId,
        sellerId: product.sellerId,
        status: ORDER_STATES.DRAFT,
        productSnapshot,
        shippingAddressSnapshot: addressSnapshot,
        productPrice: product.price,
        totalAmount: product.price,  // Final amount set after shipping quote
        items: {
          create: {
            productId: product.id,
            quantity,
            unitPrice: product.price,
            totalPrice: product.price * BigInt(quantity),
            snapshot: productSnapshot,
          },
        },
      },
      include: { items: true },
    });

    // Transition to ADDRESS_REQUIRED - buyer has provided address
    const machine = new OrderStateMachine(ORDER_STATES.DRAFT);
    const transition = machine.transition(ORDER_STATES.ADDRESS_REQUIRED, {
      actor: 'buyer',
      actorId: buyerId,
      reason: 'Order created with address',
    });

    await tx.order.update({
      where: { id: order.id },
      data: {
        status: ORDER_STATES.ADDRESS_REQUIRED,
        statusChangedBy: buyerId,
      },
    });

    // Create audit log
    await createAudit(tx, {
      actorId: buyerId,
      actorType: 'user',
      action: 'ORDER_CREATED',
      entityType: 'order',
      entityId: order.id,
      newState: { status: ORDER_STATES.ADDRESS_REQUIRED },
      requestId: `order_${order.id}`,
    });

    return order;
  });
}

// Seller submits shipping quote
async function submitShippingQuote({ orderId, sellerId, amount, estimatedDays, notes }) {
  const prisma = getPrisma();
  
  return prisma.$transaction(async (tx) => {
    const order = await tx.order.findUnique({
      where: { id: orderId },
    });

    if (!order) {
      throw new Error('ORDER_NOT_FOUND');
    }

    if (order.sellerId !== sellerId) {
      throw new Error('FORBIDDEN');
    }

    if (order.status !== ORDER_STATES.PENDING_SHIPPING_FEE) {
      throw new Error(`INVALID_ORDER_STATE: ${order.status}`);
    }

    // Basic validation against baselines would happen here
    // For now, mark as normal (review only if outside thresholds)
    const quoteStatus = 'submitted';

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

    const machine = new OrderStateMachine(order.status);
    const transition = machine.transition(ORDER_STATES.SHIPPING_FEE_SUBMITTED, {
      actor: 'seller',
      actorId: sellerId,
      reason: 'Shipping quote submitted',
    });

    await tx.order.update({
      where: { id: orderId },
      data: {
        status: ORDER_STATES.SHIPPING_FEE_SUBMITTED,
        shippingFee: amount,
        shippingQuoteSnapshot: {
          id: quote.id,
          amount: amount.toString(),
          estimatedDays,
        },
        statusChangedBy: sellerId,
      },
    });

    return { orderId, quote };
  });
}

// Approve shipping quote and move to payment
async function approveShippingQuote({ orderId, approvedBy, actorType = 'admin' }) {
  const prisma = getPrisma();
  
  return prisma.$transaction(async (tx) => {
    const order = await tx.order.findUnique({
      where: { id: orderId },
    });

    if (!order) throw new Error('ORDER_NOT_FOUND');

    if (![ORDER_STATES.SHIPPING_FEE_SUBMITTED, ORDER_STATES.SHIPPING_FEE_REVIEW].includes(order.status)) {
      throw new Error(`INVALID_ORDER_STATE: ${order.status}`);
    }

    // Calculate final totals
    const shippingFee = order.shippingFee;
    const productPrice = order.productPrice;
    
    // Platform commission (3.5% of product price)
    const commission = (productPrice * 35n) / 1000n;
    const totalAmount = productPrice + shippingFee;

    const machine = new OrderStateMachine(order.status);
    machine.transition(ORDER_STATES.AWAITING_ESCROW_PAYMENT, {
      actor: actorType,
      actorId: approvedBy,
      reason: 'Shipping quote approved',
    });

    const updated = await tx.order.update({
      where: { id: orderId },
      data: {
        status: ORDER_STATES.AWAITING_ESCROW_PAYMENT,
        platformCommission: commission,
        totalAmount,
      },
    });

    return updated;
  });
}

// Mark payment as initiated
async function initiatePayment({ orderId, buyerId, provider, amount }) {
  const prisma = getPrisma();
  
  const lock = await acquireLock(`payment:${orderId}`, 30);
  
  try {
    return await prisma.$transaction(async (tx) => {
      const order = await tx.order.findUnique({
        where: { id: orderId },
      });

      if (!order) throw new Error('ORDER_NOT_FOUND');
      if (order.buyerId !== buyerId) throw new Error('FORBIDDEN');
      
      if (order.status !== ORDER_STATES.AWAITING_ESCROW_PAYMENT) {
        throw new Error(`INVALID_ORDER_STATE: ${order.status}`);
      }

      if (amount !== order.totalAmount) {
        throw new Error('AMOUNT_MISMATCH');
      }

      // Create payment record with idempotency key
      const idempotencyKey = `pay_${orderId}_${Date.now()}`;
      
      const payment = await tx.payment.create({
        data: {
          orderId,
          provider,
          amount: order.totalAmount,
          status: 'pending',
          idempotencyKey,
        },
      });

      const machine = new OrderStateMachine(order.status);
      machine.transition(ORDER_STATES.PAYMENT_PENDING, {
        actor: 'buyer',
        actorId: buyerId,
        reason: 'Payment initiated',
      });

      await tx.order.update({
        where: { id: orderId },
        data: {
          status: ORDER_STATES.PAYMENT_PENDING,
          statusChangedBy: buyerId,
        },
      });

      return payment;
    });
  } finally {
    if (!lock.skipped) {
      await releaseLock(`payment:${orderId}`);
    }
  }
}

// Verify payment webhook and move to escrow
async function verifyPayment({ paymentId, providerPaymentId, webhookBody }) {
  const prisma = getPrisma();
  
  const lock = await acquireLock(`webhook:${paymentId}`, 30);
  
  try {
    return await prisma.$transaction(async (tx) => {
      const payment = await tx.payment.findUnique({
        where: { id: paymentId },
        include: { order: true },
      });

      if (!payment) throw new Error('PAYMENT_NOT_FOUND');

      // Only process if still pending
      if (payment.status !== 'pending') {
        return { status: 'ALREADY_PROCESSED', payment };
      }

      // Update payment
      const updatedPayment = await tx.payment.update({
        where: { id: paymentId },
        data: {
          status: 'completed',
          providerPaymentId,
          webhookReceivedAt: new Date(),
          verifiedAt: new Date(),
        },
      });

      // Create escrow hold
      await tx.escrowHold.create({
        data: {
          orderId: payment.orderId,
          paymentId: payment.id,
          amount: payment.amount,
          status: 'holding',
        },
      });

      // Transition order to IN_ESCROW
      const machine = new OrderStateMachine(payment.order.status);
      machine.transition(ORDER_STATES.IN_ESCROW, {
        actor: 'system',
        reason: 'Payment verified server-side',
      });

      const updatedOrder = await tx.order.update({
        where: { id: payment.orderId },
        data: {
          status: ORDER_STATES.IN_ESCROW,
          paidAt: new Date(),
        },
      });

      // Create ledger entry for escrow
      await tx.escrowTransaction.create({
        data: {
          escrowHoldId: (await tx.escrowHold.findFirst({
            where: { orderId: payment.orderId, status: 'holding' },
          })).id,
          type: 'FUNDS_HELD',
          amount: payment.amount,
          referenceId: payment.id,
        },
      });

      return { status: 'VERIFIED', payment: updatedPayment, order: updatedOrder };
    });
  } finally {
    if (!lock.skipped) {
      await releaseLock(`webhook:${paymentId}`);
    }
  }
}

// Seller marks as dispatched
async function markDispatched({ orderId, sellerId, courierName, trackingNumber }) {
  const prisma = getPrisma();
  
  return prisma.$transaction(async (tx) => {
    const order = await tx.order.findUnique({ where: { id: orderId } });

    if (!order) throw new Error('ORDER_NOT_FOUND');
    if (order.sellerId !== sellerId) throw new Error('FORBIDDEN');
    
    if (order.status !== ORDER_STATES.READY_TO_DISPATCH) {
      throw new Error(`INVALID_ORDER_STATE: ${order.status}`);
    }

    const machine = new OrderStateMachine(order.status);
    machine.transition(ORDER_STATES.DISPATCHED, {
      actor: 'seller',
      actorId: sellerId,
      reason: 'Seller dispatched order',
    });

    return tx.order.update({
      where: { id: orderId },
      data: {
        status: ORDER_STATES.DISPATCHED,
        courierName,
        trackingNumber,
        dispatchedAt: new Date(),
        statusChangedBy: sellerId,
      },
    });
  });
}

// Mark as delivered
async function markDelivered({ orderId, actorId }) {
  const prisma = getPrisma();
  
  return prisma.$transaction(async (tx) => {
    const order = await tx.order.findUnique({ where: { id: orderId } });

    if (!order) throw new Error('ORDER_NOT_FOUND');
    
    if (![ORDER_STATES.OUT_FOR_DELIVERY, ORDER_STATES.DELIVERY_ATTEMPTED].includes(order.status)) {
      throw new Error(`INVALID_ORDER_STATE: ${order.status}`);
    }

    const machine = new OrderStateMachine(order.status);
    machine.transition(ORDER_STATES.DELIVERED, {
      actor: 'system',
      actorId,
      reason: 'Delivery confirmed',
    });

    return tx.order.update({
      where: { id: orderId },
      data: {
        status: ORDER_STATES.DELIVERED,
        deliveredAt: new Date(),
      },
    });
  });
}

// Marketplace auto-advance: DELIVERED -> INSPECTION_PERIOD
async function startInspectionPeriod({ orderId }) {
  const prisma = getPrisma();
  
  return prisma.$transaction(async (tx) => {
    const order = await tx.order.findUnique({ where: { id: orderId } });
    if (!order) throw new Error('ORDER_NOT_FOUND');
    if (order.status !== ORDER_STATES.DELIVERED) {
      throw new Error(`INVALID_ORDER_STATE: ${order.status}`);
    }

    const machine = new OrderStateMachine(order.status);
    machine.transition(ORDER_STATES.INSPECTION_PERIOD, {
      actor: 'system',
      reason: 'Inspection period started',
    });

    return tx.order.update({
      where: { id: orderId },
      data: { status: ORDER_STATES.INSPECTION_PERIOD },
    });
  });
}

// Marketplace auto-advance: INSPECTION_PERIOD -> OTP_PENDING (if not disputed)
async function moveToOtpPending({ orderId }) {
  const prisma = getPrisma();
  
  return prisma.$transaction(async (tx) => {
    const order = await tx.order.findUnique({ where: { id: orderId } });
    if (!order) throw new Error('ORDER_NOT_FOUND');
    if (order.status !== ORDER_STATES.INSPECTION_PERIOD) {
      throw new Error(`INVALID_ORDER_STATE: ${order.status}`);
    }

    const machine = new OrderStateMachine(order.status);
    machine.transition(ORDER_STATES.OTP_PENDING, {
      actor: 'system',
      reason: 'Inspection passed, awaiting OTP handover',
    });

    return tx.order.update({
      where: { id: orderId },
      data: { status: ORDER_STATES.OTP_PENDING },
    });
  });
}

// Complete order (via OTP verification or auto-release)
async function completeOrder({ orderId, actorId, method }) {
  const prisma = getPrisma();
  
  const lock = await acquireLock(`complete:${orderId}`, 30);
  
  try {
    return await prisma.$transaction(async (tx) => {
      const order = await tx.order.findUnique({ where: { id: orderId } });

      if (!order) throw new Error('ORDER_NOT_FOUND');

      if (![ORDER_STATES.OTP_PENDING, ORDER_STATES.INSPECTION_PERIOD].includes(order.status)) {
        throw new Error(`INVALID_ORDER_STATE: ${order.status}`);
      }

      const machine = new OrderStateMachine(order.status);
      machine.transition(ORDER_STATES.COMPLETED, {
        actor: actorId === order.buyerId ? 'buyer' : 'system',
        actorId,
        reason: method === 'otp' ? 'OTP verified' : 'Auto-release after inspection window',
      });

      // Create escrow release ledger entries
      const escrowHold = await tx.escrowHold.findFirst({
        where: { orderId, status: 'holding' },
      });

      if (escrowHold) {
        await tx.escrowHold.update({
          where: { id: escrowHold.id },
          data: { status: 'released', releasedAt: new Date() },
        });

        // Split escrow: buyer payment = seller entitlement + commission
        // Seller entitlement = product price + shipping - commission
        const sellerEntitlement = order.totalAmount - order.platformCommission;
        
        await tx.escrowTransaction.create({
          data: {
            escrowHoldId: escrowHold.id,
            type: 'SETTLEMENT_TO_SELLER',
            amount: sellerEntitlement,
            referenceId: order.id,
          },
        });

        await tx.escrowTransaction.create({
          data: {
            escrowHoldId: escrowHold.id,
            type: 'COMMISSION_TO_PLATFORM',
            amount: order.platformCommission,
            referenceId: order.id,
          },
        });

        // Credit seller wallet via ledger
        const wallet = await tx.wallet.findUnique({
          where: { sellerId: order.sellerId },
        });

        if (wallet) {
          const balanceAfter = wallet.availableBalance + sellerEntitlement;
          
          await tx.walletLedgerEntry.create({
            data: {
              walletId: wallet.id,
              type: 'ORDER_SETTLEMENT',
              amount: sellerEntitlement,
              balanceAfter,
              referenceType: 'order',
              referenceId: order.id,
              idempotencyKey: `settlement_${order.id}`,
              description: 'Order settlement from escrow release',
            },
          });

          await tx.wallet.update({
            where: { id: wallet.id },
            data: {
              availableBalance: balanceAfter,
              totalEarned: wallet.totalEarned + sellerEntitlement,
            },
          });
        }
      }

      const updatedOrder = await tx.order.update({
        where: { id: orderId },
        data: {
          status: ORDER_STATES.COMPLETED,
          completedAt: new Date(),
        },
      });

      return updatedOrder;
    });
  } finally {
    if (!lock.skipped) {
      await releaseLock(`complete:${orderId}`);
    }
  }
}

// Cancel order
async function cancelOrder({ orderId, actorId, reason }) {
  const prisma = getPrisma();
  
  return prisma.$transaction(async (tx) => {
    const order = await tx.order.findUnique({ where: { id: orderId } });

    if (!order) throw new Error('ORDER_NOT_FOUND');

    // Cannot cancel if funds are held and not yet refunded
    if ([ORDER_STATES.IN_ESCROW, ORDER_STATES.DISPATCHED, ORDER_STATES.IN_TRANSIT,
         ORDER_STATES.OUT_FOR_DELIVERY, ORDER_STATES.DELIVERED, ORDER_STATES.COMPLETED].includes(order.status)) {
      throw new Error('CANNOT_CANCEL_IN_CURRENT_STATE');
    }

    const machine = new OrderStateMachine(order.status);
    machine.transition(ORDER_STATES.CANCELLED, {
      actor: 'user',
      actorId,
      reason,
    });

    return tx.order.update({
      where: { id: orderId },
      data: {
        status: ORDER_STATES.CANCELLED,
        cancelledAt: new Date(),
        statusChangedBy: actorId,
      },
    });
  });
}

// Open dispute on order
async function disputeOrder({ orderId, filedBy, reason, description }) {
  const prisma = getPrisma();
  
  return prisma.$transaction(async (tx) => {
    const order = await tx.order.findUnique({ where: { id: orderId } });

    if (!order) throw new Error('ORDER_NOT_FOUND');

    if (![ORDER_STATES.IN_ESCROW, ORDER_STATES.DISPATCHED, ORDER_STATES.IN_TRANSIT,
         ORDER_STATES.OUT_FOR_DELIVERY, ORDER_STATES.DELIVERED, ORDER_STATES.INSPECTION_PERIOD,
         ORDER_STATES.OTP_PENDING, ORDER_STATES.COMPLETED].includes(order.status)) {
      throw new Error('CANNOT_DISPUTE_IN_CURRENT_STATE');
    }

    const machine = new OrderStateMachine(order.status);
    machine.transition(ORDER_STATES.DISPUTED, {
      actor: filedBy === order.buyerId ? 'buyer' : 'seller',
      actorId: filedBy,
      reason: 'Dispute filed',
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

    // Freeze escrow funds
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
      data: { status: ORDER_STATES.DISPUTED },
    });

    return dispute;
  });
}

// Audit helper
async function createAudit(tx, data) {
  try {
    await tx.auditLog.create({
      data: {
        actorId: data.actorId,
        actorType: data.actorType,
        action: data.action,
        entityType: data.entityType,
        entityId: data.entityId,
        newState: data.newState,
        requestId: data.requestId,
      },
    });
  } catch (error) {
    console.error('[AUDIT] Failed to create audit log:', error.message);
  }
}

module.exports = {
  DEFAULT_TIMERS,
  generateOrderNumber,
  createOrder,
  submitShippingQuote,
  approveShippingQuote,
  initiatePayment,
  verifyPayment,
  markDispatched,
  markDelivered,
  startInspectionPeriod,
  moveToOtpPending,
  completeOrder,
  cancelOrder,
  disputeOrder,
};
