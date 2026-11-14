const { getStore } = require('../../config/database');
const { requireLock, releaseLock } = require('../../config/redis');
const { OrderStateMachine, ORDER_STATES } = require('../orders/order-state-machine');
const { RELEASE_REASON } = require('../escrow/escrow-release');
const { GATE_THRESHOLDS } = require('../trust/quality-gates');

const REQUIRED_SAFEGUARDS = [
  'NO_ACTIVE_DISPUTE',
  'VERIFIED_DELIVERY',
  'CORRECT_RECIPIENT_ADDRESS',
  'SELLER_DISPATCH_EVIDENCE',
  'NO_CRITICAL_FRAUD_SIGNAL',
];

// Roles whose delivery attestation is independent of the seller. A `seller`
// stamp is deliberately absent: it proves only that the seller pressed a
// button, not that the parcel moved.
const TRUSTED_DELIVERY_ATTESTORS = new Set(['courier', 'admin', 'system']);

// Moderation states that still represent an unresolved abuse claim.
const OPEN_REPORT_STATUSES = ['pending', 'open', 'reviewing'];

// Exactly 0 means "no completed history yet", not "proven bad", so only a
// positive-but-low score counts as a signal. The floor itself lives in
// GATE_THRESHOLDS so the distribution gate and the payout gate cannot drift.

/**
 * Delivery evidence strong enough to settle without the buyer's OTP.
 *
 * A courier (or admin/system) attestation is the chain-of-custody proof in an
 * offline-first market; a recorded POD artifact or a verified handover
 * credential is stronger still. Anything else — including a legacy row that
 * only carries `deliveredAt` — fails closed.
 */
function hasVerifiedDelivery(order) {
  if (order.deliveredAt && TRUSTED_DELIVERY_ATTESTORS.has(order.deliveredByRole)) return true;
  if (order.otpVerifiedAt || order.handoverVerifiedAt) return true;
  if (order.podPhotoKey || order.podSignatureKey) return true;
  return Boolean(order.deliveryProof && Object.keys(order.deliveryProof).length > 0);
}

/**
 * Real fraud signals, replacing the previous placeholder hook.
 *
 * Every query is inside the caller's transaction so a signal cannot be read
 * from one snapshot and the money released from another.
 */
async function evaluateFraudSignals(tx, order) {
  const signals = [];

  const sellerProfile = order.sellerId
    ? await tx.sellerProfile.findUnique({ where: { id: order.sellerId } })
    : null;
  const sellerUserId = sellerProfile ? (sellerProfile.userId || sellerProfile.id) : null;

  // Self-dealing: buyer and seller are the same account.
  if (sellerUserId && String(sellerUserId) === String(order.buyerId)) {
    signals.push('SELF_DEALING');
  }

  const reliabilityScore = Number(sellerProfile && sellerProfile.reliabilityScore);
  if (
    Number.isFinite(reliabilityScore) &&
    reliabilityScore > 0 &&
    reliabilityScore < GATE_THRESHOLDS.highRiskSellerScore
  ) {
    signals.push('SELLER_HIGH_RISK');
  }

  if (sellerUserId) {
    const sellerUser = await tx.user.findUnique({ where: { id: sellerUserId } });

    // A restricted account must not receive an automatic payout.
    if (sellerUser && ['suspended', 'deleted'].includes(sellerUser.accountStatus)) {
      signals.push('SELLER_ACCOUNT_RESTRICTED');
    }

    // An unresolved abuse report against the seller blocks the timer; an admin
    // resolves the report (or pays out explicitly) instead.
    const openReport = sellerUser && sellerUser.firebaseUid
      ? await tx.moderationReport.findFirst({
          where: {
            targetType: 'user',
            targetId: sellerUser.firebaseUid,
            status: { in: OPEN_REPORT_STATUSES },
          },
        })
      : null;
    if (openReport) signals.push('SELLER_OPEN_MODERATION_REPORT');
  }

  return signals;
}

/**
 * Evaluate whether an order qualifies for auto-release after the inspection window.
 * Every safeguard must pass. Returns { canRelease, missingSafeguards }.
 */
async function evaluateAutoRelease(tx, orderId) {
  const order = await tx.order.findUnique({
    where: { id: orderId },
    include: { dispute: true, escrowHold: true },
  });
  if (!order) return { canRelease: false, missingSafeguards: ['ORDER_NOT_FOUND'], fraudSignals: [] };

  const missing = [];

  // 1. No active dispute
  const hasActiveDispute = (order.dispute || []).some((d) => d.status === 'open');
  if (hasActiveDispute) missing.push('NO_ACTIVE_DISPUTE');

  // 2. Verified delivery (independent attestation, POD, or a verified handover
  //    credential — see hasVerifiedDelivery)
  if (!hasVerifiedDelivery(order)) missing.push('VERIFIED_DELIVERY');

  // 3. Correct recipient/address (best-effort: snapshot presence)
  if (!order.shippingAddressSnapshot) missing.push('CORRECT_RECIPIENT_ADDRESS');

  // 4. Seller dispatch evidence (courier/tracking present)
  if (!order.trackingNumber && !order.courierName) missing.push('SELLER_DISPATCH_EVIDENCE');

  // 5. No critical fraud signal
  const fraudSignals = await evaluateFraudSignals(tx, order);
  if (fraudSignals.length > 0) missing.push('NO_CRITICAL_FRAUD_SIGNAL');

  return { canRelease: missing.length === 0, missingSafeguards: missing, fraudSignals };
}

/**
 * Attempt to auto-release escrow for a delivered order that never got an OTP
 * within the inspection window. Authorizes release only if all safeguards pass.
 * Idempotent: does nothing if already released/completed.
 */
async function autoRelease({ orderId, triggeredBy = 'system' }) {
  const store = getStore();
  // Fail closed: an automatic sweep must never run concurrently with a manual
  // settlement just because Redis blipped.
  const lock = await requireLock(`autorelease:${orderId}`, 60);

  try {
    return await store.$transaction(async (tx) => {
      const order = await tx.order.findUnique({ where: { id: orderId } });
      if (!order) throw httpError(404, 'ORDER_NOT_FOUND');

      if (![ORDER_STATES.INSPECTION_PERIOD, ORDER_STATES.DELIVERED].includes(order.status)) {
        return { status: 'SKIPPED', reason: `STATE:${order.status}` };
      }

      const { canRelease, missingSafeguards, fraudSignals } = await evaluateAutoRelease(tx, orderId);
      if (!canRelease) {
        return { status: 'BLOCKED', missingSafeguards, fraudSignals: fraudSignals || [] };
      }

      // Everything checks out: authorize settlement (DELIVERY_CONFIRMED),
      // release escrow, then move to COMPLETED. The two-step keeps the
      // state machine honest — COMPLETED is only reachable from
      // DELIVERY_CONFIRMED, which carries the SETTLEMENT_AUTHORIZED rule.
      const stepOne = new OrderStateMachine(order.status);
      stepOne.transition(ORDER_STATES.DELIVERY_CONFIRMED, {
        actor: 'system',
        actorId: triggeredBy,
        reason: 'Auto-release: delivery verified after inspection window',
      });
      await tx.order.update({
        where: { id: orderId },
        data: { status: ORDER_STATES.DELIVERY_CONFIRMED, statusChangedBy: triggeredBy },
      });

      const stepTwo = new OrderStateMachine(ORDER_STATES.DELIVERY_CONFIRMED);
      stepTwo.transition(ORDER_STATES.COMPLETED, {
        actor: 'system',
        actorId: triggeredBy,
        reason: 'Auto-release after inspection window',
      });

      const completedOrder = await tx.order.update({
        where: { id: orderId },
        data: { status: ORDER_STATES.COMPLETED, completedAt: new Date() },
      });

      // Release escrow and settle (idempotent via releaseEscrowAndSettle).
      // The reason is explicit: AUTO_RELEASE may only touch a `holding` hold,
      // so a disputed order can never be paid out by the 14-day timer.
      const { releaseEscrowAndSettle } = require('../handover/handover-service');
      const released = await releaseEscrowAndSettle(tx, order, {
        reason: RELEASE_REASON.AUTO_RELEASE,
      });
      if (!released) {
        // Nothing eligible (the hold is disputed/refunded/absent). The order
        // state was already advanced above, so surface it rather than
        // pretending the money moved.
        return {
          status: 'NO_ELIGIBLE_ESCROW',
          order: completedOrder,
          missingSafeguards: ['NO_ELIGIBLE_ESCROW'],
        };
      }

      return { status: 'AUTO_RELEASED', order: completedOrder, missingSafeguards: [] };
    });
  } finally {
    if (lock.acquired) await releaseLock(`autorelease:${orderId}`, lock.token);
  }
}

function httpError(status, message) {
  const err = new Error(message);
  err.status = status;
  return err;
}

module.exports = {
  REQUIRED_SAFEGUARDS,
  hasVerifiedDelivery,
  evaluateFraudSignals,
  evaluateAutoRelease,
  autoRelease,
};
