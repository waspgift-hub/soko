// Legacy Flutter status vocabulary: maps every v2 Postgres order state to the
// status string the existing Flutter screens understand. Single source of truth
// for both the web-shop mirror (legacy-shop) and the order presentation mirror
// (presentation-mirror) so every writer emits identical values.
// REMOVAL PATH (Phase G): delete with the mirrored collections; the app will
// read order status straight from /api/v1/orders.

const LEGACY_STATUS = {
  payment_pending: 'pending',
  pending_shipping_fee: 'pending',
  awaiting_escrow_payment: 'pending',
  in_escrow: 'escrow_hold',
  ready_to_dispatch: 'escrow_hold',
  dispatched: 'dispatched',
  in_transit: 'dispatched',
  out_for_delivery: 'dispatched',
  delivery_attempted: 'delivered',
  delivered: 'delivered',
  inspection_period: 'delivered',
  otp_pending: 'delivered',
  completed: 'completed',
  wallet_credited: 'completed',
  payout_pending: 'completed',
  payout_complete: 'completed',
  disputed: 'disputed',
  refund_pending: 'refunded',
  refunded: 'refunded',
  cancelled: 'cancelled',
  failed: 'failed',
  expired: 'failed',
  draft: 'pending',
  published: 'pending',
  address_required: 'pending',
  shipping_fee_submitted: 'pending',
  shipping_fee_review: 'pending',
};

function legacyStatusOf(v2Status) {
  return LEGACY_STATUS[v2Status] || 'pending';
}

module.exports = {
  LEGACY_STATUS,
  legacyStatusOf,
};