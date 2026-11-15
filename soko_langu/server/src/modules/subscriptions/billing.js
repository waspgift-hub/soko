// Subscription billing via AzamPay (Firebase-only store).
const azampay = require('../payments/azampay-provider');
const { getFirebaseFirestore } = require('../../config/firebase');
const { planById } = require('./plans');
const { resolveEntitlements } = require('./subscription-service');

const COLLECTIONS = {
  subscriptions: 'subscriptions',
  billingPayments: 'billing_payments',
  entitlements: 'entitlements',
};

function db() { return getFirebaseFirestore(); }

async function initiateUpgrade({ userId, planId, phone }) {
  const plan = planById(planId);
  if (!plan || plan.priceTzs <= 0) throw new Error('INVALID_PLAN');
  const amount = plan.priceTzs;
  const orderRef = `sub_${userId}_${planId}_${Date.now()}`;
  const resp = await azampay.initiateCollection({ amount, orderReference: orderRef, phoneNumber: phone, callbackUrl: process.env.AZAMPAY_CALLBACK_URL });
  // record pending payment
  const d = db();
  await d.collection(COLLECTIONS.billingPayments).doc(orderRef).set({
    userId, planId, amount, currency: 'TZS', purpose: 'subscription_payment',
    status: 'pending', provider: 'azampay', providerRef: resp.providerReference || orderRef,
    createdAt: new Date(), updatedAt: new Date(),
  });
  await d.collection(COLLECTIONS.subscriptions).doc(String(userId)).set({
    userId, planId, status: 'pending_payment', providerRef: orderRef,
    updatedAt: new Date(),
  }, { merge: true });
  return { orderReference: orderRef, providerReference: resp.providerReference || orderRef };
}

async function handleWebhook(payload, signature) {
  if (!azampay.verifyWebhook(payload, signature)) throw new Error('INVALID_SIGNATURE');
  const norm = azampay.normalizeWebhook(payload);
  if (!norm.orderReference) throw new Error('MISSING_REFERENCE');
  const d = db();
  const payRef = d.collection(COLLECTIONS.billingPayments).doc(norm.orderReference);
  const paySnap = await payRef.get();
  if (!paySnap.exists) throw new Error('PAYMENT_NOT_FOUND');
  const pay = paySnap.data();
  if (pay.status === 'completed') return { alreadyProcessed: true };
  const status = norm.status;
  if (status === 'completed') {
    // verify amount
    if (norm.amount != null && Number(norm.amount) !== Number(pay.amount)) throw new Error('AMOUNT_MISMATCH');
    await payRef.set({ status: 'completed', providerPaymentId: norm.providerPaymentId, updatedAt: new Date() }, { merge: true });
    const periodEnd = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);
    await d.collection(COLLECTIONS.subscriptions).doc(String(pay.userId)).set({
      userId: pay.userId, planId: pay.planId, status: 'active',
      currentPeriodStart: new Date(), currentPeriodEnd: periodEnd,
      lastPaymentId: norm.orderReference, updatedAt: new Date(),
    }, { merge: true });
    await resolveEntitlements(pay.userId);
    return { success: true };
  }
  if (status === 'failed') {
    await payRef.set({ status: 'failed', failureReason: norm.failureReason, updatedAt: new Date() }, { merge: true });
    await d.collection(COLLECTIONS.subscriptions).doc(String(pay.userId)).set({ status: 'payment_failed', updatedAt: new Date() }, { merge: true });
    return { success: false };
  }
  return { status };
}

async function cancelSubscription(userId) {
  const d = db();
  const ref = d.collection(COLLECTIONS.subscriptions).doc(String(userId));
  const snap = await ref.get();
  if (!snap.exists) throw new Error('SUBSCRIPTION_NOT_FOUND');
  await ref.set({ cancelAtPeriodEnd: true, status: 'cancel_pending', updatedAt: new Date() }, { merge: true });
  return { success: true };
}

async function downgradeSubscription(userId, newPlanId) {
  const plan = planById(newPlanId);
  if (!plan) throw new Error('INVALID_PLAN');
  const d = db();
  const ref = d.collection(COLLECTIONS.subscriptions).doc(String(userId));
  const snap = await ref.get();
  if (!snap.exists) throw new Error('SUBSCRIPTION_NOT_FOUND');
  // Apply at period end: mark pending downgrade; entitlements stay until period ends.
  await ref.set({ pendingDowngradePlanId: newPlanId, updatedAt: new Date() }, { merge: true });
  return { success: true, effectiveAt: snap.data().currentPeriodEnd || null };
}

module.exports = { initiateUpgrade, handleWebhook, cancelSubscription, downgradeSubscription };