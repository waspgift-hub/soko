import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/transaction_model.dart';

class PaymentService {
  static const double processingFeePercent = 0;
  static const double platformFeePercent = 0;

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  TransactionFeeBreakdown calculateFees(double productPrice) {
    return TransactionFeeBreakdown(productPrice: productPrice);
  }

  Stream<List<MarketplaceTransaction>> getSellerTransactions() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);
    return _db
        .collection('transactions')
        .where('sellerId', isEqualTo: user.uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => MarketplaceTransaction.fromMap(doc.id, doc.data()))
              .toList(),
        );
  }

  Stream<List<MarketplaceTransaction>> getBuyerTransactions() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);
    return _db
        .collection('transactions')
        .where('buyerId', isEqualTo: user.uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => MarketplaceTransaction.fromMap(doc.id, doc.data()))
              .toList(),
        );
  }

  Future<double> getTotalPlatformEarnings() async {
    final snap = await _db
        .collection('transactions')
        .where('status', isEqualTo: 'completed')
        .get();
    return snap.docs.fold<double>(
      0,
      (total, doc) => total + ((doc.data()['platformFee'] ?? 0).toDouble()),
    );
  }

  Future<Map<String, double>> getRevenueStats() async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final monthStart = DateTime(now.year, now.month, 1);
    final all = await _db
        .collection('transactions')
        .where('status', isEqualTo: 'completed')
        .get();
    double total = 0, today = 0, monthly = 0;
    int count = 0;
    for (var doc in all.docs) {
      final d = doc.data();
      final pf = (d['platformFee'] ?? 0).toDouble();
      total += pf;
      final ts = d['createdAt'] as Timestamp?;
      if (ts != null) {
        final date = ts.toDate();
        if (date.isAfter(todayStart)) today += pf;
        if (date.isAfter(monthStart)) monthly += pf;
      }
      count++;
    }
    return {
      'totalEarnings': total,
      'todayEarnings': today,
      'monthlyEarnings': monthly,
      'totalTransactions': count.toDouble(),
    };
  }
}
