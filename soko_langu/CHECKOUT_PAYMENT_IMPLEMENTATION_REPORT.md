# Checkout Payment Implementation Report

## Implemented
- Created `server/src/utils/payment-method.js` (normalize + guards).
- Updated `server/src/modules/legacy-shop/routes.js`: reads/validates/stores canonical paymentMethod; adds `paymentMethod`, `paymentStatus`, `fulfillmentStatus`, `quoteAcceptedByBuyer` to mirror; added `POST /api/orders/:id/accept-quote`.
- Created `server/src/modules/legacy-compat/cod-compat.js` with COD endpoints: confirm-delivery, confirm-cash-collected, report-delivery-issue, report-payment-issue.
- Mounted cod router at `/api/cod` in `app.js` and `compat.js`.
- Added COD guards to escrow endpoints (dispatch/release/cancel/dispute reject COD).
- Flutter: `order_detail_screen.dart` now payment-method aware (escrow note gated, pay card gated to escrow, COD quote/cash instructions, dispute/cancel gated).
- Flutter: `checkout_v2_screen.dart` sends canonical `escrow`/`cod`.
- Migration script `server/scripts/normalize-payment-methods.js`.
- Docs: audit + architecture.

## Tests
- `flutter analyze` on changed files: no issues.
- `node --test test/legacy-shop.test.js`: 3/3 pass.

## Known limitations
- COD dispatch still uses same status flow; dispatch eligibility for COD should additionally require `quoteAcceptedByBuyer` (server-side check to be enforced in escrow-service.dispatchOrder in a follow-up).
- No automated backend tests for new COD endpoints yet.
- Legacy Firestore docs without paymentMethod default to escrow.