const admin = require('firebase-admin');
const { getPrisma } = require('../../config/database');
const { getFirebaseAuth, getFirebaseFirestore } = require('../../config/firebase');
const { notifyAdmins } = require('../legacy-compat/notify');

function httpError(status, message) {
  const err = new Error(message);
  err.status = status;
  return err;
}

// Ensure a Prisma user row exists for the Firebase identity (reporters may
// never have touched v1 commerce endpoints before reporting).
async function ensureUser({ firebaseUid, email, phone }) {
  const prisma = getPrisma();
  let user = await prisma.user.findUnique({ where: { firebaseUid } });
  if (!user) {
    user = await prisma.user.create({
      data: {
        firebaseUid,
        email: email || null,
        phone: phone || null,
        accountStatus: 'active',
      },
    });
  }
  return user;
}

async function submitReport({ reporterUid, reporterName, reportedUserId, reportedUserName, productId, productName, reason, description }) {
  if (!reportedUserId || !reason || !description) {
    throw httpError(400, 'Missing required fields');
  }
  const prisma = getPrisma();
  const auth = getFirebaseAuth();

  let email = null;
  let phone = null;
  try {
    if (auth) {
      const record = await auth.getUser(reporterUid);
      email = record.email || null;
      phone = record.phoneNumber || null;
    }
  } catch (_) {}

  const reporter = await ensureUser({ firebaseUid: reporterUid, email, phone });

  const report = await prisma.moderationReport.create({
    data: {
      reporterId: reporter.id,
      targetId: reportedUserId,
      targetType: productId ? 'product' : 'user',
      reason: String(reason).slice(0, 50),
      description: String(description).slice(0, 2000),
      status: 'pending',
    },
  });

  // Mirror to Firestore so existing admin screens keep working.
  try {
    const store = getFirebaseFirestore();
    if (store) {
      await store.collection('reports').add({
        reporterId: reporterUid,
        reporterName: reporterName || 'Anonymous',
        reportedUserId,
        reportedUserName: reportedUserName || 'Anonymous',
        productId: productId || null,
        productName: productName || null,
        reason,
        description,
        status: 'pending',
        adminNote: null,
        pgReportId: report.id,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
  } catch (e) {
    console.error('[MODERATION] firestore mirror failed:', e.message);
  }

  try {
    await notifyAdmins(
      'New report submitted',
      `${reporterName || 'A user'} reported ${reportedUserName || 'a user'}. Reason: ${reason}`,
      { type: 'report', reporterId: reporterUid, reportedUserId }
    );
  } catch (_) {}

  return report;
}

async function listReports({ status, targetType, page = 1, limit = 20 }) {
  const prisma = getPrisma();
  const where = {};
  if (status) where.status = status;
  if (targetType) where.targetType = targetType;
  const [items, total] = await Promise.all([
    prisma.moderationReport.findMany({
      where,
      include: { reporter: { select: { id: true, email: true, phone: true } } },
      orderBy: { createdAt: 'desc' },
      take: Number(limit),
      skip: (Number(page) - 1) * Number(limit),
    }),
    prisma.moderationReport.count({ where }),
  ]);
  return { items, pagination: { page: Number(page), limit: Number(limit), total } };
}

async function reviewReport({ id, status, reviewedBy }) {
  const prisma = getPrisma();
  const report = await prisma.moderationReport.findUnique({ where: { id } });
  if (!report) throw httpError(404, 'REPORT_NOT_FOUND');
  return prisma.moderationReport.update({
    where: { id },
    data: { status, reviewedBy, reviewedAt: new Date() },
  });
}

module.exports = { submitReport, listReports, reviewReport };
