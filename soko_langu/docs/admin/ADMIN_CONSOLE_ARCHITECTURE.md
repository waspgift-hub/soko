# Soko Vibe — Admin Console Architecture

## 1. Components

```
Browser panel (server/admin/*)
   |  HTTPS + x-admin-secret / staff session token
   v
Node/Express API (soko_langu/server)
   |- /admin static mount (vanilla panel)
   |- /api/v1/admin/* (admin router + sub-routers)
   |- /api/admin/* (legacy compat)
   v
Commerce store (Firestore) + Firebase Auth + R2 + external providers
```

- **Frontend**: vanilla JS panel in `server/admin` (`index.html`, `admin.js`, `admin.css`),
  served at `/admin` and rewritten from the admin hostname. No build step; assets are static.
- **Backend**: Express app in `server/src/app.js`, routes in `server/src/modules/*`.
- **Auth**: `src/middleware/auth.js` `authenticateAdmin` (shared secret OR Firebase admin role
  OR staff session). RBAC in `src/middleware/admin-rbac.js`.
- **Data**: Firestore via `commerceStore`; Firebase Auth for users; R2 for media.
- **Audit**: `src/services/audit.js` -> `admin_audit_log` (append-only).
- **Rate limiting**: `src/middleware/rateLimiter.js` (adminLimiter on `/api/v1/admin`).

## 2. Route groups (logical)

- `/api/v1/admin/config/*` — app version, commission rate (public read for commission).
- `/api/v1/admin/dashboard`, `/metrics`, `/analytics/active`.
- `/api/v1/admin/users`, `/users/:id/status`.
- `/api/v1/admin/products`, `/products/:id`, delete/restore.
- `/api/v1/admin/withdrawals/*`.
- `/api/v1/admin/settings`, `/landing`.
- `/api/v1/admin/staff/*` (incl. login).
- `/api/v1/admin/audit-logs`.
- `/api/v1/admin/kyc/*` (kyc-documents-routes + kyc routes).
- `/api/v1/admin/ai/insights`.
- `/api/v1/admin` ads routes (ads module).
- `/api/admin/*` legacy compat (admin-compat).

## 3. Permission model

- Authentication first (`authenticateAdmin`), then `requireActiveAdmin` (suspended staff blocked),
  then `requireAdminPermission(permission)`.
- Staff sessions carry `permissions` array; otherwise role defaults from `ROLE_PERMISSIONS`.
- Shared secret => `super_admin` (wildcard) for owner break-glass.

## 4. Audit

- `writeAudit({ actorId, actorRole, action, entityType, entityId, oldState, newState, reason, requestId, ip, ... })`.
- Append-only; no update/delete endpoints.
- Sensitive values (passwords, tokens, raw secrets) are never copied.

## 5. Financial safety

- Payments verified via trusted backend/provider evidence (ClickPesa), never frontend status.
- Escrow release respects order state machine (`src/modules/orders/order-state-machine.js`).
- Withdrawals use idempotency + ledger service (`src/modules/wallet/ledger-service.js`).
- Admin cannot fabricate payment success or arbitrarily set order to paid/delivered/completed.
- Wallet adjustments require audited adjustment workflows (not arbitrary edits).

## 6. Localization

- Panel uses i18n dictionaries; Kiswahili default, English secondary. Centralized keys.

## 7. Deployment

- Target hostname: `https://www.admin.sokovibe.co.tz`.
- Backend: Render (`render.yaml`); admin hostname rewritten in `app.js` to `/admin`.
- Env: `ADMIN_SECRET` (>=32 chars in prod), `ADMIN_SESSION_SECRET`, Firebase Admin creds,
  `SOKO_API_URL`/service token for the Next artifact (unused).