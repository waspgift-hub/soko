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
  admin: ['*'],
  finance_admin: [
    'finance:read',
    'finance:write',
    'reports:read',
    'users:read',
    'orders:read',
  ],
  // Staff role id used by the admin panel's staff editor.
  finance: [
    'finance:read',
    'finance:write',
    'reports:read',
    'users:read',
    'orders:read',
  ],
  kyc_reviewer: ['kyc:read', 'kyc:write', 'users:read'],
  moderator: ['catalog:read', 'catalog:write', 'reviews:read', 'reviews:write', 'orders:read'],
  support: ['users:read', 'orders:read', 'notifications:write'],
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
