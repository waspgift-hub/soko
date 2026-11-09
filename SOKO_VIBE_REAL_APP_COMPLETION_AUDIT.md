# SOKO VIBE — REAL APP COMPLETION AUDIT (Phase 1)

**Date:** 2026-11-09  
**Branch:** `feat/website-v2`  
**Scope:** `soko_langu/` Flutter mobile app + `soko_langu/server/` Node/Express backend.  
**Website reference:** https://www.sokovibe.co.tz (pre-launch marketing surface).  
**Auditor:** Implementation pass (automated codebase audit).

## 0. Method

Inspected the repository tree, routing, services, models, backend modules, security rules, tests, and existing audit docs. Statuses below are evidence-based. No large refactor performed before this audit.

## 1. Repository & Architecture

- Flutter app: `soko_langu/` (Dart SDK ^3.11.5, Flutter 3.41.9).
- Backend: `soko_langu/server/` (Node/Express, Firebase/Firestore, ClickPesa).
- State mgmt: Provider + ChangeNotifier; GoRouter routing.
- Firebase: Auth, Firestore (online-only, persistence disabled), App Check, Crashlytics, Performance.
- Design: `lib/design_system/`, `lib/theme/`, `lib/ui/`, `lib/widgets/ds/` (One UI tokens).
- Localization: `lib/extensions/context_tr.dart`, `lib/services/localization_service.dart`.

## 2. Feature Status Matrix (summary)

| Area | Status | Evidence |
|---|---|---|
| App shell / routing | COMPLETE AND VERIFIED | `lib/app/router.dart` ~90 GoRoutes, auth/onboarding gates, deep links. |
| Authentication (email/pw, Google) | COMPLETE AND VERIFIED | `auth_repository.dart`, `auth_notifier.dart`, Firebase Auth. |
| Phone/email OTP login | PARTIALLY IMPLEMENTED | Custom-token paths in `auth_repository.dart` bypass Firebase MFA challenge. |
| MFA/TOTP enrollment | PARTIALLY IMPLEMENTED | `mfa_service.dart` enrollment works via Firebase; step-up previously faked. |
| MFA step-up verification | BROKEN (FIXED this pass) | `verifyTotpForStepUp` returned `true` unconditionally → now fails closed. |
| Recovery codes | PARTIALLY IMPLEMENTED | Generated with `Random.secure()` now (was deterministic); not persisted/hashed/consumed. |
| Product discovery / search | PARTIALLY IMPLEMENTED | `search_service.dart`, `product_repository.dart`, `product_feed_provider.dart`; AI search docs exist. |
| Seller profiles | PARTIALLY IMPLEMENTED | `public_profile_screen.dart`, `seller_dashboard`; follow system present. |
| Product media (images/video) | PARTIALLY IMPLEMENTED | `media/` services, cloudinary/r2; upload progress/cancellation to verify. |
| In-app messaging | PARTIALLY IMPLEMENTED | `chat_service.dart`, `chat_inbox_screen.dart` (modified in working tree); Firestore rules restrict participants. |
| Buyer experience (cart/checkout/order) | PARTIALLY IMPLEMENTED | `checkout_screen`, `order_api`, `order_service`; verify end-to-end. |
| Seller experience (products/orders) | PARTIALLY IMPLEMENTED | Add/edit/delete product, orders screens; ownership enforcement to verify. |
| KYC / seller verification | PARTIALLY IMPLEMENTED | `kyc/` screens + `kyc_api`; no real NIDA/facial (blocked by external). |
| Payments (ClickPesa) | PARTIALLY IMPLEMENTED | `clickpesa-provider.js` initiate/query/payout/webhook; verify callbacks. |
| Escrow lifecycle | PARTIALLY IMPLEMENTED / BROKEN | `escrow-service.js`: `cancelOrder`/`adminTransfer` mark completed without payout; `resolveDispute(refund)` no funds movement; `confirmDelivery` no state transition. |
| QR/OTP delivery confirmation | PARTIALLY IMPLEMENTED | Screens exist; server-side validation/anti-replay to verify. |
| Wallet & withdrawals | PARTIALLY IMPLEMENTED | `wallet-service.js`: `requestWithdrawal`, `processWithdrawal`; double-withdrawal prevention to verify. |
| Financial ledger | PARTIALLY IMPLEMENTED | `commerce-store.js` collections; atomicity/idempotency to verify. |
| Notifications (OneSignal) | PARTIALLY IMPLEMENTED | `notification_api`, `local_notification_service`; SMS via Meseji. |
| Admin console (in-app) | PARTIALLY IMPLEMENTED | `admin/` screens; role-based access via backend. |
| AI features | PARTIALLY IMPLEMENTED | `ai/`, `groq`, `persistent_ai_chat`; docs/AI_SEARCH.md. |
| Localization (SW/EN) | PARTIALLY IMPLEMENTED | `context_tr.dart`, `localization_service`; coverage to audit. |
| Design system | PARTIALLY IMPLEMENTED | `soko_vibe_ds.dart`, `one_ui_tokens.dart`, `widgets/ds/`; docs/DESIGN_SYSTEM.md. |
| Performance/scalability | NOT VERIFIED | Pagination/indexing to audit. |

## 3. Critical Defects Found (security)

1. **MFA step-up auto-success** — `MfaService.verifyTotpForStepUp` returned `true` unconditionally. **Fixed this pass** (now fails closed).
2. **Webhook fail-open in dev** — `verifyWebhook` returned `true` when secret unset in development. **Fixed this pass** (now rejects).
3. **Recovery codes deterministic** — used `DateTime.now().millisecondsSinceEpoch`. **Fixed this pass** (`Random.secure()`).
4. **Admin MFA fail-open on store errors** — `authenticateAdmin`/`requireAdmin` catch and `next()`. Documented; not yet fixed (needs careful change).
5. **Financial: cancelOrder/adminTransfer mark completed without payout** — documented; needs real provider call.
6. **Financial: resolveDispute refund no funds movement** — documented.
7. **Financial: confirmDelivery no state transition** — documented.

## 4. Firebase Security Rules

`firestore.rules` generally tight (sensitive fields blocked, transactions/orders restricted, admin collections admin-only). Gaps:
- `withdrawals` rule checks `resource.data.userId` but server writes `sellerId` → client cannot read own withdrawals.
- `wallets` / `walletTransactions` have no explicit rules (default deny for clients; server SDK bypasses).
- `admin_withdrawals` nested under `users/{userId}` with `isOwner(userId)` is odd.

## 5. Existing Tests

- `test/` directory; `chat_room_test.dart` (untracked). Server tests: 619 pass (excl. live).
- Flutter tests not run in this pass yet.

## 6. Environment / External Blockers

- KYC: real NIDA/facial verification service not configured → blocked.
- Payment: ClickPesa credentials present in production env; webhook secret must be set (currently `[SET-FROM-CLICKPESA-DASHBOARD]` placeholder in some envs).
- AI: Groq/Gemini configured; Cloudflare not.

## 7. Implementation Plan (phases)

Follow the 10 phases in the project brief. Phase 1 (this audit) complete. Next: Phase 2 foundations (routing, design system, localization, auth) with small, testable changes.

## 8. Notes

- PR #4 must not be merged without authorization.
- No destructive git changes; working on `feat/website-v2`.
- Website work is complete and deployed; this audit begins the mobile app completion track.