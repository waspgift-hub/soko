'use strict';

const { getFirebaseFirestore } = require('../../config/firebase');

const COLLECTION = 'company_audit_events';

// Append-only audit logger. Never update or delete events; corrections are
// additional events. No secrets or unnecessary PII in metadata.
async function logAuditEvent({
  actorUid,
  action,
  targetType,
  targetId,
  reason = '',
  metadata = {},
  correlationId = '',
  legalEntityId = '',
}) {
  const db = getFirebaseFirestore();
  if (!db) throw new Error('FIRESTORE_NOT_CONFIGURED');

  const event = {
    actor_uid: actorUid,
    action,
    target_type: targetType,
    target_id: targetId,
    reason: reason || '',
    metadata: metadata || {},
    correlation_id: correlationId || '',
    legal_entity_id: legalEntityId || '',
    created_at: new Date().toISOString(),
  };

  const ref = await db.collection(COLLECTION).add(event);
  return { id: ref.id, ...event };
}

async function listAuditEvents({ limit = 50, actorUid = '', targetType = '', legalEntityId = '' } = {}) {
  const db = getFirebaseFirestore();
  if (!db) throw new Error('FIRESTORE_NOT_CONFIGURED');

  let q = db.collection(COLLECTION).orderBy('created_at', 'desc');
  if (actorUid) q = q.where('actor_uid', '==', actorUid);
  if (targetType) q = q.where('target_type', '==', targetType);
  if (legalEntityId) q = q.where('legal_entity_id', '==', legalEntityId);

  const snap = await q.limit(Math.min(limit, 200)).get();
  return snap.docs.map((d) => ({ id: d.id, ...d.data() }));
}

module.exports = { logAuditEvent, listAuditEvents, COLLECTION };
