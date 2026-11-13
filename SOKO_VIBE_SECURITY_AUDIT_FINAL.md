# Soko Vibe security audit (this pass)

Date: 2026-11-10. Scope is the code inspected and the defects fixed in this pass. This is not a penetration test and not a certification.

## Authentication

- Firebase ID tokens are verified in `server/src/middleware/auth.js`. Logout-all stamps `sessionRevokedAt` so routes that call `requireFreshSession` reject older tokens.
- Email OTP login is server-side. The code is checked in `otp-store.js` (salted SHA-256, expiry, single-use, attempt counter that resends do not reset). The client does not get to declare an email verified.
- Phone OTP is purpose-bound in the same store. Delivery is WhatsApp or the existing SMS fallback. Neither channel was live-tested.
- `verifyTotpForStepUp` in `mfa_service.dart` returns false. It does not accept a TOTP by length or by local comparison.
- Recovery codes are now created with `crypto.randomBytes` on the server, stored as SHA-256 hashes, and consumed inside a Firestore transaction so a code cannot be reused. Firestore rules deny all client access to `mfaRecovery`. The consume route only says `INVALID_RECOVERY_CODE` on failure. It does not by itself bypass Firebase MFA sign-in. A stolen unused code still proves possession of that code until it is used. Regeneration replaces the whole set.

## Authorization

- Money routes in the v1 payment service check the buyer id and the order state before creating a payment.
- `openDispute` and `cancelOrder` reject a buyer id that does not match the order.
- `x-admin-secret` does not authenticate. `authenticateAdmin`, `verifyAdmin`, `requireAdmin`, and `requireKycReviewer` ignore it. A missing session is 401. A Firebase user who is not `admin` or `super_admin` is 403. `kyc-document-privacy.test.js` asserts that a correct shared secret and a forged secret both fail.
- The legacy file `server/admin/admin.js` still puts `x-admin-secret` on its fetch calls. The API does not read that header. The Next.js console still sets the header in `backend.ts` from `SOKO_ADMIN_SERVICE_TOKEN` or `ADMIN_SECRET`. That header cannot open an admin route.
- Cron routes still accept `x-cron-secret` when it matches `CRON_SECRET` or `ADMIN_SECRET`. That is a machine secret for `POST /cron/release-escrows` and daily engagement. It is not an admin session.
- Local `auth-rbac.test.js` now gets 401 from the previously missing money routes. `e2e.live` still receives 404 or 400 from the deployed Render host for transaction-status, escrow release, order transition, and buyer-transport. Those live cases failed. They do not prove the deployed process has the new checks.

## Financial integrity

- `settleEscrowToSeller` credits a seller only when the escrow hold status is `holding`, and only once per ledger id. A missing hold throws `ESCROW_HOLD_MISSING` instead of inventing a credit. `disputed` throws `ESCROW_DISPUTED`.
- `escrow-release.js` still allows `AUTO_RELEASE` and `BUYER_CONFIRMED` to see only `holding`. `DISPUTE_TO_SELLER` is the path that may see `disputed`.
- `openDispute` writes `status: disputed` on the Firestore hold first.
- `cancelOrder` does not mark escrow released and does not mark a paid order refunded.
- Webhook dedup remains in `payment-service.js` (`recordWebhookEvent` claim). Amount mismatch still rejects confirmation.
- Dispute resolution and `adminTransfer` leave the order `REFUND_PENDING` with `DISBURSEMENT_NOT_CONFIRMED`. They do not set `REFUNDED`.
- `refund-service.disburseRefund` marks the refund `COMPLETED` only when `initiatePayout` returns a body, then the caller finalizes the order. A null or thrown payout does not move the order to `REFUNDED` and does not create a second payout row when one already exists. The unit tests mock that return value. No live disbursement ran.
- What is still unsafe to claim: AzamPay has not been shown to hold buyer funds in a regulated escrow account. The hold is an internal ledger after a merchant collection. `confirmCollection` still skips a live status re-query when the callback includes a provider reference. That is acceptable only because the callback must now pass password, RSA, or checksum checks. The status URL itself is not a confirmed AzamPay API. The disbursement path's URL was not confirmed against a live AzamPay call.

## OTP and MFA

- OTP plaintext is not written to Firestore.
- Recovery codes are not stored in plaintext.
- Rate limits exist (`otpGuard`, auth limiters). They were not load-tested across many instances beyond the existing Redis design.

## Firestore rules

- Sensitive wallet and admin fields are in `noSensitiveFieldChanges`.
- `mfaRecovery` is explicitly denied to clients. The Admin SDK bypasses rules, which is how the server writes hashes.
- A full rules emulator run was not done.

## Payments and webhooks

- Missing authenticator configuration rejects the callback.
- A wrong callback password rejects the callback.
- Checksums are compared with `crypto.timingSafeEqual` after a length check.
- The checksum field is excluded from the HMAC input so a valid checksum can match.
- Client-supplied success pages are not a confirmation path in `payment-service.js`.

## KYC and data protection

- The KYC bucket is documented as private (`R2_BUCKET_KYC`).
- `kyc-document-privacy.test.js` passed in the follow-up run, including rejection of `x-admin-secret`. That is a unit test with Firebase credentials absent. It is not a live bucket read.
- Do not log recovery codes, OTPs, callback passwords, or document bytes.
- Tanzanian privacy obligations (purpose limitation, deletion, export, consent) are not fully re-tested. Account deletion and export were not exercised.

## Residual risk

1. `x-admin-secret` cannot open admin routes. Cron still trusts `x-cron-secret` when it equals `ADMIN_SECRET`. The old admin panel and the Next console still send the unused admin header.
2. Internal escrow is not regulated custody.
3. Dispute and admin-transfer refunds stay `REFUND_PENDING`. The refund-service payout call has no sandbox proof.
4. KYC privacy is covered by unit tests only. No live private-bucket fetch was made.
5. No sandbox proof of AzamPay or WhatsApp.
6. Client order transitions are rejected for non-participants and for paid/refunded statuses. Firestore client updates of order status were already limited to soft-delete fields. The rules emulator was not run.
7. Follow-count rules tests were skipped. They are not verified.
