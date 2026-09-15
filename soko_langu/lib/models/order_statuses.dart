/// Canonical order statuses produced by the v2 Trust-Commerce engine
/// (server/src/modules/orders/order-state-machine.js) plus legacy aliases
/// from the older Firestore engine the app still talks to during migration.
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
  static const paid = 'paid';

  // Escrow hold
  static const escrowHold = 'escrow_hold';
  static const paidEscrowHold = 'paid_escrow_hold';
  static const paidEscrowHeld = 'paid_escrow_held';
  static const inEscrow = 'in_escrow';
  static const readyToDispatch = 'ready_to_dispatch';

  // Logistics
  static const dispatched = 'dispatched';
  static const inTransit = 'in_transit';
  static const outForDelivery = 'out_for_delivery';
  static const deliveryAttempted = 'delivery_attempted';

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

/// Returns the status the UI should render for a given raw status. Legacy
/// aliases with identical meaning today are mapped onto their v2 canonical
/// value so both engines share one display path during migration. Unknown
/// values pass through unchanged instead of falling back to `pending`.
String canonicalStatusOf(String status) {
  switch (status) {
    case OrderStatus.escrowHold:
    case OrderStatus.paidEscrowHold:
    case OrderStatus.paidEscrowHeld:
      return OrderStatus.inEscrow;
    case OrderStatus.deliveryConfirmed:
    case OrderStatus.confirmed:
      return OrderStatus.delivered;
    default:
      return status;
  }
}

/// The seven Trust-Commerce stages guaranteed to the user. Matches the phase
/// labels already rendered by order_flow_screen.dart.
enum TrustStage {
  initiation,
  pricing,
  transaction,
  hold,
  logistics,
  verification,
  settlement;

  /// i18n key shared with order_flow_screen for the stage label.
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

/// Maps any known status (v2 or legacy) onto its position in the seven-stage
/// Trust-Commerce journey. Terminal statuses sit on the stage where the funds
/// lifecycle halted so the stepper never looks like the order is stuck on
/// step one.
TrustStage trustStageOf(String status) {
  switch (status) {
    case OrderStatus.draft:
    case OrderStatus.pending:
    case OrderStatus.published:
    case OrderStatus.cancelled:
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
    case OrderStatus.paid:
    case OrderStatus.expired:
    case OrderStatus.failed:
      return TrustStage.transaction;
    case OrderStatus.escrowHold:
    case OrderStatus.paidEscrowHold:
    case OrderStatus.paidEscrowHeld:
    case OrderStatus.inEscrow:
    case OrderStatus.readyToDispatch:
    case OrderStatus.disputed:
    case OrderStatus.refundPending:
      return TrustStage.hold;
    case OrderStatus.dispatched:
    case OrderStatus.inTransit:
    case OrderStatus.outForDelivery:
    case OrderStatus.deliveryAttempted:
      return TrustStage.logistics;
    case OrderStatus.delivered:
    case OrderStatus.deliveryConfirmed:
    case OrderStatus.confirmed:
    case OrderStatus.inspectionPeriod:
    case OrderStatus.otpPending:
      return TrustStage.verification;
    case OrderStatus.completed:
    case OrderStatus.walletCredited:
    case OrderStatus.payoutPending:
    case OrderStatus.payoutComplete:
    case OrderStatus.refunded:
      return TrustStage.settlement;
    default:
      return TrustStage.initiation;
  }
}