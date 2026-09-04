// Append-only audit log for sensitive actions (admin ops, financial
// transitions, security events). Never update or delete rows.
const { getPrisma } = require('../config/database');

async function writeAudit({
  actorId = null,
  actorType = 'system',
  action,
  entityType = null,
  entityId = null,
  oldState = null,
  newState = null,
  requestId = null,
  ipAddress = null,
  userAgent = null,
}) {
  if (!action) throw new Error('AUDIT_ACTION_REQUIRED');
  try {
    const prisma = getPrisma();
    return await prisma.auditLog.create({
      data: {
        actorId,
        actorType,
        action,
        entityType,
        entityId,
        oldState: oldState ?? undefined,
        newState: newState ?? undefined,
        requestId,
        ipAddress,
        userAgent,
      },
    });
  } catch (e) {
    // Audit must never break the primary operation.
    console.error('[AUDIT] write failed:', e.message);
    return null;
  }
}

function auditFromReq(req, extra = {}) {
  return {
    actorId: req.user?.id || null,
    actorType: req.user ? 'user' : 'system',
    requestId: req.id || req.headers['x-request-id'] || null,
    ipAddress: req.ip || null,
    userAgent: req.headers['user-agent'] || null,
    ...extra,
  };
}

module.exports = { writeAudit, auditFromReq };
