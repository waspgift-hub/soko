const { getPrisma } = require('../../config/database');
const { acquireLock, releaseLock } = require('../../config/redis');

const EVIDENCE_TYPES = [
  'LISTING_SNAPSHOT',
  'UNBOXING_VIDEO',
  'PRODUCT_PHOTO',
  'DELIVERY_TRACKING',
  'CHAT_SCREENSHOT',
  'DISPATCH_PHOTO',
  'PACKAGING_PHOTO',
  'DISPATCH_RECEIPT',
  'COMMUNICATION',
  'PLATFORM_EVIDENCE',
];

/**
 * Upload a piece of evidence into a dispute's evidence room.
 * `type` must be one of EVIDENCE_TYPES; r2Key is the uploaded object key.
 */
async function addEvidence({ disputeId, submittedBy, type, r2Key, description }) {
  const prisma = getPrisma();
  const lock = await acquireLock(`evidence:${disputeId}`, 60);

  try {
    return await prisma.$transaction(async (tx) => {
      const dispute = await tx.dispute.findUnique({ where: { id: disputeId } });
      if (!dispute) throw httpError(404, 'DISPUTE_NOT_FOUND');
      if (dispute.status !== 'open') throw httpError(409, 'DISPUTE_NOT_OPEN');

      if (!EVIDENCE_TYPES.includes(type)) throw httpError(400, 'INVALID_EVIDENCE_TYPE');

      const evidence = await tx.disputeEvidence.create({
        data: { disputeId, submittedBy, type, r2Key, description },
      });

      return evidence;
    });
  } finally {
    if (!lock.skipped) await releaseLock(`evidence:${disputeId}`);
  }
}

/**
 * List evidence for a dispute. Access restricted to parties and admins.
 */
async function listEvidence({ disputeId, requesterId }) {
  const prisma = getPrisma();
  const dispute = await prisma.dispute.findUnique({
    where: { id: disputeId },
    include: { order: true },
  });
  if (!dispute) throw httpError(404, 'DISPUTE_NOT_FOUND');

  const isParty =
    dispute.order.buyerId === requesterId ||
    dispute.order.sellerId === requesterId ||
    dispute.filedBy === requesterId;

  const requester = await prisma.user.findUnique({ where: { id: requesterId } });
  const isAdmin = requester && ['super_admin', 'admin'].includes(requester.role);

  if (!isParty && !isAdmin) throw httpError(403, 'FORBIDDEN');

  const evidence = await prisma.disputeEvidence.findMany({
    where: { disputeId },
    orderBy: { createdAt: 'asc' },
  });

  return evidence;
}

function httpError(status, message) {
  const err = new Error(message);
  err.status = status;
  return err;
}

module.exports = { EVIDENCE_TYPES, addEvidence, listEvidence };
