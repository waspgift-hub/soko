import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'api_config.dart';

class FraudAlert {
  final String id;
  final String sellerId;
  final String sellerName;
  final String type;
  final String severity;
  final String description;
  final DateTime detectedAt;
  final bool resolved;
  final String? productId;

  FraudAlert({
    required this.id,
    required this.sellerId,
    required this.sellerName,
    required this.type,
    required this.severity,
    required this.description,
    required this.detectedAt,
    this.resolved = false,
    this.productId,
  });

  factory FraudAlert.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return FraudAlert(
      id: doc.id,
      sellerId: data['sellerId'] ?? '',
      sellerName: data['sellerName'] ?? 'Unknown',
      type: data['type'] ?? 'unknown',
      severity: data['severity'] ?? 'low',
      description: data['description'] ?? '',
      detectedAt: (data['detectedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      resolved: data['resolved'] ?? false,
      productId: data['productId'],
    );
  }

  Map<String, dynamic> toMap() => {
    'sellerId': sellerId,
    'sellerName': sellerName,
    'type': type,
    'severity': severity,
    'description': description,
    'detectedAt': FieldValue.serverTimestamp(),
    'resolved': resolved,
    'productId': productId,
  };
}

class FraudPreventionService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final FraudPreventionService _instance = FraudPreventionService._();
  factory FraudPreventionService() => _instance;
  FraudPreventionService._();

  bool get isTestMode => ApiConfig.kIsTestMode;

  Stream<List<FraudAlert>> getFraudAlerts({bool? resolved}) {
    Query query = _db.collection('fraud_alerts').orderBy('detectedAt', descending: true);
    if (resolved != null) {
      query = query.where('resolved', isEqualTo: resolved);
    }
    return query.snapshots().map((snap) =>
        snap.docs.map((doc) => FraudAlert.fromFirestore(doc)).toList());
  }

  Future<void> markResolved(String alertId) async {
    await _db.collection('fraud_alerts').doc(alertId).update({'resolved': true});
  }

  Future<Map<String, int>> getFraudStats() async {
    final total = await _db.collection('fraud_alerts').count().get();
    final unresolved = await _db.collection('fraud_alerts')
        .where('resolved', isEqualTo: false).count().get();
    final high = await _db.collection('fraud_alerts')
        .where('severity', isEqualTo: 'high').where('resolved', isEqualTo: false).count().get();
    return {
      'total': total.count ?? 0,
      'unresolved': unresolved.count ?? 0,
      'high': high.count ?? 0,
    };
  }

  Future<void> checkNewSeller(String sellerId, String sellerName) async {
    try {
      final userDoc = await _db.collection('users').doc(sellerId).get();
      final data = userDoc.data();
      if (data == null) return;

      final createdAt = data['createdAt'] as Timestamp?;
      if (createdAt == null) return;

      final accountAge = DateTime.now().difference(createdAt.toDate()).inDays;
      if (accountAge < 1) {
        debugPrint('FRAUD: New seller $sellerId ($sellerName) - account < 1 day old');
      }
    } catch (e) {
      debugPrint('Fraud checkNewSeller error: $e');
    }
  }

  Future<void> checkSuspiciousListing({
    required String sellerId,
    required String sellerName,
    required String productId,
    required String productName,
    required double price,
    required int sellerProductCount,
  }) async {
    try {
      if (sellerProductCount > 20 && price > 1000000) {
        debugPrint('FRAUD: Bulk high-value listing - $sellerName has $sellerProductCount listings, product $productName at TZS $price');
      }

      final recentSnap = await _db.collection('products')
          .where('sellerId', isEqualTo: sellerId)
          .where('createdAt', isGreaterThanOrEqualTo: DateTime.now().subtract(const Duration(hours: 1)))
          .count()
          .get();
      if ((recentSnap.count ?? 0) > 5) {
        debugPrint('FRAUD: Rapid listing - $sellerName created ${recentSnap.count} products in last hour');
      }
    } catch (e) {
      debugPrint('Fraud checkSuspiciousListing error: $e');
    }
  }

  Future<void> checkSuspiciousTransaction({
    required String buyerId,
    required String sellerId,
    required String sellerName,
    required double amount,
  }) async {
    try {
      if (amount > 5000000) {
        debugPrint('FRAUD: High-value transaction - $sellerName, TZS $amount');
      }

      final sellerDoc = await _db.collection('users').doc(sellerId).get();
      if (sellerDoc.data()?['kyc']?['approved'] != true && amount > 100000) {
        debugPrint('FRAUD: Non-KYC seller $sellerName receiving TZS $amount');
      }

      final recentTxSnap = await _db.collection('transactions')
          .where('sellerId', isEqualTo: sellerId)
          .where('createdAt', isGreaterThanOrEqualTo: DateTime.now().subtract(const Duration(hours: 24)))
          .count()
          .get();
      final dailyTotal = (recentTxSnap.count ?? 0) * amount;
      if (dailyTotal > 5000000) {
        debugPrint('FRAUD: Daily limit exceeded - $sellerName, TZS $dailyTotal in 24h');
      }
    } catch (e) {
      debugPrint('Fraud checkSuspiciousTransaction error: $e');
    }
  }
}
