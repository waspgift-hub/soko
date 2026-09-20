/// Canonical order statuses produced by the v2 Trust-Commerce engine.
/// These exactly match the server-side `ORDER_STATES` in `order-state-machine.js`.
class OrderStatus {
  OrderStatus._();

  static const draft = 'DRAFT';
  static const pendingPayment = 'PENDING_PAYMENT';
  static const paymentProcessing = 'PAYMENT_PROCESSING';
  static const paid = 'PAID';
  static const escrowHeld = 'ESCROW_HELD';
  static const sellerAccepted = 'SELLER_ACCEPTED';
  static const dispatchReady = 'DISPATCH_READY';
  static const dispatched = 'DISPATCHED';
  static const inTransit = 'IN_TRANSIT';
  static const arrived = 'ARRIVED';
  static const delivered = 'DELIVERED';
  static const deliveryConfirmed = 'DELIVERY_CONFIRMED';
  static const completed = 'COMPLETED';
  static const paymentFailed = 'PAYMENT_FAILED';
  static const cancelled = 'CANCELLED';
  static const refundPending = 'REFUND_PENDING';
  static const refunded = 'REFUNDED';
  static const disputed = 'DISPUTED';
  static const expired = 'EXPIRED';
}

/// Maps any incoming status (including legacy Firestore ones) to the v2 canonical value.
String canonicalStatusOf(String status) {
  final s = status.toUpperCase();
  if (s == 'ESCROW_HOLD' || s == 'PAID_ESCROW_HOLD' || s == 'PAID_ESCROW_HELD' || s == 'IN_ESCROW') {
    return OrderStatus.escrowHeld;
  }
  if (s == 'DELIVERY_CONFIRMED' || s == 'CONFIRMED') {
    return OrderStatus.deliveryConfirmed;
  }
  return s;
}

enum TrustStage {
  initiation,
  pricing,
  transaction,
  hold,
  logistics,
  verification,
  settlement;

  String get labelKey => switch (this) {
    TrustStage.initiation => 'phase_label_initiation',
    TrustStage.pricing => 'phase_label_pricing',
    TrustStage.transaction => 'phase_label_transaction',
    TrustStage.hold => 'phase_label_hold',
    TrustStage.logistics => 'phase_label_logistics',
    TrustStage.verification => 'phase_label_verification',
    TrustStage.settlement => 'phase_label_settlement',
  };
}

TrustStage trustStageOf(String status) {
  final s = canonicalStatusOf(status);
  switch (s) {
    case OrderStatus.draft:
    case OrderStatus.cancelled:
    case OrderStatus.expired:
      return TrustStage.initiation;
    case OrderStatus.pendingPayment:
      return TrustStage.transaction;
    case OrderStatus.paymentProcessing:
    case OrderStatus.paid:
    case OrderStatus.paymentFailed:
      return TrustStage.transaction;
    case OrderStatus.escrowHeld:
    case OrderStatus.sellerAccepted:
    case OrderStatus.dispatchReady:
    case OrderStatus.disputed:
    case OrderStatus.refundPending:
      return TrustStage.hold;
    case OrderStatus.dispatched:
    case OrderStatus.inTransit:
    case OrderStatus.arrived:
    case OrderStatus.delivered:
      return TrustStage.logistics;
    case OrderStatus.deliveryConfirmed:
    case OrderStatus.completed:
      return TrustStage.verification;
    case OrderStatus.completed:
    case OrderStatus.refunded:
      return TrustStage.settlement;
    default:
      return TrustStage.initiation;
  }
}
