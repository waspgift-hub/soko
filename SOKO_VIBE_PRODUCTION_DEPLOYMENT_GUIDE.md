# Soko Vibe production deployment guide

This is the deploy order for the system that is already in the repo. It is not a claim that every feature is ready for live money.

## 1. Backend (Node/Express)

Host the `soko_langu/server` process (the repo currently targets a long-running Node host, with Cloudflare in front of `api.sokovibe.co.tz`).

1. Set every variable in `soko_langu/server/.env.example` that this environment actually uses. Leave `PLATFORM_COMMISSION_PERCENT=0` until a published policy says otherwise.
2. Production boot refuses to start without `APP_URL`, `AZAMPAY_COLLECTION_WEBHOOK_URL`, and `AZAMPAY_CALLBACK_PASSWORD`.
3. Point `AZAMPAY_COLLECTION_WEBHOOK_URL` at `https://api.sokovibe.co.tz/api/v1/payments/webhook/azampay` and register that exact URL in the AzamPay portal.
4. Point the Meta webhook at the existing WhatsApp route and set `WHATSAPP_WEBHOOK_VERIFY_TOKEN` and `WHATSAPP_APP_SECRET`.
5. Deploy Firestore rules from `soko_langu/firestore.rules` so `mfaRecovery/{uid}` stays server-only. Deploy indexes from `soko_langu/firestore.indexes.json` if the checkpoint index changes are intended.
6. Redis must be reachable. Payment locks and OTP limits fail closed without it.
7. Run one finance worker. `FINANCE_WORKER_IN_PROCESS` defaults to on. Set it false on extra API instances if a dedicated worker is running, so jobs are not double-hosted. Settlement itself is idempotent, but do not run two payout loops on purpose.
8. Health: hit the existing health route on the API host before shifting DNS.

Rollback: deploy the previous server build. Do not roll back Firestore rules if new `mfaRecovery` documents exist unless the deny rule is kept. Do not delete ledger or escrow hold documents to "undo" a release.

## 2. Flutter release

App root: `soko_langu`. API base is `ApiConfig.baseUrl` (`https://api.sokovibe.co.tz`).

1. `flutter analyze` and the payment-related tests you can run on a device build machine.
2. Ship Android/iOS with the same Firebase project as the server.
3. Deep links should open the app when installed and `https://www.sokovibe.co.tz/product/{id}` otherwise. Store URLs stay empty until listings exist (`ANDROID_STORE_URL`, `IOS_STORE_URL`).

Rollback: ship the previous store binary. Server changes in this pass are backward compatible for old clients except that MFA recovery codes now come from the server after enrollment.

## 3. Admin console

App root: `soko_langu/apps/admin-console`. Target host: `admin.sokovibe.co.tz`.

1. Build with server-only credentials. Do not expose `ADMIN_SECRET` or Firebase private keys to the browser. The console still attaches `x-admin-secret` when calling the API. The API ignores that header. Live console actions need a Firebase admin session on the API, not the shared secret.
2. Keep dev sandbox mode off in production. `isDevSandbox()` is true only when `ADMIN_DEV_MODE=1` and `NODE_ENV` is not production. Production boot throws if that flag is set. Sandbox mode serves fixture finance and KYC data.
3. This follow-up ran `tsc --noEmit` (no TypeScript errors) and `npm run build` (exit 0). ESLint's first run died on a heap limit. Do not treat that as a lint pass until a later run prints a clean result. A browser pass, if recorded, used the existing local sandbox only.

Rollback: redeploy the previous admin build. It does not own the ledger.

## 4. Domains

| Host | Role |
| --- | --- |
| `www.sokovibe.co.tz` | Public site and product deep-link fallback |
| `api.sokovibe.co.tz` | Express API and webhooks |
| `admin.sokovibe.co.tz` | Admin console |
| `media.sokovibe.co.tz` | Public media only. KYC objects must not use this host |

## 5. Webhooks

- AzamPay collection callback: authenticated as in `PRODUCTION_API_CONFIGURATION.md`. Duplicate deliveries must hit the webhook outbox dedup key and must not credit twice.
- WhatsApp: verify token on GET, HMAC on POST.
- Never use a success page redirect as proof of payment.

## 6. Monitoring

Watch API 5xx on `/api/v1/payments/webhook/azampay`, payment status stuck in `PAYMENT_PENDING`, escrow holds stuck in `holding` past the auto-release window, and `ESCROW_DISPUTED` errors (those are expected when a release hits a dispute). Alert on Redis unavailable. Do not log OTP values, recovery codes, callback passwords, or KYC document bytes.

## 7. Rollback limits

- Do not delete `ledger` documents or edit balances by hand.
- A bad release that already credited a seller needs an explicit reversing ledger entry, not a silent overwrite.
- If AzamPay credentials are wrong, leave orders in `PAYMENT_PENDING` or `AWAITING_ESCROW_PAYMENT`. Do not mark them paid to unblock sellers.
- A buyer refund that has no confirmed disbursement stays `REFUND_PENDING`. Do not edit the order to `REFUNDED` by hand.
