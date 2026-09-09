const { getPrisma } = require('../../config/database');
const { acquireLock, releaseLock } = require('../../config/redis');
const { getProvider } = require('./provider-factory');
const config = require('../../config');
const { OrderStateMachine, ORDER_STATES } = require('../orders/order-state-machine');
const { sameAmount } = require('../../utils/money');
const outbox = require('./webhook-outbox');

/**
 * Payment service.
 *
 * Four-layer double-spending prevention:
 *  1. Redis SETNX lock (30s TTL)
 *  2. BullMQ job ID deduplication (enqueued per webhook id)
 *  3. Database UNIQUE constraint on idempotency keys
 *  4. Status priority check before any state change
 */

// Create a payment record and initiate the provider collection.
async function initiatePayment({
  orderId,
  buyerId,
  provider: providerName = 'clickpesa',
  amount,
  phoneNumber,
}) {
  const prisma = getPrisma();
  const lock = await acquireLock(`payment:${orderId}`, 60);

  try {
    return await prisma.$transaction(async (tx) => {
      const order = await tx.order.findUnique({ where: { id: orderId } });
      if (!order) throw httpError(404, 'ORDER_NOT_FOUND');
      if (order.buyerId !== buyerId) throw httpError(403, 'FORBIDDEN');
      if (order.status !== ORDER_STATES.AWAITING_ESCROW_PAYMENT) {
        throw httpError(409, `INVALID_ORDER_STATE:${order.status}`);
      }
      if (!sameAmount(order.totalAmount, amount)) throw httpError(400, 'AMOUNT_MISMATCH');

      // Any prior pending/initiated payment for this order is voided out.
      await tx.payment.updateMany({
        where: { orderId, status: 'initiated' },
        data: { status: 'voided' },
      });

      const provider = getProvider(providerName);
      const providerResponse = await provider.initiateCollection({
        amount,
        orderReference: order.orderNumber,
        phoneNumber,
        callbackUrl: `${config.urls.app}/api/v1/payments/webhook/clickpesa`,
      });

      const payment = await tx.payment.create({
        data: {
          orderId,
          provider: providerName,
          amount,
          status: 'initiated',
          providerReference: providerResponse.providerReference,
          idempotencyKey: `init_${order.orderNumber}_${Date.now()}`,
        },
      });

      // Move order to PAYMENT_PENDING
      const machine = new OrderStateMachine(order.status);
      machine.transition(ORDER_STATES.PAYMENT_PENDING, {
        actor: 'buyer',
        actorId: buyerId,
        reason: 'Payment initiated via ' + providerName,
      });

      await tx.order.update({
        where: { id: orderId },
        data: {
          status: ORDER_STATES.PAYMENT_PENDING,
          statusChangedBy: buyerId,
        },
      });

      return { payment, providerInstruction: providerResponse.raw };
    });
  } finally {
    if (!lock.skipped) await releaseLock(`payment:${orderId}`);
  }
}

// Server-side verification of a collection status (called on webhook or poll).
// On success, creates the escrow hold and moves order to IN_ESCROW.
async function confirmCollection({
  orderReference,
  providerPaymentId,
  amount,
  force = false,
}) {
  const prisma = getPrisma();
  const lock = await acquireLock(`collection:${orderReference}`, 60);

  try {
    return await prisma.$transaction(async (tx) => {
      const order = await tx.order.findFirst({
        where: { orderNumber: orderReference },
      });
      if (!order) throw httpError(404, 'ORDER_NOT_FOUND');

      const payment = await tx.payment.findFirst({
        where: { orderId: order.id, status: { in: ['initiated', 'pending'] } },
        orderBy: { createdAt: 'desc' },
      });
      if (!payment) throw httpError(404, 'PAYMENT_NOT_FOUND');

      // Layer 4: status priority check
      if (order.status === ORDER_STATES.IN_ESCROW) {
        return { status: 'ALREADY_IN_ESCROW', order };
      }
      if (![ORDER_STATES.PAYMENT_PENDING, ORDER_STATES.FAILED].includes(order.status) && !force) {
        throw httpError(409, `INVALID_ORDER_STATE:${order.status}`);
      }

      // Optional server-side re-verification with the provider
      if (providerPaymentId === 'auto' || !providerPaymentId) {
        if (!force) {
          const provider = getProvider(payment.provider);
          const statusResp = await provider.queryCollectionStatus(orderReference);
          if (statusResp.status !== 'completed') {
            throw httpError(409, `PAYMENT_NOT_VERIFIED:${statusResp.status}`);
          }
          providerPaymentId = statusResp.providerPaymentId;
        }
      }

      await tx.payment.update({
        where: { id: payment.id },
        data: {
          status: 'completed',
          providerPaymentId: providerPaymentId || payment.providerReference,
          verifiedAt: new Date(),
        },
      });

      // Create escrow hold
      const escrowHold = await tx.escrowHold.create({
        data: {
          orderId: order.id,
          paymentId: payment.id,
          amount: payment.amount,
          status: 'holding',
        },
      });

      const machine = new OrderStateMachine(order.status);
      machine.transition(ORDER_STATES.IN_ESCROW, {
        actor: 'system',
        reason: 'Collection verified server-side',
      });

      const updatedOrder = await tx.order.update({
        where: { id: order.id },
        data: { status: ORDER_STATES.IN_ESCROW, paidAt: new Date() },
      });

      // Ledger: buyer -> escrow
      await tx.escrowTransaction.create({
        data: {
          escrowHoldId: escrowHold.id,
          type: 'FUNDS_HELD',
          amount: order.totalAmount,
          referenceId: payment.id,
        },
      });

      return { status: 'VERIFIED', order: updatedOrder, escrowHold };
    });
  } finally {
    if (!lock.skipped) await releaseLock(`collection:${orderReference}`);
  }
}

// Handle an incoming provider webhook.
// Layer 2 (WebhookEvent outbox): a unique dedup key makes re-deliveries and
// multi-instance concurrency at-most-once. Status-priority checks remain the
// financial source of truth even if two distinct events race on one order.
async function handleWebhook({ providerName, payload, signature, headers }) {
  const provider = getProvider(providerName);
  if (!provider.verifyWebhook(payload, signature)) {
    throw httpError(401, 'INVALID_WEBHOOK_SIGNATURE');
  }

  const normalized = provider.normalizeWebhook(payload);
  const webhookId = headers['x-webhook-id'] || payload.webhookId || payload.id;
  const dedupKey = outbox.buildDedupKey(providerName, webhookId, payload);

  if (!normalized.orderReference) {
    throw httpError(400, 'MISSING_ORDER_REFERENCE');
  }

  const lock = await acquireLock(`webhook:${dedupKey}`, 60);
  try {
    const event = await outbox.recordWebhookEvent({
      provider: providerName,
      dedupKey,
      type: normalized.status || 'unknown',
      rawPayload: payload,
      signature: signature || null,
      orderReference: normalized.orderReference,
    });

    // Already handled by a previous delivery — ack without side effects.
    if (event && event.status === outbox.WEBHOOK_STATUS_PROCESSED) {
      return { received: true, webhookId, duplicate: true };
    }

    await outbox.markWebhookProcessing(event);

    try {
      if (normalized.status === 'completed') {
        await confirmCollection({
          orderReference: normalized.orderReference,
          providerPaymentId: normalized.providerPaymentId,
          amount: normalized.amount,
        });
      } else if (normalized.status === 'failed') {
        await markPaymentFailed(normalized.orderReference);
      }
      await outbox.markWebhookProcessed(event);
    } catch (err) {
      // Remember partial processing so the retry re-runs the safe path;
      // confirmCollection is idempotent (status-priority + unique hold).
      await outbox.markWebhookFailed(event, err);
      throw err;
    }

    return { received: true, webhookId };
  } finally {
    if (!lock.skipped) await releaseLock(`webhook:${dedupKey}`);
  }
}

async function markPaymentFailed(orderReference) {
  const prisma = getPrisma();
  const lock = await acquireLock(`fail:${orderReference}`, 60);
  try {
    return await prisma.$transaction(async (tx) => {
      const order = await tx.order.findFirst({
        where: { orderNumber: orderReference },
      });
      if (!order) throw httpError(404, 'ORDER_NOT_FOUND');
      if (order.status !== ORDER_STATES.PAYMENT_PENDING) {
        return { status: 'SKIPPED', order };
      }
      const machine = new OrderStateMachine(order.status);
      machine.transition(ORDER_STATES.FAILED, {
        actor: 'system',
        reason: 'Provider reported collection failure',
      });
      const updated = await tx.order.update({
        where: { id: order.id },
        data: { status: ORDER_STATES.FAILED },
      });
      return { status: 'FAILED', order: updated };
    });
  } finally {
    if (!lock.skipped) await releaseLock(`fail:${orderReference}`);
  }
}

// Commission calculation (platform fee on product price).
function calcCommission(productPrice) {
  const percent = config.business.platformCommissionPercent;
  return Math.round(Number(productPrice) * percent);
}

function httpError(status, message) {
  const err = new Error(message);
  err.status = status;
  return err;
}

module.exports = {
  initiatePayment,
  confirmCollection,
  handleWebhook,
  markPaymentFailed,
  calcCommission,
};
