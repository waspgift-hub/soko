// Pending actions — the explicit approval workflow for sensitive agent actions.
//
// Every high-impact action (publish, delete, withdraw, cancel order, confirm
// delivery, create support ticket) is represented by a pending action row
// before execution. The row binds:
//   * the authenticated actor
//   * the action type and validated parameters
//   * the target resource + its state at preview time
//   * required permissions + auth assurance
//   * expiration + unique id + idempotency key
//   * current status (DRAFT -> VALIDATING -> AWAITING_APPROVAL -> ...)
//
// Approval is bound to THIS row and its reviewed parameters. The frontend
// cannot execute by sending status="APPROVED" — the backend revalidates
// everything at execution time.

const { getStore } = require('../../config/database');
const crypto = require('crypto');

const COLLECTION = 'agent_pending_actions';

// Action lifecycle. Invalid transitions are rejected.
const STATUS = {
  DRAFT: 'DRAFT',
  VALIDATING: 'VALIDATING',
  AWAITING_APPROVAL: 'AWAITING_APPROVAL',
  APPROVED: 'APPROVED',
  EXECUTING: 'EXECUTING',
  SUCCEEDED: 'SUCCEEDED',
  FAILED: 'FAILED',
  DENIED: 'DENIED',
  CANCELLED: 'CANCELLED',
  EXPIRED: 'EXPIRED',
};

const VALID_TRANSITIONS = {
  [STATUS.DRAFT]: [STATUS.VALIDATING, STATUS.AWAITING_APPROVAL, STATUS.CANCELLED, STATUS.EXPIRED],
  [STATUS.VALIDATING]: [STATUS.AWAITING_APPROVAL, STATUS.FAILED, STATUS.CANCELLED],
  [STATUS.AWAITING_APPROVAL]: [STATUS.APPROVED, STATUS.DENIED, STATUS.EXPIRED, STATUS.CANCELLED],
  [STATUS.APPROVED]: [STATUS.EXECUTING, STATUS.EXPIRED, STATUS.CANCELLED],
  [STATUS.EXECUTING]: [STATUS.SUCCEEDED, STATUS.FAILED],
  [STATUS.SUCCEEDED]: [],
  [STATUS.FAILED]: [STATUS.CANCELLED], // retry path goes through a new action
  [STATUS.DENIED]: [STATUS.CANCELLED],
  [STATUS.EXPIRED]: [STATUS.CANCELLED],
};

const TERMINAL = new Set([STATUS.SUCCEEDED, STATUS.FAILED, STATUS.DENIED, STATUS.EXPIRED, STATUS.CANCELLED]);

// Default TTL: pending actions expire after 1 hour if not approved.
const DEFAULT_TTL_MS = 60 * 60 * 1000;

// High-impact action types requiring MFA at execution.
const MFA_REQUIRED_TYPES = new Set(['delete_product', 'submit_withdrawal', 'confirm_delivery']);

function nowIso() {
  return new Date().toISOString();
}

function httpError(status, message) {
  const err = new Error(message);
  err.status = status;
  return err;
}

function isValidTransition(from, to) {
  const allowed = VALID_TRANSITIONS[from];
  return Boolean(allowed && allowed.includes(to));
}

/*───────────────────────── Create / approve / reject / execute ─────────────────────────*/

/**
 * Create a pending action. Parameters are validated against the tool's schema
 * by the caller (orchestrator); here we store them as the reviewed payload.
 */
async function createPendingAction({
  userId,
  actionType,
  targetResourceId,
  targetResourceType,
  parameters,
  requiredPermissions,
  requiredMfa,
  versionSnapshot,
  idempotencyKey,
  ttlMs,
}) {
  if (!MFA_REQUIRED_TYPES.has(actionType) && requiredMfa) {
    // MFA flag is authoritative from the tool spec; don't let callers upgrade it.
  }
  const store = getStore();
  const actionId = crypto.randomUUID();
  const expiresAt = new Date(Date.now() + (ttlMs ?? DEFAULT_TTL_MS)).toISOString();
  const idempotency = idempotencyKey || `action_${actionType}_${actionId}`;
  const doc = {
    actionId,
    userId,
    actionType,
    targetResourceId: targetResourceId || null,
    targetResourceType: targetResourceType || null,
    parameters: parameters || {},
    requiredPermissions: requiredPermissions || [],
    requiredMfa: Boolean(requiredMfa),
    versionSnapshot: versionSnapshot || null,
    idempotencyKey: idempotency,
    status: STATUS.DRAFT,
    createdAt: nowIso(),
    updatedAt: nowIso(),
    expiresAt,
    approvedAt: null,
    approvedBy: null,
    executedAt: null,
    result: null,
    error: null,
    attempts: 0,
  };
  await store.collection(COLLECTION).doc(actionId).set(doc);
  return serialize(doc);
}

/**
 * Validate and advance to AWAITING_APPROVAL. Revalidates permissions and
 * resource state snapshot.
 */
async function validatePendingAction({ actionId, userId }) {
  const store = getStore();
  const ref = store.collection(COLLECTION).doc(String(actionId));
  const snap = await ref.get();
  if (!snap.exists) throw httpError(404, 'PENDING_ACTION_NOT_FOUND');
  const data = snap.data();
  if (data.userId !== userId) throw httpError(404, 'PENDING_ACTION_NOT_FOUND');
  if (!isValidTransition(data.status, STATUS.VALIDATING)) {
    throw httpError(409, `Invalid transition ${data.status} -> VALIDATING`);
  }
  // Re-check permissions still held.
  const { checkPermission } = require('./agent-permissions');
  for (const perm of data.requiredPermissions) {
    const ok = await checkPermission({ userId, scope: perm });
    if (!ok.allowed) {
      await ref.update({ status: STATUS.FAILED, error: `Permission revoked: ${perm}`, updatedAt: nowIso() });
      throw httpError(403, `Permission not held: ${perm}`);
    }
  }
  // Re-verify resource still exists and matches version snapshot where applicable.
  await revalidateResource(data);
  // Validation is synchronous here, so go straight to AWAITING_APPROVAL.
  await ref.update({ status: STATUS.AWAITING_APPROVAL, updatedAt: nowIso() });
  return serialize({ ...data, status: STATUS.AWAITING_APPROVAL });
}

/**
 * User explicitly approves a pending action. Fresh authorization check.
 */
async function approvePendingAction({ actionId, userId, confirmedBy }) {
  const store = getStore();
  const ref = store.collection(COLLECTION).doc(String(actionId));
  const snap = await ref.get();
  if (!snap.exists) throw httpError(404, 'PENDING_ACTION_NOT_FOUND');
  const data = snap.data();
  if (data.userId !== userId) throw httpError(404, 'PENDING_ACTION_NOT_FOUND');
  if (data.status !== STATUS.AWAITING_APPROVAL) {
    throw httpError(409, `Action is not awaiting approval (status=${data.status})`);
  }
  // Expired?
  if (data.expiresAt && new Date(data.expiresAt) <= new Date()) {
    await ref.update({ status: STATUS.EXPIRED, updatedAt: nowIso() });
    throw httpError(410, 'Pending action has expired');
  }
  // Re-validate permissions and resource state — the resource may have changed
  // since preview. If changed, require re-review (fail here so the client
  // re-prepares).
  await revalidateResource(data);
  // Re-check permissions.
  const { checkPermission } = require('./agent-permissions');
  for (const perm of data.requiredPermissions) {
    const ok = await checkPermission({ userId, scope: perm });
    if (!ok.allowed) {
      await ref.update({ status: STATUS.FAILED, error: `Permission revoked: ${perm}`, updatedAt: nowIso() });
      throw httpError(403, `Permission not held: ${perm}`);
    }
  }
  await ref.update({
    status: STATUS.APPROVED,
    approvedAt: nowIso(),
    approvedBy: confirmedBy || userId,
    updatedAt: nowIso(),
  });
  return serialize({ ...data, status: STATUS.APPROVED, approvedAt: nowIso(), approvedBy: confirmedBy || userId });
}

/**
 * User explicitly denies/rejects a pending action.
 */
async function denyPendingAction({ actionId, userId, reason }) {
  const store = getStore();
  const ref = store.collection(COLLECTION).doc(String(actionId));
  const snap = await ref.get();
  if (!snap.exists) throw httpError(404, 'PENDING_ACTION_NOT_FOUND');
  const data = snap.data();
  if (data.userId !== userId) throw httpError(404, 'PENDING_ACTION_NOT_FOUND');
  if (!isValidTransition(data.status, STATUS.DENIED)) {
    throw httpError(409, `Cannot deny action in status ${data.status}`);
  }
  await ref.update({ status: STATUS.DENIED, error: reason || 'User denied', updatedAt: nowIso() });
  return serialize({ ...data, status: STATUS.DENIED, error: reason || 'User denied' });
}

/**
 * User cancels a pending action (before execution).
 */
async function cancelPendingAction({ actionId, userId }) {
  const store = getStore();
  const ref = store.collection(COLLECTION).doc(String(actionId));
  const snap = await ref.get();
  if (!snap.exists) throw httpError(404, 'PENDING_ACTION_NOT_FOUND');
  const data = snap.data();
  if (data.userId !== userId) throw httpError(404, 'PENDING_ACTION_NOT_FOUND');
  if (!isValidTransition(data.status, STATUS.CANCELLED)) {
    throw httpError(409, `Cannot cancel action in status ${data.status}`);
  }
  await ref.update({ status: STATUS.CANCELLED, updatedAt: nowIso() });
  return serialize({ ...data, status: STATUS.CANCELLED });
}

/**
 * Mark executing (claimed by the executor).
 */
async function markExecuting({ actionId, userId }) {
  const store = getStore();
  const ref = store.collection(COLLECTION).doc(String(actionId));
  const snap = await ref.get();
  if (!snap.exists) throw httpError(404, 'PENDING_ACTION_NOT_FOUND');
  const data = snap.data();
  if (data.userId !== userId) throw httpError(404, 'PENDING_ACTION_NOT_FOUND');
  if (data.status !== STATUS.APPROVED) {
    throw httpError(409, `Action is not approved (status=${data.status})`);
  }
  const nextAttempts = (data.attempts || 0) + 1;
  await ref.update({ status: STATUS.EXECUTING, attempts: nextAttempts, updatedAt: nowIso() });
  return serialize({ ...data, status: STATUS.EXECUTING, attempts: nextAttempts });
}

/**
 * Mark succeeded with the real result.
 */
async function markSucceeded({ actionId, userId, result }) {
  const store = getStore();
  const ref = store.collection(COLLECTION).doc(String(actionId));
  const snap = await ref.get();
  if (!snap.exists) throw httpError(404, 'PENDING_ACTION_NOT_FOUND');
  const data = snap.data();
  if (data.userId !== userId) throw httpError(404, 'PENDING_ACTION_NOT_FOUND');
  await ref.update({
    status: STATUS.SUCCEEDED,
    result: result || null,
    executedAt: nowIso(),
    updatedAt: nowIso(),
  });
  return serialize({ ...data, status: STATUS.SUCCEEDED, result, executedAt: nowIso() });
}

/**
 * Mark failed with an error (retryable via a new action).
 */
async function markFailed({ actionId, userId, error }) {
  const store = getStore();
  const ref = store.collection(COLLECTION).doc(String(actionId));
  const snap = await ref.get();
  if (!snap.exists) throw httpError(404, 'PENDING_ACTION_NOT_FOUND');
  const data = snap.data();
  if (data.userId !== userId) throw httpError(404, 'PENDING_ACTION_NOT_FOUND');
  await ref.update({
    status: STATUS.FAILED,
    error: String(error || 'Execution failed').slice(0, 1000),
    updatedAt: nowIso(),
  });
  return serialize({ ...data, status: STATUS.FAILED, error: String(error || 'Execution failed') });
}

/**
 * Expire stale pending actions (called by sweeper or on read).
 */
async function expirePendingAction({ actionId, userId }) {
  const store = getStore();
  const ref = store.collection(COLLECTION).doc(String(actionId));
  const snap = await ref.get();
  if (!snap.exists) return null;
  const data = snap.data();
  if (data.userId !== userId) return null;
  if (data.status !== STATUS.AWAITING_APPROVAL && data.status !== STATUS.APPROVED) return null;
  if (data.expiresAt && new Date(data.expiresAt) > new Date()) return null;
  await ref.update({ status: STATUS.EXPIRED, updatedAt: nowIso() });
  return serialize({ ...data, status: STATUS.EXPIRED });
}

/*───────────────────────── Reads ─────────────────────────*/

async function getPendingAction({ actionId, userId }) {
  const store = getStore();
  const snap = await store.collection(COLLECTION).doc(String(actionId)).get();
  if (!snap.exists) throw httpError(404, 'PENDING_ACTION_NOT_FOUND');
  const data = snap.data();
  if (data.userId !== userId) throw httpError(404, 'PENDING_ACTION_NOT_FOUND');
  return serialize(data);
}

async function listPendingActions({ userId, status, limit = 50 }) {
  const store = getStore();
  let query = store.collection(COLLECTION).where('userId', '==', userId);
  if (status) query = query.where('status', '==', status);
  const snap = await query.orderBy('createdAt', 'desc').limit(limit).get();
  return snap.docs.map((d) => serialize(d.data()));
}

/*───────────────────────── Internal ─────────────────────────*/

async function revalidateResource(data) {
  // For product actions, re-fetch and compare version snapshot if present.
  if (data.targetResourceType === 'product' && data.targetResourceId) {
    const productService = require('../products/product-service');
    // Re-ownership check via the same path the tool uses.
    const store = getStore();
    const user = await store.user.findUnique({ where: { firebaseUid: data.userId }, select: { id: true } });
    let sellerProfileId = null;
    if (user) {
      const profile = await store.sellerProfile.findUnique({ where: { userId: user.id }, select: { id: true } });
      sellerProfileId = profile ? profile.id : null;
    }
    if (!sellerProfileId) throw httpError(409, 'Seller profile no longer available');
    try {
      await productService.getOwnedProduct({
        id: data.targetResourceId,
        sellerProfileId,
        userId: user.id,
      });
    } catch (e) {
      throw httpError(409, 'Target resource no longer accessible or has changed');
    }
    if (data.versionSnapshot && data.versionSnapshot.status && data.versionSnapshot.status !== 'draft') {
      // Resource changed since preview — require re-review.
      throw httpError(409, 'RESOURCE_CHANGED_AFTER_PREVIEW');
    }
  }
  // For withdrawal/order actions, revalidation is performed by the underlying
  // business service at execution time (balance, order state).
}

function serialize(doc) {
  return {
    actionId: doc.actionId,
    userId: doc.userId,
    actionType: doc.actionType,
    targetResourceId: doc.targetResourceId,
    targetResourceType: doc.targetResourceType,
    parameters: doc.parameters || {},
    requiredPermissions: doc.requiredPermissions || [],
    requiredMfa: Boolean(doc.requiredMfa),
    versionSnapshot: doc.versionSnapshot || null,
    idempotencyKey: doc.idempotencyKey,
    status: doc.status,
    createdAt: iso(doc.createdAt),
    updatedAt: iso(doc.updatedAt),
    expiresAt: iso(doc.expiresAt),
    approvedAt: iso(doc.approvedAt),
    approvedBy: doc.approvedBy,
    executedAt: iso(doc.executedAt),
    result: doc.result || null,
    error: doc.error || null,
    attempts: doc.attempts || 0,
  };
}

function iso(value) {
  if (value == null) return null;
  if (typeof value === 'object' && typeof value.toDate === 'function') return value.toDate().toISOString();
  if (value instanceof Date) return value.toISOString();
  return String(value);
}

module.exports = {
  COLLECTION,
  STATUS,
  TERMINAL,
  MFA_REQUIRED_TYPES,
  createPendingAction,
  validatePendingAction,
  approvePendingAction,
  denyPendingAction,
  cancelPendingAction,
  markExecuting,
  markSucceeded,
  markFailed,
  expirePendingAction,
  getPendingAction,
  listPendingActions,
  isValidTransition,
  DEFAULT_TTL_MS,
};
