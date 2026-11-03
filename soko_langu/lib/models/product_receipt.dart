class ProductReceipt {
  final String transactionId;
  final String orderId;
  final String buyerName;
  final String shopName;
  final String productTitle;
  final double productPrice;
  final double shippingCost;
  final double grandTotal;
  final String paymentMethod;
  final DateTime timestamp;
  final String status;
  final String escrowStatus;

  String get receiptNumber => transactionId;
  String get productName => productTitle;
  double get amount => grandTotal;
  String get sellerName => shopName;
  DateTime get createdAt => timestamp;

  ProductReceipt({
    required this.transactionId,
    required this.orderId,
    required this.buyerName,
    required this.shopName,
    required this.productTitle,
    required this.productPrice,
    required this.shippingCost,
    required this.grandTotal,
    required this.paymentMethod,
    required this.timestamp,
    this.status = 'completed',
    this.escrowStatus = 'Pending',
  });
}
