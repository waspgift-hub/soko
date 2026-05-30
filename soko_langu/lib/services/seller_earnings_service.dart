import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../models/withdrawal_model.dart';
import '../models/transaction_model.dart';
import 'mongike_service.dart';

class SellerEarningsService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get _uid => _auth.currentUser?.uid;

  bool get isFriday {
    final now = DateTime.now();
    return now.weekday == DateTime.friday;
  }

  String get nextPayoutDate {
    final now = DateTime.now();
    final currentWeekday = now.weekday;
    int daysUntilFriday;
    if (currentWeekday <= DateTime.friday) {
      daysUntilFriday = DateTime.friday - currentWeekday;
    } else {
      daysUntilFriday = 7 - (currentWeekday - DateTime.friday);
    }
    if (daysUntilFriday == 0 && currentWeekday == DateTime.friday) {
      return 'Today (Friday)';
    }
    final nextFriday = now.add(Duration(days: daysUntilFriday));
    return DateFormat('EEEE, MMMM d').format(nextFriday);
  }

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

  String? canWithdraw() {
    if (!isFriday) {
      return 'Withdrawals are only available on Fridays (Ijumaa). Next payout: $nextPayoutDate';
    }
    return null;
  }

  Future<String?> requestWithdrawal({
    required String phone,
    String? userName,
  }) async {
    final uid = _uid;
    if (uid == null) return 'Not logged in';

    const minWithdraw = 5000;
    const payoutFee = 2000;

    final blockReason = canWithdraw();
    if (blockReason != null) return blockReason;

    final balance = await getSellerBalance();
    if (balance < minWithdraw) {
      return 'Minimum balance for withdrawal is TZS ${minWithdraw.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')} (net TZS ${(minWithdraw - payoutFee).toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')} after TZS ${payoutFee.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')} fee)';
    }

    final netAmount = balance - payoutFee;

    try {
      await MongikeService.sellerWithdraw(
        userId: uid,
        amount: balance.round(),
        phone: phone,
      );

      await _db.collection('withdrawals').add({
        'userId': uid,
        'userName': userName ?? '',
        'phone': phone,
        'amount': balance,
        'fee': payoutFee,
        'netAmount': netAmount,
        'status': 'completed',
        'withdrawalDay': 'Friday',
        'createdAt': FieldValue.serverTimestamp(),
        'processedAt': FieldValue.serverTimestamp(),
      });

      await _db.collection('users').doc(uid).set({
        'sellerBalance': 0,
        'lastWithdrawalAt': FieldValue.serverTimestamp(),
        'totalWithdrawn': FieldValue.increment(netAmount),
      }, SetOptions(merge: true));

      return null;
    } catch (e) {
      await _db.collection('withdrawals').add({
        'userId': uid,
        'userName': userName ?? '',
        'phone': phone,
        'amount': balance,
        'fee': payoutFee,
        'netAmount': netAmount,
        'status': 'failed',
        'failureReason': e.toString(),
        'withdrawalDay': 'Friday',
        'createdAt': FieldValue.serverTimestamp(),
      });

      return 'Withdrawal failed: $e';
    }
  }
}
