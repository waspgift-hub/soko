import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/transaction_model.dart';
import 'fraud_prevention_service.dart';

class PaymentService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  TransactionFeeBreakdown calculateFees(double productPrice) {
    return TransactionFeeBreakdown(productPrice: productPrice);
  }

  Future<void> processTransaction({
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
    final breakdown = TransactionFeeBreakdown(productPrice: productPrice);

    await FraudPreventionService().checkSuspiciousTransaction(
      buyerId: buyerId,
      sellerId: sellerId,
      sellerName: sellerName,
      amount: productPrice,
    );

    final docRef = await _db.collection('transactions').add({
      'buyerId': buyerId,
      'buyerName': buyerName,
      'buyerPhone': buyerPhone,
      'sellerId': sellerId,
      'sellerName': sellerName,
      'productId': productId,
      'productName': productName,
      'productPrice': productPrice,
      'processingFee': breakdown.processingFee,
      'platformFee': breakdown.platformFee,
      'mongikeFee': breakdown.processingFee,
      'sokoLanguCommission': breakdown.platformFee,
      'totalAmount': breakdown.totalAmount,
      'sellerReceives': breakdown.sellerReceives,
      'status': 'completed',
      'paymentMethod': 'Mongike',
      'transactionReference': transactionReference ?? '',
      'createdAt': FieldValue.serverTimestamp(),
    });

    await _db.collection('users').doc(sellerId).set({
      'sellerBalance': FieldValue.increment(breakdown.sellerReceives),
      'totalSales': FieldValue.increment(1),
      'grossSalesVolume': FieldValue.increment(productPrice),
      'lastSaleAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _db.collection('revenue_transactions').add({
      'userId': sellerId,
      'amount': breakdown.sellerReceives,
      'type': 'sale',
      'description': 'Sale of $productName',
      'transactionId': docRef.id,
      'productName': productName,
      'productPrice': productPrice,
      'mongikeFee': breakdown.processingFee,
      'sokoLanguCommission': breakdown.platformFee,
      'buyerName': buyerName,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<MarketplaceTransaction>> getSellerTransactions() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);
    return _db
        .collection('transactions')
        .where('sellerId', isEqualTo: user.uid)
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
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => MarketplaceTransaction.fromMap(doc.id, doc.data()))
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
        );
  }

  Future<double> getTotalPlatformEarnings() async {
    final snap = await _db
        .collection('transactions')
        .where('status', isEqualTo: 'completed')
        .get();
    return snap.docs.fold<double>(
      0,
      (total, doc) => total + ((doc.data()['sokoLanguCommission'] ?? doc.data()['globaseCommission'] ?? doc.data()['platformFee'] ?? 0).toDouble()),
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
      final pf = (d['sokoLanguCommission'] ?? d['globaseCommission'] ?? d['platformFee'] ?? 0).toDouble();
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
