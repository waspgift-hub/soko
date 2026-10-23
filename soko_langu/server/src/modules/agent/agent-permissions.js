// Agent permission system.
//
// Scopes are narrowly defined capabilities bound to the authenticated account.
// A saved permission NEVER independently authorizes high-impact actions
// (publish, delete, pay, withdraw, confirm delivery). Those require a fresh,
// specific pending-action approval per operation.
//
// Permission lifecycle:
//   granted  → user explicitly allowed (via the permission UI)
//   expired  → TTL elapsed (user must re-grant)
//   revoked  → user revoked
//
// Default: no permissions. Nothing is permanent by default.

const { getStore } = require('../../config/database');
const crypto = require('crypto');

const COLLECTION = 'agent_permissions';

// Narrowly defined capabilities. Each maps to one or more tool impact levels.
const SCOPES = {
  // Account
  read_my_profile: { label: 'Read my profile', description: 'Read your own name, email, phone, KYC and account status.' },
  // Products
  read_my_products: { label: 'Read my product listings', description: 'Read your own product listings and drafts.' },
  prepare_product_drafts: { label: 'Prepare product drafts', description: 'Create and update draft product listings (not published).' },
  publish_products: { label: 'Publish products', description: 'Publish draft products to the marketplace (requires per-action confirmation).' },
  delete_products: { label: 'Delete products', description: 'Soft-delete your products (destructive, requires per-action confirmation + MFA).' },
  // Orders
  read_my_orders: { label: 'Read my orders', description: 'Read your own order status and history.' },
  manage_my_orders: { label: 'Manage my orders', description: 'Cancel orders and confirm delivery (requires per-action confirmation).' },
  // Wallet
  read_my_wallet: { label: 'Read my wallet', description: 'Read your wallet balance and transaction history.' },
  prepare_withdrawal: { label: 'Prepare withdrawals', description: 'Prepare a withdrawal for review (no money moves until confirmed).' },
  execute_withdrawal: { label: 'Execute withdrawals', description: 'Send a prepared withdrawal to the payment provider (requires per-action confirmation + MFA).' },
  // Support
  create_support_tickets: { label: 'Create support tickets', description: 'Create support tickets (requires per-action confirmation).' },
  read_my_notifications: { label: 'Read my notifications', description: 'Read your own notifications.' },
};

// All known scopes, in insertion order.
const ALL_SCOPES = Object.keys(SCOPES);

// Default TTLs per scope (ms). Read-only scopes last longer; financial/destructive shorter.
const DEFAULT_TTL_MS = {
  read_my_profile: 30 * 24 * 60 * 60 * 1000,      // 30 days
  read_my_products: 30 * 24 * 60 * 60 * 1000,
  read_my_orders: 30 * 24 * 60 * 60 * 1000,
  read_my_wallet: 30 * 24 * 60 * 60 * 1000,
  read_my_notifications: 30 * 24 * 60 * 60 * 1000,
  prepare_product_drafts: 7 * 24 * 60 * 60 * 1000,  // 7 days
  prepare_withdrawal: 24 * 60 * 60 * 1000,         // 1 day
  publish_products: 24 * 60 * 60 * 1000,           // 1 day
  delete_products: 24 * 60 * 60 * 1000,            // 1 day
  manage_my_orders: 24 * 60 * 60 * 1000,           // 1 day
  execute_withdrawal: 1 * 60 * 60 * 1000,          // 1 hour
  create_support_tickets: 7 * 24 * 60 * 60 * 1000, // 7 days
};

function scopeTtlMs(scope) {
  return DEFAULT_TTL_MS[scope] ?? 24 * 60 * 60 * 1000;
}

function nowIso() {
  return new Date().toISOString();
}

function httpError(status, message) {
  const err = new Error(message);
  err.status = status;
  return err;
}

/*───────────────────────── Grant / revoke / check ─────────────────────────*/

async function grantPermission({ userId, scope, grantedBy, ttlMs, reason }) {
  if (!ALL_SCOPES.includes(scope)) throw httpError(400, `Unknown permission scope: ${scope}`);
  const store = getStore();
  const permissionId = crypto.randomUUID();
  const expiresAt = new Date(Date.now() + (ttlMs ?? scopeTtlMs(scope))).toISOString();
  const ref = store.collection(COLLECTION).doc(permissionId);
  const doc = {
    permissionId,
    userId,
    scope,
    status: 'granted',
    grantedBy: grantedBy || userId,
    reason: reason || null,
    grantedAt: nowIso(),
    expiresAt,
    revokedAt: null,
    revokedBy: null,
    updatedAt: nowIso(),
  };
  await ref.set(doc);
  return serialize(doc);
}

async function revokePermission({ userId, scope, permissionId, revokedBy }) {
  const store = getStore();
  let ref;
  if (permissionId) {
    ref = store.collection(COLLECTION).doc(permissionId);
  } else {
    // Revoke all active grants of this scope for the user.
    const snap = await store.collection(COLLECTION)
      .where('userId', '==', userId)
      .where('scope', '==', scope)
      .where('status', '==', 'granted')
      .get();
    if (snap.empty) return { revoked: 0 };
    // Batch revoke.
    const batch = store.batch();
    for (const doc of snap.docs) batch.update(doc.ref, { status: 'revoked', revokedAt: nowIso(), revokedBy: revokedBy || userId, updatedAt: nowIso() });
    await batch.commit();
    return { revoked: snap.size };
  }
  const snap = await ref.get();
  if (!snap.exists) throw httpError(404, 'PERMISSION_NOT_FOUND');
  const data = snap.data();
  if (data.userId !== userId) throw httpError(404, 'PERMISSION_NOT_FOUND');
  await ref.update({ status: 'revoked', revokedAt: nowIso(), revokedBy: revokedBy || userId, updatedAt: nowIso() });
  return serialize({ ...data, status: 'revoked', revokedAt: nowIso(), revokedBy: revokedBy || userId });
}

async function listPermissions({ userId, includeExpired = false, includeRevoked = false }) {
  const store = getStore();
  const snap = await store.collection(COLLECTION).where('userId', '==', userId).get();
  const now = new Date();
  return snap.docs
    .map((d) => {
      const data = d.data();
      const expired = data.expiresAt && new Date(data.expiresAt) <= now;
      let effective = data.status === 'granted' && !expired;
      if (!includeExpired && expired) effective = false;
      if (!includeRevoked && data.status === 'revoked') effective = false;
      return { ...serialize(data), expired, effective };
    })
    .filter((p) => (includeRevoked || p.status !== 'revoked') && (includeExpired || !p.expired || p.status === 'granted'));
}

async function checkPermission({ userId, scope }) {
  const store = getStore();
  const now = new Date();
  const snap = await store.collection(COLLECTION)
    .where('userId', '==', userId)
    .where('scope', '==', scope)
    .where('status', '==', 'granted')
    .get();
  for (const doc of snap.docs) {
    const data = doc.data();
    if (data.expiresAt && new Date(data.expiresAt) <= now) continue; // expired
    return { allowed: true, permissionId: doc.id, expiresAt: data.expiresAt };
  }
  return { allowed: false };
}

/*───────────────────────── Tool-level authorization ─────────────────────────*/

// Map a tool name to the permission scope(s) required to invoke it.
// Returns null for tools that need no pre-grant permission (public reads).
function requiredScopesForTool(toolName) {
  const mapping = {
    // Read tools
    search_products: null,
    get_product_details: null,
    get_my_profile: ['read_my_profile'],
    get_my_orders: ['read_my_orders'],
    get_my_wallet_balance: ['read_my_wallet'],
    get_my_transactions: ['read_my_wallet'],
    get_my_notifications: ['read_my_notifications'],
    search_support_articles: null,
    // Prepare tools
    create_product_draft: ['prepare_product_drafts'],
    update_product_draft: ['prepare_product_drafts'],
    prepare_withdrawal: ['prepare_withdrawal'],
    // Execute tools
    publish_product: ['publish_products'],
    archive_product: ['publish_products'],
    delete_product: ['delete_products'],
    submit_withdrawal: ['execute_withdrawal'],
    cancel_order: ['manage_my_orders'],
    confirm_delivery: ['manage_my_orders'],
    create_support_ticket: ['create_support_tickets'],
  };
  return mapping[toolName] ?? null;
}

/**
 * Authorize a tool invocation for a user.
 * Returns { allowed: true } or { allowed: false, reason, scope, requiresMfa }.
 * High-impact tools (financial/destructive) always require a separate pending
 * action approval regardless of saved permission — that is enforced by the
 * orchestrator, not here.
 */
async function authorizeTool({ userId, toolName }) {
  const tool = require('./agent-tools').get(toolName);
  if (!tool) return { allowed: false, reason: 'Unknown tool' };
  const scopes = requiredScopesForTool(toolName);
  if (!scopes) return { allowed: true, requiresMfa: Boolean(tool.requiresMfa) };
  // Any one granted scope is sufficient.
  for (const scope of scopes) {
    const result = await checkPermission({ userId, scope });
    if (result.allowed) return { allowed: true, scope, requiresMfa: Boolean(tool.requiresMfa) };
  }
  return {
    allowed: false,
    reason: `Missing permission: ${scopes.join(' or ')}`,
    scopes,
    requiresMfa: Boolean(tool.requiresMfa),
  };
}

function serialize(doc) {
  return {
    permissionId: doc.permissionId,
    userId: doc.userId,
    scope: doc.scope,
    status: doc.status,
    grantedBy: doc.grantedBy,
    reason: doc.reason,
    grantedAt: iso(doc.grantedAt),
    expiresAt: iso(doc.expiresAt),
    revokedAt: doc.revokedAt ? iso(doc.revokedAt) : null,
    revokedBy: doc.revokedBy,
    updatedAt: iso(doc.updatedAt),
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
  SCOPES,
  ALL_SCOPES,
  grantPermission,
  revokePermission,
  listPermissions,
  checkPermission,
  authorizeTool,
  requiredScopesForTool,
  scopeTtlMs,
};
