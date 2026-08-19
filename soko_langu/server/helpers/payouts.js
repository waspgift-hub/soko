const clickpesaPayout = require('../clickpesa').clickpesaPayout;

module.exports = function ({ admin, db }) {
  function generatePayoutReference(prefix = 'po') {
    return `${prefix}${Date.now().toString(36)}${Math.random().toString(36).substring(2, 8)}`;
  }

  const PAYOUT_RETRY_MAX = 3;
  const PAYOUT_STATUSES = { PENDING: 'pending', PROCESSING: 'processing', SUCCESS: 'success', FAILED: 'failed', REFUNDED: 'refunded', REVERSED: 'reversed' };

  async function createPayoutRecord({ userId, phone, amount, fee, netAmount, source, type, metadata }) {
    const payoutId = generatePayoutReference();
    const now = admin.firestore.FieldValue.serverTimestamp();
    const record = {
      payoutId,
      userId,
      userPhone: phone,
      amount: Math.round(amount),
      fee: Math.round(fee),
      netAmount: Math.round(netAmount),
      status: PAYOUT_STATUSES.PENDING,
      type,
      source: source || '',
      retryCount: 0,
      maxRetries: PAYOUT_RETRY_MAX,
      createdAt: now,
      updatedAt: now,
      metadata: metadata || {},
    };
    await db.collection('payouts').doc(payoutId).set(record);
    return payoutId;
  }

  async function updatePayoutStatus(payoutId, status, extra = {}) {
    if (!db || !payoutId) return;
    const updates = { status, updatedAt: admin.firestore.FieldValue.serverTimestamp(), ...extra };
    if (status === PAYOUT_STATUSES.SUCCESS || status === PAYOUT_STATUSES.FAILED) {
      updates.completedAt = admin.firestore.FieldValue.serverTimestamp();
    }
    await db.collection('payouts').doc(payoutId).update(updates);
  }

  async function processPayout({ payoutId, userId, phone, amount, fee, netAmount, source, type, metadata }) {
    if (!payoutId) {
      payoutId = await createPayoutRecord({ userId, phone, amount, fee, netAmount, source, type, metadata });
    }
    await updatePayoutStatus(payoutId, PAYOUT_STATUSES.PROCESSING);

    if (type === 'seller_withdrawal' && db) {
      await db.collection('transactions').doc(payoutId).set({
        type: 'seller_withdrawal',
        userId,
        userPhone: phone,
        amount: Math.round(amount),
        fee: Math.round(fee),
        netAmount: Math.round(netAmount),
        status: 'PENDING',
        paymentMethod: 'ClickPesa',
        source: source || '',
        metadata: metadata || {},
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    const result = await clickpesaPayout({
      amount: netAmount,
      phoneNumber: phone,
      orderReference: payoutId,
    });

    // ClickPesa accepted the request — leave the payout in PROCESSING. The
    // provider's payout webhook is the source of truth and transitions it to
    // SUCCESS or FAILED. Marking SUCCESS here would falsely report money sent
    // before the provider actually disburses it.
    const clickpesaRef = result.id || result.orderReference || '';
    await updatePayoutStatus(payoutId, PAYOUT_STATUSES.PROCESSING, { clickpesaReference: clickpesaRef });

    return { payoutId, clickpesaReference: clickpesaRef, netAmount, fee };
  }

  async function retryFailedPayout(payoutId) {
    const doc = await db.collection('payouts').doc(payoutId).get();
    if (!doc.exists) throw new Error('Payout not found');
    const payout = doc.data();
    if (payout.status !== PAYOUT_STATUSES.FAILED) throw new Error(`Cannot retry payout with status: ${payout.status}`);
    if (payout.retryCount >= payout.maxRetries) throw new Error('Max retries reached');

    await db.collection('payouts').doc(payoutId).update({
      retryCount: admin.firestore.FieldValue.increment(1),
      failureReason: '',
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return processPayout({
      payoutId, userId: payout.userId, phone: payout.userPhone,
      amount: payout.amount, fee: payout.fee, netAmount: payout.netAmount,
      source: payout.source, type: payout.type, metadata: payout.metadata,
    });
  }

  async function auditLog({ userId, type, amount, balanceBefore, balanceAfter, reason, relatedId, metadata }) {
    if (!db) return;
    try {
      await db.collection('audit_log').add({
        userId,
        type,
        amount,
        balanceBefore: balanceBefore ?? 0,
        balanceAfter: balanceAfter ?? 0,
        reason: reason || '',
        relatedId: relatedId || '',
        metadata: metadata || {},
        ip: '',
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (e) {
      console.error('Audit log error:', e);
    }
  }

  return {
    generatePayoutReference,
    PAYOUT_RETRY_MAX,
    PAYOUT_STATUSES,
    createPayoutRecord,
    updatePayoutStatus,
    processPayout,
    retryFailedPayout,
    auditLog,
  };
};
