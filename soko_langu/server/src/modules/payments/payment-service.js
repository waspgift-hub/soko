const { getPrisma } = require('../../config/database');
const { acquireLock, releaseLock } = require('../../config/redis');
const { getProvider } = require('./provider-factory');
const config = require('../../config');
const { OrderStateMachine, ORDER_STATES } = require('../orders/order-state-machine');
const { sameAmount } = require('../../utils/money');
const outbox = require('./webhook-outbox');
const { syncLegacyOrderStatus } = require('../legacy-compat/presentation-mirror');
const { sendOneSignalNotification } = require('../legacy-compat/notify');

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
      if (order.status !== ORDER_STATES.AWAITING_PAYMENT) {
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
      machine.transition(ORDER_STATES.PAYMENT_PROCESSING, {
        actor: 'buyer',
        actorId: buyerId,
        reason: 'Payment initiated via ' + providerName,
      });

      await tx.order.update({
        where: { id: orderId },
        data: {
          status: ORDER_STATES.PAYMENT_PROCESSING,
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
// On success, creates the escrow hold and moves order to PAID_IN_ESCROW.
// Idempotent: the status-priority check and SceneHold's unique orderId make
// re-entry (webhook redelivery, multi-instance, job re-run) a no-op or a
// rollback-safe unique violation — never a double-credit.
async function confirmCollection({
  orderReference,
  providerPaymentId,
  amount,
  force = false,
}) {
  const prisma = getPrisma();
  const lock = await acquireLock(`collection:${orderReference}`, 60);

  let result;
  try {
    await prisma.$transaction(async (tx) => {
      const order = await tx.order.findFirst({
        where: { orderNumber: orderReference },
      });
      if (!order) throw httpError(404, 'ORDER_NOT_FOUND');

      // Layer 4: status priority check — runs BEFORE the payment lookup so a
      // webhook redelivery or poll sweep after a successful commit is a fast,
      // idempotent no-op instead of a 404 on the now-completed payment.
      if (order.status === ORDER_STATES.PAID_IN_ESCROW) {
        result = { status: 'ALREADY_IN_ESCROW', order };
        return;
      }

      const payment = await tx.payment.findFirst({
        where: { orderId: order.id, status: { in: ['initiated', 'pending'] } },
        orderBy: { createdAt: 'desc' },
      });
      if (!payment) throw httpError(404, 'PAYMENT_NOT_FOUND');

      // The provider-reported amount must match the server-fixed payable; the
      // escrow books the server amount, never a client/provider figure.
      if (amount != null && !sameAmount(payment.amount, amount)) {
        throw httpError(409, `PAYMENT_AMOUNT_MISMATCH:expected=${Number(payment.amount)}`);
      }

      // A provider completion landing after the order left the pay window
      // (cancelled/expired/failed while pre-escrow) still captures the money
      // into a hold and parks the order REFUND_PENDING so the buyer gets it
      // back via the standard refund path instead of it being stranded.
      if (order.status !== ORDER_STATES.PAYMENT_PROCESSING) {
        if (![ORDER_STATES.CANCELLED, ORDER_STATES.EXPIRED, ORDER_STATES.PAYMENT_FAILED].includes(order.status)) {
          throw httpError(409, `INVALID_ORDER_STATE:${order.status}`);
        }
        // Idempotency: a redelivered webhook after a successful park must not
        // open a second refund obligation for the same payment.
        const parkedRefund = await tx.refund.findFirst({
          where: { paymentId: payment.id },
        });
        if (parkedRefund) {
          result = { status: 'ALREADY_REFUND_PARKED', order };
          return;
        }
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

        const escrowHold = await tx.escrowHold.create({
          data: {
            orderId: order.id,
            paymentId: payment.id,
            amount: payment.amount,
            status: 'holding',
          },
        });

        const machine = new OrderStateMachine(order.status);
        machine.transition(ORDER_STATES.REFUND_PENDING, {
          actor: 'system',
          reason: 'Provider confirmed payment after order left the pay window',
        });

        const parked = await tx.order.update({
          where: { id: order.id },
          data: {
            status: ORDER_STATES.REFUND_PENDING,
            paidAt: new Date(),
            statusChangedBy: 'system',
          },
        });

        const { buildCorrelationId } = require('../refunds/refund-service');
        await tx.refund.create({
          data: {
            orderId: order.id,
            paymentId: payment.id,
            amount: payment.amount,
            mode: 'full',
            reason: 'Late provider confirmation after cancel/expiry',
            correlationId: buildCorrelationId(order.orderNumber),
            requestedBy: order.buyerId,
            status: 'pending',
          },
        });

        result = { status: 'REFUND_PARKED', order: parked, escrowHold };
        return;
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
      machine.transition(ORDER_STATES.PAID_IN_ESCROW, {
        actor: 'system',
        reason: 'Collection verified server-side',
      });

      const updatedOrder = await tx.order.update({
        where: { id: order.id },
        data: { status: ORDER_STATES.PAID_IN_ESCROW, paidAt: new Date() },
      });

      result = { status: 'VERIFIED', order: updatedOrder, escrowHold };
    });
  } finally {
    if (!lock.skipped) await releaseLock(`collection:${orderReference}`);
  }

  // Presentation mirror + seller notification AFTER commit.
  if (result && result.status === 'VERIFIED') {
    await syncLegacyOrderStatus(result.order);
    await notifySellerEscrowFunded(result.order);
  }
  if (result && result.status === 'REFUND_PARKED') {
    await syncLegacyOrderStatus(result.order);
  }
  return result;
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
  let result;
  try {
    await prisma.$transaction(async (tx) => {
      const order = await tx.order.findFirst({
        where: { orderNumber: orderReference },
      });
      if (!order) throw httpError(404, 'ORDER_NOT_FOUND');
      if (order.status !== ORDER_STATES.PAYMENT_PROCESSING) {
        result = { status: 'SKIPPED', order };
        return;
      }
      const machine = new OrderStateMachine(order.status);
      machine.transition(ORDER_STATES.PAYMENT_FAILED, {
        actor: 'system',
        reason: 'Provider reported collection failure',
      });
      const updated = await tx.order.update({
        where: { id: order.id },
        data: { status: ORDER_STATES.PAYMENT_FAILED },
      });
      result = { status: 'FAILED', order: updated };
    });
  } finally {
    if (!lock.skipped) await releaseLock(`fail:${orderReference}`);
  }

  if (result && result.status === 'FAILED') {
    await syncLegacyOrderStatus(result.order);
  }
  return result;
}

// Best-effort: the seller learns their order is funded and can dispatch. Never
// fails the webhook when the notification stack hiccups.
async function notifySellerEscrowFunded(order) {
  try {
    const prisma = getPrisma();
    const seller = await prisma.sellerProfile.findUnique({
      where: { id: order.sellerId },
      include: { user: { select: { id: true, firebaseUid: true } } },
    });
    if (!seller || !seller.user) return;
    const title = 'Malipo Yamefika';
    const body = `Malipo ya oda ${order.orderNumber} yameingia escrow. Tayarisha kupeleka.`;
    const data = { type: 'order', orderId: order.id, escrowFunded: true };
    try {
      await prisma.notification.create({
        data: { userId: seller.user.id, type: 'payment', title, body, data },
      });
    } catch (e) {
      console.error('[PAYMENT][NOTIFY-SELLER-DB]', e.message);
    }
    try {
      await sendOneSignalNotification(seller.user.firebaseUid, title, body, data);
    } catch (e) {
      console.error('[PAYMENT][NOTIFY-SELLER-OS]', e.message);
    }
  } catch (e) {
    console.error('[PAYMENT][NOTIFY-SELLER]', e.message);
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
