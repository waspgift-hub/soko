import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/withdrawal_model.dart';
import '../models/transaction_model.dart';
import 'clickpesa_service.dart';

class SellerEarningsData {
  final double balance;
  final int totalSales;
  final double grossSalesVolume;
  final double totalWithdrawn;
  final double pendingEscrow;

  const SellerEarningsData({
    this.balance = 0,
    this.totalSales = 0,
    this.grossSalesVolume = 0,
    this.totalWithdrawn = 0,
    this.pendingEscrow = 0,
  });
}

class SellerEarningsService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get _uid => _auth.currentUser?.uid;

  Stream<SellerEarningsData> streamEarnings() {
    final uid = _uid;
    if (uid == null) return Stream.value(const SellerEarningsData());
    return _db.collection('users').doc(uid).snapshots().map((snap) {
      if (!snap.exists) return const SellerEarningsData();
      final d = snap.data()!;
      return SellerEarningsData(
        balance: (d['sellerBalance'] as num? ?? 0).toDouble(),
        totalSales: (d['totalSales'] as num? ?? 0).toInt(),
        grossSalesVolume: (d['grossSalesVolume'] as num? ?? 0).toDouble(),
        totalWithdrawn: (d['totalWithdrawn'] as num? ?? 0).toDouble(),
        pendingEscrow: (d['pendingEscrow'] as num? ?? 0).toDouble(),
      );
    });
  }

  Future<SellerEarningsData> getEarnings() async {
    final uid = _uid;
    if (uid == null) return const SellerEarningsData();
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) return const SellerEarningsData();
    final d = doc.data()!;
    return SellerEarningsData(
      balance: (d['sellerBalance'] as num? ?? 0).toDouble(),
      totalSales: (d['totalSales'] as num? ?? 0).toInt(),
      grossSalesVolume: (d['grossSalesVolume'] as num? ?? 0).toDouble(),
      totalWithdrawn: (d['totalWithdrawn'] as num? ?? 0).toDouble(),
      pendingEscrow: (d['pendingEscrow'] as num? ?? 0).toDouble(),
    );
  }

  Stream<List<MarketplaceTransaction>> streamTransactions() {
    final uid = _uid;
    if (uid == null) return Stream.value([]);
    return _db
        .collection('transactions')
        .where('sellerId', isEqualTo: uid)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => MarketplaceTransaction.fromMap(doc.id, doc.data()))
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
  }

  Stream<List<WithdrawalRequest>> streamWithdrawals() {
    final uid = _uid;
    if (uid == null) return Stream.value([]);
    return _db
        .collection('withdrawals')
        .where('userId', isEqualTo: uid)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => WithdrawalRequest.fromMap(doc.id, doc.data()))
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
  }

  Stream<List<Map<String, dynamic>>> streamPayouts() {
    final uid = _uid;
    if (uid == null) return Stream.value([]);
    return _db
        .collection('payouts')
        .where('userId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => ({'id': d.id, ...d.data()})).toList());
  }

  Future<String?> requestWithdrawal({
    required String phone,
    String? userName,
  }) async {
    final uid = _uid;
    if (uid == null) return 'Not logged in';

    final earnings = await getEarnings();
    if (earnings.balance <= 0) {
      return 'No balance to withdraw';
    }

    try {
      await ClickPesaService.sellerWithdraw(
        userId: uid,
        amount: earnings.balance.round(),
        phone: phone,
      );

      return null;
    } catch (e) {
      return 'Withdrawal failed: $e';
    }
  }
}
