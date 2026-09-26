// Presentation-only mapping from canonical Postgres states to the legacy
// Firestore vocabulary still consumed by older Flutter/web surfaces.
const LEGACY_STATUS = {
  AWAITING_SELLER_SHIPPING: 'pending',
  pending_shipping_fee: 'pending',
  awaiting_escrow_payment: 'pending',
  AWAITING_PAYMENT: 'quoted',
  PAYMENT_PROCESSING: 'pending',
  payment_pending: 'pending',
  PAID_IN_ESCROW: 'escrow_hold',
  in_escrow: 'escrow_hold',
  READY_FOR_DISPATCH: 'ready_to_dispatch',
  ready_to_dispatch: 'escrow_hold',
  DISPATCHED: 'dispatched',
  dispatched: 'dispatched',
  DELIVERED_PENDING_CONFIRMATION: 'delivered',
  delivered: 'delivered',
  inspection_period: 'delivered',
  otp_pending: 'delivered',
  COMPLETED: 'completed',
  completed: 'completed',
  PAYMENT_FAILED: 'failed',
  failed: 'failed',
  CANCELLED: 'cancelled',
  cancelled: 'cancelled',
  DISPUTED: 'disputed',
  disputed: 'disputed',
  REFUND_PENDING: 'refunded',
  REFUNDED: 'refunded',
  refunded: 'refunded',
  EXPIRED: 'failed',
  expired: 'failed',
  wallet_credited: 'completed',
};

function legacyStatusOf(v2Status) {
  const raw = String(v2Status || '').trim();
  return LEGACY_STATUS[raw] || LEGACY_STATUS[raw.toLowerCase()] || LEGACY_STATUS[raw.toUpperCase()] || 'pending';
}

module.exports = { LEGACY_STATUS, legacyStatusOf };
