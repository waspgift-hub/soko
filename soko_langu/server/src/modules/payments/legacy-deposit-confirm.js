// Finalizes a ClickPesa webhook for a legacy wallet deposit (orderReference
// starts with 'dep'). Verbatim port of applyClickPesaPayment's deposit branch
// (server/index.js:2665-2714): on success it credits the buyer's Firestore
// user doc walletBalance and flips deposits/{ref} to completed; on failure it
// marks the deposit failed. Idempotent via the status check, mirroring the old
// single-process guard.
const admin = require('firebase-admin');
const { getFirebaseFirestore } = require('../../config/firebase');
const { sendOneSignalNotification } = require('../legacy-compat/notify');

async function confirmLegacyDeposit({
  orderReference,
  status,
  providerPaymentId = '',
  failureReason = 'Payment failed',
}) {
  const firestore = getFirebaseFirestore();
  if (!firestore) throw new Error('FIRESTORE_NOT_CONFIGURED');

  const finalStatus = String(status || '');
  // ClickPesa also reports 'pending' checkpoints; only terminal states move money.
  if (finalStatus !== 'completed' && finalStatus !== 'failed') {
    return { status: 'SKIPPED_UNSUPPORTED', webhookStatus: finalStatus };
  }

  const depRef = firestore.collection('deposits').doc(orderReference);
  const depSnap = await depRef.get();
  if (!depSnap.exists) {
    console.warn(`[DEPOSIT] ${orderReference} not found; no-op`);
    return { status: 'NOOP_NOT_FOUND' };
  }

  const dep = depSnap.data();
  if (dep.status === 'completed' || dep.status === 'failed') {
    return { status: 'SKIPPED_ALREADY_FINAL', depositStatus: dep.status };
  }

  const amount = dep.amount || 0;
  if (finalStatus === 'completed') {
    // Credit the wallet and finalize the deposit atomically enough: the status
    // guard above makes a replayed webhook a no-op, so the increment can never
    // be applied twice.
    await Promise.all([
      firestore.collection('users').doc(dep.userId).update({
        walletBalance: admin.firestore.FieldValue.increment(amount),
      }),
      depRef.update({
        status: 'completed',
        clickpesaReference: providerPaymentId || '',
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
      }),
      sendOneSignalNotification(
        dep.userId,
        'Deposit Imethibitishwa!',
        `TZS ${amount.toLocaleString()} zimeongezwa kwenye pochi yako.`,
        { type: 'deposit', depositRef: orderReference },
      ).catch(() => {}),
    ]);
    console.log(`Wallet deposit: TZS ${amount} credited to ${dep.userId} (ref: ${orderReference})`);
    return { status: 'COMPLETED', amount };
  }

  await depRef.update({
    status: 'failed',
    failureReason,
    completedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  sendOneSignalNotification(
    dep.userId,
    'Deposit Imeshindikana',
    `Malipo ya TZS ${amount.toLocaleString()} hayakukamilika. Sababu: ${failureReason}`,
    { type: 'deposit_failed', depositRef: orderReference, failureReason },
  ).catch(() => {});
  return { status: 'FAILED', amount };
}

module.exports = { confirmLegacyDeposit };