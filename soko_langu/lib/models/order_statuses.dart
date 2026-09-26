/// Single canonical order vocabulary shared by the Flutter UI and the V3 server.
///
/// Canonical happy path:
/// AWAITING_SELLER_SHIPPING → AWAITING_PAYMENT → PAYMENT_PROCESSING
/// → PAID_IN_ESCROW → READY_FOR_DISPATCH → DISPATCHED
/// → DELIVERED_PENDING_CONFIRMATION → COMPLETED
///
/// Legacy Firestore/API spellings are accepted at the presentation boundary
/// and normalized by [canonicalStatusOf].
class OrderStatus {
  OrderStatus._();

  static const awaitingSellerShipping = 'AWAITING_SELLER_SHIPPING';
  static const awaitingPayment = 'AWAITING_PAYMENT';
  static const paymentProcessing = 'PAYMENT_PROCESSING';
  static const paidInEscrow = 'PAID_IN_ESCROW';
  static const readyForDispatch = 'READY_FOR_DISPATCH';
  static const dispatched = 'DISPATCHED';
  static const deliveredPendingConfirmation = 'DELIVERED_PENDING_CONFIRMATION';
  static const completed = 'COMPLETED';

  static const paymentFailed = 'PAYMENT_FAILED';
  static const cancelled = 'CANCELLED';
  static const disputed = 'DISPUTED';
  static const refundPending = 'REFUND_PENDING';
  static const refunded = 'REFUNDED';
  static const expired = 'EXPIRED';

  static const draft = awaitingSellerShipping;
  static const pending = awaitingSellerShipping;
  static const published = awaitingSellerShipping;
  static const addressRequired = awaitingSellerShipping;
  static const awaitingShippingQuote = awaitingSellerShipping;
  static const pendingShippingFee = awaitingSellerShipping;
  static const shippingFeeSubmitted = awaitingPayment;
  static const shippingFeeReview = awaitingPayment;
  static const quoted = awaitingPayment;
  static const pendingPayment = awaitingPayment;
  static const awaitingEscrowPayment = awaitingPayment;
  static const paymentPending = paymentProcessing;
  static const paid = paidInEscrow;
  static const escrowHeld = paidInEscrow;
  static const inEscrow = paidInEscrow;
  static const escrowHold = paidInEscrow;
  static const paidEscrowHold = paidInEscrow;
  static const paidEscrowHeld = paidInEscrow;
  static const readyToDispatch = readyForDispatch;
  static const inTransit = dispatched;
  static const outForDelivery = dispatched;
  static const deliveryAttempted = dispatched;
  static const delivered = deliveredPendingConfirmation;
  static const inspectionPeriod = deliveredPendingConfirmation;
  static const otpPending = deliveredPendingConfirmation;
  static const walletCredited = completed;
  static const payoutPending = completed;
  static const payoutComplete = completed;
  static const failed = paymentFailed;
}

String canonicalStatusOf(String rawStatus) {
  final s = rawStatus.trim().toUpperCase();
  switch (s) {
    case 'AWAITING_SELLER_SHIPPING':
    case 'DRAFT':
    case 'PENDING':
    case 'PUBLISHED':
    case 'ADDRESS_REQUIRED':
    case 'AWAITING_SHIPPING_QUOTE':
    case 'PENDING_SHIPPING_FEE':
    case 'PENDING_SHIPPING':
      return OrderStatus.awaitingSellerShipping;
    case 'AWAITING_PAYMENT':
    case 'PENDING_PAYMENT':
    case 'QUOTED':
    case 'SHIPPING_FEE_SUBMITTED':
    case 'SHIPPING_FEE_REVIEW':
    case 'AWAITING_ESCROW_PAYMENT':
    case 'AWAITING_ESCROW':
      return OrderStatus.awaitingPayment;
    case 'PAYMENT_PROCESSING':
    case 'PAYMENT_PENDING':
      return OrderStatus.paymentProcessing;
    case 'PAID_IN_ESCROW':
    case 'PAID':
    case 'ESCROW_HELD':
    case 'ESCROW_HOLD':
    case 'PAID_ESCROW_HOLD':
    case 'PAID_ESCROW_HELD':
    case 'IN_ESCROW':
      return OrderStatus.paidInEscrow;
    case 'READY_FOR_DISPATCH':
    case 'DISPATCH_READY':
    case 'READY_TO_DISPATCH':
      return OrderStatus.readyForDispatch;
    case 'DISPATCHED':
    case 'IN_TRANSIT':
    case 'OUT_FOR_DELIVERY':
    case 'DELIVERY_ATTEMPTED':
      return OrderStatus.dispatched;
    case 'DELIVERED_PENDING_CONFIRMATION':
    case 'DELIVERED':
    case 'INSPECTION_PERIOD':
    case 'OTP_PENDING':
    case 'DELIVERY_CONFIRMED':
    case 'CONFIRMED':
      return OrderStatus.deliveredPendingConfirmation;
    case 'COMPLETED':
    case 'WALLET_CREDITED':
    case 'PAYOUT_PENDING':
    case 'PAYOUT_COMPLETE':
      return OrderStatus.completed;
    case 'PAYMENT_FAILED':
    case 'FAILED':
      return OrderStatus.paymentFailed;
    case 'CANCELLED':
      return OrderStatus.cancelled;
    case 'DISPUTED':
      return OrderStatus.disputed;
    case 'REFUND_PENDING':
      return OrderStatus.refundPending;
    case 'REFUNDED':
      return OrderStatus.refunded;
    case 'EXPIRED':
      return OrderStatus.expired;
    default:
      return s;
  }
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
  switch (canonicalStatusOf(status)) {
    case OrderStatus.awaitingSellerShipping:
      return TrustStage.pricing;
    case OrderStatus.awaitingPayment:
    case OrderStatus.paymentProcessing:
    case OrderStatus.paymentFailed:
      return TrustStage.transaction;
    case OrderStatus.paidInEscrow:
    case OrderStatus.readyForDispatch:
    case OrderStatus.disputed:
    case OrderStatus.refundPending:
      return TrustStage.hold;
    case OrderStatus.dispatched:
      return TrustStage.logistics;
    case OrderStatus.deliveredPendingConfirmation:
      return TrustStage.verification;
    case OrderStatus.completed:
    case OrderStatus.refunded:
      return TrustStage.settlement;
    case OrderStatus.cancelled:
    case OrderStatus.expired:
      return TrustStage.initiation;
    default:
      return TrustStage.initiation;
  }
}
