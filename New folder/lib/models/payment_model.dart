import 'package:cloud_firestore/cloud_firestore.dart';

enum PaymentStatus { pending, completed, failed, refunded }

enum PaymentMethod {
  creditCard,
  debitCard,
  mobileMoney,
  bankTransfer,
  cashOnDelivery,
}

class Payment {
  final String id;
  final String orderId;
  final String userId;
  final double amount;
  final PaymentMethod method;
  final PaymentStatus status;
  final DateTime createdAt;
  final String? transactionId;
  final String? errorMessage;

  Payment({
    required this.id,
    required this.orderId,
    required this.userId,
    required this.amount,
    required this.method,
    required this.status,
    required this.createdAt,
    this.transactionId,
    this.errorMessage,
  });

  factory Payment.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return Payment(
      id: doc.id,
      orderId: data['orderId'] ?? '',
      userId: data['userId'] ?? '',
      amount: (data['amount'] ?? 0).toDouble(),
      method: _parseMethod(data['method'] ?? 'mobileMoney'),
      status: _parseStatus(data['status'] ?? 'pending'),
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      transactionId: data['transactionId'],
      errorMessage: data['errorMessage'],
    );
  }

  static PaymentMethod _parseMethod(String method) {
    switch (method) {
      case 'creditCard':
        return PaymentMethod.creditCard;
      case 'debitCard':
        return PaymentMethod.debitCard;
      case 'bankTransfer':
        return PaymentMethod.bankTransfer;
      case 'cashOnDelivery':
        return PaymentMethod.cashOnDelivery;
      default:
        return PaymentMethod.mobileMoney;
    }
  }

  static PaymentStatus _parseStatus(String status) {
    switch (status) {
      case 'completed':
        return PaymentStatus.completed;
      case 'failed':
        return PaymentStatus.failed;
      case 'refunded':
        return PaymentStatus.refunded;
      default:
        return PaymentStatus.pending;
    }
  }

  Map<String, dynamic> toMap() => {
    'orderId': orderId,
    'userId': userId,
    'amount': amount,
    'method': method.toString().split('.').last,
    'status': status.toString().split('.').last,
    'createdAt': FieldValue.serverTimestamp(),
    'transactionId': transactionId,
    'errorMessage': errorMessage,
  };

  String get methodText {
    switch (method) {
      case PaymentMethod.creditCard:
        return 'Credit Card';
      case PaymentMethod.debitCard:
        return 'Debit Card';
      case PaymentMethod.mobileMoney:
        return 'Mobile Money';
      case PaymentMethod.bankTransfer:
        return 'Bank Transfer';
      case PaymentMethod.cashOnDelivery:
        return 'Cash on Delivery';
    }
  }

  String get statusText {
    switch (status) {
      case PaymentStatus.pending:
        return 'Pending';
      case PaymentStatus.completed:
        return 'Completed';
      case PaymentStatus.failed:
        return 'Failed';
      case PaymentStatus.refunded:
        return 'Refunded';
    }
  }
}
