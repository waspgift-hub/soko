# Checkout Payment Architecture (Soko Vibe)

## Canonical payment methods
- `escrow` (secure mobile money via ClickPesa)
- `cod` (cash on delivery)

Legacy aliases `mobile_money`/`cash` normalize at API boundary via `server/src/utils/payment-method.js`.

## State dimensions
- paymentMethod (immutable after creation)
- paymentStatus: escrow -> unpaid/payment_pending/held/released; cod -> cash_due/cash_collection_pending/cash_collected
- fulfillmentStatus: awaiting_shipping_quote -> (buyer accept) ready_for_dispatch -> dispatched -> delivered -> completed

## Escrow flow
Checkout -> quote -> ClickPesa payment -> webhook verified -> EscrowHold FUNDS_HELD -> in_escrow -> dispatch -> buyer delivery confirm (OTP) -> release exactly once -> completed.

## COD flow
Checkout -> quote -> buyer accept-quote -> ready_for_dispatch -> dispatch -> buyer confirm delivery -> seller confirm cash collected -> completed. No ClickPesa, no escrow, no wallet credit.

## Guards
- Escrow endpoints reject COD orders (INVALID_PAYMENT_METHOD).
- COD endpoints reject non-COD orders.
- Payment method immutable after creation.