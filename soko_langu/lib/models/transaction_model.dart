import 'package:cloud_firestore/cloud_firestore.dart';

class TransactionFeeBreakdown {
  final double productPrice;
  static const double platformCommissionPercent = 0.04;
  final double processingFee;
  final double platformFee;
  final double payoutFee;
  final double totalFees;
  final double totalAmount;
  final double sellerReceives;

  TransactionFeeBreakdown({required this.productPrice})
    : processingFee = 0,
      platformFee = productPrice * platformCommissionPercent,
      payoutFee = 0,
      totalFees = productPrice * platformCommissionPercent,
      totalAmount = productPrice,
      sellerReceives = productPrice - (productPrice * platformCommissionPercent);

  Map<String, dynamic> toMap() => {
    'productPrice': productPrice,
    'processingFee': processingFee,
    'platformFee': platformFee,
    'payoutFee': payoutFee,
    'platformCommissionPercent': platformCommissionPercent,
    'totalFees': totalFees,
    'totalAmount': totalAmount,
    'sellerReceives': sellerReceives,
  };
}

enum TransactionStatus {
  pending,
  completed,
  failed,
  refunded,
  escrowHold,
  delivered,
}

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
  final double sokoLanguCommission;
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
    this.sokoLanguCommission = 0,
    required this.totalAmount,
    required this.sellerReceives,
    required this.status,
    this.paymentMethod = 'ClickPesa',
    this.transactionReference,
    required this.createdAt,
  });

  factory MarketplaceTransaction.fromMap(String id, Map<String, dynamic> data) {
    final breakdown = TransactionFeeBreakdown(
      productPrice: (data['productPrice'] ?? 0).toDouble(),
    );
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
      processingFee: (data['processingFee'] ?? breakdown.processingFee)
          .toDouble(),
      platformFee: (data['platformFee'] ?? breakdown.platformFee).toDouble(),
      sokoLanguCommission:
          (data['sokoLanguCommission'] ??
                  data['globaseCommission'] ??
                  breakdown.platformFee)
              .toDouble(),
      totalAmount: (data['totalAmount'] ?? breakdown.totalAmount).toDouble(),
      sellerReceives: (data['sellerReceives'] ?? breakdown.sellerReceives)
          .toDouble(),
      status: _parseStatus(data['status'] ?? 'pending'),
      paymentMethod: data['paymentMethod'] ?? 'ClickPesa',
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
    'sokoLanguCommission': sokoLanguCommission,
    'totalAmount': totalAmount,
    'sellerReceives': sellerReceives,
    'status': status == TransactionStatus.escrowHold
        ? 'escrow_hold'
        : status == TransactionStatus.delivered
        ? 'delivered'
        : status.toString().split('.').last,
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
      case 'escrow_hold':
        return TransactionStatus.escrowHold;
      case 'delivered':
        return TransactionStatus.delivered;
      default:
        return TransactionStatus.pending;
    }
  }
}
