# Production API configuration

No real secrets belong in this file. Names below match `soko_langu/server/.env.example`. The workspace has **no** `soko_langu/server/.env`, so this pass could not verify that production hosting already has values. "Assumed configured" in the brief is not the same as verified.

## Already in the codebase (confirm values on the host)

These integrations have server code. Whether the host has working keys was **not** verified from this workspace.

| Service | Variables | Notes |
| --- | --- | --- |
| Firebase Auth + Firestore | `FIREBASE_SERVICE_ACCOUNT_JSON` or `FIREBASE_PROJECT_ID`, `FIREBASE_PRIVATE_KEY`, `FIREBASE_CLIENT_EMAIL` | Production data plane |
| Redis | `REDIS_URL` | OTP rate limits and payment locks fail closed when Redis is down |
| Cloudflare R2 | `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, bucket names, `R2_PUBLIC_URL` | KYC bucket must stay private |
| Cloudflare Email | `CLOUDFLARE_ACCOUNT_ID`, `CLOUDFLARE_API_TOKEN`, `EMAIL_FROM` | Transactional mail |
| OneSignal | `ONE_SIGNAL_APP_ID`, `ONE_SIGNAL_REST_API_KEY` | Push |
| AI | `GROQ_API_KEY`, `GEMINI_API_KEY`, `AI_PROVIDER_ORDER`, `CF_AI_URL`, `CF_AI_KEY` | Optional. Missing keys must disable that provider, not invent answers |
| Admin bootstrap | `ADMIN_SECRET`, `SUPER_ADMIN_EMAILS`, `ENCRYPTION_KEY` | `ADMIN_SECRET` is the fallback for `x-cron-secret` on machine cron routes. It does not authenticate `x-admin-secret`. Admin routers require a Firebase ID token and a server-side admin role. Do not put `ADMIN_SECRET` in a browser app |
| Commission | `PLATFORM_COMMISSION_PERCENT` | Keep `0` unless a published policy change is intentional. Admin field `paymentsAndCurrency.platformCommissionPct` overrides it when greater than 0 |

## AzamPay (owner must configure)

Official references used:

- Token and checkout flow: [AzamPay developer docs](https://developerdocs.azampay.co.tz/redoc) and the Neurotech checkout description.
- Sandbox authenticator: `https://authenticator-sandbox.azampay.co.tz/AppRegistration/GenerateToken` with JSON `appName`, `clientId`, `clientSecret`.
- Sandbox checkout base used by this server: `https://sandbox.azampay.co.tz/azampay` plus `POST /mno/checkout`.
- Checkout body this server sends: `accountNumber` (255…), `amount` (string), `currency` (`TZS`), `externalId` (our unique reference), `provider` (`Airtel`, `Tigo`, `Halopesa`, `Azampesa`, or `Mpesa`).
- Callback example documented by AzamPay's public client libraries:

```json
{
  "msisdn": "2557xxxxxxx",
  "amount": "2000",
  "message": "any message",
  "utilityref": "our-external-id",
  "operator": "Tigo",
  "reference": "gateway-reference",
  "transactionstatus": "success"
}
```

Additional callback authentication seen in current integrator docs (RSA signature and a portal callback password) is supported and required when the matching env var is set. Register one callback URL in the AzamPay portal. This server expects `AZAMPAY_COLLECTION_WEBHOOK_URL` (example `https://api.sokovibe.co.tz/api/v1/payments/webhook/azampay`).

| Variable | Purpose |
| --- | --- |
| `AZAMPAY_AUTH_BASE` | Authenticator origin. Sandbox default is the authenticator host above. Production host comes from the AzamPay portal after KYC |
| `AZAMPAY_API_BASE` | Checkout origin including `/azampay` |
| `AZAMPAY_APP_NAME` | App name from the portal |
| `AZAMPAY_CLIENT_ID` | Client id. If the callback includes `clientId`, it must match |
| `AZAMPAY_CLIENT_SECRET` | Client secret. Server only |
| `AZAMPAY_CALLBACK_PASSWORD` | Shared password AzamPay is configured to echo. Required in production by `src/config/index.js`. Callbacks without a match are rejected |
| `AZAMPAY_CHECKSUM_KEY` | HMAC key when a checksum is used. Also read as `AZAMPAY_WEBHOOK_SECRET` |
| `AZAMPAY_PUBLIC_KEY` | PEM from `GET /azampay/v1/public-key?format=Pem` when callbacks include `signature` |
| `AZAMPAY_DEFAULT_PROVIDER` | MNO used when the caller does not pass one |
| `AZAMPAY_COLLECTION_WEBHOOK_URL` | Exact public URL registered in the portal |
| `AZAMPAY_ALLOWED_IPS` | Optional allow list |

Provider approval: live collections require AzamPay business KYC. Sandbox keys are not production approval. This API collects into the merchant AzamPay wallet. It is not a regulated escrow account.

Buyer refunds: a Firestore dispute or admin transfer stays `REFUND_PENDING` with reason `DISBURSEMENT_NOT_CONFIRMED`. The refund service calls `POST /disbursement/create-mobile-money-payout` through `initiatePayout` and marks the refund completed only when that call returns a body. A failed or empty payout does not mark the order refunded and does not move the wallet twice. That disbursement URL was not exercised against AzamPay in this workspace.

Do not treat a browser return URL as payment proof. The server accepts a callback only after the authenticator above, then compares the amount to the order.

## WhatsApp Business Platform (owner must configure)

Code already verifies the Meta webhook (`GET` hub challenge and `POST` `X-Hub-Signature-256`). No SMS provider was added.

| Variable | Purpose |
| --- | --- |
| `WHATSAPP_BUSINESS_TOKEN` | Cloud API token. Server only |
| `WHATSAPP_PHONE_NUMBER_ID` | Sender phone number id |
| `WHATSAPP_TEMPLATE_NAME` | Approved template. Default name in the example is `otp` |
| `WHATSAPP_LANGUAGE` | Template language. Example uses `sw` |
| `WHATSAPP_WEBHOOK_VERIFY_TOKEN` | Value entered in the Meta callback configuration |
| `WHATSAPP_APP_SECRET` | App secret used to check `X-Hub-Signature-256` |
| `WHATSAPP_GRAPH_BASE_URL` | Optional. Default `https://graph.facebook.com/v20.0` |

Meta must approve the OTP and transactional templates before sends work. Marketing templates require a separate opt-in. Do not send marketing on the transactional template. This pass did not send a test message.

## Admin console

`soko_langu/apps/admin-console/.env.example` is the console template. Do not put `ADMIN_SECRET`, AzamPay secrets, or the Firebase private key in `NEXT_PUBLIC_*` variables. The browser must call the console's own server routes, which call the backend with server credentials.

## Explicitly not verified on the host

Firebase, email, R2, OneSignal, and AI keys were not read from a deployed environment. There is no `.env` in the repo to inspect. Treat them as **unverified**, not as confirmed configured.
