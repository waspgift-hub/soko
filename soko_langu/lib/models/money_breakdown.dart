/// Whole-shilling TZS money model shared by checkout, orders and receipts.
///
/// The backend is the authoritative price source. A breakdown stored on the
/// order wins over any locally recomputed figure; local values are only a
/// fallback for legacy rows written before the breakdown existed.
library;

/// Who bears the mobile-money processing fee for an order.
enum ProcessingFeePayer { buyer, seller }

/// Parses a TZS amount into non-negative whole shillings.
///
/// Financial values must never be fractional: Firebase and the payment provider
/// both settle in whole shillings, and doubles drift at the 3.5% commission
/// boundary. Invalid or negative inputs collapse to zero rather than throwing
/// inside a build method.
int toWholeTzs(dynamic value) {
  if (value is! num || !value.isFinite) return 0;
  final rounded = value.round();
  return rounded < 0 ? 0 : rounded;
}

/// Parsing helper accepting the string representations used by older rows.
int tzsFromDynamic(dynamic value) {
  if (value is num) return toWholeTzs(value);
  if (value is String) return toWholeTzs(double.tryParse(value.replaceAll(',', '')));
  return 0;
}

/// One order's immutable pricing record.
///
/// `gatewayAmount` is what the platform pushes to the payment provider and what
/// escrow holds. The provider's processing fee is charged to the buyer on top
/// of that amount (AzamPay MNO checkout), so `buyerTotal` includes it while
/// `gatewayAmount` deliberately does not — otherwise the fee would be charged
/// twice. Historical rows keep their own stored breakdown when fee settings
/// change later.
class PricingBreakdown {
  const PricingBreakdown({
    required this.productPrice,
    this.shippingCost = 0,
    this.commission = 0,
    this.processingFee = 0,
    this.discount = 0,
    this.processingFeePayer = ProcessingFeePayer.buyer,
    this.terminal = false,
  });

  final int productPrice;
  final int shippingCost;
  final int commission;
  final int processingFee;
  final int discount;
  final ProcessingFeePayer processingFeePayer;

  /// Cancelled/refunded orders still have a historical total but nothing due.
  final bool terminal;

  /// Amount handed to the payment provider and held in escrow.
  int get gatewayAmount {
    final raw = productPrice + shippingCost + commission - discount;
    return raw < 0 ? 0 : raw;
  }

  /// Seller entitlement before any seller-borne processing fee.
  int get sellerEntitlement {
    final raw = gatewayAmount - commission;
    return raw < 0 ? 0 : raw;
  }

  /// What the buyer actually parts with, including a buyer-borne fee.
  int get buyerTotal => processingFeePayer == ProcessingFeePayer.buyer
      ? gatewayAmount + processingFee
      : gatewayAmount;

  /// What reaches the seller after a seller-borne fee is deducted.
  int get sellerNet => processingFeePayer == ProcessingFeePayer.seller
      ? (sellerEntitlement - processingFee).clamp(0, 1 << 62).toInt()
      : sellerEntitlement;

  /// Zero once the order is cancelled or refunded.
  int get amountDueNow => terminal ? 0 : buyerTotal;

  /// Every displayed row must reconcile with the displayed total.
  bool get isBalanced => buyerTotal == gatewayAmount +
      (processingFeePayer == ProcessingFeePayer.buyer ? processingFee : 0);

  /// Builds from an order document, preferring a server-stored breakdown.
  ///
  /// Legacy rows have no breakdown object, so individual money fields are used.
  factory PricingBreakdown.fromOrder(Map<String, dynamic> data) {
    final stored = data['pricingBreakdown'];
    final Map<String, dynamic> src = stored is Map
        ? Map<String, dynamic>.from(stored)
        : data;
    final payerRaw = (src['processingFeePayer'] ?? data['processingFeePayer'])
        ?.toString()
        .toLowerCase();
    final payer = payerRaw == 'seller'
        ? ProcessingFeePayer.seller
        : ProcessingFeePayer.buyer;
    final status = (data['status'] ?? '').toString().toLowerCase();
    return PricingBreakdown(
      productPrice: tzsFromDynamic(src['productPrice'] ?? data['productPrice']),
      shippingCost: tzsFromDynamic(src['shippingCost'] ?? data['shippingCost']),
      commission: tzsFromDynamic(src['commission'] ??
          data['platformFee'] ??
          data['sokoLanguCommission']),
      processingFee: tzsFromDynamic(src['processingFee'] ?? data['processingFee']),
      discount: tzsFromDynamic(src['discount'] ?? data['discount']),
      processingFeePayer: payer,
      terminal: const {'cancelled', 'refunded', 'expired', 'failed'}
          .contains(status),
    );
  }

  Map<String, dynamic> toMap() => {
        'productPrice': productPrice,
        'shippingCost': shippingCost,
        'commission': commission,
        'processingFee': processingFee,
        'discount': discount,
        'processingFeePayer': processingFeePayer == ProcessingFeePayer.seller
            ? 'seller'
            : 'buyer',
        'gatewayAmount': gatewayAmount,
        'buyerTotal': buyerTotal,
        'sellerNet': sellerNet,
      };
}
