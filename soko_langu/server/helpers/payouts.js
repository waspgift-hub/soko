const clickpesaPayout = require('../clickpesa').clickpesaPayout;

module.exports = function ({ commerceStore }) {
  function generatePayoutReference(prefix = 'po') {
    return `${prefix}${Date.now().toString(36)}${Math.random().toString(36).substring(2, 8)}`;
  }

  const PAYOUT_RETRY_MAX = 3;
  const PAYOUT_STATUSES = { PENDING: 'pending', PROCESSING: 'processing', SUCCESS: 'success', FAILED: 'failed', REFUNDED: 'refunded', REVERSED: 'reversed' };

  async function createPayoutRecord({ userId, phone, amount, fee, netAmount, source, type, metadata }) {
    const payoutId = generatePayoutReference();
    const now = commerceStore.serverTimestamp;
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
    await commerceStore.setDocument('payouts', payoutId, record);
    return payoutId;
  }

  async function updatePayoutStatus(payoutId, status, extra = {}) {
    if (!payoutId) return;
    const updates = { status, updatedAt: commerceStore.serverTimestamp, ...extra };
    if (status === PAYOUT_STATUSES.SUCCESS || status === PAYOUT_STATUSES.FAILED) {
      updates.completedAt = commerceStore.serverTimestamp;
    }
    await commerceStore.updateDocument('payouts', payoutId, updates);
  }

  async function processPayout({ payoutId, userId, phone, amount, fee, netAmount, source, type, metadata }) {
    if (!payoutId) {
      payoutId = await createPayoutRecord({ userId, phone, amount, fee, netAmount, source, type, metadata });
    }
    await updatePayoutStatus(payoutId, PAYOUT_STATUSES.PROCESSING);

    if (type === 'seller_withdrawal') {
      await commerceStore.setDocument('transactions', payoutId, {
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
        createdAt: commerceStore.serverTimestamp,
      });
    }

    const result = await clickpesaPayout({
      amount: netAmount,
      phoneNumber: phone,
      orderReference: payoutId,
    });

    const clickpesaRef = result.id || result.orderReference || '';
    await updatePayoutStatus(payoutId, PAYOUT_STATUSES.PROCESSING, { clickpesaReference: clickpesaRef });

    return { payoutId, clickpesaReference: clickpesaRef, netAmount, fee };
  }

  async function retryFailedPayout(payoutId) {
    const payout = await commerceStore.getDocument('payouts', payoutId);
    if (!payout) throw new Error('Payout not found');
    if (payout.status !== PAYOUT_STATUSES.FAILED) throw new Error(`Cannot retry payout with status: ${payout.status}`);
    if (payout.retryCount >= payout.maxRetries) throw new Error('Max retries reached');

    await commerceStore.updateDocument('payouts', payoutId, {
      retryCount: commerceStore.increment(1),
      failureReason: '',
      updatedAt: commerceStore.serverTimestamp,
    });
    return processPayout({
      payoutId, userId: payout.userId, phone: payout.userPhone,
      amount: payout.amount, fee: payout.fee, netAmount: payout.netAmount,
      source: payout.source, type: payout.type, metadata: payout.metadata,
    });
  }

  async function auditLog({ userId, type, amount, balanceBefore, balanceAfter, reason, relatedId, metadata }) {
    try {
      await commerceStore.addDocument('audit_log', {
        userId,
        type,
        amount,
        balanceBefore: balanceBefore ?? 0,
        balanceAfter: balanceAfter ?? 0,
        reason: reason || '',
        relatedId: relatedId || '',
        metadata: metadata || {},
        ip: '',
        timestamp: commerceStore.serverTimestamp,
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
