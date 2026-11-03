// Finalizes a ClickPesa webhook for a legacy wallet deposit (orderReference
// starts with 'dep'). Verbatim port of applyClickPesaPayment's deposit branch
// (server/index.js:2665-2714): on success it credits the buyer's Firestore
// user doc walletBalance and flips deposits/{ref} to completed; on failure it
// marks the deposit failed. Idempotent via the status check, mirroring the old
// single-process guard.
const commerceStore = require('../../services/commerce-store');
const { sendOneSignalNotification } = require('../legacy-compat/notify');
const { sendSms } = require('../../services/sms-service');
const { sendMail } = require('../../services/mailer');
const { renderEmail } = require('../../services/email-layout');

// Deposit notices go out by email only. SMS stays disabled until the sender
// ID and credit are sorted; the code is kept so it can be switched back on.
const SMS_NOTIFICATIONS_ENABLED = false;

// Fire-and-forget from the caller: a delivery failure must never block or roll
// back the wallet credit, so each channel is isolated with allSettled.
async function notifyDepositOutcome({ dep, orderReference, status, channel, failureReason }) {
  const user = await commerceStore.getDocument('users', dep.userId).catch(() => null);
  const amountText = `TZS ${Number(dep.amount || 0).toLocaleString('en-US')}`;
  const ok = status === 'completed';
  const smsText = ok
    ? `Soko Vibe: Malipo ya ${amountText} yamepokelewa. Salio la pochi yako limeongezeka. Kumbukumbu: ${orderReference}`
    : `Soko Vibe: Malipo ya ${amountText} hayakukamilika. Jaribu tena kwenye app. Kumbukumbu: ${orderReference}`;
  const subject = ok ? `Malipo yamepokelewa: ${amountText}` : `Malipo hayakukamilika: ${amountText}`;
  const name = user?.displayName || user?.name || '';
  const maskedPhone = dep.phone ? `***${String(dep.phone).slice(-4)}` : '-';
  const date = new Date().toLocaleString('en-GB', { timeZone: 'Africa/Dar_es_Salaam' });
  const html = renderEmail({
    lang: 'sw',
    preheader: ok ? `${amountText} imeongezwa kwenye pochi yako` : `Malipo ya ${amountText} hayakukamilika`,
    title: ok ? 'Malipo yamepokelewa' : 'Malipo hayakukamilika',
    paragraphs: [
      `Habari${name ? ` ${name}` : ''}.`,
      ok
        ? 'Salio la pochi yako limeongezeka. Unaweza kulitumia kulipia bidhaa au kutoa fedha.'
        : 'Hatukuweza kukamilisha malipo yako. Unaweza kujaribu tena kutoka kwenye app.',
    ],
    rows: [
      { label: 'Kiasi', value: amountText },
      { label: 'Njia ya malipo', value: channel || 'Mobile money (USSD)' },
      { label: 'Namba ya simu', value: maskedPhone },
      { label: 'Kumbukumbu', value: orderReference },
      { label: 'Tarehe', value: `${date} (EAT)` },
      ...(ok ? [] : [{ label: 'Sababu', value: failureReason || 'Haijulikani' }]),
    ],
    cta: { label: ok ? 'Fungua Soko Vibe' : 'Jaribu tena', path: '/' },
  });

  await Promise.allSettled([
    SMS_NOTIFICATIONS_ENABLED && dep.phone ? sendSms(dep.phone, smsText) : Promise.resolve(false),
    user?.email ? sendMail(user.email, subject, html) : Promise.resolve(false),
  ]);
}

async function confirmLegacyDeposit({
  orderReference,
  status,
  providerPaymentId = '',
  failureReason = 'Payment failed',
  channel = '',
}) {
  const finalStatus = String(status || '');
  // ClickPesa also reports 'pending' checkpoints; only terminal states move money.
  if (finalStatus !== 'completed' && finalStatus !== 'failed') {
    return { status: 'SKIPPED_UNSUPPORTED', webhookStatus: finalStatus };
  }

  const dep = await commerceStore.getDocument('deposits', orderReference);
  if (!dep) {
    console.warn(`[DEPOSIT] ${orderReference} not found; no-op`);
    return { status: 'NOOP_NOT_FOUND' };
  }

  if (dep.status === 'completed' || dep.status === 'failed') {
    return { status: 'SKIPPED_ALREADY_FINAL', depositStatus: dep.status };
  }

  const amount = dep.amount || 0;
  if (finalStatus === 'completed') {
    // Credit the wallet and finalize the deposit atomically enough: the status
    // guard above makes a replayed webhook a no-op, so the increment can never
    // be applied twice.
    await Promise.all([
      commerceStore.updateDocument('users', dep.userId, {
        walletBalance: commerceStore.increment(amount),
      }),
      commerceStore.updateDocument('deposits', orderReference, {
        status: 'completed',
        clickpesaReference: providerPaymentId || '',
        completedAt: commerceStore.serverTimestamp(),
      }),
      sendOneSignalNotification(
        dep.userId,
        'Deposit Imethibitishwa!',
        `TZS ${amount.toLocaleString()} zimeongezwa kwenye pochi yako.`,
        { type: 'deposit', depositRef: orderReference },
      ).catch(() => {}),
    ]);
    console.log(`Wallet deposit: TZS ${amount} credited to ${dep.userId} (ref: ${orderReference})`);
    notifyDepositOutcome({ dep, orderReference, status: 'completed', channel }).catch((e) =>
      console.error('[DEPOSIT] notify failed:', e.message));
    return { status: 'COMPLETED', amount };
  }

  await commerceStore.updateDocument('deposits', orderReference, {
    status: 'failed',
    failureReason,
    completedAt: commerceStore.serverTimestamp(),
  });
  notifyDepositOutcome({ dep, orderReference, status: 'failed', channel, failureReason }).catch((e) =>
    console.error('[DEPOSIT] notify failed:', e.message));
  sendOneSignalNotification(
    dep.userId,
    'Deposit Imeshindikana',
    `Malipo ya TZS ${amount.toLocaleString()} hayakukamilika. Sababu: ${failureReason}`,
    { type: 'deposit_failed', depositRef: orderReference, failureReason },
  ).catch(() => {});
  return { status: 'FAILED', amount };
}

module.exports = { confirmLegacyDeposit };