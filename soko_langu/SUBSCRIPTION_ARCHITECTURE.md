# Subscription Architecture (Soko Vibe) — Firebase Only

## Canonical store
- **Firestore** is the single canonical store (no PostgreSQL). All subscription, entitlement, credit, and billing records live in Firestore. Backups via Firebase.

## Gateway
- **AzamPay** is the payment gateway (initiateCollection, queryCollectionStatus). BillPay not supported → USSD push only for subscriptions/credits/boosts.

## Collections
- `subscriptions/{userId}` — planId, status, periodStart, periodEnd, cancelAtPeriodEnd, lastPaymentId
- `entitlements/{userId}` — planId, features[], aiActionsPerDay, updatedAt
- `ai_credit_accounts/{userId}` — available, reserved
- `ai_credit_ledger/{autoId}` — type, amount, balanceAfter, reference, idempotencyKey, createdAt
- `ai_credit_reservations/{autoId}` — accountId, amount, status, expiresAt
- `billing_payments/{autoId}` — purpose (subscription/ai_credit/boost), userId, amount, status, providerRef, idempotencyKey
- `plans` (static in code, not Firestore)

## Flows
- Upgrade: select plan → AzamPay collect → webhook verified → subscription active + entitlements.
- Renewal: cron (monthly) → collect → on success extend; on failure → past_due → grace 3 days → expired.
- Cancel: at period end.
- AI credits: top-up via AzamPay → credits added; usage debits ledger; reservation prevents overspend.

## Entitlements
- Backend is source of truth; Flutter caches but re-validates.
- Feature gating via `resolveEntitlements(userId)` + `hasEntitlement()`.

## Security
- Server-side amount calc; webhook HMAC; idempotency; audit logs; no client-side balance edits.