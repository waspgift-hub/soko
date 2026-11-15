# Soko Vibe — Application Action Inventory

Generated as part of the Admin Control Center audit. This inventory describes the
*actual* code paths in the repository, not hypothetical features.

## 1. Source of truth

- **Backend**: Node/Express service in `soko_langu/server` (`src/index.js`, `src/app.js`).
- **Data store**: Firestore via `commerceStore` (`src/services/commerce-store.js`) + Firebase Auth.
- **Admin console (browser)**: static panel served from `server/admin` (`admin.js`, `admin.css`, `index.html`) on the `/admin` mount; admin hostname `admin.sokovibe.co.tz` / `www.admin.sokovibe.co.tz` is rewritten onto `/admin`.
- **Admin API**: `/api/v1/admin/*` (mounted in `src/app.js`), gated by `authenticateAdmin` + `requireAdminPermission`.
- **Audit**: `src/services/audit.js` (`writeAudit`, `auditFromReq`), append-only collection `admin_audit_log`.

## 2. User-facing actions (buyer / seller)

| Action | Origin | Role | Frontend | API | Backend service | DB records | Financial | Notification | Audited | Admin investigable |
|---|---|---|---|---|---|---|---|---|---|---|
| Register | Flutter app | guest | auth screens | /api/v1/auth/* | auth/controller.js | users | no | yes (welcome) | no | yes (user search) |
| Login / logout | Flutter app | user | auth screens | /api/v1/auth/* | auth/* | users, sessions | no | no | partial | yes |
| Password reset | Flutter app | user | auth screens | /api/v1/auth/* | auth/controller.js | users, otp | no | yes (SMS/email) | partial | yes |
| Profile update | Flutter app | user | profile | /api/v1/users/* | users/controller.js | users | no | no | no | yes |
| Follow user | Flutter app | user | social | /api/v1/social/* | social/social-service.js | follows | no | yes | no | partial |
| Create product | Flutter app | seller | seller products | /api/v1/products/* | products/product-service.js | products | no | no | no | yes (products list) |
| Edit product | Flutter app | seller | seller products | /api/v1/products/* | products/product-service.js | products | no | no | no | yes |
| Delete/archive product | Flutter app / admin | seller/admin | seller products / admin | /api/v1/products/*, /api/v1/admin/products/:id | products/product-service.js, admin routes | products | no | no | yes (admin) | yes |
| Upload product media | Flutter app | seller | seller products | /api/v1/media/* | media/upload-service.js | products, r2 | no | no | no | partial |
| Create buyer request | Flutter app | buyer | buyer requests | /api/v1/* | orders/legacy | buyer_requests | no | yes | no | yes |
| Place order | Flutter app | buyer | checkout | /api/v1/orders/* | orders/order-service.js | orders, escrow | yes (escrow) | yes | partial | yes |
| Make payment | Flutter app | buyer | checkout | /api/v1/payments/* | payments/payment-service.js | transactions, escrow | yes | yes | yes | yes |
| Payment callback (ClickPesa) | provider webhook | system | n/a | /api/v1/payments/webhooks/* | payments/payment-webhooks.js | transactions, orders, escrow | yes | yes | yes | yes |
| Request withdrawal | Flutter app | seller | wallet | /api/v1/wallet/* | wallet/wallet-service.js | withdrawals, ledger | yes | yes | yes | yes |
| Submit KYC documents | Flutter app | seller | KYC | /api/v1/kyc/* | kyc/kyc-service.js | kyc, media | no | yes | partial | yes |
| Submit report/complaint | Flutter app | user | report | /api/v1/reports/* (legacy) | moderation | reports | no | yes | partial | yes |
| Send message | Flutter app | user | chat | /api/v1/* | comments/* | messages | no | yes | no | partial |
| Subscribe to seller plan | Flutter app | seller | subscription | /api/v1/subscriptions/* | subscriptions/* | subscriptions, payments | yes | yes | yes | yes |
| Purchase boost | Flutter app | seller | ads/boost | /api/v1/ads/* | ads/* | boosts, payments | yes | yes | partial | yes |
| Use AI features | Flutter app | user | AI chat | /api/v1/ai/* | ai/* | ai_usage, credits | yes (credits) | no | partial | yes (AI management) |

## 3. Seller-facing actions

| Action | Origin | API | Backend | DB | Financial |
|---|---|---|---|---|---|
| Manage products / inventory | Flutter | /api/v1/products | products/product-service.js | products | no |
| Receive orders | system | /api/v1/orders | orders/order-service.js | orders | yes |
| Set shipping fees | Flutter | /api/v1/shipping | shipping/* | shipping | no |
| Confirm shipment / submit evidence | Flutter | /api/v1/handover, /api/v1/shipping | handover/*, shipping/* | orders, evidence | no |
| Manage subscriptions | Flutter/admin | /api/v1/subscriptions, /api/v1/admin/subscriptions | subscriptions/* | subscriptions | yes |
| Manage promotions | Flutter/admin | /api/v1/ads | ads/* | campaigns | yes |
| View earnings | Flutter | /api/v1/wallet | wallet/* | ledger | no (read) |
| Manage withdrawal requests | Flutter | /api/v1/wallet | wallet/* | withdrawals | yes |

## 4. System actions

| Action | Origin | Backend | DB | Financial | Notification |
|---|---|---|---|---|---|
| OTP generation/verification | auth | services/otp-store.js, otp-delivery.js | otp | no | yes (SMS) |
| Escrow state transitions | orders/payments | services/escrow-service.js, disputes/* | escrow | yes | yes |
| Subscription renewal | scheduler | subscriptions/renewal.js | subscriptions | yes | yes |
| Notification delivery (push/SMS/email) | workers | services/notification-worker.js, push-service.js, sms-service.js, mailer.js | notifications | no | yes |
| Background jobs (finance) | worker | services/finance-runner.js, workers/index.js | ledger | yes | partial |
| Media processing / R2 uploads | media | media/*, r2-client.js | products, kyc | no | no |
| Fraud checks | orders | trust/*, legacy-compat/fraud-checks.js | orders, alerts | no | yes (admin alert) |
| AI requests | ai | ai/*, ai-gateway.js | ai_usage | credits | no |
| Scheduled tasks | index.js | renewal, finance-runner, notification-worker, daily-engagement | various | yes | yes |

## 5. Admin actions (existing backend)

Provided by `/api/v1/admin/*` (`src/modules/admin/routes.js`) plus sub-routers:

- Dashboard KPIs: `GET /api/v1/admin/dashboard`, `GET /api/v1/admin/metrics`.
- Users: `GET /api/v1/admin/users`, `PUT /api/v1/admin/users/:userId/status`.
- Products: `GET /api/v1/admin/products`, `GET /api/v1/admin/products/:id`, `DELETE /api/v1/admin/products/:id`, `POST /api/v1/admin/products/:id/restore`.
- Withdrawals: `GET /api/v1/admin/withdrawals/:id/status`, `POST .../process`, `POST .../retry`, `GET /api/v1/admin/withdrawals` (legacy compat).
- Settings: `GET/PUT /api/v1/admin/settings`, `GET/POST /api/v1/admin/landing`.
- Staff: `GET/POST /api/v1/admin/staff`, `PUT/DELETE /api/v1/admin/staff/:id`, `POST /api/v1/admin/staff/login`.
- Audit logs: `GET /api/v1/admin/audit-logs`.
- KYC documents: `GET /api/v1/admin/kyc/:userId/:documentId/read-url` (kyc-documents-routes).
- AI insights: `POST /api/v1/admin/ai/insights`.
- Active analytics: `GET /api/v1/admin/analytics/active`.
- Data deletion: `GET/...` under `/api/v1/admin/data-deletion` (see routes).
- Ads admin: mounted via `ads/routes.js` under `/api/v1/admin`.
- Legacy compat admin: `/api/admin/*` (`legacy-compat/admin-compat.js`).

All admin routes require `authenticateAdmin` and per-route `requireAdminPermission(...)`.

## 6. Coverage gaps (honest)

Many prompt modules (executive dashboard charts, full seller management UI, KYC review UI beyond documents, order investigation UI, full finance reconciliation UI, subscription plan CRUD UI, advertising campaign UI, wallet adjustment UI, support ticketing UI, notification broadcast UI, AI management UI, system health UI) are only partially present or live in the legacy vanilla panel. The backend primitives exist; the unified console UI is the remaining work. See `ADMIN_ACTION_COMPLETENESS.md`.