'use strict';

// Company OS role templates (Phase 1). Keep in sync with the discovery report.
const ROLES = {
  founder: { level: 0, modules: ['*'] },
  ceo: { level: 1, modules: ['*'] },
  executive_viewer: { level: 2, modules: ['dashboard', 'reports', 'projects', 'finance'] },
  legal_entity_admin: { level: 3, modules: ['settings', 'legal_entities', 'departments', 'employees'] },
  department_director: { level: 4, modules: ['dashboard', 'projects', 'tasks', 'employees', 'calendar'] },
  department_manager: { level: 5, modules: ['projects', 'tasks', 'employees', 'calendar'] },
  project_manager: { level: 5, modules: ['projects', 'tasks', 'calendar'] },
  finance_officer: { level: 5, modules: ['finance', 'procurement', 'reports'] },
  finance_approver: { level: 4, modules: ['finance', 'procurement', 'reports'] },
  hr_manager: { level: 5, modules: ['employees', 'calendar', 'reports'] },
  procurement_officer: { level: 5, modules: ['procurement', 'inventory'] },
  asset_manager: { level: 5, modules: ['inventory', 'assets'] },
  technical_admin: { level: 5, modules: ['infrastructure', 'integrations', 'reports'] },
  security_officer: { level: 4, modules: ['security', 'audit', 'reports'] },
  auditor: { level: 6, modules: ['audit', 'reports', 'finance'] },
  employee: { level: 7, modules: ['tasks', 'calendar', 'documents'] },
  contractor: { level: 7, modules: ['tasks', 'calendar', 'documents'] },
  consultant: { level: 7, modules: ['tasks', 'documents'] },
};

const ACTIONS = ['read', 'create', 'edit', 'submit', 'approve', 'reject', 'export', 'delete', 'configure', 'administer'];

function roleDef(role) {
  return ROLES[role] || null;
}

function canAccessModule(role, moduleName) {
  const def = roleDef(role);
  if (!def) return false;
  if (def.modules.includes('*')) return true;
  return def.modules.includes(moduleName);
}

// Read-only roles: may read but never mutate.
const READ_ONLY_ROLES = new Set(['executive_viewer', 'auditor']);

function isReadOnly(role) {
  return READ_ONLY_ROLES.has(role);
}

// Middleware: requires an authenticated Firebase user with a company membership.
function requireCompanyMember(req, res, next) {
  const membership = req.companyMembership;
  if (!membership) {
    return res.status(403).json({ success: false, code: 'COMPANY_MEMBER_REQUIRED', error: 'No company membership' });
  }
  if (membership.status !== 'active') {
    return res.status(403).json({ success: false, code: 'MEMBERSHIP_INACTIVE', error: 'Membership is not active' });
  }
  next();
}

// Middleware factory: requires one of the given roles.
function requireCompanyRole(...roles) {
  return (req, res, next) => {
    const membership = req.companyMembership;
    if (!membership) {
      return res.status(403).json({ success: false, code: 'COMPANY_MEMBER_REQUIRED', error: 'No company membership' });
    }
    if (!roles.includes(membership.role)) {
      return res.status(403).json({ success: false, code: 'INSUFFICIENT_ROLE', error: 'Insufficient role' });
    }
    next();
  };
}

// Middleware factory: requires module access + action permission.
// Mutating actions are blocked for read-only roles.
const MUTATING_ACTIONS = new Set(['create', 'edit', 'submit', 'approve', 'reject', 'delete', 'configure', 'administer']);
function requirePermission(moduleName, action) {
  return (req, res, next) => {
    const membership = req.companyMembership;
    if (!membership) {
      return res.status(403).json({ success: false, code: 'COMPANY_MEMBER_REQUIRED', error: 'No company membership' });
    }
    if (!canAccessModule(membership.role, moduleName)) {
      return res.status(403).json({ success: false, code: 'MODULE_ACCESS_DENIED', error: 'Module access denied' });
    }
    if (MUTATING_ACTIONS.has(action) && isReadOnly(membership.role)) {
      return res.status(403).json({ success: false, code: 'READ_ONLY_ROLE', error: 'Role is read-only' });
    }
    next();
  };
}

module.exports = {
  ROLES,
  ACTIONS,
  roleDef,
  canAccessModule,
  isReadOnly,
  requireCompanyMember,
  requireCompanyRole,
  requirePermission,
};
