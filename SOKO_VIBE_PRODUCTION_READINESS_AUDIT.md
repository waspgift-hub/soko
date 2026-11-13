# Soko Vibe production readiness audit

Inspection date: 2026-11-10. Workspace `C:\Users\user\Desktop\SOKO VIBE\ttr`, branch created for this pass: `checkpoint/pre-p0-hardening-2026-11-10`.

Runtime data source is Firebase Auth + Cloud Firestore. Prisma-shaped calls in `server/src` go through the Firestore store adapter. There is no evidence in this workspace that PostgreSQL is the production database. No new database was added.

This audit records what the code actually does. A screen, route, or collection is not treated as a finished feature.

## P0 — money, auth, integrity

| Feature | Existing implementation | Missing or defective | Required change | Tests | Acceptance |
| --- | --- | --- | --- | --- | --- |
| Email/password, Google, phone OTP, logout, logout-all | `lib/repositories/auth_repository.dart`, `server/src/modules/auth/controller.js`, `routes.js` (`/logout-all`) | Phone OTP delivery depends on WhatsApp or SMS credentials that are not in the repo | Keep one server-verified OTP path | `email-otp-verification.test.js` passed | User can sign in and revoke sessions without a client-side OTP check |
| Email OTP login contract | Flutter `POST /api/v1/auth/email-otp-login` and backend `routes.js` both exist | None found on the route name | None this pass | Email OTP tests passed (10) | Contract matches |
| OTP storage | `otp-store.js` stores salted SHA-256, TTL, attempt carry-over, single-use | Redis is the multi-instance store; memory fallback is per-process | Do not weaken hashing | Existing OTP guard tests were in the suite | Plaintext OTP is never stored |
| MFA / TOTP | Firebase enrollment in `mfa_service.dart`. `verifyTotpForStepUp` already returns false | Recovery codes were generated only on the device and never stored, so they could not recover an account | Server issues codes, stores SHA-256 hashes in `mfaRecovery/{uid}`, client shows that list once | `mfa-recovery.test.js` passed. Consume path not run against Firestore | Step-up never succeeds locally. A code works once on the server |
| Guest browse vs auth | Public product reads exist. Orders and checkout call authenticated APIs | Not re-audited screen by screen | Keep server checks as the boundary | Not re-run as UI tests | Backend rejects unauthenticated money mutations |
| Escrow | Canonical Firestore settlement is `commerce-store.settleEscrowToSeller`. `escrow-release.js` is the shared release function for the order engine. `escrow-service.js` is the legacy transaction orchestrator | AzamPay collects into the merchant wallet. A Firestore `escrowHolds` document is an internal ledger, not regulated custody. `cancelOrder` used to set `escrowReleased: true` without a disbursement. Settlement used to create a released hold and credit the seller when no hold existed | This pass refuses settlement without a `holding` row, marks the hold `disputed` when a dispute opens, and refuses unpaid-only cancellation to pretend a refund | `wallet-settle.test.js` and `order-escrow-flow.test.js` passed | Disputed holds are not auto-released. Duplicate settlement does not credit twice. No fake refund |
| Order state machine | `order-state-machine.js` is the vocabulary (includes `ESCROW_HELD`, `DISPATCHED`, `DISPUTED`, `REFUNDED`, `COMPLETED`, and legacy aliases) | Client must not send arbitrary status. Some legacy rows still use `pending` / `quoted` | Cancellations of paid states now throw `ESCROW_REFUND_REQUIRES_DISBURSEMENT` | State-machine tests inside `order-escrow-flow.test.js` passed | Illegal transitions throw |
| AzamPay | `azampay-provider.js` checkout `POST /mno/checkout`, token from `GenerateToken` | Callback shape is `utilityref` + `transactionstatus`, not the old ClickPesa `orderReference`/`status`. Callback password was required at boot and not checked. MNO was hardcoded to Airtel. `server/azampay.js` called methods on the class instead of an instance. Status URL `GET /payments/{ref}` is not the confirmed AzamPay status API | This pass authenticates callbacks (password, optional RSA, checksum with the checksum field excluded), maps official callback fields, and uses the configured MNO | `azampay-contract.test.js` 19/19 passed. No sandbox call | Webhook auth fails closed. Amount still checked in `confirmCollection`. Sandbox scenarios remain blocked |
| Commission | Default `platformCommissionPercent` is 0 unless env or admin settings say otherwise. Public policy is no commission | `.env.example` previously showed `0.035` | Example is now `0` with a comment that a non-zero rate requires an authorized policy | Not a new rounding suite | Buyers are not charged a hidden commission by the template |
| Disputes | `dispute-service.js` plus `escrow-service.openDispute` | Admin resolution that refunds the buyer still needs a real AzamPay disbursement. This pass does not invent one | Hold is marked `disputed` before the order status flips, which blocks `settleEscrowToSeller` | Not a new dispute integration test | Auto-release cannot pay a disputed hold |

## P1 — marketplace core

| Feature | Existing | Gap | Acceptance still open |
| --- | --- | --- | --- |
| Profiles, follow, block | Firestore user docs and follow flows exist | Private vs public field split was not re-proven this pass | Public endpoints must not return phone, wallet, or KYC |
| Products and media | Product store, R2 buckets in env template | Full media pipeline was not re-tested | Upload auth, size limits, deletion |
| Search | V1 search and ranking tests passed inside the server suite (ranking, pagination) | Swahili intent quality was not manually verified | No full-collection scan for normal search |
| Reviews | Code exists for verified-purchase checks in places | Not re-tested end to end | Rating only after a completed order the server can see |
| Chat | Participant checks exist in server chat modules | Not re-tested | No cross-user reads |
| Wishlist, buyer requests, deep links | Screens and models exist, including uncommitted buyer-request edits in the checkpoint | Not exercised on a device | Auth required for wishlist sync |

## P2 — subscriptions, admin, AI, i18n

| Feature | Existing | Gap |
| --- | --- | --- |
| Plans | Public prices are represented in product copy and server settings. This pass did not re-verify every quota | Do not invent quotas. Renewal must be an explicit payment if AzamPay has no approved recurring mandate |
| Boost | Bronze/Silver/Gold amounts exist in boost handlers. Payment goes through the same AzamPay collect path | Sandbox purchase not run |
| KYC | Manual review path and private R2 bucket intent exist. `kyc-document-privacy.test.js` failed in this run | Do not invent NIDA success. Fix the failing privacy test before calling KYC done |
| WhatsApp | Cloud API webhook verify + HMAC tests passed (`whatsapp` cases in the server suite) | Tokens are not in the repo. No live template send was attempted |
| Admin console | Next.js app under `soko_langu/apps/admin-console` with server session code and RBAC tests on disk | `data.ts` still serves sandbox fixtures when `isDevSandbox()` is true. Legacy server admin still accepts `x-admin-secret`. Not browser-verified this pass |
| AI assistant | Provider order groq/gemini/cloudflare in env template | Must not invent stock or release escrow. Not re-tested against live catalog |
| i18n | EN/SW maps exist, including MFA strings | Not proven free of mixed language on every screen |
| Legal | Public site and in-app pages exist | Account deletion and export were not re-verified |

## Production blockers

1. AzamPay does not provide regulated escrow custody in the API this server calls. Funds are a merchant collection plus an internal hold. Do not describe that as bank-grade escrow.
2. No `soko_langu/server/.env` in the workspace. AzamPay sandbox and WhatsApp test delivery were not run. Scenarios A–E are blocked, not passed.
3. `GET /payments/{orderReference}` is still the status query. It was inherited from the previous gateway shape and is not confirmed against AzamPay's current status API. Authenticated callbacks are the confirmation path. A second live query is not yet reliable.
4. Buyer refunds are not executed as AzamPay disbursements. Paid orders cannot be marked refunded by `cancelOrder`.
5. Admin authorization is not yet a single server-side RBAC session. Shared-secret admin access remains in the legacy server.
6. KYC privacy and contact OTP tests failed in the full server run.
7. Load testing for a large user base was not done.
