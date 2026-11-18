// Subscription renewal scheduler (in-process, Firebase-only, AzamPay).
//
// Reads the same collection as subscription-store.js. It previously queried
// `subscriptions`, a collection nothing writes to, so trials never expired and
// cancellations never took effect.

const { getFirebaseFirestore } = require('../../config/firebase');
const { planById, SUBSCRIPTION_STATUS } = require('./plans');
const { COLLECTIONS } = require('./subscription-store');
const service = require('./subscription-service');

const GRACE_DAYS = 3;

function db() { return getFirebaseFirestore(); }

async function runRenewals() {
  const d = db();
  if (!d) return { processed: 0 };
  const now = new Date();
  const snap = await d.collection(COLLECTIONS.subscriptions)
    .where('status', 'in', [
      SUBSCRIPTION_STATUS.ACTIVE,
      SUBSCRIPTION_STATUS.TRIALING,
      SUBSCRIPTION_STATUS.PAST_DUE,
      SUBSCRIPTION_STATUS.CANCEL_PENDING,
    ])
    .get();
  let processed = 0;
  for (const doc of snap.docs) {
    const sub = doc.data();
    const userId = sub.userId || doc.id;
    const plan = planById(sub.planId);
    if (!plan || plan.priceTzs <= 0) {
      // Expire a free trial whose plan is gone rather than leaving it usable.
      if (sub.status === SUBSCRIPTION_STATUS.TRIALING) {
        const trialEnd = sub.trialEndsAt ? new Date(sub.trialEndsAt) : null;
        if (trialEnd && trialEnd <= now) {
          await d.collection(COLLECTIONS.subscriptions).doc(String(userId))
            .set({ status: SUBSCRIPTION_STATUS.EXPIRED, updatedAt: new Date() }, { merge: true });
          await service.resolveEntitlements(userId);
          processed++;
        }
      }
      continue;
    }
    const periodEnd = sub.currentPeriodEnd ? new Date(sub.currentPeriodEnd) : null;

    // Trial end is independent of currentPeriodEnd: startTrial only sets
    // trialEndsAt, so this branch is what actually ends a 7-day trial.
    if (sub.status === SUBSCRIPTION_STATUS.TRIALING) {
      const trialEnd = sub.trialEndsAt ? new Date(sub.trialEndsAt) : null;
      if (trialEnd && trialEnd <= now) {
        await d.collection(COLLECTIONS.subscriptions).doc(String(userId))
          .set({ status: SUBSCRIPTION_STATUS.EXPIRED, updatedAt: new Date() }, { merge: true });
        await service.resolveEntitlements(userId);
        processed++;
      }
      continue;
    }

    if (!periodEnd) continue;

    if (sub.cancelAtPeriodEnd && periodEnd <= now) {
      await d.collection(COLLECTIONS.subscriptions).doc(String(userId))
        .set({ status: SUBSCRIPTION_STATUS.EXPIRED, updatedAt: new Date() }, { merge: true });
      await service.resolveEntitlements(userId);
      processed++;
      continue;
    }

    // A scheduled downgrade takes effect at the period boundary; the new plan's
    // entitlements are resolved by the same call so the app sees it immediately.
    if (sub.pendingDowngradePlanId && periodEnd <= now) {
      await d.collection(COLLECTIONS.subscriptions).doc(String(userId)).set({
        planId: sub.pendingDowngradePlanId,
        pendingDowngradePlanId: null,
        status: SUBSCRIPTION_STATUS.ACTIVE,
        updatedAt: new Date(),
      }, { merge: true });
      await service.resolveEntitlements(userId);
      processed++;
      continue;
    }

    if (periodEnd <= now && sub.status === SUBSCRIPTION_STATUS.ACTIVE) {
      // Charging is user-initiated (AzamPay USSD), so a due renewal becomes
      // past_due until the user pays again; grace expiry below ends access.
      await d.collection(COLLECTIONS.subscriptions).doc(String(userId))
        .set({ status: SUBSCRIPTION_STATUS.PAST_DUE, updatedAt: new Date() }, { merge: true });
      processed++;
      continue;
    }

    if (sub.status === SUBSCRIPTION_STATUS.PAST_DUE) {
      const graceEnd = new Date(periodEnd.getTime() + GRACE_DAYS * 24 * 60 * 60 * 1000);
      if (now > graceEnd) {
        await d.collection(COLLECTIONS.subscriptions).doc(String(userId))
          .set({ status: SUBSCRIPTION_STATUS.EXPIRED, updatedAt: new Date() }, { merge: true });
        await service.resolveEntitlements(userId);
        processed++;
      }
    }
  }
  return { processed };
}

let timer = null;
function startScheduler() {
  if (timer) return;
  timer = setInterval(() => { runRenewals().catch((e) => console.error('[SUB-RENEWAL]', e.message)); }, 6 * 60 * 60 * 1000);
  timer.unref?.();
  // initial run after 1 min
  const initial = setTimeout(() => { runRenewals().catch((e) => console.error('[SUB-RENEWAL]', e.message)); }, 60 * 1000);
  initial.unref?.();
}

function stopScheduler() {
  if (timer) { clearInterval(timer); timer = null; }
}

module.exports = { runRenewals, startScheduler, stopScheduler, GRACE_DAYS };
