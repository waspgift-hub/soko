# Subscription Implementation Report (Phase 2-3 core)

## What was implemented
- SUBSCRIPTION_ARCHITECTURE.md (Firebase-only, AzamPay gateway).
- Subscription billing via AzamPay: `server/src/modules/subscriptions/billing.js` (initiateUpgrade, handleWebhook, cancelSubscription).
- Routes: POST /api/v1/subscriptions/upgrade, /cancel, /webhook/azampay.
- AI credit wallet: `server/src/modules/ai/credits/credit-service.js` (getBalance, topUp, handleTopUpWebhook, debit, getLedger).
- Routes: GET/POST /api/v1/ai/credits/* + webhook.

## Existing reused
- plans.js, subscription-service.js (resolveEntitlements), subscription-store.js (Firestore).
- AzamPay provider (initiateCollection, verifyWebhook, normalizeWebhook).

## Remaining
- Renewal cron, downgrade, proration, admin plan management, organization/team, AI agent tool registry/budgets, Flutter UI, tests.

## Notes
- Gateway standardized to AzamPay per user instruction.
- Store is Firestore-only (no PostgreSQL) per user clarification.