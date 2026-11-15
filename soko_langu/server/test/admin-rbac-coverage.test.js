// Role catalog coverage for the admin console.
//
// The console ships a role editor whose grants are stored on each staff row, and
// routes gate privileged work with `requireAdminPermission('<domain>:<action>')`.
// Two lists, one contract: if a route starts gating on a permission no role
// grants, the feature becomes unreachable for every staff member but the shared
// owner secret — and nothing fails at boot. This test keeps them aligned.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');

const ROUTES = path.join(__dirname, '..', 'src', 'modules', 'admin', 'routes.js');
const { STAFF_ROLES } = require(ROUTES);

const source = fs.readFileSync(ROUTES, 'utf8');
const gated = [...new Set([...source.matchAll(/requireAdminPermission\('([^']+)'\)/g)].map((m) => m[1]))];

function grants(role, permission) {
  const perms = (STAFF_ROLES.find((r) => r.id === role) || {}).perms || [];
  if (perms.includes('*') || perms.includes(permission)) return true;
  return perms.includes(permission.split(':')[0] + ':*');
}

test('routes actually gate privileged endpoints', () => {
  assert.ok(gated.length >= 8, 'expected the admin routes to declare permission gates');
});

test('every gated permission is granted to at least one staff role', () => {
  const ungranted = gated.filter((permission) => !STAFF_ROLES.some((r) => grants(r.id, permission)));
  assert.deepEqual(ungranted, []);
});

test('the admin role can reach every gated endpoint', () => {
  const blocked = gated.filter((permission) => !grants('admin', permission));
  assert.deepEqual(blocked, []);
});

test('super_admin keeps the wildcard and support stays read-mostly', () => {
  assert.deepEqual(STAFF_ROLES.find((r) => r.id === 'super_admin').perms, ['*']);
  assert.equal(grants('support', 'finance:write'), false);
  assert.equal(grants('support', 'settings:write'), false);
  assert.equal(grants('support', 'users:write'), false);
});

test('staff roles keep stable ids and human labels', () => {
  const ids = STAFF_ROLES.map((r) => r.id);
  assert.deepEqual(ids, [...new Set(ids)]);
  for (const role of STAFF_ROLES) {
    assert.ok(role.label && role.label.trim(), role.id + ' is missing a label');
    assert.ok(Array.isArray(role.perms) && role.perms.length, role.id + ' has no permissions');
  }
});
