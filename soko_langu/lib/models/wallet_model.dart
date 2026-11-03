import 'package:flutter/foundation.dart';

/// Money values arrive as int, double, or String (Prisma serializes
/// Decimal/BigInt columns as strings), so parsing must stay type-tolerant.
int _moneyOf(Object? value) {
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

DateTime? _dateOf(Object? value) {
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

/// One row of the Postgres seller wallet ledger
/// (`server/src/modules/wallet`). Ledger entries are append-only and carry an
/// idempotency key, so the same entry can never post twice.
@immutable
class WalletLedgerEntryData {
  final String id;
  final String type;
  final int amount;
  final int balanceAfter;
  final String? referenceType;
  final String? referenceId;
  final String? description;
  final DateTime? createdAt;

  const WalletLedgerEntryData({
    required this.id,
    required this.type,
    required this.amount,
    required this.balanceAfter,
    this.referenceType,
    this.referenceId,
    this.description,
    this.createdAt,
  });

  factory WalletLedgerEntryData.fromApi(Map<String, dynamic> json) {
    return WalletLedgerEntryData(
      id: json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      amount: _moneyOf(json['amount']),
      balanceAfter: _moneyOf(json['balanceAfter']),
      referenceType: json['referenceType']?.toString(),
      referenceId: json['referenceId']?.toString(),
      description: json['description']?.toString(),
      createdAt: _dateOf(json['createdAt']),
    );
  }
}

/// Seller wallet balances + recent ledger, as returned by
/// `GET /api/v1/wallet`.
@immutable
class WalletDetail {
  final int available;
  final int pending;
  final int frozen;
  final int totalEarned;
  final int totalWithdrawn;
  final List<WalletLedgerEntryData> ledger;

  const WalletDetail({
    required this.available,
    required this.pending,
    required this.frozen,
    required this.totalEarned,
    required this.totalWithdrawn,
    this.ledger = const [],
  });

  factory WalletDetail.fromApi(Map<String, dynamic> json) {
    final balances = json['balances'] is Map<String, dynamic>
        ? json['balances'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final ledger = json['ledger'] is List
        ? (json['ledger'] as List)
              .whereType<Map<String, dynamic>>()
              .map(WalletLedgerEntryData.fromApi)
              .toList()
        : const <WalletLedgerEntryData>[];
    return WalletDetail(
      available: _moneyOf(balances['available']),
      pending: _moneyOf(balances['pending']),
      frozen: _moneyOf(balances['frozen']),
      totalEarned: _moneyOf(balances['totalEarned']),
      totalWithdrawn: _moneyOf(balances['totalWithdrawn']),
      ledger: ledger,
    );
  }
}

/// A seller withdrawal request as returned by the wallet endpoints.
@immutable
class WithdrawalData {
  final String id;
  final int amount;
  final String provider;
  final String status;
  final String? providerPayoutId;
  final String? idempotencyKey;
  final String? phoneNumber;
  final DateTime? createdAt;

  const WithdrawalData({
    required this.id,
    required this.amount,
    required this.provider,
    required this.status,
    this.providerPayoutId,
    this.idempotencyKey,
    this.phoneNumber,
    this.createdAt,
  });

  factory WithdrawalData.fromApi(Map<String, dynamic> json) {
    return WithdrawalData(
      id: json['id']?.toString() ?? '',
      amount: _moneyOf(json['amount']),
      provider: json['provider']?.toString() ?? 'clickpesa',
      status: json['status']?.toString() ?? 'pending',
      providerPayoutId: json['providerPayoutId']?.toString(),
      idempotencyKey: json['idempotencyKey']?.toString(),
      phoneNumber: json['phoneNumber']?.toString(),
      createdAt: _dateOf(json['createdAt']),
    );
  }
}