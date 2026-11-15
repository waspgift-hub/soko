// Credit-aware AI agent runner. Reserves credits before execution, debits after.
const creditService = require('../credits/credit-service');
const aiGateway = require('../ai-gateway');
const { getFirebaseFirestore } = require('../../../config/firebase');

const CREDITS_PER_1K_TOKENS = 2; // configurable pricing

async function runAgent({ userId, prompt, maxCredits = 50, model = 'llama-3.3-70b-versatile' }) {
  if (!prompt || typeof prompt !== 'string') throw new Error('INVALID_PROMPT');
  maxCredits = Math.max(1, Math.min(Number(maxCredits) || 50, 500));

  const balance = await creditService.getBalance(userId);
  if (balance.available < 1) throw new Error('INSUFFICIENT_CREDITS');

  const budget = Math.min(maxCredits, balance.available);

  // estimate tokens: rough 4 chars per token
  const estTokens = Math.ceil(prompt.length / 4) + 500;
  const estCredits = Math.max(1, Math.ceil((estTokens / 1000) * CREDITS_PER_1K_TOKENS));
  if (estCredits > budget) throw new Error('BUDGET_TOO_SMALL');

  // reserve
  const d = getFirebaseFirestore();
  const resRef = await d.collection('ai_credit_reservations').add({
    userId, amount: estCredits, status: 'reserved', expiresAt: new Date(Date.now() + 10 * 60 * 1000), createdAt: new Date(),
  });
  const accSnap = await d.collection('ai_credit_accounts').doc(String(userId)).get();
  const avail = accSnap.exists ? Number(accSnap.data().available || 0) : 0;
  await d.collection('ai_credit_accounts').doc(String(userId)).set({ available: avail - estCredits, reserved: (accSnap.exists ? Number(accSnap.data().reserved || 0) : 0) + estCredits, updatedAt: new Date() }, { merge: true });

  let result;
  let actualCredits = estCredits;
  try {
    const r = await aiGateway.chat({ model, messages: [{ role: 'user', content: prompt }], max_tokens: 1024 });
    const text = r.text || '';
    const outTokens = Math.ceil(text.length / 4);
    const totalTokens = estTokens + outTokens;
    actualCredits = Math.max(1, Math.ceil((totalTokens / 1000) * CREDITS_PER_1K_TOKENS));
    actualCredits = Math.min(actualCredits, budget);
    result = { text, provider: r.provider, tokens: totalTokens };
  } catch (e) {
    // release reservation
    await d.collection('ai_credit_reservations').doc(resRef.id).set({ status: 'released' }, { merge: true });
    const accSnap2 = await d.collection('ai_credit_accounts').doc(String(userId)).get();
    const avail2 = accSnap2.exists ? Number(accSnap2.data().available || 0) : 0;
    const res2 = accSnap2.exists ? Number(accSnap2.data().reserved || 0) : 0;
    await d.collection('ai_credit_accounts').doc(String(userId)).set({ available: avail2 + estCredits, reserved: Math.max(0, res2 - estCredits), updatedAt: new Date() }, { merge: true });
    throw e;
  }

  // settle: debit actual, release remainder
  const remainder = estCredits - actualCredits;
  await creditService.debit({ userId, amount: actualCredits, referenceType: 'ai_usage', referenceId: resRef.id, idempotencyKey: `agent_${resRef.id}` });
  await d.collection('ai_credit_reservations').doc(resRef.id).set({ status: 'settled', settledCredits: actualCredits }, { merge: true });
  if (remainder > 0) {
    const accSnap3 = await d.collection('ai_credit_accounts').doc(String(userId)).get();
    const res3 = accSnap3.exists ? Number(accSnap3.data().reserved || 0) : 0;
    await d.collection('ai_credit_accounts').doc(String(userId)).set({ reserved: Math.max(0, res3 - remainder), updatedAt: new Date() }, { merge: true });
  }
  // usage event
  await d.collection('ai_usage_events').add({
    userId, creditsCharged: actualCredits, model, prompt: prompt.slice(0, 200), createdAt: new Date(),
  });
  return { ...result, creditsCharged: actualCredits, budget };
}

module.exports = { runAgent };