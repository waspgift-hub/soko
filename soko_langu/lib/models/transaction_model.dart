import 'package:cloud_firestore/cloud_firestore.dart';

class TransactionFeeBreakdown {
  final double productPrice;
  final double processingFeePercent;
  final double platformFeePercent;
  final double processingFee;
  final double platformFee;
  final double totalFee;
  final double totalAmount;
  final double sellerReceives;

  TransactionFeeBreakdown({
    required this.productPrice,
    this.processingFeePercent = 0.03,
    this.platformFeePercent = 0.02,
  }) : processingFee = productPrice * processingFeePercent,
       platformFee = productPrice * platformFeePercent,
       totalFee = productPrice * (processingFeePercent + platformFeePercent),
       totalAmount =
           productPrice * (1 + processingFeePercent + platformFeePercent),
       sellerReceives = productPrice;

  Map<String, dynamic> toMap() => {
    'productPrice': productPrice,
    'processingFeePercent': processingFeePercent,
    'platformFeePercent': platformFeePercent,
    'processingFee': processingFee,
    'platformFee': platformFee,
    'totalFee': totalFee,
    'totalAmount': totalAmount,
    'sellerReceives': sellerReceives,
  };
}

enum TransactionStatus { pending, completed, failed, refunded }

class MarketplaceTransaction {
  final String id;
  final String buyerId;
  final String buyerName;
  final String buyerPhone;
  final String sellerId;
  final String sellerName;
  final String productId;
  final String productName;
  final double productPrice;
  final double processingFee;
  final double platformFee;
  final double totalAmount;
  final double sellerReceives;
  final TransactionStatus status;
  final String paymentMethod;
  final String? transactionReference;
  final DateTime createdAt;

  MarketplaceTransaction({
    required this.id,
    required this.buyerId,
    required this.buyerName,
    this.buyerPhone = '',
    required this.sellerId,
    required this.sellerName,
    required this.productId,
    required this.productName,
    required this.productPrice,
    required this.processingFee,
    required this.platformFee,
    required this.totalAmount,
    required this.sellerReceives,
    required this.status,
    this.paymentMethod = 'Mongike',
    this.transactionReference,
    required this.createdAt,
  });

  factory MarketplaceTransaction.fromMap(String id, Map<String, dynamic> data) {
    return MarketplaceTransaction(
      id: id,
      buyerId: data['buyerId'] ?? '',
      buyerName: data['buyerName'] ?? '',
      buyerPhone: data['buyerPhone'] ?? '',
      sellerId: data['sellerId'] ?? '',
      sellerName: data['sellerName'] ?? '',
      productId: data['productId'] ?? '',
      productName: data['productName'] ?? '',
      productPrice: (data['productPrice'] ?? 0).toDouble(),
      processingFee: (data['processingFee'] ?? 0).toDouble(),
      platformFee: (data['platformFee'] ?? 0).toDouble(),
      totalAmount: (data['totalAmount'] ?? 0).toDouble(),
      sellerReceives: (data['sellerReceives'] ?? 0).toDouble(),
      status: _parseStatus(data['status'] ?? 'pending'),
      paymentMethod: data['paymentMethod'] ?? 'Mongike',
      transactionReference: data['transactionReference'],
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
    'buyerId': buyerId,
    'buyerName': buyerName,
    'buyerPhone': buyerPhone,
    'sellerId': sellerId,
    'sellerName': sellerName,
    'productId': productId,
    'productName': productName,
    'productPrice': productPrice,
    'processingFee': processingFee,
    'platformFee': platformFee,
    'totalAmount': totalAmount,
    'sellerReceives': sellerReceives,
    'status': status.toString().split('.').last,
    'paymentMethod': paymentMethod,
    'transactionReference': transactionReference,
    'createdAt': FieldValue.serverTimestamp(),
  };

  static TransactionStatus _parseStatus(String status) {
    switch (status) {
      case 'completed':
        return TransactionStatus.completed;
      case 'failed':
        return TransactionStatus.failed;
      case 'refunded':
        return TransactionStatus.refunded;
      default:
        return TransactionStatus.pending;
    }
  }
}
