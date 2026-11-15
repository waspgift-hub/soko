// Subscription renewal scheduler (in-process, Firebase-only, AzamPay).
const { getFirebaseFirestore } = require('../../config/firebase');
const billing = require('./billing');
const { planById } = require('./plans');
const service = require('./subscription-service');

const GRACE_DAYS = 3;

function db() { return getFirebaseFirestore(); }

async function runRenewals() {
  const d = db();
  if (!d) return { processed: 0 };
  const now = new Date();
  const snap = await d.collection('subscriptions').where('status', 'in', ['active', 'past_due', 'cancel_pending']).get();
  let processed = 0;
  for (const doc of snap.docs) {
    const sub = doc.data();
    const userId = sub.userId || doc.id;
    const plan = planById(sub.planId);
    if (!plan || plan.priceTzs <= 0) continue;
    const periodEnd = sub.currentPeriodEnd ? new Date(sub.currentPeriodEnd) : null;
    if (!periodEnd) continue;
    // cancel at period end
    if (sub.cancelAtPeriodEnd && periodEnd <= now) {
      await d.collection('subscriptions').doc(String(userId)).set({ status: 'expired', updatedAt: new Date() }, { merge: true });
      await service.resolveEntitlements(userId);
      processed++;
      continue;
    }
    // renewal due
    if (periodEnd <= now && sub.status === 'active') {
      // attempt: mark past_due; actual charge happens via user-initiated upgrade (AzamPay USSD)
      await d.collection('subscriptions').doc(String(userId)).set({ status: 'past_due', updatedAt: new Date() }, { merge: true });
      processed++;
      continue;
    }
    // grace expiry
    if (sub.status === 'past_due' && periodEnd) {
      const graceEnd = new Date(periodEnd.getTime() + GRACE_DAYS * 24 * 60 * 60 * 1000);
      if (now > graceEnd) {
        await d.collection('subscriptions').doc(String(userId)).set({ status: 'expired', updatedAt: new Date() }, { merge: true });
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
  // run every 6 hours
  timer = setInterval(() => { runRenewals().catch((e) => console.error('[SUB-RENEWAL]', e.message)); }, 6 * 60 * 60 * 1000);
  // initial run after 1 min
  setTimeout(() => { runRenewals().catch((e) => console.error('[SUB-RENEWAL]', e.message)); }, 60 * 1000);
}

function stopScheduler() {
  if (timer) { clearInterval(timer); timer = null; }
}

module.exports = { runRenewals, startScheduler, stopScheduler };