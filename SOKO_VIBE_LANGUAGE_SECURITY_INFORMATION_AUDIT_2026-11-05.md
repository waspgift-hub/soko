# SOKO VIBE — APPLICATION-WIDE AUDIT (LANGUAGE, SECURITY, INFORMATION)
**Date:** 2026-11-05  
**Scope:** Audit only (no source/Firebase/auth/payment/database/production config changes). No files staged/unstaged/committed/reset by this audit.  
**Repo/branch:** `C:\Users\user\Desktop\SOKO VIBE\ttr` — branch `master`, up to date with `origin/master` (git status checked).  
**Flutter app root:** `soko_langu/` (`pubspec.yaml` name `soko_vibe`, version `1.0.1+2`, Dart `^3.11.5`).  
**Method:** Static code inspection with file-path evidence. Runtime behavior, live Firebase/Auth/Firestore/ClickPesa config, deployed server behavior, and rendered UI were **not** executed as authoritative proof except where stated.

## Executive Summary
Soko Vibe has real implementations for localization infrastructure, auth/OTP screens, app-lock (PIN/biometric UX), KYC submission/fee/OTP flows, seller verification reads, and legal/about screens. Several areas are **partially implemented, UI-forward, or have security gaps** requiring controlled follow-up:

| Area | Severity | Summary |
|---|---|---|
| 2FA/MFA sign-in enforcement | **Critical/High** | TOTP enrollment/management exists, but **no Firebase MFA sign-in challenge resolver found** in `lib/` (`FirebaseAuthMultiFactorException`/`MultiFactorResolver`/`resolveSignIn`/`getAssertionForSignIn` absent). “2FA enabled” may not enforce second factor at login. |
| Logout all devices (server) | **High** | Client posts `/api/v1/auth/logout-all`; server revocation service exists, but matching route handler not found in `server/src`/non-node_modules search. Revocation call is best-effort in client. |
| Boost payments/activation | **High** | Client uses legacy `/api/boost-product` + transaction-status polling; tiers/prices client-defined. Server validation, webhook settlement, idempotency, ownership, expiry/activation must be verified server-side. |
| Verification trust boundary | **High/Medium** | KYC/seller verification services use trusted reads and note server-controlled fields; full Firestore rules/admin workflow/document security still need verification (rules file modified in worktree). |
| Localization consistency | **Medium** | Large inline SW/EN map (`localization_service.dart`, 5570 lines). No app `LocalizationsDelegate`; `humanizeKey` fallback and possible hardcoded strings create mixed-language/maintainability risk. Automated parity audit needed. |
| Privacy/Terms/About | **Medium** | In-app legal screens are localization-key-driven; About contains official URLs/contacts. Source-of-truth, versioning, acceptance evidence, and legal parity need governance. |
| Auth/registration consent | **Medium** | Register UI has terms-acceptance state; enforce/blocking and consent evidence storage require confirmation. |
| Worktree release risk | **High (ops)** | Git has extensive staged/unstaged changes, including staged deletions of `payment-system/`, `whatsapp-service/`, and `soko_langu/lib/screens_new/`. **Do not assume safe; no git actions taken.** |

## Severity Scale
- **Critical:** Likely security/control bypass or material data-protection risk.
- **High:** Major functional/security gap or incomplete enforcement.
- **Medium:** Partial implementation, compliance/maintainability/UX risk, or needs verification.
- **Low:** Minor inconsistency or polish.

## 1. Kiswahili and English Language Consistency

### What currently works
- **Central service:** `soko_langu/lib/services/localization_service.dart` (5570 lines). Static `translations` with `'sw'` and `'en'`; `supportedLanguages={'sw':'Kiswahili','en':'English'}`; currency map/persistence.
- **Default/persistence:** `getLanguage()` defaults `sw` via SharedPreferences `language_code`; `setLanguage()` stores locally. `getCurrency()` defaults `TZS`.
- **Lookup:** `translate()` resolves requested → English → caller fallback → `humanizeKey()` (snake_case to title case). `trParams()` replaces `{n}` tokens.
- **Access pattern:** `soko_langu/lib/extensions/context_tr.dart` provides `context.tr`/`trParams`/`trError` and formatting helpers.
- **Key areas present (sample):** `pp_*`, `tos_*`, `about`, `mfa_*`, `verification_center_title`/`vc_*`, `kyc_*`, `boost` appear in SW/EN regions (heuristic sample count ~345 keys across those families split by section).

### What partially works / risks
- **No Flutter `LocalizationsDelegate` for app strings** (custom map via extension). System Material/Cupertino widgets may follow device locale, not app-selected language.
- **Fallback behavior:** English fallback and `humanizeKey()` can produce mixed-language or developer-readable labels when keys are missing.
- **Maintainability:** 5570-line monolith increases merge/conflict risk (worktree already has broad unrelated changes).
- **Hardcoded strings:** likely remain in some UI/server-generated messages; exhaustive parity scan not completed.

### Missing / UI placeholders / not evidenced
- Automated SW/EN key parity report, missing-key CI, unused-key detection.
- Full screen-by-screen Kiswahili/English QA and pluralization/gender strategy.

### Bugs / security weaknesses
- **Medium:** Mixed-language UX/comprehension risk in critical flows if keys missing.
- **Low:** `humanizeKey` can mask missing translations.

### File paths / services / dependencies
- `soko_langu/lib/services/localization_service.dart`
- `soko_langu/lib/extensions/context_tr.dart`
- `soko_langu/lib/main.dart` (localization delegates context)
- `soko_langu/lib/screens/profile/settings_screen.dart`

### Recommended corrections
1. Add automated SW/EN parity + missing-key checks in CI.
2. Consider structured ARB/JSON/generated localization with migration path.
3. Telemetry/safe fallback for missing keys in auth/payment/verification/legal.
4. Run hardcoded-string extraction for user-facing Dart screens.
5. Verify SMS/notification language templates (client/server).

## 2. Boost System — UI, Pricing, Payments, Activation, Expiry, Backend Integration

### What currently works (client-evidenced)
- **UI flow:** `soko_langu/lib/screens/boost/boost_product_screen.dart` — loads seller products, tier/provider/method selection, phone validation, payment initiation, BillPay instructions, USSD settlement polling with progress/success/failure/pending overlays.
- **Routes:** `lib/app/routes.dart` `boostProduct`; `lib/app/router.dart` registers `BoostProductScreen`; promo/product surfaces link to boost.
- **Pricing/tiers (client-defined):** `lib/screens/boost/boost_tiers.dart` defines `BoostTier` (bronze 1500/3d, silver 3000/7d popular, gold 10000/30d) and estimated reach/views/chats/savings/multipliers. Comment states values mirror `/api/boost-product` billing.
- **Service:** `lib/services/boost_service.dart`
  - `POST ${ApiConfig.baseUrl}/api/boost-product` (bearer token) with productId/name/image/price/tier/phone/paymentMethod/provider. Timeout 60s. **Single attempt** to avoid double charge.
  - `GET ${ApiConfig.baseUrl}/api/transaction-status/{orderId}` polls until `completed` (paid), `failed/cancelled`, or timeout pending.
- **Product fields:** `lib/models/product_model.dart` includes boost-related fields (`isBoosted`, `boostedUntil`, `boostTier`, etc.).

### Partially works / UI-forward
- Reach/views/chats/savings are **computed estimates** (marketing) — present as projections; verify copy avoids guarantee claims.
- Activation/expiry displayed based on model/state, but **authoritative activation/expiry** must be server/webhook driven.

### Missing / not evidenced
- **Server `/api/boost-product` handler not found** in `server/src`/non-node_modules quick search (may exist in legacy/other service; also note staged deletions of `payment-system/` and `whatsapp-service/` — **risk, do not assume**).
- Not evidenced: server tier/amount validation, ownership/eligibility checks, idempotency keys, ClickPesa webhook signature verification, atomic transaction+boost updates, expiry scheduler, refund/failure reconciliation, abuse/rate limits.

### Bugs / security weaknesses
- **High:** Never trust client price/tier/product ownership without server validation.
- **High:** Legacy base URL path (not v1 namespace) — confirm auth/rate-limit/CORS/logging.
- **Medium (ops):** Staged deletions of payment-related top-level services in git require explicit review before release.

### File paths / APIs / collections
- `soko_langu/lib/screens/boost/boost_product_screen.dart`, `boost_tiers.dart`, `widgets/*`
- `soko_langu/lib/services/boost_service.dart`
- `soko_langu/lib/models/product_model.dart`
- APIs (client): `POST /api/boost-product`, `GET /api/transaction-status/{orderId}`
- Implied collections: `transactions` (type boost, per comment), product boost fields — **confirm server truth**.

### Recommended corrections
1. Locate and audit actual boost backend + webhook handler.
2. Enforce server-side pricing/tier/product ownership/idempotency.
3. Make activation/expiry server-authoritative; add reconciliation jobs.
4. Add integration tests for pending/paid/failed/duplicate submit.
5. Review payment-service deletions and deployment topology before release.

## 3. Two-Factor Authentication (2FA) — Actual Security Implementation

### What currently works (present)
- **Service:** `soko_langu/lib/services/mfa_service.dart` — Firebase TOTP multi-factor enrollment using `TotpMultiFactorGenerator.generateSecret`, QR URI, `getAssertionForEnrollment`, `multiFactor.enroll`, enrolled-factor checks, unenroll, local recovery code generation, email-verified prerequisite.
- **State:** `soko_langu/lib/notifiers/auth_notifier.dart` tracks MFA enrolled/pending enrollment and loads MFA state (best-effort/time-bounded in init/login/register paths).
- **UI/routes:** `soko_langu/lib/screens/auth/mfa_enrollment_screen.dart`; `AppRoutes.mfaEnrollment` in router/routes; settings/verification center link to MFA management/enrollment.
- **Server artifact:** `soko_langu/server/src/services/totp.js` exists — purpose vs Firebase MFA must be clarified.

### Partially works / UI placeholders
- Enrollment UI and status display exist; this is not proof of enforced sign-in MFA.
- Recovery codes are generated/shown client-side; secure persistence/verification/invalidation not evidenced.

### Missing / critical gaps
- **No MFA sign-in challenge resolution found in `lib/`:** searches found no `FirebaseAuthMultiFactorException`, `MultiFactorResolver`, `resolver.resolveSignIn`, or `TotpMultiFactorGenerator.getAssertionForSignIn`. **Critical/High:** enrolled MFA may not be challenged during login.
- **No MFA verify/challenge screen file found** (`*mfa*verify*` in `lib/screens`).
- `verifyTotpForStepUp` implementation (as read earlier) appears limited and includes SDK-flow caveats — treat as **unverified for security enforcement**.

### Bugs / security weaknesses
- **Critical/High:** MFA status can create false sense of security if login path does not require second factor.
- **Medium:** Recovery codes without secure backend model are incomplete.

### File paths / dependencies
- `soko_langu/lib/services/mfa_service.dart`
- `soko_langu/lib/notifiers/auth_notifier.dart`
- `soko_langu/lib/repositories/auth_repository.dart`
- `soko_langu/lib/screens/auth/mfa_enrollment_screen.dart`
- `soko_langu/lib/screens/profile/settings_screen.dart`, `lib/screens/verification/verification_center_screen.dart`
- `soko_langu/server/src/services/totp.js`

### Recommended corrections
1. **Urgent:** handle `FirebaseAuthMultiFactorException` across all sign-in methods; build resolver/challenge UI; complete sign-in with verified TOTP assertion.
2. Add runtime security tests: enrolled user cannot complete login without valid second factor.
3. Define recovery-code backend (hash/store/consume/rate-limit) or remove unsupported claims.
4. Clarify/retire duplicate TOTP systems if unused.
5. Consider MFA/step-up for sensitive actions (withdrawals/admin/KYC changes) with server enforcement.

## 4. Logout and Session Management

### What currently works
- **Local logout:** `AuthNotifier.logout()` → `AuthRepository.logout()` signs out Firebase Auth; Google sign-out handled as implemented.
- **Logout all devices (client):** `AuthNotifier.logoutAllDevices()` → `AuthRepository.logoutAll()` posts `POST /api/v1/auth/logout-all` with bearer token (15s timeout, best-effort), then local logout. Settings UI has “logout all devices”.
- **Server revocation service exists:** `soko_langu/server/src/services/session-revocation.js` writes `session_revocations/{uid}.revokedAt`; `isSessionRevoked(uid, authTimeSec)` rejects tokens minted before stamp. Design note explains Firebase `checkRevoked` is unsuitable for custom-token sessions and expects `requireFreshSession` on sensitive routes.
- **App lock:** `soko_langu/lib/services/app_lock_service.dart` provides PIN/biometric local lock on background/resume; `lock_screen` exists. This is local UX security, not server session revocation.
- **Auth gate/state:** `lib/screens/auth/auth_gate.dart`, `lib/notifiers/auth_notifier.dart`, `lib/app/app_state.dart` handle loading, guest read-only mode, suspension, profile setup.

### Partially works / gaps
- **Server route handler not found:** `/api/v1/auth/logout-all` handler not located in `server/src`/non-node_modules quick search. Endpoint wiring and middleware coverage must be confirmed.
- **Best-effort behavior:** client still signs out locally if revocation call fails — may mislead users into thinking all devices were revoked.

### Missing / not evidenced
- Device/session inventory UI.
- Full `requireFreshSession` coverage on money/admin/auth-sensitive endpoints.
- Revocation on password reset/critical events (beyond Firebase defaults).

### File paths / APIs / collections
- `soko_langu/lib/notifiers/auth_notifier.dart`, `lib/repositories/auth_repository.dart`, `lib/services/app_lock_service.dart`, `lib/screens/profile/settings_screen.dart`, `lib/screens/auth/auth_gate.dart`
- Server: `soko_langu/server/src/services/session-revocation.js` (`session_revocations` collection)
- Client API: `POST /api/v1/auth/logout-all`

### Recommended corrections
1. Confirm/implement logout-all route and hook into `revokeUserSessions`/`requireFreshSession`.
2. Surface revocation result to user (or clearly label local-only fallback).
3. Test revocation with custom-token OTP sessions and token refresh.
4. Document local app lock vs server session invalidation.

## 5. Privacy Policy

### What currently works
- **In-app screen:** `soko_langu/lib/screens/legal/privacy_policy_screen.dart`, route `AppRoutes.privacyPolicy`/router registration. Renders localized keys (`pp_title`, `pp_last_updated`, `pp_founder_summary`, `pp_section_*`, `pp_section_pdpa_*`).
- **External reference:** `soko_langu/lib/screens/profile/about_app_screen.dart` defines `privacyPolicyUrl=https://www.sokovibe.co.tz/privacy.html`, `termsUrl`, `supportEmail`, `dpoEmail`.

### Partially works / gaps
- Content is key-driven in localization maps; legal accuracy, completeness, and parity with website/approved policy depend on governance.
- “Last updated”/founder summary are localized strings — verify authoritative version/date management.

### Missing / not evidenced
- Policy version acceptance tracking tied to user consent events (if required).
- PDPA/legal compliance validation (process).

### Files
- `soko_langu/lib/screens/legal/privacy_policy_screen.dart`
- `soko_langu/lib/services/localization_service.dart` (`pp_*`)
- `soko_langu/lib/screens/profile/about_app_screen.dart`

### Recommended corrections
1. Single approved legal source of truth with app/web sync.
2. Add policy version/effective date metadata and acceptance records if needed.
3. Validate all `pp_*` keys in SW/EN and render QA.

## 6. Terms and Conditions

### What currently works
- **In-app screen:** `soko_langu/lib/screens/legal/terms_of_service_screen.dart`, route `AppRoutes.termsOfService`. Renders localized `tos_*` keys (including chat/withhold sections).
- **External reference:** About screen links `https://www.sokovibe.co.tz/terms.html`.
- **Registration:** `soko_langu/lib/screens/auth/register_screen.dart` includes `_acceptedTerms` state (acceptance UX exists).

### Partially works / gaps
- **Medium:** Enforcement that registration cannot proceed without acceptance, and whether acceptance/version/timestamp is recorded, must be confirmed in full submit logic.
- Terms must cover real marketplace/escrow/payments/boost/refunds/KYC behaviors; legal review needed.

### Files
- `soko_langu/lib/screens/legal/terms_of_service_screen.dart`
- `soko_langu/lib/services/localization_service.dart` (`tos_*`)
- `soko_langu/lib/screens/auth/register_screen.dart`

### Recommended corrections
1. Confirm blocking acceptance + audit trail (version/date).
2. Keep SW/EN parity and app/web alignment.

## 7. About Soko Vibe

### What currently works
- **Screen:** `soko_langu/lib/screens/profile/about_app_screen.dart`, route `AppRoutes.about`.
- Displays app name/tagline, package version/build (`package_info_plus`), update check (`AppUpdateService`), credits (localized labels), contact `support@soko-vibe.com`, DPO `dpo@soko-vibe.com`, website/terms/privacy links, stable YouTube channel ID URL/label, features/thank-you/copyright.

### Gaps
- **Low:** Hardcoded official constants require governance when changed.
- **Low:** Update/support behavior depends on `AppUpdateService` and published listing.

### Files
- `soko_langu/lib/screens/profile/about_app_screen.dart`
- `soko_langu/lib/services/app_update_service.dart`

## 8. Account, Phone, Email, Identity, and Seller Verification

### What currently works (evidenced)
- **Auth/account:** `lib/repositories/auth_repository.dart`, `lib/notifiers/auth_notifier.dart` support email/password, Google, phone OTP/custom-token login, email OTP/custom-token login, registration/profile creation, email verification send/check, logout/logoutAll.
- **Email verification:** `lib/screens/auth/verify_email_screen.dart` uses universal OTP request flow; `AuthNotifier.verifyEmailOtp` integration pattern.
- **Phone OTP:** `lib/screens/auth/otp_screen.dart` wraps `OtpVerificationScreen`; login/register use OTP flows.
- **Verification hub:** `lib/screens/verification/verification_center_screen.dart` shows status for auth, email, phone linkage, MFA, KYC, Blue Tick using Firebase user + `SellerVerificationService` + `AuthNotifier`; CTAs open real flows. States it does not write verification state.
- **KYC:** `lib/screens/kyc/kyc_screen.dart` (passport-style data, DOB/address/phone/email/ID number, ID image, selfie, shop video cap 90MB), fee status/initiation/polling, phone/email OTP, submit via `KycService` (v1 + legacy fallback). `lib/services/kyc_service.dart`/`kyc_api.dart` implement API calls.
- **Seller/Blue Tick reads:** `lib/services/seller_verification_service.dart` (implements `AdEligibilitySource`) resolves self from `GET /api/v1/users/me` with Firestore fallback; other sellers from `GET /api/v1/trust/sellers/:id/passport` or `userPublic/{id}` fallback. Clears cache on auth transitions; notes client never writes verification flags and Firestore rules protect sensitive fields.
- **Server modules present:** `server/src/modules/kyc/kyc-service.js`, `modules/admin/kyc-documents-routes.js`, `modules/media/kyc-documents.js`, `services/otp-delivery.js`, `otp-store.js`, `middleware/otpGuard.js`.

### Partially works / UI-forward
- KYC end-to-end depends on server payment settlement, OTP delivery, signed document storage/URLs, and admin review transitions — not proven by client inspection.
- Phone “linked” in verification center may reflect Firebase phone number presence; proof-of-possession/ownership policy needs confirmation.
- Seller badge/ads exemption depend on authoritative trust data; all surfaces must use trusted service.

### Missing / not evidenced
- Admin review workflow/SLAs, liveness/anti-spoof, document retention/access policy details.
- Full Firestore rules verification for KYC/trust/admin/boost fields (file is modified in worktree; inspect carefully before deploy).

### Bugs / security weaknesses
- **High:** Any client/server path that accepts verification/boost/admin flags from users would be critical; services claim read-only trust boundary, but backend/rules must confirm.
- **Medium:** v1 + legacy fallbacks increase contract divergence risk.

### File paths / APIs / collections
- `soko_langu/lib/screens/verification/verification_center_screen.dart`, `lib/screens/kyc/kyc_screen.dart`, `lib/screens/auth/verify_email_screen.dart`, `otp_screen.dart`
- `soko_langu/lib/services/kyc_service.dart`, `kyc_api.dart`, `seller_verification_service.dart`, `trust_api.dart`
- APIs: `/api/v1/users/me`, `/api/v1/trust/sellers/:id/passport`, `/api/v1/auth/*` custom-token flows, `/api/kyc/*` legacy fallbacks, KYC v1 methods
- Collections (implied): `users`, `userPublic`, KYC/trust fields, `session_revocations`; admin/event collections — confirm.

### Recommended corrections
1. Full Firestore rules + server authorization audit for verification/trust/admin fields.
2. Verify signed document URL scope/expiry and access controls.
3. E2E KYC tests (submit, fee, OTP, approval/rejection, re-submit rules).
4. Confirm OTP/phone/email verification semantics are possession-based where required.

## 9. Authentication and Security Experience

### What currently works
- Auth screens and routes: login, register, forgot password, verify email, OTP, MFA enrollment, lock screen, auth gate/profile setup.
- Error handling uses localized messages (`context.trError`); resend cooldown comments align with server OTP guard patterns.
- Guest read-only browsing via `AuthGate` (`MainScreen` for unauthenticated), with protected actions expected to gate (verify across features).
- Firestore rules snippets (inspected) show intent to protect sensitive fields (`isAdmin`, `isSuspended`, `kyc`, `trust`, boost/seller verification-related fields) and restrict user reads — **full rules file review required**.

### Gaps / weaknesses
- **Critical/High:** MFA login enforcement gap.
- **High:** logout-all server route coverage unclear.
- **Medium:** Terms acceptance enforcement/evidence needs confirmation.
- **Medium:** Custom-token OTP auth + session revocation model requires endpoint coverage verification.
- **Ops risk:** large mixed worktree (payment/whatsapp deletions, server/app/theme/banner/social changes) complicates secure release.

### Recommended corrections
1. Prioritize MFA enforcement and session revocation verification.
2. Perform targeted penetration/logic review for authz, OTP, custom tokens, and Firestore rules.
3. Separate release units and re-verify before deploy.

## Implementation Priorities (Phased Plan)
1. **Phase 0 (safety):** review worktree intent, especially staged deletions of `payment-system/`, `whatsapp-service/`, `soko_langu/lib/screens_new/`; isolate change sets. No git actions taken.
2. **Phase 1 (critical security):** MFA sign-in challenge/resolution; logout-all endpoint + `requireFreshSession` coverage; Firestore rules deep audit.
3. **Phase 2 (trust/payments):** boost backend/webhook/idempotency/expiry; KYC/document/OTP/fee E2E and server authorization.
4. **Phase 3 (language/legal UX):** SW/EN parity automation, hardcoded string cleanup, legal/consent versioning and acceptance evidence.
5. **Phase 4 (QA/release):** targeted automated tests, rendered visual QA, staging validation, authorized production config review.

## Audit Evidence Notes
- Audit only. No runtime sign-in/MFA/KYC/payment execution.
- Server search excluded `node_modules`; some legacy handlers may live elsewhere.
- Report reflects files at `C:\Users\user\Desktop\SOKO VIBE\ttr` on 2026-11-05 with a heavily modified worktree.
