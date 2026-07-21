import 'package:cloud_firestore/cloud_firestore.dart';

class TransactionFeeBreakdown {
  final double productPrice;
  static const double platformCommissionPercent = 0.035;
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
      totalAmount = productPrice + (productPrice * platformCommissionPercent),
      sellerReceives = productPrice;

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
  awaitingShippingQuote,
  awaitingPayment,
  paidEscrowHeld,
  dispatched,
  delivered,
  completed,
  failed,
  refunded,
  escrowHold,
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
  final double? shippingCost;
  final Map<String, dynamic>? deliveryAddress;
  final String? courierName;
  final String? driverPhone;
  final String? receiptImageUrl;
  final String? trackingNumber;
  final Map<String, dynamic>? dispatchProof;

  // ── 11 Bus Receipt text fields (zero Firebase Storage) ──
  final String? passengerName;
  final String? busName;
  final String? receiptNumber;
  final String? departureTime;
  final String? arrivalTime;
  final String? originStation;
  final String? destinationStation;
  final String? travelDate;
  final String? travelDay;
  final double? shippingFare;
  final String? plateNumber;

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
    this.paymentMethod = 'Mongike',
    this.transactionReference,
    required this.createdAt,
    this.shippingCost,
    this.deliveryAddress,
    this.courierName,
    this.driverPhone,
    this.receiptImageUrl,
    this.trackingNumber,
    this.dispatchProof,
    this.passengerName,
    this.busName,
    this.receiptNumber,
    this.departureTime,
    this.arrivalTime,
    this.originStation,
    this.destinationStation,
    this.travelDate,
    this.travelDay,
    this.shippingFare,
    this.plateNumber,
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
      status: parseStatus(data['status'] ?? 'pending'),
      paymentMethod: data['paymentMethod'] ?? 'Mongike',
      transactionReference: data['transactionReference'],
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      shippingCost: (data['shippingCost'] as num?)?.toDouble(),
      deliveryAddress: data['deliveryAddress'] as Map<String, dynamic>?,
      courierName: data['courierName'] as String?,
      driverPhone: data['driverPhone'] as String?,
      receiptImageUrl: data['receiptImageUrl'] as String?,
      trackingNumber: data['trackingNumber'] as String?,
      dispatchProof: data['dispatchProof'] as Map<String, dynamic>?,
      passengerName: data['passengerName'] as String?,
      busName: data['busName'] as String?,
      receiptNumber: data['receiptNumber'] as String?,
      departureTime: data['departureTime'] as String?,
      arrivalTime: data['arrivalTime'] as String?,
      originStation: data['originStation'] as String?,
      destinationStation: data['destinationStation'] as String?,
      travelDate: data['travelDate'] as String?,
      travelDay: data['travelDay'] as String?,
      shippingFare: (data['shippingFare'] as num?)?.toDouble(),
      plateNumber: data['plateNumber'] as String?,
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
    'status': _statusToString(status),
    'paymentMethod': paymentMethod,
    'transactionReference': transactionReference,
    'createdAt': FieldValue.serverTimestamp(),
    if (shippingCost != null) 'shippingCost': shippingCost,
    if (deliveryAddress != null) 'deliveryAddress': deliveryAddress,
    if (courierName != null) 'courierName': courierName,
    if (driverPhone != null) 'driverPhone': driverPhone,
    if (receiptImageUrl != null) 'receiptImageUrl': receiptImageUrl,
    if (trackingNumber != null) 'trackingNumber': trackingNumber,
    if (dispatchProof != null) 'dispatchProof': dispatchProof,
    if (passengerName != null) 'passengerName': passengerName,
    if (busName != null) 'busName': busName,
    if (receiptNumber != null) 'receiptNumber': receiptNumber,
    if (departureTime != null) 'departureTime': departureTime,
    if (arrivalTime != null) 'arrivalTime': arrivalTime,
    if (originStation != null) 'originStation': originStation,
    if (destinationStation != null) 'destinationStation': destinationStation,
    if (travelDate != null) 'travelDate': travelDate,
    if (travelDay != null) 'travelDay': travelDay,
    if (shippingFare != null) 'shippingFare': shippingFare,
    if (plateNumber != null) 'plateNumber': plateNumber,
  };

  static String _statusToString(TransactionStatus s) {
    switch (s) {
      case TransactionStatus.escrowHold:
        return 'escrow_hold';
      case TransactionStatus.awaitingShippingQuote:
        return 'awaiting_shipping_quote';
      case TransactionStatus.awaitingPayment:
        return 'awaiting_payment';
      case TransactionStatus.paidEscrowHeld:
        return 'paid_escrow_held';
      default:
        return s.toString().split('.').last;
    }
  }

  static TransactionStatus parseStatus(String status) {
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
      case 'awaiting_shipping_quote':
        return TransactionStatus.awaitingShippingQuote;
      case 'awaiting_payment':
        return TransactionStatus.awaitingPayment;
      case 'paid_escrow_held':
        return TransactionStatus.paidEscrowHeld;
      case 'dispatched':
        return TransactionStatus.dispatched;
      default:
        return TransactionStatus.pending;
    }
  }
}
