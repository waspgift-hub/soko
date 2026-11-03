// KYC application store (Phase D bridge). One row per user mirrors the
// embedded Firestore users/{uid}.kyc doc that is the current source of truth.
// userId is the Firebase UID (opaque), so the row exists even before the
// Postgres users backfill and while the app-admin panel still reads Firestore.
const { getPrisma } = require('../../config/database');
const { getFirebaseFirestore } = require('../../config/firebase');
const { sendOneSignalNotification, notifyAdmins } = require('../legacy-compat/notify');

function httpError(status, code, message) {
  const e = new Error(message);
  e.status = status;
  e.code = code;
  return e;
}

function toPublic(row) {
  if (!row) return null;
  return {
    fullName: row.fullName,
    idType: row.idType,
    idNumber: row.idNumber,
    idImageUrl: row.idImageUrl,
    selfieUrl: row.selfieUrl,
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

// Validation mirrors the legacy /api/kyc/submit handler byte-for-byte:
// submissions always land in 'pending' and problems surface in reviewNotes,
// they never hard-fail. The idType switch keys are the legacy labels; the
// Flutter app sends kyc_id_* values which therefore skip the format branch
// (exactly as before), so behavior is preserved rather than tightened.
function validateSubmission(fullName, idType, idNumber, idImageUrl, selfieUrl) {
  const errors = [];
  const nameParts = (fullName || '').trim().split(/\s+/);
  if (nameParts.length < 2) errors.push('Jina kamili linahitaji angalau majina mawili');
  if (!idImageUrl) errors.push('Picha ya kitambulisho haijapakiwa');
  if (!selfieUrl) errors.push('Selfie haijapakiwa');
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

/**
 * Create (or resubmit) the caller's application. One per Firebase UID: an
 * existing row is overwritten back to 'pending' — except an approved one,
 * which blocks resubmission (mirrors the legacy 400 'KYC already approved').
 */
async function submitKyc({ userId, fullName, idType, idNumber, idImageUrl, selfieUrl }) {
  const prisma = getPrisma();
  if (!userId || !fullName || !idType || !idNumber) {
    throw httpError(400, 'VALIDATION', 'Missing required KYC fields');
  }
  const existing = await prisma.kycApplication.findUnique({ where: { userId } });
  if (existing && existing.status === 'approved') {
    throw httpError(400, 'KYC_ALREADY_APPROVED', 'KYC already approved');
  }

  const { errors, cleanId, reason } = validateSubmission(fullName, idType, idNumber, idImageUrl, selfieUrl);
  const now = new Date();
  const data = {
    userId,
    fullName: String(fullName).trim().slice(0, 200),
    idType: String(idType).slice(0, 50),
    idNumber: cleanId.slice(0, 50),
    idImageUrl: String(idImageUrl || '').slice(0, 2000) || null,
    selfieUrl: String(selfieUrl || '').slice(0, 2000) || null,
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
      idType: row.idType,
      idNumber: row.idNumber,
      idImageUrl: row.idImageUrl || '',
      selfieUrl: row.selfieUrl || '',
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
  getStatus,
  submitKyc,
  listApplications,
  reviewKyc,
  revokeKyc,
  deleteKyc,
  validateSubmission,
  toPublic,
};