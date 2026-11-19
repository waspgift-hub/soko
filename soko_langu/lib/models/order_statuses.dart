/// Client-side order status vocabulary.
///
/// Values are the lowercase strings the legacy Firestore engine writes for the
/// existing screens (see server `legacy-status.js`), so raw statuses compare
/// cleanly against these constants. [canonicalStatusOf] normalises the
/// server-shipped uppercase `ORDER_STATES` (and legacy spellings) onto these
/// values so both data pipes converge on one display path.
class OrderStatus {
  OrderStatus._();

  // Pre-order / drafting
  static const draft = 'draft';
  static const pending = 'pending';
  static const published = 'published';

  // Address + shipping quote
  static const addressRequired = 'address_required';
  static const awaitingShippingQuote = 'awaiting_shipping_quote';
  static const pendingShippingFee = 'pending_shipping_fee';
  static const shippingFeeSubmitted = 'shipping_fee_submitted';
  static const shippingFeeReview = 'shipping_fee_review';
  static const quoted = 'quoted';

  // Payment
  static const awaitingPayment = 'awaiting_payment';
  static const awaitingEscrowPayment = 'awaiting_escrow_payment';
  static const paymentPending = 'payment_pending';
  static const paymentProcessing = 'payment_processing';
  static const paid = 'paid';
  static const paymentFailed = 'payment_failed';

  // Escrow hold
  static const escrowHold = 'escrow_hold';
  static const paidEscrowHold = 'paid_escrow_hold';
  static const paidEscrowHeld = 'paid_escrow_held';
  static const inEscrow = 'in_escrow';
  static const escrowHeld = 'escrow_held';
  static const sellerAccepted = 'seller_accepted';
  static const dispatchReady = 'dispatch_ready';
  static const readyToDispatch = 'ready_to_dispatch';

  // Logistics
  static const dispatched = 'dispatched';
  static const inTransit = 'in_transit';
  static const outForDelivery = 'out_for_delivery';
  static const deliveryAttempted = 'delivery_attempted';
  static const arrived = 'arrived';

  // Verification
  static const delivered = 'delivered';
  static const deliveryConfirmed = 'delivery_confirmed';
  static const confirmed = 'confirmed';
  static const inspectionPeriod = 'inspection_period';
  static const otpPending = 'otp_pending';

  // Settlement
  static const completed = 'completed';
  static const walletCredited = 'wallet_credited';
  static const payoutPending = 'payout_pending';
  static const payoutComplete = 'payout_complete';

  // Protective / terminal
  static const disputed = 'disputed';
  static const refundPending = 'refund_pending';
  static const refunded = 'refunded';
  static const cancelled = 'cancelled';
  static const expired = 'expired';
  static const failed = 'failed';
}

/// Maps any incoming status (server `ORDER_STATES` uppercase or legacy
/// Firestore snake_case/CamelCase spelling) onto the client vocabulary above.
/// Unknown values pass through unchanged instead of falling back to `pending`.
String canonicalStatusOf(String status) {
  // Legacy rows mix snake_case, lowerCamelCase and UpperCamelCase; folding
  // them first keeps every display path on one vocabulary.
  final normalized = status.replaceAllMapped(
    RegExp(r'([a-z0-9])([A-Z])'),
    (match) => '${match.group(1)}_${match.group(2)}',
  );
  switch (normalized.toUpperCase()) {
    case 'DRAFT':
      return OrderStatus.draft;
    case 'PENDING':
      return OrderStatus.pending;
    case 'PUBLISHED':
      return OrderStatus.published;
    case 'ADDRESS_REQUIRED':
      return OrderStatus.addressRequired;
    case 'AWAITING_SHIPPING_QUOTE':
      return OrderStatus.awaitingShippingQuote;
    case 'PENDING_SHIPPING_FEE':
      return OrderStatus.pendingShippingFee;
    case 'SHIPPING_FEE_SUBMITTED':
      return OrderStatus.shippingFeeSubmitted;
    case 'SHIPPING_FEE_REVIEW':
      return OrderStatus.shippingFeeReview;
    case 'QUOTED':
      return OrderStatus.quoted;
    case 'AWAITING_PAYMENT':
      return OrderStatus.awaitingPayment;
    case 'AWAITING_ESCROW_PAYMENT':
      return OrderStatus.awaitingEscrowPayment;
    case 'PENDING_PAYMENT':
      return OrderStatus.paymentPending;
    case 'PAYMENT_PENDING':
      return OrderStatus.paymentPending;
    case 'PAYMENT_PROCESSING':
      return OrderStatus.paymentProcessing;
    case 'PAID':
      return OrderStatus.paid;
    case 'FAILED':
      return OrderStatus.failed;
    case 'PAYMENT_FAILED':
      return OrderStatus.paymentFailed;
    // Escrow spellings kept distinct so the escrow-hold label resolves the
    // same way for legacy rows and newly mirrors docs.
    case 'ESCROW_HOLD':
    case 'PAID_ESCROW_HOLD':
    case 'PAID_ESCROW_HELD':
    case 'IN_ESCROW':
      return OrderStatus.inEscrow;
    case 'ESCROW_HELD':
      return OrderStatus.escrowHeld;
    case 'SELLER_ACCEPTED':
      return OrderStatus.sellerAccepted;
    case 'DISPATCH_READY':
      return OrderStatus.dispatchReady;
    case 'READY_TO_DISPATCH':
      return OrderStatus.readyToDispatch;
    case 'DISPATCHED':
      return OrderStatus.dispatched;
    case 'IN_TRANSIT':
      return OrderStatus.inTransit;
    case 'OUT_FOR_DELIVERY':
      return OrderStatus.outForDelivery;
    case 'DELIVERY_ATTEMPTED':
      return OrderStatus.deliveryAttempted;
    case 'ARRIVED':
      return OrderStatus.arrived;
    case 'DELIVERED':
      return OrderStatus.delivered;
    case 'DELIVERY_CONFIRMED':
    case 'CONFIRMED':
      return OrderStatus.delivered;
    case 'INSPECTION_PERIOD':
      return OrderStatus.inspectionPeriod;
    case 'OTP_PENDING':
      return OrderStatus.otpPending;
    case 'COMPLETED':
      return OrderStatus.completed;
    case 'WALLET_CREDITED':
      return OrderStatus.walletCredited;
    case 'PAYOUT_PENDING':
      return OrderStatus.payoutPending;
    case 'PAYOUT_COMPLETE':
      return OrderStatus.payoutComplete;
    case 'CANCELLED':
      return OrderStatus.cancelled;
    case 'REFUND_PENDING':
      return OrderStatus.refundPending;
    case 'REFUNDED':
      return OrderStatus.refunded;
    case 'DISPUTED':
      return OrderStatus.disputed;
    case 'EXPIRED':
      return OrderStatus.expired;
    default:
      return status;
  }
}

/// Buyer-facing filter buckets. A raw status always lands in exactly one
/// bucket after canonicalisation, so list counts and displayed rows agree.
enum PurchaseBucket { pending, active, completed, failed }

const Set<String> _pendingPurchaseStatuses = {
  OrderStatus.pending,
  OrderStatus.awaitingShippingQuote,
  OrderStatus.awaitingPayment,
  OrderStatus.addressRequired,
  OrderStatus.pendingShippingFee,
  OrderStatus.shippingFeeSubmitted,
  OrderStatus.shippingFeeReview,
  OrderStatus.quoted,
  OrderStatus.awaitingEscrowPayment,
  OrderStatus.paymentPending,
};

const Set<String> _activePurchaseStatuses = {
  OrderStatus.paid,
  OrderStatus.inEscrow,
  OrderStatus.escrowHeld,
  OrderStatus.readyToDispatch,
  OrderStatus.sellerAccepted,
  OrderStatus.dispatchReady,
  OrderStatus.dispatched,
  OrderStatus.inTransit,
  OrderStatus.outForDelivery,
  OrderStatus.deliveryAttempted,
  OrderStatus.arrived,
  OrderStatus.delivered,
  OrderStatus.inspectionPeriod,
  OrderStatus.otpPending,
  OrderStatus.disputed,
  OrderStatus.refundPending,
};

const Set<String> _completedPurchaseStatuses = {
  OrderStatus.completed,
  OrderStatus.walletCredited,
  OrderStatus.payoutPending,
  OrderStatus.payoutComplete,
};

const Set<String> _failedPurchaseStatuses = {
  OrderStatus.failed,
  OrderStatus.paymentFailed,
  OrderStatus.cancelled,
  OrderStatus.refunded,
  OrderStatus.expired,
};

/// Classifies a raw order status into one buyer-facing purchase filter bucket.
PurchaseBucket? purchaseBucketOf(String rawStatus) {
  final status = canonicalStatusOf(rawStatus);
  if (_pendingPurchaseStatuses.contains(status)) return PurchaseBucket.pending;
  if (_activePurchaseStatuses.contains(status)) return PurchaseBucket.active;
  if (_completedPurchaseStatuses.contains(status)) return PurchaseBucket.completed;
  if (_failedPurchaseStatuses.contains(status)) return PurchaseBucket.failed;
  return null;
}

/// Only pre-payment and terminal failed orders may be hidden by the buyer.
/// Hiding an escrow-held order would detach the buyer from live money flow.
bool canHidePurchaseFromBuyer(String rawStatus) {
  final bucket = purchaseBucketOf(rawStatus);
  return bucket == PurchaseBucket.pending || bucket == PurchaseBucket.failed;
}

enum TrustStage {
  initiation,
  pricing,
  transaction,
  hold,
  logistics,
  verification,
  settlement,
  terminal;

  /// i18n key shared with order_flow_screen for the stage label.
  String get labelKey => switch (this) {
    TrustStage.initiation => 'phase_label_initiation',
    TrustStage.pricing => 'phase_label_pricing',
    TrustStage.transaction => 'phase_label_transaction',
    TrustStage.hold => 'phase_label_hold',
    TrustStage.logistics => 'phase_label_logistics',
    TrustStage.verification => 'phase_label_verification',
    TrustStage.settlement => 'phase_label_settlement',
    // Terminal is a distinct outcome banner, never a second settlement row.
    TrustStage.terminal => 'phase_label_closed',
  };
}

/// Buyer can still pay (or retry) in these states.
bool canPayForOrderStatus(String status) {
  switch (canonicalStatusOf(status)) {
    case OrderStatus.awaitingPayment:
    case OrderStatus.awaitingEscrowPayment:
    case OrderStatus.paymentPending:
    case OrderStatus.paymentFailed:
    case OrderStatus.quoted:
      return true;
    default:
      return false;
  }
}

/// Buyer may open a dispute in escrow, transit, inspection or delivered.
bool canDisputeForOrderStatus(String status) {
  switch (canonicalStatusOf(status)) {
    case OrderStatus.inEscrow:
    case OrderStatus.escrowHeld:
    case OrderStatus.sellerAccepted:
    case OrderStatus.dispatched:
    case OrderStatus.inTransit:
    case OrderStatus.outForDelivery:
    case OrderStatus.inspectionPeriod:
    case OrderStatus.delivered:
      return true;
    default:
      return false;
  }
}

/// Valid TZ mobile: 07xx/06xx (10 digits) or 2556x/2557x.
bool isValidTzMobile(String raw) {
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  final local = digits.startsWith('255') ? '0${digits.substring(3)}' : digits;
  return RegExp(r'^0[67]\d{8}$').hasMatch(local);
}

/// Maps any known status (v2 or legacy) onto its position in the seven-stage
/// Trust-Commerce journey. Terminal statuses sit on the stage where the funds
/// lifecycle halted so the stepper never looks like the order is stuck on
/// step one.
TrustStage trustStageOf(String status) {
  switch (canonicalStatusOf(status)) {
    case OrderStatus.draft:
    case OrderStatus.pending:
    case OrderStatus.published:
      return TrustStage.initiation;
    case OrderStatus.addressRequired:
    case OrderStatus.awaitingShippingQuote:
    case OrderStatus.pendingShippingFee:
    case OrderStatus.shippingFeeSubmitted:
    case OrderStatus.shippingFeeReview:
    case OrderStatus.quoted:
      return TrustStage.pricing;
    case OrderStatus.awaitingPayment:
    case OrderStatus.awaitingEscrowPayment:
    case OrderStatus.paymentPending:
    case OrderStatus.paymentProcessing:
    case OrderStatus.paid:
    case OrderStatus.paymentFailed:
      return TrustStage.transaction;
    case OrderStatus.inEscrow:
    case OrderStatus.escrowHeld:
    case OrderStatus.sellerAccepted:
    case OrderStatus.dispatchReady:
    case OrderStatus.readyToDispatch:
    case OrderStatus.disputed:
    case OrderStatus.refundPending:
      return TrustStage.hold;
    case OrderStatus.arrived:
    case OrderStatus.dispatched:
    case OrderStatus.inTransit:
    case OrderStatus.outForDelivery:
    case OrderStatus.deliveryAttempted:
      return TrustStage.logistics;
    case OrderStatus.delivered:
    case OrderStatus.inspectionPeriod:
    case OrderStatus.otpPending:
      return TrustStage.verification;
    case OrderStatus.completed:
    case OrderStatus.walletCredited:
    case OrderStatus.payoutPending:
    case OrderStatus.payoutComplete:
      return TrustStage.settlement;
    case OrderStatus.cancelled:
    case OrderStatus.expired:
    case OrderStatus.failed:
    case OrderStatus.refunded:
      // Terminal states get their own stage so stepper never shows step 0.
      return TrustStage.terminal;
    default:
      return TrustStage.initiation;
  }
}
