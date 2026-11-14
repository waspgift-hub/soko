# Soko Vibe production implementation report

Date: 2026-11-10. This report lists work completed in the checkpoint pass and the follow-up pass. It does not mark the marketplace production-ready. Nothing from this follow-up was committed. Checkpoint `1d9f50e1` on `checkpoint/pre-p0-hardening-2026-11-10` was not pushed.

## Git checkpoint

- Branch: `checkpoint/pre-p0-hardening-2026-11-10` (created from `feat/website-v2` at `6795e607`).
- Checkpoint commit: `1d9f50e1` — `checkpoint: preserve working tree before P0 hardening`.
- 164 source files. `.next`, `.open-next`, and `buyer_requests_screen.dart.bak` were left untracked.
- Not pushed.
- `soko_langu/lib/services/localization_service.dart` stayed dirty and was not part of the checkpoint.
- Every financial, auth, and refund edit after that commit is an uncommitted working-tree change.

## Completed in the first pass

1. AzamPay checkout callback reads `utilityref`, `externalreference`, `transactionstatus`, and `reference`. `transactionstatus: success` becomes `completed`.
2. Callback authentication fails closed unless the callback password, an RSA signature, or a checksum succeeds.
3. Checkout MNO comes from the caller or `AZAMPAY_DEFAULT_PROVIDER`, limited to Airtel, Tigo, Halopesa, Azampesa, and Mpesa.
4. `server/azampay.js` calls the provider instance.
5. `settleEscrowToSeller` throws `ESCROW_HOLD_MISSING` when there is no holding row. A second settle of a released hold does not move money. A disputed hold can settle only when `allowDisputed` is set.
6. Opening a dispute marks the Firestore hold `disputed`.
7. `cancelOrder` no longer sets `escrowReleased: true`. Paid states throw `ESCROW_REFUND_REQUIRES_DISBURSEMENT`.
8. MFA recovery codes are server-minted SHA-256 hashes in `mfaRecovery/{uid}`. Firestore rules deny client access.
9. `.env.example` commission template is 0.

## Completed in this follow-up

1. **Legacy routers boot again.** `server/clickpesa.js` re-exports the AzamPay adapter under the old function names. It is not a second payment provider. Without it, `app.js` skipped the compat mount and KYC, trust, and auth-rbac tests crashed on `MODULE_NOT_FOUND`.
2. **`x-admin-secret` is not an admin login.** `authenticateAdmin`, `verifyAdmin`, `requireAdmin`, `requireKycReviewer`, and launch admin now require a Firebase ID token whose server-side role is `admin` or `super_admin` (or a configured bootstrap super-admin email). A missing session is 401. A signed-in user without that role is 403. Tests cover a missing secret, a forged secret, and a non-admin user.
3. **Machine cron is separate.** `POST /cron/release-escrows` and the daily-engagement route still compare `x-cron-secret` to `CRON_SECRET` or `ADMIN_SECRET`. That header is not `x-admin-secret`. Knowing the cron secret does not open the admin routers.
4. **The old browser panel still sends `x-admin-secret`.** The server ignores that header. The panel cannot sign in with the shared secret anymore. The Next.js console still attaches the header in `apps/admin-console/src/lib/server/backend.ts`. The API does not honor it.
5. **Firestore dispute refunds stay pending.** `resolveDispute` for `refund_to_buyer` and `adminTransfer` set `REFUND_PENDING` and `refundBlockReason: DISBURSEMENT_NOT_CONFIRMED` and return `success: false`. They do not set `REFUNDED` or `escrowReleased`.
6. **`refund-service` completes only after `initiatePayout` returns a body.** A null or thrown payout calls `markRefundFailed('DISBURSEMENT_NOT_CONFIRMED')` and leaves the order `REFUND_PENDING`. An existing payout row short-circuits a second call. Unit tests still treat a returned `{ id, status: 'processing' }` as provider acceptance and expect `REFUNDED`. No live AzamPay disbursement was executed. The payout URL in the adapter is `POST /disbursement/create-mobile-money-payout`. That call was not proven against AzamPay's published disbursement API in this workspace.
7. **Client order transitions have one server path.** `transitionOrder` refuses anyone who is not `buyerId`, `sellerId`, or `userId`, including orders with no participants. It refuses `PAID`, `ESCROW_HELD`, `IN_ESCROW`, `COMPLETED`, `REFUNDED`, `WALLET_CREDITED`, and `REFUND_PENDING`. Illegal machine moves return `INVALID_ORDER_STATE`. `PATCH /orders/:id/transition` had been calling `isOwnerOrAdmin` with the wrong arguments, so the check never ran. It now uses the same participant list and maps the service errors. `GET /transaction/:id` uses the same participant check.
8. **Launch and contact validate the body before Turnstile.** A short message or missing consent is 400. In non-production, a missing Turnstile secret is skipped so local tests can store the message. Production still returns 503 `TURNSTILE_NOT_CONFIGURED` when the secret is absent.
9. **Email OTP login was already one server route** (`POST /api/v1/auth/email-otp-login`) and the existing email-OTP tests passed inside the full suite. It was not rewritten.
10. **Follow relationships were not changed.** The five Firestore-emulator follow tests stayed skipped because no emulator was running.

## Admin console checks

- Typecheck: `tsc --noEmit` reported no TypeScript errors.
- Production build: `npm run build` exit code 0 (Next.js 15.5.29).
- Lint: first `eslint . --max-warnings=0` died with a heap out-of-memory error (exit 134). `.open-next/**` was added to the ignore list and lint was restarted with a larger heap. If that process had not printed a pass/fail line when this report was written, lint is not marked passed.
- `.env.local` has `ADMIN_DEV_MODE=1`. Firebase web keys and `ADMIN_SESSION_SECRET` are empty. Development uses the in-repo session fallback. Demo staff exist only in that sandbox and share the password constant in `src/lib/config.ts`. Browser verification is recorded in the test report only for a login that actually succeeded. Sandbox screens are fixture data, not live finance or KYC.

## Production-readiness assessment

The server can reject unsigned admin calls, refuse client-forged paid statuses, and refuse to mark a Firestore dispute as refunded without a disbursement. It is not ready for live goods payments.

Blocked on the owner:

- AzamPay sandbox or production app name, client id, client secret, callback password, and the portal callback URL. There is no server `.env` in this workspace.
- WhatsApp Business token, phone number id, template approval, verify token, and app secret.
- A decision to keep commission at 0.

Critical blockers still in the product:

- AzamPay checkout is merchant collection plus an internal Firestore hold. It is not regulated escrow custody.
- Buyer money is not returned on the dispute/admin-transfer path. The refund-service path marks success only when `initiatePayout` returns, and that HTTP call has no sandbox proof.
- `GET /payments/{reference}` is still not a confirmed AzamPay status API. Confirmation is an authenticated callback plus the amount check.
- The deployed Render process still 404s or 400s four legacy routes that the local app now answers with 401. Deploy is required before live e2e can pass.
- The admin console can show sandbox fixtures when `ADMIN_DEV_MODE=1` and `NODE_ENV` is not production. Production boot rejects that flag.
- Follow-count rules were not executed. Localization warnings remain.
