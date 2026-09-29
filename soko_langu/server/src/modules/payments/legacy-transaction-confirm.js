// Finalizes ClickPesa webhooks for legacy `transactions`-collection money:
// boost placements (type 'boost') and the one-time KYC verification fee
// (type 'kyc_fee'). These rows live outside the ecommerce `orders` table, so
// the escrow webhook path cannot settle them. Verbatim port of the
// applyClickPesaPayment success/failure branches (server/index.js:2738-2797 &
// 2939-2997). The deployed failStalePendingBoosts sweeper only covers stale
// USSD boosts after ~10min; real-time callbacks (and BillPay/KYC) needed the
// v1 webhook, which previously routed them to the order path and 404'd.
const admin = require('firebase-admin');
const { getFirebaseFirestore } = require('../../config/firebase');
const { sendOneSignalNotification } = require('../legacy-compat/notify');

const BOOST_TIERS = {
  bronze: { price: 1500, days: 3 },
  silver: { price: 3000, days: 7 },
  gold: { price: 10000, days: 30 },
};

function sessionTimestamp() {
  return admin.firestore.FieldValue.serverTimestamp();
}

async function addRevenue(firestore, data) {
  try {
    await firestore.collection('revenue_transactions').add({ ...data, createdAt: sessionTimestamp() });
  } catch (e) {
    console.error('[REVENUE]', data.type, e.message);
  }
}

async function confirmLegacyTransaction({
  orderReference,
  status,
  providerPaymentId = '',
  failureReason = 'Payment failed',
}) {
  const firestore = getFirebaseFirestore();
  if (!firestore) throw new Error('FIRESTORE_NOT_CONFIGURED');

  const finalStatus = String(status || '');
  // ClickPesa reports pending checkpoints too; only terminal states move money.
  if (finalStatus !== 'completed' && finalStatus !== 'failed') {
    return { status: 'SKIPPED_UNSUPPORTED', webhookStatus: finalStatus };
  }

  const txDoc = await firestore.collection('transactions').doc(orderReference).get();
  if (!txDoc.exists) {
    console.warn(`[TX] ${orderReference} not found in transactions; no-op`);
    return { status: 'NOOP_NOT_FOUND' };
  }
  const tx = txDoc.data();

  // Idempotency (same guard as the legacy router): finalized rows are skipped,
  // except a failed->completed recovery when ClickPesa later confirms success.
  if (tx.status === 'completed' || tx.status === 'escrow_hold') {
    return { status: 'SKIPPED_ALREADY_FINAL', txStatus: tx.status };
  }
  if (tx.status === 'failed' && finalStatus !== 'completed') {
    return { status: 'SKIPPED_ALREADY_FINAL', txStatus: tx.status };
  }

  if (finalStatus === 'failed') {
    await txDoc.ref.update({
      status: 'failed',
      failureReason,
      completedAt: sessionTimestamp(),
    });
    const notifyUserId = tx.userId || tx.buyerId;
    if (notifyUserId) {
      sendOneSignalNotification(
        notifyUserId,
        'Malipo Yameshindikana',
        `Malipo ya ${tx.productName || 'ada'} hayakukamilika. Sababu: ${failureReason}`,
        { type: 'payment_failed', transactionId: orderReference },
      ).catch(() => {});
    }
    return { status: 'FAILED', type: tx.type, notifyUserId };
  }

  if (tx.type === 'boost') {
    return boostSuccess(firestore, txDoc, tx, orderReference, providerPaymentId);
  }
  if (tx.type === 'kyc_fee') {
    return kycSuccess(firestore, txDoc, tx, orderReference, providerPaymentId);
  }
  return { status: 'SKIPPED_UNKNOWN_TYPE', txType: tx.type };
}

async function boostSuccess(firestore, txDoc, tx, orderId, providerPaymentId) {
  const tier = tx.tier || 'bronze';
  const tierConfig = BOOST_TIERS[tier] || BOOST_TIERS.bronze;
  const boostedUntil = new Date(Date.now() + tierConfig.days * 24 * 60 * 60 * 1000);

  // Atomic batch: both the transaction and the product-boost state commit
  // together or not at all — the exact "hela imeingia lakini hamna service"
  // bug this prevents in the legacy router.
  const batch = firestore.batch();
  batch.update(txDoc.ref, {
    status: 'completed',
    clickpesaReference: providerPaymentId || '',
    completedAt: sessionTimestamp(),
  });
  if (tx.productId) {
    batch.update(firestore.collection('products').doc(tx.productId), {
      isBoosted: true,
      boostedUntil: admin.firestore.Timestamp.fromDate(boostedUntil),
      boostTier: tier,
      isFeatured: true,
      featuredUntil: admin.firestore.Timestamp.fromDate(boostedUntil),
    });
  }

  try {
    await batch.commit();
    console.log(`[Boost] Atomic batch committed for ${orderId}`);
  } catch (batchErr) {
    // Both rolls back together; keep the transaction pending so the outbox
    // retry or the stale-boost sweeper re-applies it — never half-apply.
    console.error(`[Boost] Batch commit failed for ${orderId}:`, batchErr.message);
    return { status: 'COMPLETED_BATCH_FAILED' };
  }

  if (tx.userId) {
    sendOneSignalNotification(
      tx.userId,
      'Boost imewashwa!',
      `Bidhaa yako imepandishwa kwa daraja la ${tier} kwa siku ${tierConfig.days}.`,
      { type: 'boost', productId: tx.productId || '' },
    ).catch(() => {});
  }
  await addRevenue(firestore, {
    userId: 'platform',
    amount: tx.amount || tierConfig.price,
    sokoLanguCommission: tx.amount || tierConfig.price,
    type: 'boost',
    subType: tier,
    productId: tx.productId,
    transactionId: orderId,
    buyerPhone: tx.buyerPhone || '',
    paymentMethod: 'ClickPesa',
  });
  return { status: 'COMPLETED', type: 'boost' };
}

async function kycSuccess(firestore, txDoc, tx, orderId, providerPaymentId) {
  // The completed transaction doubles as the fee receipt:
  // kyc-service.hasPaidKycFee looks for exactly this shape, so the fee stays
  // paid across rejection/resubmission cycles (one time per seller).
  await txDoc.ref.update({
    status: 'completed',
    clickpesaReference: providerPaymentId || '',
    completedAt: sessionTimestamp(),
  });

  const feeAmount = tx.amount || 15000;
  await addRevenue(firestore, {
    userId: 'platform',
    amount: feeAmount,
    sokoLanguCommission: feeAmount,
    type: 'kyc_fee',
    description: 'KYC verification fee (one time)',
    transactionId: orderId,
    buyerPhone: tx.buyerPhone || '',
    paymentMethod: 'ClickPesa',
  });

  if (tx.userId) {
    sendOneSignalNotification(
      tx.userId,
      'Ada ya Uthibitisho Imelipwa!',
      `Malipo ya TZS ${feeAmount.toLocaleString()} yamepokelewa. Sasa tuma KYC yako kwa ukaguzi.`,
      { type: 'kyc_fee', orderId },
    ).catch(() => {});
  }
  return { status: 'COMPLETED', type: 'kyc_fee' };
}

module.exports = { confirmLegacyTransaction, BOOST_TIERS };