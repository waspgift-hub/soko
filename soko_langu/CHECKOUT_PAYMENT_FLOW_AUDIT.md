# Checkout Payment Flow Audit (Soko Vibe)

## Existing architecture
- Two checkout UIs: `lib/screens/home/checkout_screen.dart` (old, escrow vs cod) and `lib/ui/screens/checkout_v2_screen.dart` (v2, mobile_money vs cash).
- Server: `server/src/modules/legacy-shop/routes.js` serves `POST /api/orders/create` for both. It ignored `preferredPaymentMethod` and always created an order mirrored to Firestore with `escrowStatus: 'none'`.
- Escrow money flow lives in `server/src/modules/legacy-compat/escrow-compat.js` + `escrow-service.js` (dispatch/release/dispute/cancel). It assumed an escrow hold existed.
- COD had no backend: no payment intent, no escrow hold, but also no delivery/cash-collection tracking; UI still showed escrow notes and Pay Now.

## Defects found
1. `preferredPaymentMethod` not read or stored by `/api/orders/create`.
2. No canonical payment-method normalization (aliases scattered).
3. COD orders could enter escrow endpoints (no guard).
4. Order detail UI not payment-method aware (escrow note shown for COD, Pay Now shown for COD).
5. V2 checkout sent non-canonical aliases (`mobile_money`/`cash`).
6. No COD delivery/cash-collection confirmation endpoints.
7. No buyer quote-acceptance endpoint.

## Source of truth
- PostgreSQL (v2) authoritative for transactional order state; Firestore mirrors for Flutter reads.
- ClickPesa authoritative for money collection.

## Files changed
See CHECKOUT_PAYMENT_IMPLEMENTATION_REPORT.md.