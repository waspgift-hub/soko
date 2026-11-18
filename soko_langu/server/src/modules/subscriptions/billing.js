// Subscription billing via AzamPay (Firebase-only store).
//
// The subscription document lives in the SAME collection that
// subscription-store.js reads (`ai_subscriptions`). Keeping a local copy of the
// collection names here is how paid plans silently stopped being applied: the
// webhook wrote `subscriptions/*` while entitlement resolution read
// `ai_subscriptions/*`. Both sides now import the shared constant.

const azampay = require('../payments/azampay-provider');
const { getFirebaseFirestore } = require('../../config/firebase');
const { planById } = require('./plans');
const { resolveEntitlements } = require('./subscription-service');
const { COLLECTIONS: SUBSCRIPTION_COLLECTIONS } = require('./subscription-store');

const COLLECTIONS = {
  subscriptions: SUBSCRIPTION_COLLECTIONS.subscriptions,
  entitlements: SUBSCRIPTION_COLLECTIONS.entitlements,
  billingPayments: 'billing_payments',
};

const PERIOD_DAYS = 30;

function db() {
  const d = getFirebaseFirestore();
  if (!d) {
    const e = new Error('SUBSCRIPTION_STORE_UNAVAILABLE');
    e.status = 503;
    e.code = 'SUBSCRIPTION_STORE_UNAVAILABLE';
    throw e;
  }
  return d;
}

function fail(status, code) {
  const e = new Error(code);
  e.status = status;
  e.code = code;
  return e;
}

function isValidPhone(phone) {
  return typeof phone === 'string' && /^\+?[0-9]{9,15}$/.test(phone.replace(/[\s-]/g, ''));
}

async function initiateUpgrade({ userId, planId, phone }) {
  const plan = planById(planId);
  if (!plan || plan.priceTzs <= 0) throw fail(400, 'INVALID_PLAN');
  if (!isValidPhone(phone)) throw fail(400, 'INVALID_PHONE');
  const amount = plan.priceTzs;
  const orderRef = `sub_${userId}_${planId}_${Date.now()}`;
  const resp = await azampay.initiateCollection({
    amount,
    orderReference: orderRef,
    phoneNumber: phone,
    callbackUrl: process.env.AZAMPAY_CALLBACK_URL,
  });
  const d = db();
  await d.collection(COLLECTIONS.billingPayments).doc(orderRef).set({
    userId,
    planId,
    amount,
    currency: 'TZS',
    purpose: 'subscription_payment',
    status: 'pending',
    provider: 'azampay',
    providerRef: resp.providerReference || orderRef,
    createdAt: new Date(),
    updatedAt: new Date(),
  });
  await d.collection(COLLECTIONS.subscriptions).doc(String(userId)).set({
    userId,
    planId,
    status: 'pending_payment',
    providerRef: orderRef,
    updatedAt: new Date(),
  }, { merge: true });
  return { orderReference: orderRef, providerReference: resp.providerReference || orderRef };
}

/**
 * Applies a normalized provider result to a subscription payment.
 *
 * Split out from [handleWebhook] so the shared payments webhook can settle a
 * `sub_...` reference after it has already verified the provider signature.
 * Idempotent: a payment row that is already `completed` is a no-op.
 */
async function settlePayment({
  orderReference,
  status,
  providerPaymentId = null,
  amount = null,
  failureReason = null,
}) {
  const d = db();
  const payRef = d.collection(COLLECTIONS.billingPayments).doc(orderReference);
  const paySnap = await payRef.get();
  if (!paySnap.exists) throw fail(404, 'PAYMENT_NOT_FOUND');
  const pay = paySnap.data();
  if (pay.status === 'completed') return { alreadyProcessed: true };

  if (status === 'completed') {
    if (amount != null && Number(amount) !== Number(pay.amount)) {
      throw fail(400, 'AMOUNT_MISMATCH');
    }
    await payRef.set(
      { status: 'completed', providerPaymentId, updatedAt: new Date() },
      { merge: true },
    );
    const periodEnd = new Date(Date.now() + PERIOD_DAYS * 24 * 60 * 60 * 1000);
    await d.collection(COLLECTIONS.subscriptions).doc(String(pay.userId)).set({
      userId: pay.userId,
      planId: pay.planId,
      status: 'active',
      currentPeriodStart: new Date(),
      currentPeriodEnd: periodEnd,
      cancelAtPeriodEnd: false,
      pendingDowngradePlanId: null,
      lastPaymentId: orderReference,
      updatedAt: new Date(),
    }, { merge: true });
    await resolveEntitlements(pay.userId);
    return { success: true };
  }

  if (status === 'failed') {
    await payRef.set(
      {
        status: 'failed',
        failureReason: failureReason || 'Payment failed',
        updatedAt: new Date(),
      },
      { merge: true },
    );
    await d.collection(COLLECTIONS.subscriptions).doc(String(pay.userId)).set(
      { status: 'payment_failed', updatedAt: new Date() },
      { merge: true },
    );
    await resolveEntitlements(pay.userId);
    return { success: false };
  }

  return { status };
}

async function handleWebhook(payload, signature) {
  if (!azampay.verifyWebhook(payload, signature)) throw fail(401, 'INVALID_SIGNATURE');
  const norm = azampay.normalizeWebhook(payload);
  if (!norm.orderReference) throw fail(400, 'MISSING_REFERENCE');
  return settlePayment({
    orderReference: norm.orderReference,
    status: norm.status,
    providerPaymentId: norm.providerPaymentId,
    amount: norm.amount,
    failureReason: norm.failureReason,
  });
}

async function cancelSubscription(userId) {
  const d = db();
  const ref = d.collection(COLLECTIONS.subscriptions).doc(String(userId));
  const snap = await ref.get();
  if (!snap.exists) throw fail(404, 'SUBSCRIPTION_NOT_FOUND');
  const sub = snap.data();
  if (sub.status !== 'active' && sub.status !== 'trialing') {
    throw fail(409, 'SUBSCRIPTION_NOT_CANCELLABLE');
  }
  // Cancelling keeps entitlements until the paid period ends: billing has
  // already been collected for it, so cutting access now would be a refund.
  await ref.set({
    cancelAtPeriodEnd: true,
    status: 'cancel_pending',
    cancelledAt: new Date(),
    updatedAt: new Date(),
  }, { merge: true });
  return { success: true, effectiveAt: sub.currentPeriodEnd || sub.trialEndsAt || null };
}

async function resumeSubscription(userId) {
  const d = db();
  const ref = d.collection(COLLECTIONS.subscriptions).doc(String(userId));
  const snap = await ref.get();
  if (!snap.exists) throw fail(404, 'SUBSCRIPTION_NOT_FOUND');
  const sub = snap.data();
  if (sub.status !== 'cancel_pending') throw fail(409, 'SUBSCRIPTION_NOT_CANCELLABLE');
  const periodEnd = sub.currentPeriodEnd ? new Date(sub.currentPeriodEnd) : null;
  if (periodEnd && periodEnd.getTime() <= Date.now()) {
    throw fail(409, 'SUBSCRIPTION_PERIOD_ENDED');
  }
  await ref.set({
    cancelAtPeriodEnd: false,
    status: sub.trialEndsAt && !sub.currentPeriodEnd ? 'trialing' : 'active',
    updatedAt: new Date(),
  }, { merge: true });
  await resolveEntitlements(userId);
  return { success: true, status: 'active' };
}

async function downgradeSubscription(userId, newPlanId) {
  const plan = planById(newPlanId);
  if (!plan) throw fail(400, 'INVALID_PLAN');
  const d = db();
  const ref = d.collection(COLLECTIONS.subscriptions).doc(String(userId));
  const snap = await ref.get();
  if (!snap.exists) throw fail(404, 'SUBSCRIPTION_NOT_FOUND');
  // Applied at period end so the user keeps what they paid for. Upgrade (a
  // higher tier) goes through initiateUpgrade instead: it charges immediately.
  await ref.set({ pendingDowngradePlanId: newPlanId, updatedAt: new Date() }, { merge: true });
  return { success: true, effectiveAt: snap.data().currentPeriodEnd || null };
}

async function listInvoices(userId, limit = 20) {
  const d = db();
  const snap = await d
    .collection(COLLECTIONS.billingPayments)
    .where('userId', '==', String(userId))
    .orderBy('createdAt', 'desc')
    .limit(Math.min(Math.max(Number(limit) || 20, 1), 50))
    .get();
  return snap.docs.map((doc) => {
    const data = doc.data();
    return {
      id: doc.id,
      planId: data.planId || null,
      amount: Number(data.amount) || 0,
      currency: data.currency || 'TZS',
      status: data.status || 'pending',
      provider: data.provider || 'azampay',
      failureReason: data.failureReason || null,
      createdAt: data.createdAt?.toDate ? data.createdAt.toDate().toISOString() : data.createdAt || null,
    };
  });
}

module.exports = {
  initiateUpgrade,
  handleWebhook,
  settlePayment,
  cancelSubscription,
  resumeSubscription,
  downgradeSubscription,
  listInvoices,
  isValidPhone,
  COLLECTIONS,
};
