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
    final status = _parseStatus(data['status'] ?? 'pending');
    return WithdrawalRequest(
      id: id,
      userId: data['userId'] ?? '',
      userName: data['userName'] ?? '',
      // Compat engine writes userPhone; legacy docs used phone.
      phone: _first(data, ['phone', 'userPhone']),
      amount: (data['amount'] ?? 0).toDouble(),
      fee: (data['fee'] ?? 2000).toDouble(),
      netAmount: (data['netAmount'] ?? 0).toDouble(),
      status: status,
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      processedAt: data['processedAt'] is Timestamp
          ? (data['processedAt'] as Timestamp).toDate()
          : null,
      failureReason: data['failureReason'],
    );
  }

  static String _first(Map<String, dynamic> data, List<String> keys) {
    for (final k in keys) {
      final v = data[k];
      if (v is String && v.isNotEmpty) return v;
    }
    return '';
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
      case 'success':
        return WithdrawalStatus.completed;
      case 'failed':
        return WithdrawalStatus.failed;
      default:
        // 'pending'/'processing': async payout in flight.
        return WithdrawalStatus.pending;
    }
  }
}
