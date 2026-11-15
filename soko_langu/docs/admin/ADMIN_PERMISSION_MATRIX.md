# Soko Vibe — Admin Permission Matrix

Roles are enforced server-side via `src/middleware/admin-rbac.js` (`can`, `requireAdminPermission`)
and the staff account store (`admin_staff` in Firestore). The shared `x-admin-secret` maps to
`super_admin` (wildcard). Firebase-backed staff carry their own `permissions` array, which
overrides role defaults.

## Roles

Role ids below exist in **both** places that matter: `ROLE_PERMISSIONS` in
`src/middleware/admin-rbac.js` (used when the role comes from a Firebase user or
a staff row without an explicit permission list) and `STAFF_ROLES` in
`src/modules/admin/routes.js` (the catalog the console's staff editor renders and
the API validates against).

| Role id | Purpose |
|---|---|
| super_admin | Wildcard `*`; also what the shared `x-admin-secret` maps to. |
| owner | Wildcard `*`; break-glass owner account. |
| admin | Broad operator: users, orders, products, refunds, disputes, KYC, finance, settings, staff, audit, landing. |
| operations_admin | Ordinary operations: users, orders, products, disputes, support; KYC read, reports/audit read. |
| finance_admin / finance | Payments, escrow, wallets, withdrawals, commissions, reconciliation, reports. `finance` is the id already on live rows. |
| support_admin / support | User investigation, disputes read, notifications, landing email. |
| moderation_admin / moderator | Product and content moderation, reviews, refunds, disputes, KYC. |
| kyc_reviewer | KYC review only. |
| security_admin | Security events, sessions, account restrictions, audit. |
| technical_ops | System health, integrations, jobs, config, logs. |
| analyst / analyst_readonly | Read-only reports and analytics. |

## Permission domains

`users`, `sellers`, `products`, `catalog`, `orders`, `disputes`, `support`, `notifications`,
`reviews`, `finance`, `payments`, `wallets`, `withdrawals`, `escrow`, `commissions`,
`reconciliation`, `kyc`, `security`, `sessions`, `system`, `integrations`, `health`, `logs`,
`jobs`, `config`, `staff`, `audit`, `reports`, `analytics`, `landing`, `broadcasts`.

Each domain supports `:read`, `:write`, and `:*` (domain wildcard). `*` is platform wildcard.

## Matrix (read / write)

| Capability | super | ops | finance | support | moderation | kyc_rev | security | tech_ops | analyst |
|---|---|---|---|---|---|---|---|---|---|
| Dashboard / metrics | RW | R | R | R | R | R | R | R | R |
| User management | RW | RW | R | RW | R | R | RW | R | R |
| Seller management | RW | RW | R | R | R | - | R | - | R |
| Product / catalog moderation | RW | RW | - | - | RW | - | - | - | R |
| KYC review | RW | R | - | - | R (subset) | RW | - | - | - |
| Orders investigation | RW | RW | R | R | R | - | R | - | R |
| Disputes | RW | RW | R | R | RW | - | R | - | R |
| Payments / transactions | RW | R | RW | - | - | - | R | - | R |
| Escrow | RW | R | RW | - | - | - | R | - | R |
| Wallets / withdrawals | RW | - | RW | - | - | - | - | - | R |
| Subscriptions | RW | R | RW | - | - | - | - | R | R |
| Advertising / campaigns | RW | RW | - | - | - | - | - | R | R |
| Notifications / broadcasts | RW | RW | - | RW | - | - | - | R | - |
| AI management | RW | - | - | - | - | - | - | RW | R |
| System config (high-risk) | RW | - | - | - | - | - | R (security) | RW | - |
| Staff & permissions | RW | - | - | - | - | - | - | - | - |
| Audit logs | RW | R (own actions) | R (finance) | R (support) | R (moderation) | R | RW | R | R |
| System health / logs | RW | - | - | - | - | - | R | RW | - |

`R` = read, `W` = write, `RW` = read+write, `-` = no access.

## Enforcement notes

- Frontend hiding is never sufficient; privileged endpoints call `requireAdminPermission`.
- Live gates in `src/modules/admin/routes.js` (the permissions routes actually check):

  | Permission | Endpoint | Why |
  |---|---|---|
  | `users:write` | `PUT /users/:id/status`, `PUT /data-deletion-requests/:id/status` | Account state and data erasure. |
  | `kyc:write` | `PUT /sellers/:sellerId/verification` | Approving a seller unlocks selling and withdrawals. |
  | `products:moderate` | `DELETE /products/:id`, `POST /products/:id/restore` | Catalog takedown/restore. |
  | `finance:read` | `GET /withdrawals`, `GET /withdrawals/:id/status` | Money read access. |
  | `finance:write` | `POST /withdrawals/:id/process`, `.../retry`, `.../confirm` | Moving real money. |
  | `settings:write` | `PUT /settings` | Commission, escrow window, gateway credentials. |
  | `staff:write` | `POST/PUT/DELETE /staff` | Granting permissions. |
  | `landing:write` | `POST /landing/broadcast` | Bulk email to the waitlist. |

- Staff rows carry their own `permissions` array (from `STAFF_ROLES`), which takes
  precedence over role defaults; `test/admin-rbac-coverage.test.js` fails if a route
  gates on a permission no role grants, or if `admin` cannot reach a gate.
- Shared secret (`x-admin-secret`) grants `super_admin` and is intended as the owner
  break-glass path; production requires a non-placeholder secret of >= 32 chars.
- High-risk actions (commission rate, subscription pricing, large withdrawals, permission
  changes, disabling security controls) require step-up auth + explicit reason + audit event;
  second approval where appropriate. The existing `x-admin-totp` header supports TOTP MFA.
- Suspended/deleted staff accounts are blocked by `requireActiveAdmin`.