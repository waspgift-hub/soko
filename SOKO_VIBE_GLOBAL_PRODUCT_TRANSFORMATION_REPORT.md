# Soko Vibe — Global Product Transformation Report

## 1. Initial architecture findings

- Flutter app (`soko_langu/`) with go_router; mixed direct-Firestore and v1 HTTP API access gated by `ApiConfig` bridge flags.
- Node/Express backend (`soko_langu/server/`) with ~40 routers under `/api/v1`; Firestore + Postgres (Prisma) dual store; Redis + BullMQ.
- Buyer-request feature existed as a complete but **unmounted** backend module plus a legacy direct-Firestore Flutter client that exposed seller WhatsApp numbers in a publicly readable document.
- Flash sales, KYC, orders, AI, subscriptions are largely Firestore-era with varying levels of v1 migration.

## 2. Screens redesigned

- `lib/screens/requests/buyer_requests_screen.dart` — tabbed list (All/Active/Receiving offers/Limit reached/Expiring/Expired/Completed/Closed) with status chips, offer/view counts, time remaining.
- `lib/screens/requests/post_buyer_request_screen.dart` — full creation form (title, description, brand/model, condition, location, delivery, min/max budget, requirements, expiration, seller limit) loaded from backend policy.
- `lib/screens/requests/buyer_request_detail_screen.dart` — detail view with seller views, offers, WhatsApp contact, accept/decline, extend/close/reopen, offer submission.
- `lib/screens/profile/subscription_screen.dart` — redesigned Subscription & Billing: current plan hero, status badge, renewal/expiry, AI usage meter, plan comparison cards (buyer/seller/business) with feature bullets, AzamPay upgrade/trial, cancel/resume/downgrade, payment history, cancellation policy.
- `lib/screens/kyc/kyc_screen.dart` — revoked status handling, refresh action, null-safe document preview, pending status check.
- `lib/screens/orders/order_detail_screen.dart` — dispatched OTP card reachable, buyer-only verification under v1, dispute/cancel availability fixes.
- `lib/screens/home/category_products_screen.dart` — loads via v2 ProductRepository with Firestore fallback so API-published products appear.
- `lib/screens/notification/notification_preferences_screen.dart` — buyer-request view/offer toggles.

## 3. New functionality implemented

- Server-side buyer-request v1 API (mounted at `/api/v1/buyer-requests` and `/api/v1/admin/buyer-requests`).
- Expiry sweep (in-process, every 15 min) with idempotent expiration + expiring-soon notifications.
- Unique seller view tracking with deduplicated notifications.
- Consent-gated WhatsApp deep links with prefilled messages and click analytics.
- Request versioning + edit history + seller notification on important changes.
- Atomic offer counting with limit-reached transition and buyer notification.

## 4. Backend operations implemented

- `server/src/modules/buyer-requests/controller.js` — all read/write/admin handlers.
- `server/src/modules/buyer-requests/routes.js` — user + admin routers.
- `server/src/modules/buyer-requests/buyer-request-jobs.js` — expiry sweep entrypoint.
- `server/src/index.js` — schedules the sweep.
- `server/src/app.js` — mounts routers.

## 5. Database changes

- No new collections: reuses `buyer_requests`, `buyer_request_offers`, `buyer_request_views`, `buyer_request_events`, `app_settings/admin_settings.buyerRequests`.
- Status-for reads are now authoritative (lazy expiration) via `statusFor` preferring `expiresAtMs`.
- Settings-driven policy (no hardcoded limits in Flutter).

## 6. Admin controls introduced

- Admin endpoints: config get/patch, dashboard stats, list/detail, moderate (suspend/restore/close/extend), moderate offer (hide/review).
- Policy: enabled, expiry options, max expiry, active-per-buyer, offer limits, edits, extension, eligibility, visibility, auto-expire, seller-view notifications, moderation threshold.

## 7. Notification architecture changes

- Buyer-request notifications reuse the existing OneSignal + inbox path (`request-notifications.js`): seller viewed, offer received, limit reached, expiring soon, expired, updated, closed, moderated, offer decided.
- Preference gating via `user_notification_preferences` (default allow).
- One notification per unique seller/request view.

## 8. Security changes

- Removed legacy direct-Firestore buyer request path from Flutter (no more client-side `unlockedBy` or exposed WhatsApp).
- Ownership, authorization, validation, and atomic counters enforced server-side.
- WhatsApp reveal requires seller opt-in + KYC approval + valid number.
- Buyer phone never exposed automatically.

## 9. Performance improvements

- Bounded feed (100 docs) with in-memory facet filtering and pagination.
- Indexed Firestore queries for expiry sweeps.
- Idempotent sweeps with bounded batches.

## 10. Files created

- `server/src/modules/subscriptions/billing.js` (rewritten: shared collections, settlePayment, cancel/resume/downgrade, invoices)
- `server/src/modules/subscriptions/renewal.js` (rewritten: correct collection, trial expiry, scheduled downgrade)
- `lib/screens/profile/subscription_screen.dart` (redesigned)
- `lib/services/subscription_service.dart` (extended)
- `lib/screens/admin/admin_buyer_requests_screen.dart`
- `lib/screens/requests/my_buyer_requests_screen.dart`
- `lib/screens/kyc/kyc_screen.dart` (revoked handling, refresh, null-safe preview)
- `lib/screens/orders/order_detail_screen.dart` (OTP/dispute/cancel fixes)
- `lib/screens/home/category_products_screen.dart` (v2 repository fallback)
- `lib/screens/notification/notification_preferences_screen.dart` (buyer-request toggles)

## 11. Files modified

- `server/src/app.js` (mount routers)
- `server/src/index.js` (schedule sweep + renewal scheduler)
- `server/src/modules/subscriptions/routes.js` (upgrade/cancel/resume/downgrade/invoices)
- `server/src/modules/subscriptions/billing.js` (collection fix + settlePayment)
- `server/src/modules/subscriptions/renewal.js` (collection fix + trial expiry)
- `server/src/modules/payments/payment-service.js` (subscription webhook branch)
- `server/src/modules/legacy-compat/feature-compat.js` (flash-sale server validation)
- `lib/app/routes.dart`, `lib/app/router.dart` (new routes)
- `lib/services/buyer_request_service.dart` (HTTP client + admin + prefs)
- `lib/services/subscription_service.dart` (extended)
- `lib/screens/requests/buyer_requests_screen.dart` (redesigned)
- `lib/screens/requests/post_buyer_request_screen.dart` (redesigned)
- `lib/screens/profile/subscription_screen.dart` (redesigned)
- `lib/screens/profile/settings_screen.dart` (subscription link)
- `lib/screens/kyc/kyc_screen.dart`
- `lib/screens/orders/order_detail_screen.dart`
- `lib/screens/home/category_products_screen.dart`
- `lib/screens/notification/notification_preferences_screen.dart`

## 12. Files removed

- None (legacy service replaced in place; backward-compat classes retained).

## 13. Tests executed

- Backend: `npm test` → 796 pass, 0 fail, 72 skipped (live E2E disabled).
- `node --test test/buyer-requests-config.test.js` → 8 pass, 0 fail.
- `dart analyze` on changed Flutter files → no issues.
- New: subscription plans unit tests (5) still pass; flash-sale create route hardened server-side.

## 14. Actual test results

- 796 passing unit/integration tests; buyer-request config tests 8/8.
- Flutter static analysis clean on changed files.

## 15. Screenshots

- Not captured in this environment (requires a running device/emulator). Screens follow the existing One UI design tokens and Ds components; both light/dark themes inherit from `Theme.of(context).colorScheme`.

## 16. Known limitations

- My Purchases is still Firestore-backed; v1-native orders created through `/api/v1/orders` are not yet listed there.
- Order detail reads Firestore snapshots; a missing doc is not distinguished from a pending one.
- Flash sale stock is not decremented at purchase time (display-only sales).
- Admin buyer-request web panel (server/admin) not yet updated; REST endpoints are available.
- Firestore emulator tests skipped (no emulator in CI).

## 17. Remaining work

- Phase 7/8: migrate My Purchases + Order Details to the v1 orders API (list, detail, timeline, invoice).
- Phase 9: surface AI usage meter inside the AI chat screen and the upgrade CTA on `AI_QUOTA_EXCEEDED`.
- Phase 10/11: notification heads-up channels + design system unification + accessibility audit.
- Phase 12: further backend hardening (KYC phone/email verification state, flash-sale stock enforcement).
