// Fine-grained admin authorization.
//
// Problem it solves: every admin route only checked "is this an admin at all".
// A support agent could therefore process a real-money withdrawal because the
// route had no notion of *which* admin. Roles below are deliberately small and
// additive; `authenticateAdmin` still performs the authentication step.
//
// The shared `x-admin-secret` has no user row, so it maps to `super_admin`.
// That is intentional: rotating the secret is the platform owner's break-glass
// path. Firebase-backed staff should use their own accounts and get only the
// permissions their role grants.

const ROLE_PERMISSIONS = {
  super_admin: ['*'],
  owner: ['*'],
  admin: ['*'],
  operations_admin: ['users:*', 'orders:*', 'products:*', 'disputes:*', 'kyc:*', 'audit:read'],
  finance_admin: ['finance:*', 'withdrawals:*', 'revenue:*', 'reconciliation:*', 'users:read', 'orders:read', 'audit:read'],
  finance: ['finance:read', 'finance:write', 'withdrawals:*', 'revenue:read', 'reconciliation:read', 'users:read', 'orders:read'],
  support_admin: ['users:read', 'users:write', 'orders:read', 'notifications:write', 'broadcasts:send', 'landing:*', 'audit:read'],
  support: ['users:read', 'orders:read', 'notifications:write', 'broadcasts:send', 'landing:write'],
  moderation_admin: ['catalog:read', 'catalog:write', 'reviews:read', 'reviews:write', 'disputes:*', 'refunds:*', 'products:moderate', 'kyc:*', 'users:read', 'orders:read', 'audit:read'],
  moderator: ['catalog:read', 'catalog:write', 'reviews:read', 'reviews:write', 'disputes:*', 'refunds:*', 'products:moderate', 'kyc:read', 'kyc:write', 'users:read', 'orders:read'],
  kyc_reviewer: ['kyc:read', 'kyc:write', 'users:read'],
  security_admin: ['users:*', 'audit:*', 'settings:write'],
  technical_ops: ['settings:write', 'audit:read'],
  analyst: ['users:read', 'orders:read', 'finance:read', 'revenue:read', 'audit:read'],
  analyst_readonly: ['users:read', 'orders:read', 'finance:read', 'revenue:read'],
};

function roleOf(req) {
  if (req.adminStaff && req.adminStaff.role) return req.adminStaff.role;
  if (req.user && req.user.role) return req.user.role;
  if (req.isAdmin) return 'super_admin';
  return null;
}

function permissionsFor(req) {
  // A staff session carries its own permission list (custom grants are allowed
  // by the staff editor), so prefer it over the role defaults.
  if (req.adminStaff && Array.isArray(req.adminStaff.permissions)) {
    return req.adminStaff.permissions;
  }
  const role = roleOf(req);
  return ROLE_PERMISSIONS[role] || [];
}

function matches(perms, permission) {
  if (perms.includes('*') || perms.includes(permission)) return true;
  const domain = String(permission).split(':')[0];
  return perms.includes(`${domain}:*`);
}

function can(req, permission) {
  return matches(permissionsFor(req), permission);
}

// Mount AFTER `authenticateAdmin`. Returns 401 when unauthenticated and 403
// when authenticated but outside the permission's role set.
function requireAdminPermission(permission) {
  return (req, res, next) => {
    if (!req.isAdmin && !req.user && !req.adminStaff) {
      return res.status(401).json({ success: false, error: 'AUTH_REQUIRED' });
    }
    if (!can(req, permission)) {
      return res.status(403).json({ success: false, error: 'ADMIN_PERMISSION_REQUIRED', permission });
    }
    return next();
  };
}

module.exports = {
  ROLE_PERMISSIONS,
  roleOf,
  permissionsFor,
  can,
  requireAdminPermission,
};
