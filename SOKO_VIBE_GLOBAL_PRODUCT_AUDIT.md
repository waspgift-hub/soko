# Soko Vibe — Global Product Experience Audit

Generated: 2026-11-17

## 1. Flutter application architecture

- App entry: `soko_langu/lib/main.dart`. Routing via `go_router` (`lib/app/router.dart`, `lib/app/routes.dart`).
- State management: `provider` + notifiers; services under `lib/services/`.
- Design system: two parallel systems — `lib/design_system/` (tokens, theme, components) and `lib/theme/` + `lib/ui/` + `lib/widgets/ds/`. Risk of duplication.
- Localization: `lib/services/localization_service.dart` + `lib/extensions/context_tr.dart`; bilingual (en/sw). `context.tr('key')`.
- Backend access: mix of direct Firestore (`cloud_firestore`) and HTTP v1 API (`ApiConfig.v1`) controlled by bridge flags in `ApiConfig`. Most modern features use the v1 API.

## 2. Existing navigation and routes

- Routes centralized in `lib/app/routes.dart` and `lib/app/router.dart`.
- Buyer request routes: `/buyer-requests`, `/post-buyer-request` (and now `/buyer-requests/:id`).
- Flash sale routes: `/flash-sale`, `/create-flash-sale`.
- Deep-link aliases and web fallback routes in `server/src/modules/sharing/fallback-routes.js`.

## 3. Design system and reusable components

- `lib/widgets/ds/` provides `DsCard`, `DsButton`, `DsChip`, `DsBadge`, `DsAvatar`.
- Color scheme extensions in `lib/theme/app_colors.dart` (brandSuccess, contentMuted, cardBase, hairline, etc.); no `warning` token.
- Dark mode uses brightness-based scheme; some screens use arbitrary greys — needs true-black audit.
- Responsive helpers limited; tablet/web layouts mostly stretch mobile.

## 4. Existing Buyer Request implementation (before)

- Legacy: direct Firestore collection `BuyerRequests` (`lib/services/buyer_request_service.dart`), client-side "unlock contact" via `unlockedBy` array. WhatsApp link stored in the document and readable by any signed-in user — **security hole**.
- No expiration, seller limits, editing, versioning, view tracking, or admin config.
- Backend module `server/src/modules/buyer-requests/` existed (config, store, service, notifications) but was **not mounted** (no controller/routes). Untracked, untested.

## 5. Existing Flash Sale implementation

- Model: `lib/models/flash_sale_model.dart`; service `lib/services/flash_sale_service.dart` (Firestore streams).
- Screens: `lib/screens/home/flash_sale_screen.dart`, `lib/screens/profile/create_flash_sale_screen.dart`.
- Backend: no dedicated flash-sale module found in `server/src/modules` (search returned none). Flash sales are Firestore-only; no server-side pricing/stock enforcement, no scheduling jobs, no admin controls beyond Firestore.
- Gaps: no multi-step create flow with inventory reservation, no admin dashboard analytics, no reliable expiration alerts.

## 6. Admin management capabilities

- Web admin panel: `server/admin/` (single `admin.js`).
- Flutter admin screens under `lib/screens/admin/` (dashboard, KYC, banners, broadcast, users, transactions).
- Admin auth: shared secret + optional TOTP + staff sessions (`middleware/auth.js`).
- RBAC partially implemented (staff permissions). Buyer-request admin endpoints now added.

## 7. Authentication and authorization

- Firebase ID token → Express `authenticate` middleware resolves Postgres user (provisions row if missing).
- Account status gates (suspended/deleted). Session revocation via `requireActive`/`requireFreshSession` on money routes.
- Admin gate `authenticateAdmin` supports secret or staff token.
- Buyer-request endpoints enforce ownership server-side.

## 8. Subscription and payment architecture

- Service: `lib/services/subscription_service.dart`; backend `server/src/modules/subscriptions/` (plans.js).
- Payments: Azampay/ClickPesa (`server/azampay.js`, `clickpesa.js`), wallet, escrow, refunds.
- No dedicated Subscription screen in Settings found — gap (Phase 5).
- Plans fetched from backend config (good); entitlements tied to AI usage.

## 9. KYC services and verification workflow

- Flutter: `lib/screens/kyc/kyc_screen.dart` (1301 lines), `lib/services/kyc_service.dart`, `kyc_api.dart`.
- Backend: `server/src/modules/kyc/`, admin `modules/admin/kyc-documents-routes.js`.
- Statuses mapped to backend. Document privacy enforced via rules (test `kyc-document-privacy.test.js`).
- Gaps: UX modernization, camera guidance, quality validation (Phase 6).

## 10. My Purchases and Order Details

- `lib/screens/orders/my_purchases_screen.dart` (1772 lines), `order_detail_screen.dart` (3162 lines).
- Backend order state machine (`modules/orders/order-state-machine.js`), escrow, handover OTP/QR.
- Heavy screens; need redesign for clarity and timeline (Phases 7/8).

## 11. AI Chat and AI usage management

- `lib/screens/ai/agent_screen.dart`, `ai_assistant_screen.dart`; `lib/services/persistent_ai_chat_service.dart`.
- Backend: `modules/ai/`, `modules/ai/chat/`, `modules/agent/`.
- Usage accounting server-side (AI usage limits per plan). Upgrade alerts partially.
- Gaps: streaming UX, usage meter, contextual upgrade screen (Phase 9).

## 12. Firebase, database and backend architecture

- Firestore (Firebase) for legacy + many modules; Postgres (Prisma) for v2 trust-commerce (orders, products, users, wallet, reviews, comments, KYC).
- Express app (`server/src/app.js`) mounts ~40 routers under `/api/v1`.
- Commerce store seam (`services/commerce-store.js`) abstracts Firestore/Postgres.
- Redis for locks/queues; BullMQ for finance/notification/media queues.

## 13. OneSignal and FCM notification implementation

- OneSignal app ID in `ApiConfig.oneSignalAppId`; `lib/services/notification_service.dart`, `notification_api.dart`, `local_notification_service.dart`.
- Backend: `modules/notifications/`, `modules/legacy-compat/notify.js`, `notificationPrefs.js`.
- Android channels/importance: buyer-request notifications use default (not forced high). Good.
- Idempotency: notification events use unique keys/throttles; buyer-request view notification once per seller/request.

## 14. Background workers, scheduled tasks and queues

- BullMQ queues: media, finance, notifications (`services/queue.js`).
- Finance worker in-process by default (`finance-runner.js`).
- Buyer-request expiry sweep now scheduled in-process every 15 min (`buyer-request-jobs.js`).
- Daily engagement scheduler in `index.js`.

## 15. Analytics, logging and error monitoring

- `lib/services/analytics_service.dart`, `error_reporting_service.dart`.
- Backend: request ID correlation, structured JSON error logs, activity tracking.
- Load shedder, rate limiters, request timeouts.

## Current problems (summary)

1. Buyer request feature was legacy direct-Firestore with exposed WhatsApp numbers and no server authority — **fixed** by wiring v1 API.
2. Flash sales are Firestore-only with no server-side enforcement — **partial** (documented, not fully migrated).
3. No Subscription screen in Settings — **gap**.
4. KYC/order/AI screens need UX modernization — **gap** (large; tracked).
5. Design system duplication and dark-mode true-black inconsistency — **gap**.
6. Admin buyer-request web UI not yet built (endpoints available).

## Security issues identified

- Legacy buyer request stored seller WhatsApp in a publicly readable Firestore doc.
- Client-trusted budgets/expiration in legacy form.
- Fixed by server-side validation, ownership checks, atomic counters, and consent-gated WhatsApp reveal.

## Recommended implementation sequence

1. Wire buyer-requests backend + tests (done).
2. Migrate Flutter buyer-request UI to v1 API (done: model, service, list, detail, create).
3. Add buyer-request detail route (done).
4. Flash sale backend enforcement + multi-step create (next).
5. Subscription screen in Settings (next).
6. KYC UX modernization (next).
7. My Purchases / Order Details redesign (next).
8. AI chat UX + usage meter (next).
9. Design system unification + true-black dark mode + accessibility (next).
10. Admin web UI for buyer requests (next).
