const crypto = require('crypto');
const { getPrisma } = require('../../config/database');

function httpError(status, message) {
  const err = new Error(message);
  err.status = status;
  return err;
}

// Deterministic-ish personal code from user id (stable, shareable).
function personalCode(userId) {
  const hash = crypto.createHash('sha256').update(`sv-referral:${userId}`).digest('hex');
  return hash.slice(0, 8).toUpperCase();
}

async function getMyCode({ userId }) {
  return { code: personalCode(userId) };
}

async function resolveReferrerIdScan(code) {
  const prisma = getPrisma();
  const clean = String(code || '').trim().toUpperCase();
  if (!/^[A-Z0-9]{8}$/.test(clean)) throw httpError(400, 'INVALID_REFERRAL_CODE');
  // Scan users in chunks; stops at first match. Fine at current scale;
  // replace with indexed referral_codes table when volume grows.
  const pageSize = 500;
  let skip = 0;
  for (;;) {
    const users = await prisma.user.findMany({
      select: { id: true },
      take: pageSize,
      skip,
    });
    if (users.length === 0) break;
    const hit = users.find((u) => personalCode(u.id) === clean);
    if (hit) return hit.id;
    if (users.length < pageSize) break;
    skip += pageSize;
    if (skip > 20000) break;
  }
  throw httpError(404, 'REFERRAL_CODE_NOT_FOUND');
}

async function applyReferral({ userId, code }) {
  const prisma = getPrisma();
  const referrerId = await resolveReferrerId(code);
  if (referrerId === userId) throw httpError(400, 'SELF_REFERRAL_NOT_ALLOWED');
  const existing = await prisma.referral.findFirst({ where: { referredId: userId } });
  if (existing) throw httpError(409, 'ALREADY_REFERRED');
  const referral = await prisma.referral.create({
    data: {
      referrerId,
      referredId: userId,
      code: String(code).trim().toUpperCase(),
      status: 'pending',
    },
  });
  return referral;
}

async function listMine({ userId }) {
  const prisma = getPrisma();
  const [asReferrer, asReferred] = await Promise.all([
    prisma.referral.findMany({
      where: { referrerId: userId },
      orderBy: { createdAt: 'desc' },
      take: 100,
    }),
    prisma.referral.findFirst({ where: { referredId: userId } }),
  ]);
  return { asReferrer, asReferred };
}

// Admin/system completes a referral after a qualifying action.
// Rewards are platform credits (voucher/boost), never wallet cash.
async function completeReferral({ id, qualifyingAction, rewardType, rewardAmount }) {
  const prisma = getPrisma();
  const referral = await prisma.referral.findUnique({ where: { id } });
  if (!referral) throw httpError(404, 'REFERRAL_NOT_FOUND');
  if (referral.status === 'completed') return referral;
  return prisma.referral.update({
    where: { id },
    data: {
      status: 'completed',
      qualifyingAction: qualifyingAction || referral.qualifyingAction,
      rewardType: rewardType || referral.rewardType,
      rewardAmount: rewardAmount != null ? BigInt(rewardAmount) : referral.rewardAmount,
      completedAt: new Date(),
    },
  });
}

module.exports = { personalCode, getMyCode, applyReferral, listMine, completeReferral };
