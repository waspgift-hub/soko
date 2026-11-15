// AI credit wallet (Firebase-only). Credits are purchased via AzamPay and spent
// by the AI agent. Ledger is append-only.
const { getFirebaseFirestore } = require('../../../config/firebase');
const azampay = require('../../payments/azampay-provider');

const C = {
  accounts: 'ai_credit_accounts',
  ledger: 'ai_credit_ledger',
  payments: 'billing_payments',
};

function db() { return getFirebaseFirestore(); }

async function getBalance(userId) {
  const snap = await db().collection(C.accounts).doc(String(userId)).get();
  if (!snap.exists) return { available: 0, reserved: 0 };
  const d = snap.data();
  return { available: Number(d.available || 0), reserved: Number(d.reserved || 0) };
}

async function topUp({ userId, packageId, phone }) {
  const pkg = { starter: { credits: 100, price: 1000 }, value: { credits: 550, price: 5000 }, growth: { credits: 1150, price: 10000 }, business: { credits: 3000, price: 25000 } }[packageId];
  if (!pkg) throw new Error('INVALID_PACKAGE');
  const orderRef = `aic_${userId}_${packageId}_${Date.now()}`;
  const resp = await azampay.initiateCollection({ amount: pkg.price, orderReference: orderRef, phoneNumber: phone });
  await db().collection(C.payments).doc(orderRef).set({
    userId, purpose: 'ai_credit_topup', packageId, credits: pkg.credits, amount: pkg.price,
    currency: 'TZS', status: 'pending', provider: 'azampay', providerRef: resp.providerReference || orderRef,
    createdAt: new Date(), updatedAt: new Date(),
  });
  return { orderReference: orderRef, providerReference: resp.providerReference || orderRef, credits: pkg.credits, amount: pkg.price };
}

async function handleTopUpWebhook(payload, signature) {
  if (!azampay.verifyWebhook(payload, signature)) throw new Error('INVALID_SIGNATURE');
  const norm = azampay.normalizeWebhook(payload);
  if (!norm.orderReference) throw new Error('MISSING_REFERENCE');
  const d = db();
  const payRef = d.collection(C.payments).doc(norm.orderReference);
  const paySnap = await payRef.get();
  if (!paySnap.exists) throw new Error('PAYMENT_NOT_FOUND');
  const pay = paySnap.data();
  if (pay.status === 'completed') return { alreadyProcessed: true };
  if (norm.status !== 'completed') {
    if (norm.status === 'failed') await payRef.set({ status: 'failed', updatedAt: new Date() }, { merge: true });
    return { status: norm.status };
  }
  if (norm.amount != null && Number(norm.amount) !== Number(pay.amount)) throw new Error('AMOUNT_MISMATCH');
  await payRef.set({ status: 'completed', providerPaymentId: norm.providerPaymentId, updatedAt: new Date() }, { merge: true });
  // credit account + ledger
  const accRef = d.collection(C.accounts).doc(String(pay.userId));
  const accSnap = await accRef.get();
  const prev = accSnap.exists ? Number(accSnap.data().available || 0) : 0;
  const newBal = prev + Number(pay.credits);
  await accRef.set({ userId: pay.userId, available: newBal, reserved: accSnap.exists ? Number(accSnap.data().reserved || 0) : 0, updatedAt: new Date() }, { merge: true });
  await d.collection(C.ledger).add({
    userId: pay.userId, type: 'purchase', amount: Number(pay.credits), balanceAfter: newBal,
    referenceType: 'billing_payment', referenceId: norm.orderReference, idempotencyKey: `topup_${norm.orderReference}`,
    description: `AI credit top-up (${pay.packageId})`, createdAt: new Date(),
  });
  return { success: true, credits: pay.credits };
}

async function debit({ userId, amount, referenceType, referenceId, idempotencyKey }) {
  const d = db();
  const accRef = d.collection(C.accounts).doc(String(userId));
  const accSnap = await accRef.get();
  const avail = accSnap.exists ? Number(accSnap.data().available || 0) : 0;
  if (avail < amount) throw new Error('INSUFFICIENT_CREDITS');
  const newBal = avail - amount;
  await accRef.set({ available: newBal, updatedAt: new Date() }, { merge: true });
  await d.collection(C.ledger).add({
    userId, type: 'debit', amount: -Number(amount), balanceAfter: newBal,
    referenceType, referenceId, idempotencyKey, description: 'AI usage', createdAt: new Date(),
  });
  return { balance: newBal };
}

async function getLedger(userId, limit = 50) {
  const snap = await db().collection(C.ledger).where('userId', '==', String(userId)).orderBy('createdAt', 'desc').limit(limit).get();
  return snap.docs.map((x) => ({ id: x.id, ...x.data() }));
}

module.exports = { getBalance, topUp, handleTopUpWebhook, debit, getLedger };