// Legacy Flutter status vocabulary: maps every v2 Postgres order state to the
// status string the existing Flutter screens understand. Single source of truth
// for both the web-shop mirror (legacy-shop) and the order presentation mirror
// (presentation-mirror) so every writer emits identical values.
// REMOVAL PATH (Phase G): delete with the mirrored collections; the app will
// read order status straight from /api/v1/orders.

// Canonical money-model spellings (ORDER_STATES) -> legacy display string.
const CANONICAL_TO_LEGACY = {
  DRAFT: 'pending',
  PENDING_SHIPPING_FEE: 'pending',
  SHIPPING_FEE_SUBMITTED: 'pending',
  SHIPPING_FEE_REVIEW: 'pending',
  AWAITING_ESCROW_PAYMENT: 'pending',
  PENDING_PAYMENT: 'pending',
  PAYMENT_PENDING: 'pending',
  PAYMENT_PROCESSING: 'pending',
  PAID: 'pending',
  FAILED: 'failed',
  PAYMENT_FAILED: 'failed',
  ESCROW_HELD: 'escrow_hold',
  IN_ESCROW: 'escrow_hold',
  SELLER_ACCEPTED: 'escrow_hold',
  DISPATCH_READY: 'escrow_hold',
  READY_TO_DISPATCH: 'escrow_hold',
  DISPATCHED: 'dispatched',
  IN_TRANSIT: 'dispatched',
  OUT_FOR_DELIVERY: 'dispatched',
  DELIVERY_ATTEMPTED: 'delivered',
  ARRIVED: 'delivered',
  DELIVERED: 'delivered',
  INSPECTION_PERIOD: 'delivered',
  OTP_PENDING: 'delivered',
  DELIVERY_CONFIRMED: 'delivered',
  COMPLETED: 'completed',
  WALLET_CREDITED: 'completed',
  CANCELLED: 'cancelled',
  REFUND_PENDING: 'refunded',
  REFUNDED: 'refunded',
  DISPUTED: 'disputed',
  EXPIRED: 'failed',
};

// Pre-V3 Firestore / app vocabulary also seen in persisted rows.
const LEGACY_SPELLINGS = {
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

const LEGACY_STATUS = Object.assign(
  {},
  LEGACY_SPELLINGS,
  CANONICAL_TO_LEGACY,
);

function legacyStatusOf(v2Status) {
  return LEGACY_STATUS[v2Status] || 'pending';
}

module.exports = {
  LEGACY_STATUS,
  CANONICAL_TO_LEGACY,
  legacyStatusOf,
};