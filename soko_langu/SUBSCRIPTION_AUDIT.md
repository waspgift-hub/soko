# Subscription Audit (Soko Vibe)

## Existing state
- `server/src/modules/subscriptions/` exists: plans.js, subscription-service.js, subscription-store.js, routes.js.
- Storage: Firestore collections `ai_subscriptions`, `ai_entitlements`, `ai_usage` (per subscription-store.js).
- Plans: buyer (free), seller_basic (free), seller_plus (14,900), seller_pro (29,900), business (79,900). aiActionsPerDay: 5/5/50/200/500.
- Statuses: inactive, trialing, pending_payment, active, past_due, cancel_pending, expired, suspended, payment_failed.
- Entitlements derived from plan features; cached in Firestore.
- AI quota: checkAiQuota increments daily usage; limit per plan.
- Trial: 7-day Seller Plus trial requires KYC approved.
- No payment/billing integration for subscriptions: no ClickPesa/AzamPay checkout, no renewal cron, no invoices.
- No PostgreSQL tables for subscriptions (Firestore only).

## Gaps vs master prompt
- No billing/payment flow for upgrades/renewals.
- No entitlement enforcement on backend endpoints (only AI quota).
- No admin plan management (plans hard-coded).
- No organization/team management.
- No AI credit wallet (pay-as-you-go) — only daily quota.
- No AI agent tool registry with budgets.
- No usage metering/cost tracking.
- Gateway: codebase has both ClickPesa and AzamPay modules; Flutter uses AzamPayService for fee preview. Need to standardize.

## Payment gateway decision
Per user instruction, gateway for payments should be AzamPay. Existing `server/azampay.js` and `server/src/...` ClickPesa modules coexist; discovery needed to determine which is live. Flutter's `AzamPayService` suggests AzamPay is the intended client-facing gateway.

## Next steps
Phase 2: architecture + migration plan before implementing billing/credits/agent.