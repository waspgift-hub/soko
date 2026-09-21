// KYC application store (Phase D bridge). One row per user mirrors the
// embedded Firestore users/{uid}.kyc doc that is the current source of truth.
// userId is the Firebase UID (opaque), so the row exists even before the
// Postgres users backfill and while the app-admin panel still reads Firestore.
const { getPrisma } = require('../../config/database');
const { getFirebaseFirestore } = require('../../config/firebase');
const { sendOneSignalNotification, notifyAdmins } = require('../legacy-compat/notify');
const { clickpesaCollect, clickpesaCreateBillPayOrder, calcGatewayFee } = require('../../../clickpesa');
// Contact (phone/email) verification OTPs reuse the same store the auth login
// flow uses, so a seller never has two unrelated OTP systems. SMS goes through
// the real sms-service (Meseji → Notify Africa); email through the SMTP mailer.
const { saveOtp, getOtp, markUsed, bumpAttempts } = require('../../services/otp-store');
const smsService = require('../../services/sms-service');
const { sendMail } = require('../../services/mailer');

const crypto = require('crypto');

// One-time seller verification fee (TSh). The fee is paid BEFORE submission via
// ClickPesa (kyc_fee transaction); resubmissions after rejection never re-charge.
const KYC_FEE_AMOUNT = 15000;

function httpError(status, code, message) {
  const e = new Error(message);
  e.status = status;
  e.code = code;
  return e;
}

// Date of birth travels as a bare calendar date (YYYY-MM-DD) so it never picks
// up timezone drift; anything longer than 10 chars is rejected, not repaired.
const DOB_RE = /^\d{4}-\d{2}-\d{2}$/;

function toPublic(row) {
  if (!row) return null;
  return {
    fullName: row.fullName,
    firstName: row.firstName,
    middleName: row.middleName,
    lastName: row.lastName,
    idType: row.idType,
    idNumber: row.idNumber,
    idImageUrl: row.idImageUrl,
    selfieUrl: row.selfieUrl,
    dateOfBirth: row.dateOfBirth,
    address: row.address,
    phone: row.phone,
    email: row.email,
    shopVideoUrl: row.shopVideoUrl,
    feeAmount: row.feeAmount,
    feeReference: row.feeReference,
    feePaidAt: row.feePaidAt ? row.feePaidAt.toISOString() : null,
    status: row.status,
    approved: row.approved,
    reviewNotes: row.reviewNotes,
    submittedAt: row.submittedAt ? row.submittedAt.toISOString() : null,
    reviewedAt: row.reviewedAt ? row.reviewedAt.toISOString() : null,
    revokedAt: row.revokedAt ? row.revokedAt.toISOString() : null,
  };
}

/** The caller's current KYC status (or the legacy 'none' shape). */
async function getStatus({ userId }) {
  const prisma = getPrisma();
  const row = await prisma.kycApplication.findUnique({ where: { userId } });
  return row ? toPublic(row) : { status: 'none', approved: false };
}

// Validation keeps the legacy contract: submissions always land in 'pending'
// and problems surface in reviewNotes, they never hard-fail. The fee is the
// one exception (a payment gate, not a data-quality issue). The idType switch
// keys are the legacy labels; the Flutter app sends kyc_id_* values which
// therefore skip the format branch (exactly as before).
function validateSubmission({ fullName, firstName, middleName, lastName, idType, idNumber, idImageUrl, selfieUrl, dateOfBirth, address, phone, email, shopVideoUrl }) {
  const errors = [];
  const nameParts = (fullName || '').trim().split(/\s+/);
  if (nameParts.length < 2) errors.push('Jina kamili linahitaji angalau majina mawili');
  if (!firstName) errors.push('Jina la kwanza linahitajika');
  if (!middleName) errors.push('Jina la kati linahitajika');
  if (!lastName) errors.push('Jina la ukoo linahitajika');
  if (!idImageUrl) errors.push('Picha ya pasipoti haijapakiwa');
  if (!selfieUrl) errors.push('Selfie haijapakiwa');
  if (!shopVideoUrl) errors.push('Video ya duka haijapakiwa');
  if (!dateOfBirth) {
    errors.push('Tarehe ya kuzaliwa inahitajika');
  } else if (!DOB_RE.test(String(dateOfBirth))) {
    errors.push('Tarehe ya kuzaliwa inatakiwa kuwa YYYY-MM-DD');
  } else {
    const dob = new Date(`${dateOfBirth}T00:00:00Z`);
    const age = (Date.now() - dob.getTime()) / (365.25 * 24 * 60 * 60 * 1000);
    if (Number.isNaN(dob.getTime()) || age < 0) errors.push('Tarehe ya kuzaliwa si sahihi');
    else if (age < 18) errors.push('Muuzaji anatakiwa kuwa na miaka 18 au zaidi');
  }
  if (!address) errors.push('Anwani inahitajika');
  if (!phone) errors.push('Namba ya simu inahitajika');
  if (!email || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(String(email))) errors.push('Barua pepe halali inahitajika');
  const cleanId = String(idNumber || '').replace(/\s/g, '');
  switch (idType) {
    case 'National ID':
      if (!/^\d{20}$/.test(cleanId)) errors.push('Namba ya National ID inatakiwa kuwa na tarakimu 20');
      break;
    case 'Passport':
      if (cleanId.length < 6) errors.push('Namba ya Passport inatakiwa kuwa na angalau herufi 6');
      break;
    case 'Drivers License':
      if (cleanId.length < 6) errors.push('Namba ya Drivers License inatakiwa kuwa na angalau herufi 6');
      break;
    case 'Voters ID':
      if (cleanId.length < 6) errors.push('Namba ya Voters ID inatakiwa kuwa na angalau herufi 6');
      break;
  }
  return { errors, cleanId, reason: errors.length ? errors.join('; ') : 'Inahitaji ukaguzi wa admin' };
}

// ---------------------------------------------------------------------------
// One-time verification fee (ClickPesa). The Firestore kyc_fee transaction is
// the source of truth so a paid fee survives rejection + resubmission cycles
// ("one time" means per seller, not per application attempt).
// ---------------------------------------------------------------------------

async function hasPaidKycFee(userId) {
  const store = getFirebaseFirestore();
  if (!store || !userId) return { paid: false };
  const snap = await store.collection('transactions')
    .where('type', '==', 'kyc_fee')
    .where('userId', '==', userId)
    .where('status', '==', 'completed')
    .limit(1)
    .get();
  if (snap.empty) return { paid: false };
  const doc = snap.docs[0];
  const completedAt = doc.data().completedAt;
  return {
    paid: true,
    orderId: doc.id,
    paidAt: completedAt && completedAt.toDate ? completedAt.toDate() : (completedAt ? new Date(completedAt) : new Date()),
  };
}

/** Whether the caller has already settled the one-time verification fee. */
async function getKycFeeStatus({ userId }) {
  const fee = await hasPaidKycFee(userId);
  return { ...fee, amount: KYC_FEE_AMOUNT };
}

/**
 * Starts a ClickPesa collection for the verification fee. USSD push is fired
 * in the background (same contract as marketplace payments); BillPay returns
 * a control number the seller enters manually in M-Pesa.
 */
async function initiateKycFee({ userId, phone, paymentMethod = 'ussd_push', baseUrl }) {
  if (!userId) throw httpError(401, 'UNAUTHORIZED', 'Not authenticated');
  const existing = await hasPaidKycFee(userId);
  if (existing.paid) {
    return { alreadyPaid: true, orderId: existing.orderId, amount: KYC_FEE_AMOUNT, method: 'paid' };
  }

  const phoneDigits = String(phone || '').replace(/\D/g, '');
  const normalizedPhone = phoneDigits.startsWith('0')
    ? '255' + phoneDigits.substring(1)
    : phoneDigits.startsWith('255')
      ? phoneDigits
      : '255' + phoneDigits;
  if (normalizedPhone.length < 12) {
    throw httpError(400, 'INVALID_PHONE', 'Namba ya simu batili. Tumia namba ya Tanzania, mfano 0712 345 678');
  }

  // ClickPesa requires an alphanumeric orderReference; the UID fragment keeps
  // the id traceable to the seller without leaking the full Firebase UID.
  const suffix = userId.replace(/[^A-Za-z0-9]/g, '').substring(0, 4) || 'x';
  const orderId = `kyc${Date.now().toString(36)}${suffix}`;
  const isBillPay = paymentMethod === 'billpay';
  // BillPay's 1% fee is deducted from the collected amount, so it is added on
  // top to keep the platform's full TSh 15,000. USSD push fees are charged to
  // the customer by ClickPesa on top, never pre-added (double-charge guard).
  const gatewayFee = isBillPay ? calcGatewayFee('billpay', KYC_FEE_AMOUNT) : 0;
  const totalAmount = KYC_FEE_AMOUNT + gatewayFee;

  const store = getFirebaseFirestore();
  const txBase = {
    type: 'kyc_fee',
    userId,
    amount: KYC_FEE_AMOUNT,
    gatewayFee,
    totalAmount,
    status: 'pending',
    description: `Ada ya uthibitisho wa KYC (one time) - TZS ${KYC_FEE_AMOUNT}`,
    buyerId: userId,
    buyerPhone: normalizedPhone,
    createdAt: new Date(),
  };

  if (isBillPay) {
    const billResult = await clickpesaCreateBillPayOrder({
      billAmount: totalAmount,
      billDescription: 'KYC verification fee',
      billPaymentMode: 'EXACT',
      billReference: orderId,
    });
    if (!billResult || billResult.success === false || (!billResult.billPayNumber && !billResult.data?.billPayNumber)) {
      const errMsg = billResult?.message || billResult?.error || 'BillPay API failed to generate control number';
      throw httpError(502, 'BILLPAY_FAILED', `BillPay error: ${errMsg}`);
    }
    const billPayNumber = billResult.billPayNumber || billResult.data?.billPayNumber || billResult.billReference || '';
    const clickpesaRef = billResult.id || billResult.data?.id || billPayNumber || '';
    if (store) {
      await store.collection('transactions').doc(orderId).set({
        ...txBase,
        paymentMethod: 'BillPay',
        billPayNumber,
        clickpesaReference: clickpesaRef,
      }).catch(() => {});
    }
    return { orderId, billPayNumber, amount: KYC_FEE_AMOUNT, totalAmount, gatewayFee, method: 'billpay' };
  }

  if (store) {
    await store.collection('transactions').doc(orderId).set({ ...txBase, paymentMethod: 'ClickPesa' }).catch(() => {});
  }
  // Fire the push async — the caller gets an instant response and the webhook
  // flips the transaction to 'completed' (applyClickPesaPayment, kyc_fee branch).
  const callbackUrl = `${baseUrl}/api/clickpesa/webhook`;
  clickpesaCollect({ amount: totalAmount, orderReference: orderId, phoneNumber: normalizedPhone, callbackUrl })
    .then((result) => {
      const ref = result?.id || result?.orderReference || '';
      if (ref && store) {
        return store.collection('transactions').doc(orderId).update({ clickpesaReference: ref, ussdSent: true });
      }
    })
    .catch((err) => {
      console.error(`[KYC fee] ClickPesa USSD error for ${orderId}:`, err?.response?.data || err.message);
      if (store) {
        store.collection('transactions').doc(orderId).update({ ussdFailed: true, ussdError: err?.message || 'ClickPesa error' }).catch(() => {});
      }
    });
  return { orderId, amount: KYC_FEE_AMOUNT, totalAmount, gatewayFee: 0, method: 'ussd_push' };
}

/**
 * Create (or resubmit) the caller's application. One per Firebase UID: an
 * existing row is overwritten back to 'pending' — except an approved one,
 * which blocks resubmission (mirrors the legacy 400 'KYC already approved').
 * The one-time fee must already be settled (402 otherwise); the app collects
 * it up-front via initiateKycFee, so a resubmission after rejection is free.
 */
async function submitKyc({ userId, fullName, firstName, middleName, lastName, idType, idNumber, idImageUrl, selfieUrl, dateOfBirth, address, phone, email, shopVideoUrl }) {
  const prisma = getPrisma();
  if (!userId || !fullName || !idType || !idNumber) {
    throw httpError(400, 'VALIDATION', 'Missing required KYC fields');
  }
  const existing = await prisma.kycApplication.findUnique({ where: { userId } });
  if (existing && existing.status === 'approved') {
    throw httpError(400, 'KYC_ALREADY_APPROVED', 'KYC already approved');
  }

  // Fee gate — the only hard failure besides auth/shape errors. Payment is a
  // business prerequisite, not a data-quality issue the admin can wave through.
  const fee = await hasPaidKycFee(userId);
  if (!fee.paid) {
    throw httpError(402, 'KYC_FEE_UNPAID', `Lipa ada ya uthibitisho TZS ${KYC_FEE_AMOUNT.toLocaleString()} kwanza`);
  }

  const { errors, cleanId, reason } = validateSubmission({ fullName, firstName, middleName, lastName, idType, idNumber, idImageUrl, selfieUrl, dateOfBirth, address, phone, email, shopVideoUrl });
  const now = new Date();
  const cleanDob = DOB_RE.test(String(dateOfBirth || '')) ? String(dateOfBirth) : null;
  const data = {
    userId,
    fullName: String(fullName).trim().slice(0, 200),
    firstName: String(firstName || '').trim().slice(0, 100) || null,
    middleName: String(middleName || '').trim().slice(0, 100) || null,
    lastName: String(lastName || '').trim().slice(0, 100) || null,
    idType: String(idType).slice(0, 50),
    idNumber: cleanId.slice(0, 50),
    idImageUrl: String(idImageUrl || '').slice(0, 2000) || null,
    selfieUrl: String(selfieUrl || '').slice(0, 2000) || null,
    dateOfBirth: cleanDob,
    address: String(address || '').trim().slice(0, 500) || null,
    phone: String(phone || '').trim().slice(0, 30) || null,
    email: String(email || '').trim().slice(0, 200) || null,
    shopVideoUrl: String(shopVideoUrl || '').slice(0, 2000) || null,
    feeAmount: KYC_FEE_AMOUNT,
    feeReference: fee.orderId || null,
    feePaidAt: fee.paidAt || now,
    status: 'pending',
    approved: false,
    reviewNotes: reason,
    submittedAt: now,
    reviewedAt: null,
    revokedAt: null,
  };
  const row = existing
    ? await prisma.kycApplication.update({ where: { userId }, data })
    : await prisma.kycApplication.create({ data });

  await notifyAdminOfSubmission(row).catch(() => {});
  await mirrorToFirestore(row).catch(() => {});
  return { approved: false, reason, message: 'KYC imewasilishwa. Subiri ukaguzi wa admin.' };
}

/** All applications for the admin queue, newest first. */
async function listApplications({ status, page = 1, limit = 50 }) {
  const prisma = getPrisma();
  const where = status ? { status } : {};
  const take = Math.min(Math.max(1, limit), 100);
  const skip = (Math.max(1, page) - 1) * take;
  const [rows, total] = await Promise.all([
    prisma.kycApplication.findMany({ where, orderBy: { submittedAt: 'desc' }, skip, take }),
    prisma.kycApplication.count({ where }),
  ]);
  return { applications: rows.map(toPublic).map((k, i) => ({ ...k, userId: rows[i].userId, id: rows[i].id })), pagination: { page: Math.max(1, page), limit: take, total } };
}

/** Admin approve/reject. */
async function reviewKyc({ userId, approve, notes }) {
  const prisma = getPrisma();
  const row = await prisma.kycApplication.findUnique({ where: { userId } });
  if (!row) throw httpError(404, 'KYC_NOT_FOUND', 'KYC application not found');
  const status = approve ? 'approved' : 'rejected';
  const updated = await prisma.kycApplication.update({
    where: { userId },
    data: {
      status,
      approved: approve === true,
      reviewedAt: new Date(),
      reviewNotes: String(notes || '').slice(0, 2000) || null,
    },
  });
  await notifyUser(updated, approve ? 'KYC Imekubaliwa!' : 'KYC Imekataliwa',
    approve
      ? 'Umekubaliwa kuuza bidhaa. Sasa unaweza kuongeza bidhaa mpya.'
      : `KYC yako imekataliwa. Sababu: ${notes || 'Tafadhali wasiliana na msaada'}. Wasilisha tena baada ya kurekebisha.`)
    .catch(() => {});
  await mirrorToFirestore(updated).catch(() => {});
  return updated;
}

/** Admin revoke. */
async function revokeKyc({ userId, reason }) {
  const prisma = getPrisma();
  const row = await prisma.kycApplication.findUnique({ where: { userId } });
  if (!row) throw httpError(404, 'KYC_NOT_FOUND', 'KYC application not found');
  const updated = await prisma.kycApplication.update({
    where: { userId },
    data: {
      status: 'revoked',
      approved: false,
      revokedAt: new Date(),
      reviewNotes: String(reason || 'KYC imefutwa na admin.').slice(0, 2000),
    },
  });
  await notifyUser(updated, 'KYC Imefutwa',
    `KYC yako imefutwa na admin. Sababu: ${reason || 'Wasiliana na msaada'}. Tuma tena KYC yako.`)
    .catch(() => {});
  await mirrorToFirestore(updated).catch(() => {});
  return updated;
}

/** Admin delete: removes the application row + Firestore mirror. */
async function deleteKyc({ userId }) {
  const prisma = getPrisma();
  const existing = await prisma.kycApplication.findUnique({ where: { userId } });
  if (existing) {
    await prisma.kycApplication.delete({ where: { userId } });
  }
  const store = getFirebaseFirestore();
  if (store) {
    await store.collection('users').doc(userId).set({ kyc: { status: 'none' } }, { merge: true }).catch(() => {});
    await updateProductsKycFlag(userId, false).catch(() => {});
  }
  return { deleted: Boolean(existing) };
}

// ---------------------------------------------------------------------------
// Best-effort mirrors (never block the primary Postgres write)
// ---------------------------------------------------------------------------

async function notifyAdminOfSubmission(row) {
  await notifyAdmins('KYC Mpya Imewasilishwa', `${row.fullName} ametuma KYC yake. Tafadhali kagua.`, { type: 'kyc', userId: row.userId });
}

async function notifyUser(row, title, body) {
  // Postgres inbox first (the app reads it when kUseNotificationsApi is on).
  const prisma = getPrisma();
  const user = await prisma.user.findUnique({ where: { firebaseUid: row.userId } });
  if (user) {
    await prisma.notification.create({
      data: { userId: user.id, type: 'kyc', title, body, data: { type: 'kyc', status: row.status } },
    }).catch(() => {});
  }
  // OneSignal + Firestore fallback for app versions on the legacy inbox.
  const store = getFirebaseFirestore();
  if (store) {
    await store.collection('notifications').add({
      userId: row.userId,
      title,
      body,
      isRead: false,
      createdAt: new Date(),
      data: { type: 'kyc', status: row.status },
    }).catch(() => {});
  }
  await sendOneSignalNotification(row.userId, title, body, { type: 'kyc', status: row.status }).catch(() => {});
}

// Keep users/{uid}.kyc + products.sellerKycApproved in sync so the legacy
// admin panel and Firestore rules still see decisions made on Postgres.
async function mirrorToFirestore(row) {
  const store = getFirebaseFirestore();
  if (!store) return;
  await store.collection('users').doc(row.userId).set({
    kyc: {
      fullName: row.fullName,
      firstName: row.firstName || '',
      middleName: row.middleName || '',
      lastName: row.lastName || '',
      idType: row.idType,
      idNumber: row.idNumber,
      idImageUrl: row.idImageUrl || '',
      selfieUrl: row.selfieUrl || '',
      dateOfBirth: row.dateOfBirth || '',
      address: row.address || '',
      phone: row.phone || '',
      email: row.email || '',
      shopVideoUrl: row.shopVideoUrl || '',
      feeAmount: row.feeAmount || 0,
      feeReference: row.feeReference || '',
      feePaidAt: row.feePaidAt || null,
      status: row.status,
      approved: row.approved,
      reviewNotes: row.reviewNotes || '',
      submittedAt: row.submittedAt,
      reviewedAt: row.reviewedAt || null,
      revokedAt: row.revokedAt || null,
    },
  }, { merge: true });
  if (row.status === 'approved') {
    await updateProductsKycFlag(row.userId, true);
  } else if (row.status === 'revoked' || row.status === 'rejected') {
    await updateProductsKycFlag(row.userId, false);
  }
}

// ---------------------------------------------------------------------------
// Contact (phone/email) verification: "Verify your number" / "Verify your
// email" each send an OTP through the SAME store the auth login flow uses, so
// a seller never juggles two unrelated OTP systems (rule: one OTP infra).
// ---------------------------------------------------------------------------

const CONTACT_OTP_TTL_SECONDS = 300; // 5 minutes, same as auth
const CONTACT_OTP_KEY_LIMIT = 7; // send OTP per (userId, channel) within TTL

function hashContactOtp(otp) {
  return crypto.createHash('sha256').update(String(otp)).digest('hex');
}

// Normalise a Tanzanian phone like the auth flow does (0/255 prefix both OK).
function cleanPhoneForOtp(phone) {
  const digits = String(phone || '').replace(/[^\d]/g, '');
  if (digits.length < 9) return null;
  const rest = digits.startsWith('255') ? digits.slice(3) : digits.replace(/^0/, '');
  if (rest.length !== 9) return null;
  return rest;
}

function cleanEmailForOtp(email) {
  return String(email || '').trim().toLowerCase().replace(/\s+/g, '');
}

// Record that the given contact passed its OTP. The embedded Firestore
// users/{uid}.kyc doc is the legacy source of truth (submission reads it), so
// write the flag there with a dotted field path — merge keeps every other field
// and never clobbers an existing application.
async function saveContactVerified(userId, channel, value) {
  const store = getFirebaseFirestore();
  if (!store || !userId) return;
  const key = channel === 'phone' ? 'kyc.phoneVerified' : 'kyc.emailVerified';
  await store.collection('users').doc(userId).set({ [key]: true }, { merge: true }).catch(() => {});
}

// Send a 6-digit OTP to the seller's phone (SMS) or email (SMTP). Returns
// `{ sent, expiresInSec }`; `sent:false` means the carrier/mailer rejected it.
async function sendContactOtp({ userId, channel, value }) {
  const otp = crypto.randomInt(100000, 1000000).toString();
  if (channel === 'phone') {
    const clean = cleanPhoneForOtp(value);
    if (!clean) throw httpError(400, 'KYC_PHONE_INVALID', 'Invalid phone number');
    const smsText = `Soko Vibe KYC code: ${otp}. Inatumika dakika 5.`;
    await saveOtp(`kyc:phone:${userId}`, hashContactOtp(otp), CONTACT_OTP_TTL_SECONDS);
    const sent = await smsService.sendSms(clean, smsText);
    return { sent, expiresInSec: CONTACT_OTP_TTL_SECONDS, phone: clean };
  }
  const email = cleanEmailForOtp(value);
  if (!email || !email.includes('@')) throw httpError(400, 'KYC_EMAIL_INVALID', 'Invalid email address');
  await saveOtp(`kyc:email:${userId}`, hashContactOtp(otp), CONTACT_OTP_TTL_SECONDS);
  const subject = 'Soko Vibe — Uthibitisho wa anwani';
  const html = `
    <html><body style="font-family:Arial,sans-serif;padding:20px;max-width:600px;margin:0 auto">
      <h2 style="color:#40916C">Soko Vibe</h2>
      <p>Namba yako ya uthibitisho:</p>
      <p style="font-size:32px;font-weight:bold;letter-spacing:8px;color:#40916C">${otp}</p>
      <p>Inaisha kwa dakika 5. Usiishirikishe na mtu yeyote.</p>
    </body></html>`;
  const sent = await sendMail(email, subject, html);
  return { sent, expiresInSec: CONTACT_OTP_TTL_SECONDS, email };
}

// Verify a submitted OTP. Reuses the auth timing-safe compare + attempt bump
// so a brute-forcer hits the same lockout as the login flow.
async function verifyContactOtp({ userId, channel, value, otp }) {
  const key = `kyc:${channel}:${userId}`;
  const record = await getOtp(key);
  if (!record || record.used) throw httpError(400, 'KYC_OTP_INVALID', 'OTP is invalid or already used');
  if (Date.now() > record.expiresAt) throw httpError(400, 'KYC_OTP_EXPIRED', 'OTP imeisha wakati wake');
  const attempts = await bumpAttempts(key);
  if (attempts > 5) throw httpError(400, 'KYC_OTP_LIMIT', 'Jaribio nyingi mno — tuma OTP mpya');
  const hashed = hashContactOtp(String(otp || ''));
  const a = Buffer.from(record.value);
  const b = Buffer.from(hashed);
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) {
    throw httpError(400, 'KYC_OTP_INVALID', 'OTP si sahihi');
  }
  await markUsed(key);
  // Mark that this contact succeeded so submitKyc can require it (mirrored on
  // the embedded Firestore kyc doc by mirrorToFirestore).
  await saveContactVerified(userId, channel, value);
  return { verified: true, channel };
}

async function updateProductsKycFlag(sellerId, approved) {
  const store = getFirebaseFirestore();
  if (!store || !sellerId) return;
  const snap = await store.collection('products').where('sellerId', '==', sellerId).get();
  const batch = store.batch();
  let count = 0;
  snap.forEach((doc) => {
    batch.update(doc.ref, { sellerKycApproved: approved });
    count++;
  });
  if (count > 0) await batch.commit();
}

module.exports = {
  KYC_FEE_AMOUNT,
  getStatus,
  submitKyc,
  hasPaidKycFee,
  getKycFeeStatus,
  initiateKycFee,
  listApplications,
  reviewKyc,
  revokeKyc,
  deleteKyc,
  validateSubmission,
  toPublic,
  sendContactOtp,
  verifyContactOtp,
};