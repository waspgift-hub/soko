import 'package:cloud_firestore/cloud_firestore.dart';

enum WithdrawalStatus { pending, completed, failed }

class WithdrawalRequest {
  final String id;
  final String userId;
  final String userName;
  final String phone;
  final double amount;
  final double fee;
  final double netAmount;
  final WithdrawalStatus status;
  final DateTime createdAt;
  final DateTime? processedAt;
  final String? failureReason;

  WithdrawalRequest({
    required this.id,
    required this.userId,
    this.userName = '',
    required this.phone,
    required this.amount,
    this.fee = 2000,
    required this.netAmount,
    this.status = WithdrawalStatus.pending,
    required this.createdAt,
    this.processedAt,
    this.failureReason,
  });

  factory WithdrawalRequest.fromMap(String id, Map<String, dynamic> data) {
    return WithdrawalRequest(
      id: id,
      userId: data['userId'] ?? '',
      userName: data['userName'] ?? '',
      phone: data['phone'] ?? '',
      amount: (data['amount'] ?? 0).toDouble(),
      fee: (data['fee'] ?? 2000).toDouble(),
      netAmount: (data['netAmount'] ?? 0).toDouble(),
      status: _parseStatus(data['status'] ?? 'pending'),
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      processedAt: data['processedAt'] is Timestamp
          ? (data['processedAt'] as Timestamp).toDate()
          : null,
      failureReason: data['failureReason'],
    );
  }

  Map<String, dynamic> toMap() => {
    'userId': userId,
    'userName': userName,
    'phone': phone,
    'amount': amount,
    'fee': fee,
    'netAmount': netAmount,
    'status': status.toString().split('.').last,
    'createdAt': FieldValue.serverTimestamp(),
    'processedAt': processedAt != null ? Timestamp.fromDate(processedAt!) : null,
    'failureReason': failureReason,
  };

  static WithdrawalStatus _parseStatus(String status) {
    switch (status) {
      case 'completed':
        return WithdrawalStatus.completed;
      case 'failed':
        return WithdrawalStatus.failed;
      default:
        return WithdrawalStatus.pending;
    }
  }
}
