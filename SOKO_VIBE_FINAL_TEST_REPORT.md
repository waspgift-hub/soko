# Soko Vibe final test report

Date: 2026-11-10. Commands were run on this machine. Untested items are not marked passed. The counts below are from the second pass, after the compat-router, admin-auth, refund, and order-transition fixes. The earlier full-suite result (661 tests, 641 passed, 15 failed, 5 skipped) is superseded by the run recorded here.

## Passed

### Previously failing local suites

Command:

```text
node --test test/auth-rbac.test.js test/kyc-contact-otp.test.js test/kyc-document-privacy.test.js test/trust.test.js test/launch-contact-routes.test.js test/azampay-contract.test.js test/mfa-recovery.test.js
```

Working directory: `soko_langu/server`. Exit code 0. 71 tests, 71 passed.

Those files had failed in the first full suite because `clickpesa.js` was missing (the app did not mount legacy routers) and because launch/contact returned 503 before validating the body. After the shim and the validation-order fix they passed, including the assertion that a shared `x-admin-secret` does not open KYC document reads.

### Refund and admin-auth recheck

```text
node --test test/order-transition-auth.test.js test/auth-rbac.test.js test/kyc-document-privacy.test.js
```

Exit code 0. 35 tests, 35 passed, 0 failed. Includes non-participant order transitions, financial-state writes refused, and a forged admin secret refused.

`cancel-refund.test.js` and `refund-ledger-safety.test.js` were re-run with `auth-rbac.test.js` earlier in this pass: 36 passed, 0 failed. The later full suite includes them again.

### AzamPay and MFA (unchanged from the first pass)

```text
node --test test/azampay-contract.test.js test/mfa-recovery.test.js
```

21 tests, 21 passed. No sandbox HTTP call.

## Full server suite (this pass)

Command:

```text
node --test test/*.test.js
```

Working directory: `soko_langu/server`. Exit code 1. Duration about 223 seconds.

- tests 702
- pass 693
- fail 4
- skipped 5
- todo 0

The four failures are all in `test/e2e.live.test.js`. That file calls the deployed host `https://soko-langu-server.onrender.com`, not the process under test. Local `auth-rbac.test.js` covers the same routes in-process and passed.

| Live request | Deployed response | Local in-process result |
| --- | --- | --- |
| GET `/api/transaction-status/some-order` | 404 | 401 in `auth-rbac.test.js` |
| POST `/api/escrow/release` | 400 | 401 in `auth-rbac.test.js` |
| POST `/api/orders/transition` | 404 | 401 in `auth-rbac.test.js` |
| POST `/api/escrow/buyer-transport` | 404 | 401 in `auth-rbac.test.js` |

These four stay failed until the current server is deployed. They are not marked passed.

## Skipped

5 tests skipped because `FIRESTORE_EMULATOR_HOST` is not set (`unauthenticated cannot read users`, `owner can read own user`, `non-owner cannot read other user`, `only the owner may flip their own visibility`, `follower counts are server-owned`). Skipped, not passed.

## Flutter

```text
flutter analyze --no-fatal-infos
```

Working directory: `soko_langu`. Flutter 3.41.9. Exit code 1. Duration about 997 seconds.

- 67 issues
- 0 errors
- 60 warnings
- 7 infos

No issue was reported in `mfa_service.dart` or `mfa_enrollment_screen.dart`. Warnings in auth and profile screens are unused imports and unused fields (`forgot_password_screen.dart`, `otp_screen.dart`, `admin_privacy_screen.dart`). They do not block compilation. They were not rewritten in this pass. No Flutter unit or widget suite was run.

## Admin console

- `npm run typecheck` (`tsc --noEmit`) completed with no TypeScript errors.
- `npm run build` (`next build`) exit code 0. Next.js 15.5.29 compiled, type-checked, and generated the static pages. Webpack printed EPERM warnings while renaming pack files. The build still finished.
- `npm run lint` (`eslint . --max-warnings=0`) first attempt exited 134: JavaScript heap out of memory. A second attempt with `--max-old-space-size=8192` was started after `.open-next/**` was added to the ESLint ignore list. See the implementation report for the second result if it finished; do not treat the OOM as a clean lint pass.
- Playwright was not run.
- Browser login was attempted only if the local sandbox already in `.env.local` answered. See the implementation report. No production admin secret was created.

## Blocked

- Buyer checkout with AzamPay sandbox. No server `.env` and no sandbox call.
- Seller settlement against a real collection. Blocked on sandbox payment.
- Subscription purchase. Blocked on sandbox payment.
- Dispute refund that actually reaches a buyer's phone. The Firestore dispute path stays `REFUND_PENDING` with `DISBURSEMENT_NOT_CONFIRMED`. The `refund-service` path calls `initiatePayout`, and unit tests accept a mocked payout object. No live disbursement was sent.
- WhatsApp OTP and transactional delivery. Webhook signature unit tests passed. No message was sent.
- Live AzamPay webhook. Not received.
- Firestore rules emulator. Not running.

## Rule used

A feature is passed only when a command in this report succeeded for that behavior. Live e2e 404/400 responses are failed. Sandbox payment and WhatsApp delivery are blocked.
