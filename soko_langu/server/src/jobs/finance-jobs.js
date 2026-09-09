/**
 * Finance safety-net jobs (BullMQ 'finance' queue).
 *
 * Every job is idempotent: state-machine guards, unique keys, and Redis locks
 * make re-runs (overlapping instances, manual triggers, crash retries) no-ops.
 *
 * Jobs:
 *   finance.paymentExpire          — expire abandoned orders (re-verify paid ones first)
 *   finance.inspectionAutoRelease  — release escrow after inspection window w/ safeguards
 *   finance.withdrawalProcess      — auto-process eligible pending withdrawals; flag stuck
 *   finance.reconciliationRun      — run ClickPesa reconciliation; alert on mismatch
 *   finance.disputeEscalate        — alert admins when open disputes exceed SLA
 */
const config = require('../config');
const { getPrisma } = require('../config/database');
const { acquireLock, releaseLock } = require('../config/redis');
const { getProvider } = require('../modules/payments/provider-factory');
const paymentService = require('../modules/payments/payment-service');
const { OrderStateMachine, ORDER_STATES } = require('../modules/orders/order-state-machine');
const { autoRelease } = require('../modules/disputes/auto-release-service');
const { processWithdrawal } = require('../modules/wallet/wallet-service');
const { runReconciliation } = require('../modules/reconciliation/reconciliation-service');
const { sendOneSignalNotification, notifyAdmins } = require('../modules/legacy-compat/notify');

// Sentinel used so a stale-but-paid order is never expired. Only ACTIVE holds
// / initiated payments are re-verified; anything else is left for admin.
const PAYMENT_STATES_ACTIVE = ['initiated', 'pending'];

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
        requestId: data.requestId || `job_${data.action}`,
      },
    });
  } catch (e) {
    console.error('[FINANCE][AUDIT]', e.message);
  }
}

// Fire a notification at most once per window (Redis SETNX key, TTL window).
async function throttledNotify(key, ttlSeconds, fn) {
  const lock = await acquireLock(`notify:${key}`, ttlSeconds);
  if (!lock.acquired) return;
  try {
    await fn();
  } catch (e) {
    console.error('[FINANCE][NOTIFY]', key, e.message);
  }
}

async function notifyBuyer(order, title, body, data) {
  const prisma = getPrisma();
  try {
    const buyer = await prisma.user.findUnique({ where: { id: order.buyerId } });
    if (buyer) {
      await sendOneSignalNotification(buyer.firebaseUid, title, body, { ...data, orderId: order.id });
    }
  } catch (e) {
    console.error('[FINANCE][NOTIFY-BUYER]', order.id, e.message);
  }
}

/* ------------------------------------------------------------------ */
/* 1. paymentExpire                                                    */
/* ------------------------------------------------------------------ */

async function expireStalePayments({ now = new Date() } = {}) {
  const prisma = getPrisma();
  const due = new Date(now.getTime() - config.finance.paymentExpireMs);
  const prismaOrders = await prisma.order.findMany({
    where: {
      status: { in: [ORDER_STATES.AWAITING_ESCROW_PAYMENT, ORDER_STATES.PAYMENT_PENDING] },
      createdAt: { lte: due },
    },
    take: 100,
    orderBy: { createdAt: 'asc' },
  });

  const summary = { expired: 0, paidRecovered: 0, skipped: 0, failed: 0 };
  for (const order of prismaOrders) {
    const lock = await acquireLock(`expire:${order.id}`, 60);
    try {
      const fresh = await prisma.order.findUnique({ where: { id: order.id } });
      if (![ORDER_STATES.AWAITING_ESCROW_PAYMENT, ORDER_STATES.PAYMENT_PENDING].includes(fresh.status)) {
        summary.skipped += 1;
        continue;
      }

      // Orders whose payment was actually initiated are re-verified against the
      // provider before any expiry. Expiring a paid-but-lost-webhook order would
      // trap buyer money — that must never happen.
      if (fresh.status === ORDER_STATES.PAYMENT_PENDING) {
        const payment = await prisma.payment.findFirst({
          where: { orderId: fresh.id, status: { in: PAYMENT_STATES_ACTIVE } },
          orderBy: { createdAt: 'desc' },
        });
        if (payment) {
          let providerStatus = null;
          try {
            const provider = getProvider(payment.provider);
            providerStatus = (await provider.queryCollectionStatus(fresh.orderNumber)).status;
          } catch (e) {
            console.warn('[FINANCE] provider re-verify failed', fresh.orderNumber, e.message);
          }

          if (providerStatus === 'completed') {
            try {
              await paymentService.confirmCollection({ orderReference: fresh.orderNumber });
              summary.paidRecovered += 1;
              continue;
            } catch (e) {
              console.warn('[FINANCE] recovery failed', fresh.orderNumber, e.message);
            }
          }
          if (providerStatus === 'failed') {
            try {
              await paymentService.markPaymentFailed(fresh.orderNumber);
              summary.expired += 1; // reached a terminal, retryable state
              continue;
            } catch (e) {
              console.warn('[FINANCE] mark-failed failed', fresh.orderNumber, e.message);
            }
          }
          // pending or provider unreachable → leave for webhook/admin/reconciliation
          summary.skipped += 1;
          continue;
        }
      }

      // No payment was ever initiated (or provider says it never landed): safe to expire.
      await prisma.$transaction(async (tx) => {
        const machine = new OrderStateMachine(fresh.status);
        machine.transition(ORDER_STATES.EXPIRED, { actor: 'system', reason: 'Payment window elapsed' });
        const updated = await tx.order.update({
          where: { id: fresh.id },
          data: { status: ORDER_STATES.EXPIRED, statusChangedAt: new Date() },
        });
        await audit(tx, {
          action: 'ORDER_EXPIRED',
          entityType: 'order',
          entityId: fresh.id,
          oldState: { status: fresh.status },
          newState: { status: ORDER_STATES.EXPIRED },
        });
        return updated;
      });
      summary.expired += 1;
      await notifyBuyer(fresh, 'Order expired', 'Malipo yale kuchezewa. Tafadhali weka oda mpya.', { type: 'order_expired', expiry: true });
    } catch (e) {
      summary.failed += 1;
      console.error('[FINANCE] expireStalePayments order', order.id, e.message);
    } finally {
      if (!lock.skipped) await releaseLock(`expire:${order.id}`);
    }
  }
  return summary;
}

/* ------------------------------------------------------------------ */
/* 2. inspectionAutoRelease                                            */
/* ------------------------------------------------------------------ */

async function runAutoReleaseSweep({ now = new Date() } = {}) {
  const prisma = getPrisma();
  const due = new Date(now.getTime() - config.finance.autoReleaseDays * 24 * 3600 * 1000);
  const orders = await prisma.order.findMany({
    where: {
      status: { in: [ORDER_STATES.INSPECTION_PERIOD, ORDER_STATES.DELIVERED] },
      deliveredAt: { lte: due },
    },
    take: 50,
    orderBy: { deliveredAt: 'asc' },
  });

  const summary = { released: 0, blocked: 0, skipped: 0, errored: 0 };
  for (const order of orders) {
    try {
      const result = await autoRelease({ orderId: order.id });
      if (result.status === 'AUTO_RELEASED') {
        summary.released += 1;
      } else if (result.status === 'BLOCKED') {
        summary.blocked += 1;
        await throttledNotify(`autorelease:${order.id}`, 24 * 3600, () =>
          notifyAdmins(
            'Auto-release blocked',
            `Oda ${order.orderNumber}: ${(result.missingSafeguards || []).join(', ')}`,
            { type: 'escrow_auto_release', orderId: order.id, blocked: true }
          )
        );
      } else {
        summary.skipped += 1;
      }
    } catch (e) {
      summary.errored += 1;
      console.error('[FINANCE] autoRelease order', order.id, e.message);
    }
  }
  return summary;
}

/* ------------------------------------------------------------------ */
/* 3. withdrawalProcess                                                */
/* ------------------------------------------------------------------ */

async function processPendingWithdrawals({ now = new Date() } = {}) {
  const prisma = getPrisma();
  const autoCutoff = new Date(now.getTime() - config.finance.withdrawalAutoProcessMs);
  const stuckCutoff = new Date(now.getTime() - config.finance.withdrawalStuckMs);

  const pendings = await prisma.withdrawal.findMany({
    where: { status: 'pending', createdAt: { lte: autoCutoff } },
    take: 50,
    orderBy: { createdAt: 'asc' },
  });
  const summary = { processed: 0, skipped: 0, stuckAlerted: 0, errored: 0 };

  for (const w of pendings) {
    try {
      await processWithdrawal({ withdrawalId: w.id, executedBy: 'system' });
      summary.processed += 1;
    } catch (e) {
      summary.errored += 1;
      console.warn('[FINANCE] withdrawal process', w.id, e.message);
    }
  }

  const stuck = await prisma.withdrawal.findMany({
    where: { status: 'processing', createdAt: { lte: stuckCutoff } },
    take: 20,
    orderBy: { createdAt: 'asc' },
  });
  for (const s of stuck) {
    summary.stuckAlerted += 1;
    await throttledNotify(`withdrawalStuck:${s.id}`, 24 * 3600, () =>
      notifyAdmins('Payout stuck in processing', `Withdrawal ${s.id} is processing past the window. Reconcile with ClickPesa.`, {
        type: 'withdrawal_failed', withdrawalId: s.id, stuck: true,
      })
    );
  }
  return summary;
}

/* ------------------------------------------------------------------ */
/* 4. reconciliationRun                                                */
/* ------------------------------------------------------------------ */

async function runReconciliationSweep({ now = new Date() } = {}) {
  const start = new Date(now.getTime() - config.finance.reconciliationWindowMs);
  try {
    const row = await runReconciliation({
      provider: 'clickpesa',
      periodStart: start.toISOString(),
      periodEnd: now.toISOString(),
    });
    if (row && row.status === 'mismatched') {
      await throttledNotify('reconciliation:mismatch', 24 * 3600, () =>
        notifyAdmins(
          'Payment reconciliation mismatch',
          `Diff: ${row.difference.toString()} TZS (${row.periodStart.toISOString()} - ${row.periodEnd.toISOString()}).`,
          { type: 'reconciliation', mismatch: true, reconciliationId: row.id }
        )
      );
    }
    return { status: row ? row.status : 'error' };
  } catch (e) {
    console.error('[FINANCE] reconciliation run', e.message);
    return { status: 'error', error: e.message };
  }
}

/* ------------------------------------------------------------------ */
/* 5. disputeEscalate                                                  */
/* ------------------------------------------------------------------ */

async function escalateDisputes({ now = new Date() } = {}) {
  const prisma = getPrisma();
  const cutoff = new Date(now.getTime() - config.finance.disputeSlaMs);
  const open = await prisma.dispute.findMany({
    where: { status: 'open', createdAt: { lte: cutoff } },
    take: 20,
    orderBy: { createdAt: 'asc' },
    include: { order: { select: { orderNumber: true } } },
  });
  const summary = { escalated: 0 };
  for (const d of open) {
    summary.escalated += 1;
    await throttledNotify(`dispute:${d.id}`, 24 * 3600, () =>
      notifyAdmins(
        'Dispute over SLA',
        `Mtafaruku ${d.id} (oda ${d.order ? d.order.orderNumber : '?'}) umechelewesha kutatuliwa.`,
        { type: 'order_disputed', disputeId: d.id, sla: true }
      )
    );
  }
  return summary;
}

/* ------------------------------------------------------------------ */
/* Dispatch                                                           */
/* ------------------------------------------------------------------ */

const JOB_HANDLERS = {
  'finance.paymentExpire': expireStalePayments,
  'finance.inspectionAutoRelease': runAutoReleaseSweep,
  'finance.withdrawalProcess': processPendingWithdrawals,
  'finance.reconciliationRun': runReconciliationSweep,
  'finance.disputeEscalate': escalateDisputes,
};

async function runFinanceJob(name, data = {}) {
  const handler = JOB_HANDLERS[name];
  if (!handler) throw new Error(`Unknown finance job: ${name}`);
  return handler(data);
}

module.exports = {
  expireStalePayments,
  runAutoReleaseSweep,
  processPendingWithdrawals,
  runReconciliationSweep,
  escalateDisputes,
  runFinanceJob,
};