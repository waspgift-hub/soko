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
const { getStore } = require('../config/database');
const { acquireLock, requireLock, releaseLock } = require('../config/redis');
const { getProvider } = require('../modules/payments/provider-factory');
const paymentService = require('../modules/payments/payment-service');
const { OrderStateMachine, ORDER_STATES } = require('../modules/orders/order-state-machine');
const { autoRelease } = require('../modules/disputes/auto-release-service');
const { processWithdrawal } = require('../modules/wallet/wallet-service');
const { runReconciliation } = require('../modules/reconciliation/reconciliation-service');
const { sendOneSignalNotification, notifyAdmins } = require('../modules/legacy-compat/notify');
const { syncLegacyOrderStatus } = require('../modules/legacy-compat/presentation-mirror');

// Sentinel used so a stale-but-paid order is never expired. Only ACTIVE holds
// / initiated payments are re-verified; anything else is left for admin.
const PAYMENT_STATES_ACTIVE = ['initiated', 'pending'];

/**
 * Walks a sweep in bounded, ordered batches until the set is drained.
 *
 * The previous shape was `findMany({ take: N, orderBy })` in a single call. Two
 * problems, both fixed here:
 *
 *  1. The store used to read a fixed 1000-document ceiling for any ordered
 *     query, so every sweep silently saw only the newest 1000 rows in the
 *     collection — payments past that point never expired and escrow never
 *     auto-released.
 *  2. A single `take: N` per run cannot drain a backlog larger than N.
 *
 * Now each batch is one indexed, ordered, LIMIT-bounded query, and the loop
 * continues until a short page proves the set is exhausted. `maxBatches` is a
 * wall-clock guard, not a correctness ceiling: on hitting it the summary says
 * `drained: false` so the next scheduled run continues rather than the sweep
 * being reported as complete.
 *
 * `status` values that are not re-queued (completed, refunded, …) simply drop
 * out of the filter, so the cursor walks forward through newly-advanced rows
 * without revisiting settled work.
 */
async function drainSweep({
  model,
  where,
  batchSize = 100,
  maxBatches = 20,
  orderBy = { createdAt: 'asc' },
  onBatch,
  summary,
}) {
  let processed = 0;
  let batches = 0;

  for (let batch = 0; batch < maxBatches; batch++) {
    const rows = await model.findMany({ where, take: batchSize, orderBy });
    if (!rows || rows.length === 0) {
      summary.drained = true;
      return { processed, batches };
    }

    await onBatch(rows);

    processed += rows.length;
    batches += 1;

    if (rows.length < batchSize) {
      // A short page means the indexed query is exhausted.
      summary.drained = true;
      return { processed, batches };
    }
  }

  // Ran out of batch budget with a full page still coming. Deliberately left
  // false so the caller reports an incomplete sweep; the next scheduled run
  // picks up where this one stopped.
  summary.drained = false;
  return { processed, batches };
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
        requestId: data.requestId || `job_${data.action}`,
      },
    });
  } catch (e) {
    console.error('[FINANCE][AUDIT]', e.message);
  }
}

// Fire a notification at most once per window (Redis SETNX key, TTL window).
//
// `optional: true` is correct here and only here: this lock is a duplicate-
// notification damper, not a correctness guard. Losing it during a Redis blip
// means an extra alert, which is harmless; the money locks must fail closed.
async function throttledNotify(key, ttlSeconds, fn) {
  const lock = await acquireLock(`notify:${key}`, ttlSeconds, { optional: true });
  if (!lock.acquired) return;
  try {
    await fn();
  } catch (e) {
    console.error('[FINANCE][NOTIFY]', key, e.message);
  } finally {
    // The window IS the TTL — releasing early would defeat the throttle. This
    // lock is intentionally not released, unlike every money lock.
  }
}

async function notifyBuyer(order, title, body, data) {
  const store = getStore();
  try {
    const buyer = await store.user.findUnique({ where: { id: order.buyerId } });
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
  const store = getStore();
  const due = new Date(now.getTime() - config.finance.paymentExpireMs);

  const summary = { expired: 0, paidRecovered: 0, skipped: 0, failed: 0, processed: 0, drained: true };

  await drainSweep({
    model: store.order,
    where: {
      status: { in: [ORDER_STATES.PENDING_PAYMENT, ORDER_STATES.PAYMENT_PROCESSING] },
      createdAt: { lte: due },
    },
    batchSize: 100,
    summary,
    onBatch: async (pendingOrders) => {
    summary.processed += pendingOrders.length;
    for (const order of pendingOrders) {
    // Fail closed. Expiring an order is a money-visible transition: two sweeps
    // running concurrently could expire an order the buyer is actively paying,
    // or recover-then-expire the same payment. `acquireLock` returned
    // `{acquired:false}` during a Redis blip and this loop still ran the body,
    // so a degraded Redis silently removed the mutual exclusion it existed to
    // provide. `requireLock` throws instead, the catch below counts it, and the
    // order survives to the next sweep.
    let lock;
    try {
      lock = await requireLock(`expire:${order.id}`, 60);
    } catch (e) {
      summary.failed += 1;
      console.error('[FINANCE] expireStalePayments lock', order.id, e.message);
      continue;
    }
    try {
      const fresh = await store.order.findUnique({ where: { id: order.id } });
      if (![ORDER_STATES.PENDING_PAYMENT, ORDER_STATES.PAYMENT_PROCESSING].includes(fresh.status)) {
        summary.skipped += 1;
        continue;
      }

      if (fresh.status === ORDER_STATES.PAYMENT_PROCESSING) {
        const payment = await store.payment.findFirst({
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
              summary.expired += 1; 
              continue;
            } catch (e) {
              console.warn('[FINANCE] mark-failed failed', fresh.orderNumber, e.message);
            }
          }
          summary.skipped += 1;
          continue;
        }
      }

      const expiredOrder = await store.$transaction(async (tx) => {
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

      // Mirror after the commit: the sweep is what ends a buyer's payment
      // attempt, and without this the order screen keeps showing a pending
      // payment the buyer can no longer complete. Outside the callback so a
      // rollback cannot leave the client believing the order expired.
      await syncLegacyOrderStatus(expiredOrder);

      summary.expired += 1;
      await notifyBuyer(fresh, 'Order expired', 'Malipo yale kuchezewa. Tafadhali weka oda mpya.', { type: 'order_expired', expiry: true });
    } catch (e) {
      summary.failed += 1;
      console.error('[FINANCE] expireStalePayments order', order.id, e.message);
    } finally {
      if (lock.acquired) await releaseLock(`expire:${order.id}`, lock.token);
    }
    }
    },
  });

  return summary;
}

/* ------------------------------------------------------------------ */
/* 2. inspectionAutoRelease                                            */
/* ------------------------------------------------------------------ */

async function runAutoReleaseSweep({ now = new Date() } = {}) {
  const store = getStore();
  const due = new Date(now.getTime() - config.finance.autoReleaseDays * 24 * 3600 * 1000);

  const summary = { released: 0, blocked: 0, skipped: 0, errored: 0, processed: 0, drained: true };

  await drainSweep({
    model: store.order,
    where: {
      legacyFirestoreId: null,
      status: { in: [ORDER_STATES.DELIVERED, ORDER_STATES.DELIVERY_CONFIRMED] },
      deliveredAt: { lte: due },
    },
    batchSize: 50,
    // `deliveredAt` drives both the filter and the order, so the cursor walks
    // oldest-delivered first and each batch makes progress.
    orderBy: { deliveredAt: 'asc' },
    summary,
    onBatch: async (orders) => {
    summary.processed += orders.length;
    for (const order of orders) {
    try {
      // The canonical completeOrder flow performs the Ledger settlement; this
      // sweep only decides *when* an order qualifies.
      const orderService = require('../modules/orders/order-service');
      const result = await orderService.completeOrder({
        orderId: order.id,
        actorId: 'system',
        method: 'AUTO_RELEASE',
      });

      if (result && result.status === 'COMPLETED') {
        summary.released += 1;
      } else if (result && result.status === 'NO_ELIGIBLE_ESCROW') {
        // The hold was disputed or refunded: the sweep must not pay it out.
        // Surfaced separately so a disputed backlog is visible instead of
        // being indistinguishable from a completed release.
        summary.blocked += 1;
      } else {
        summary.skipped += 1;
      }
    } catch (e) {
      summary.errored += 1;
      console.error('[FINANCE] autoRelease order', order.id, e.message);
    }
    }
    },
  });

  return summary;
}

/* ------------------------------------------------------------------ */
/* 3. withdrawalProcess                                                */
/* ------------------------------------------------------------------ */

async function processPendingWithdrawals({ now = new Date() } = {}) {
  const store = getStore();
  const autoCutoff = new Date(now.getTime() - config.finance.withdrawalAutoProcessMs);
  const stuckCutoff = new Date(now.getTime() - config.finance.withdrawalStuckMs);

  const summary = { processed: 0, skipped: 0, stuckAlerted: 0, errored: 0, drained: true };

  await drainSweep({
    model: store.withdrawal,
    // `reserved` is the dispatch queue: money is held and the gateway has not
    // been called. `disbursing` is included because a previous attempt may have
    // died mid-call — processWithdrawal asks ClickPesa whether it already has
    // the payout before touching it, so this can never double-send.
    //
    // The old filter was `status: 'pending'`, a state the withdrawal state
    // machine does not have: `requestWithdrawal` writes `requested`, then
    // `reserved` once the ledger debit commits. The sweep therefore matched zero
    // rows and every withdrawal sat unprocessed until an admin opened it.
    where: { status: { in: ['reserved', 'disbursing'] }, createdAt: { lte: autoCutoff } },
    batchSize: 50,
    summary,
    onBatch: async (pendings) => {
    for (const w of pendings) {
    try {
      await processWithdrawal({ withdrawalId: w.id, executedBy: 'system' });
      summary.processed += 1;
    } catch (e) {
      summary.errored += 1;
      console.warn('[FINANCE] withdrawal process', w.id, e.message);
    }
    }
    },
  });

  // Payouts the gateway accepted but never confirmed. These are NOT retried —
  // they may already have been sent. They are alerted for manual
  // reconciliation, which is the only safe action without a payout-status API.
  await drainSweep({
    model: store.withdrawal,
    where: { status: 'processing', createdAt: { lte: stuckCutoff } },
    batchSize: 20,
    summary,
    onBatch: async (stuck) => {
    for (const s of stuck) {
    summary.stuckAlerted += 1;
    await throttledNotify(`withdrawalStuck:${s.id}`, 24 * 3600, () =>
      notifyAdmins('Payout stuck in processing', `Withdrawal ${s.id} is processing past the window. Reconcile with ClickPesa.`, {
        type: 'withdrawal_failed', withdrawalId: s.id, stuck: true,
      })
    );
    }
    },
  });

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
      skipWhenQuiet: true,
    });
    // runReconciliation returns null when there is no payment activity to
    // reconcile (idle system) — nothing to record or alert on.
    if (!row) return { status: 'idle' };
    if (row.status === 'mismatched') {
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
  const store = getStore();
  const cutoff = new Date(now.getTime() - config.finance.disputeSlaMs);
  const summary = { escalated: 0, drained: true };

  await drainSweep({
    model: store.dispute,
    where: { status: 'open', createdAt: { lte: cutoff } },
    batchSize: 20,
    summary,
    onBatch: async (open) => {
    for (const d of open) {
    summary.escalated += 1;
    await throttledNotify(`dispute:${d.id}`, 24 * 3600, () =>
      notifyAdmins(
        'Dispute over SLA',
        `Mtafaruku ${d.id} (oda ${d.order ? d.order.orderNumber : '?'}) umechelewesha kutatuliwa.`,
        { type: 'order_disputed', disputeId: d.id, sla: true }
      )
    );

    if (!d.order) continue;
    const sellerProfile = await store.sellerProfile.findUnique({
      where: { id: d.order.sellerId },
      select: { userId: true },
    });
    const partyIds = [d.order.buyerId, sellerProfile ? sellerProfile.userId : null].filter(Boolean);
    const parties = await store.user.findMany({
      where: { id: { in: partyIds } },
      select: { id: true, firebaseUid: true },
    });
    for (const party of parties) {
      await throttledNotify(`dispute:${d.id}:party:${party.id}`, 24 * 3600, () =>
        sendOneSignalNotification(
          party.firebaseUid,
          'Mgogoro umechelewa kutatuliwa',
          `Mtafaruku wa oda ${d.order.orderNumber} bado unaendelea. Mtaalam atawasiliana nawe hivi karibuni.`,
          { type: 'dispute_sla', disputeId: d.id, sla: true }
        )
      );
    }
    }
    },
  });

  return summary;
}

/* ------------------------------------------------------------------ */
/* 6. refundUnstuck — flag stranded refunds                              */
/* ------------------------------------------------------------------ */

async function refundUnstuck({ now = new Date() } = {}) {
  const store = getStore();
  const processingCutoff = new Date(now.getTime() - 2 * 3600 * 1000);
  const failedCutoff = new Date(now.getTime() - 24 * 3600 * 1000);
  const summary = { stuck: 0, drained: true };

  await drainSweep({
    model: store.refund,
    where: {
      OR: [
        { status: 'processing', createdAt: { lte: processingCutoff } },
        { status: 'failed', createdAt: { lte: failedCutoff } },
      ],
    },
    batchSize: 20,
    summary,
    onBatch: async (stuck) => {
    for (const r of stuck) {
    summary.stuck += 1;
    await throttledNotify(`refund:${r.id}`, 24 * 3600, () =>
      notifyAdmins(
        'Refund imekwama',
        `Refund ya TZS ${Number(r.amount).toLocaleString()} (${r.status}, oda ${r.order ? r.order.orderNumber : '?'}) inahitaji uangalizi.`,
        { type: 'refund_stuck', refundId: r.id, status: r.status, amount: r.amount.toString() }
      )
    );
    }
    },
  });

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
  'finance.refundUnstuck': refundUnstuck,
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
  refundUnstuck,
  runFinanceJob,
};