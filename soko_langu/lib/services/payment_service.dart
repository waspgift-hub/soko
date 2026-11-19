import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../models/transaction_model.dart';
import 'admin_dashboard_api.dart';
import 'api_config.dart';
import 'fraud_prevention_service.dart';

class PaymentService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final AdminDashboardApi _dashboardApi;

  PaymentService({AdminDashboardApi? dashboardApi})
      : _dashboardApi = dashboardApi ?? AdminDashboardApi();

  TransactionFeeBreakdown calculateFees(double productPrice) {
    return TransactionFeeBreakdown(productPrice: productPrice);
  }

  Future<String> processTransaction({
    required String buyerId,
    required String buyerName,
    required String buyerPhone,
    required String sellerId,
    required String sellerName,
    required String productId,
    required String productName,
    required double productPrice,
    String? transactionReference,
  }) async {
    await FraudPreventionService().checkSuspiciousTransaction(
      buyerId: buyerId,
      sellerId: sellerId,
      sellerName: sellerName,
      amount: productPrice,
    );

    final user = _auth.currentUser;
    if (user == null) throw Exception('User not logged in');
    final token = await user.getIdToken(true);
    final resp = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/api/transactions/create'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'buyerId': buyerId,
        'buyerName': buyerName,
        'buyerPhone': buyerPhone,
        'sellerId': sellerId,
        'sellerName': sellerName,
        'productId': productId,
        'productName': productName,
        'productPrice': productPrice,
        'transactionReference': transactionReference ?? '',
      }),
    );
    final result = jsonDecode(resp.body);
    if (result['success'] != true) {
      throw Exception(result['error'] ?? 'Failed to process transaction');
    }
    return result['transactionId'] as String;
  }

  Stream<List<MarketplaceTransaction>> getSellerTransactions() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);
    return _db
        .collection('transactions')
        .where('sellerId', isEqualTo: user.uid)
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => MarketplaceTransaction.fromMap(doc.id, doc.data()))
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
        );
  }

  Stream<List<MarketplaceTransaction>> getBuyerTransactions() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);
    return _db
        .collection('transactions')
        .where('buyerId', isEqualTo: user.uid)
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => MarketplaceTransaction.fromMap(doc.id, doc.data()))
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
        );
  }

  Future<double> getTotalPlatformEarnings() async {
    final stats = await _dashboardApi.fetchCommissionStats();
    return stats['totalEarnings']!;
  }

  Future<Map<String, double>> getRevenueStats() =>
      _dashboardApi.fetchCommissionStats();
}
