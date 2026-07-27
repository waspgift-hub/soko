import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/withdrawal_model.dart';
import '../models/transaction_model.dart';
import 'clickpesa_service.dart';

class SellerEarningsService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get _uid => _auth.currentUser?.uid;

  Stream<double> streamSellerBalance() {
    final uid = _uid;
    if (uid == null) return Stream.value(0);
    return _db.collection('users').doc(uid).snapshots().map((snap) {
      if (!snap.exists) return 0;
      return (snap.data()?['sellerBalance'] as num? ?? 0).toDouble();
    });
  }

  Stream<int> streamTotalSales() {
    final uid = _uid;
    if (uid == null) return Stream.value(0);
    return _db.collection('users').doc(uid).snapshots().map((snap) {
      if (!snap.exists) return 0;
      return (snap.data()?['totalSales'] as num? ?? 0).toInt();
    });
  }

  Stream<double> streamGrossSalesVolume() {
    final uid = _uid;
    if (uid == null) return Stream.value(0);
    return _db.collection('users').doc(uid).snapshots().map((snap) {
      if (!snap.exists) return 0;
      return (snap.data()?['grossSalesVolume'] as num? ?? 0).toDouble();
    });
  }

  Stream<double> streamSellerTotalWithdrawn() {
    final uid = _uid;
    if (uid == null) return Stream.value(0);
    return _db.collection('users').doc(uid).snapshots().map((snap) {
      if (!snap.exists) return 0;
      return (snap.data()?['totalWithdrawn'] as num? ?? 0).toDouble();
    });
  }

  Future<double> getSellerBalance() async {
    final uid = _uid;
    if (uid == null) return 0;
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) return 0;
    return (doc.data()?['sellerBalance'] as num? ?? 0).toDouble();
  }

  Future<int> getTotalSales() async {
    final uid = _uid;
    if (uid == null) return 0;
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) return 0;
    return (doc.data()?['totalSales'] as num? ?? 0).toInt();
  }

  Future<double> getGrossSalesVolume() async {
    final uid = _uid;
    if (uid == null) return 0;
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) return 0;
    return (doc.data()?['grossSalesVolume'] as num? ?? 0).toDouble();
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

    const minWithdraw = 5000;

    final balance = await getSellerBalance();
    if (balance < minWithdraw) {
      return 'Minimum balance for withdrawal is TZS 5,000';
    }

    try {
      await ClickPesaService.sellerWithdraw(
        userId: uid,
        amount: balance.round(),
        phone: phone,
      );

      return null;
    } catch (e) {
      return 'Withdrawal failed: $e';
    }
  }
}