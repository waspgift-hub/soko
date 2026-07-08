import 'payment_model.dart';

class BoostReceipt {
  final String boostTransactionId;
  final String sellerName;
  final String productId;
  final String boostPackageName;
  final double amountPaid;
  final String paymentMethod;
  final DateTime timestamp;
  final DateTime boostExpiryDate;
  final PaymentStatus paymentStatus;

  String get receiptNumber => boostTransactionId;
  String get productName => boostPackageName;
  double get amount => amountPaid;
  String get boostType => boostPackageName;
  int get durationDays => boostExpiryDate.difference(timestamp).inDays;
  DateTime get createdAt => timestamp;

  BoostReceipt({
    required this.boostTransactionId,
    required this.sellerName,
    required this.productId,
    required this.boostPackageName,
    required this.amountPaid,
    required this.paymentMethod,
    required this.timestamp,
    required this.boostExpiryDate,
    required this.paymentStatus,
  });
}
