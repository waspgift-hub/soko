// Presentation-only mapping from canonical Postgres states to the legacy
// Firestore vocabulary still consumed by older Flutter/web surfaces.
const LEGACY_STATUS = {
  AWAITING_SELLER_SHIPPING: 'pending',
  AWAITING_PAYMENT: 'quoted',
  PAYMENT_PROCESSING: 'pending',
  PAID_IN_ESCROW: 'escrow_hold',
  READY_FOR_DISPATCH: 'ready_to_dispatch',
  DISPATCHED: 'dispatched',
  DELIVERED_PENDING_CONFIRMATION: 'delivered',
  COMPLETED: 'completed',
  PAYMENT_FAILED: 'failed',
  CANCELLED: 'cancelled',
  DISPUTED: 'disputed',
  REFUND_PENDING: 'refunded',
  REFUNDED: 'refunded',
  EXPIRED: 'failed',
};

function legacyStatusOf(v2Status) {
  return LEGACY_STATUS[String(v2Status || '').toUpperCase()] || 'pending';
}

module.exports = { LEGACY_STATUS, legacyStatusOf };
