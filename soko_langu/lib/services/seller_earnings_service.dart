import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/withdrawal_model.dart';
import '../models/transaction_model.dart';
import 'wallet_api.dart';

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
    // Wallet mode: money lives in the Postgres wallet; Firestore only
    // contributes the sales counters, never balances.
    return Stream.fromFuture(_walletEarnings(uid));
  }

  Future<SellerEarningsData> getEarnings() async {
    final uid = _uid;
    if (uid == null) return const SellerEarningsData();
    return _walletEarnings(uid);
  }

  Stream<List<MarketplaceTransaction>> streamTransactions() {
    final uid = _uid;
    if (uid == null) return Stream.value([]);
    return _db
        .collection('transactions')
        .where('sellerId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => MarketplaceTransaction.fromMap(doc.id, doc.data()))
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
  }

  Stream<List<WithdrawalRequest>> streamWithdrawals() {
    final uid = _uid;
    if (uid == null) return Stream.value([]);
    return Stream.fromFuture(_walletWithdrawals(uid));
  }

  Future<String?> requestWithdrawal({
    required String phone,
    String? userName,
  }) async {
    final uid = _uid;
    if (uid == null) return 'Not logged in';
    return _walletRequestWithdrawal(phone);
  }

  Future<SellerEarningsData> _walletEarnings(String uid) async {
    double balance = 0, withdrawn = 0, escrow = 0;
    int totalSales = 0;
    double gross = 0;
    try {
      final wallet = await WalletApiClient().fetchWallet();
      balance = wallet.available.toDouble();
      withdrawn = wallet.totalWithdrawn.toDouble();
      escrow = wallet.pending.toDouble();
    } catch (_) {
      // Wallet unreachable: surface a zeroed state so the withdrawal card stays
      // disabled instead of showing stale money.
    }
    try {
      final doc = await _db.collection('users').doc(uid).get();
      final d = doc.data();
      if (d != null) {
        totalSales = (d['totalSales'] as num? ?? 0).toInt();
        gross = (d['grossSalesVolume'] as num? ?? 0).toDouble();
      }
    } catch (_) {
      // Sales counters are supplementary; a read failure must not blank money.
    }
    return SellerEarningsData(
      balance: balance,
      totalSales: totalSales,
      grossSalesVolume: gross,
      totalWithdrawn: withdrawn,
      pendingEscrow: escrow,
    );
  }

  Future<List<WithdrawalRequest>> _walletWithdrawals(String uid) async {
    try {
      final rows = await WalletApiClient().fetchWithdrawals();
      return rows.map((w) => WithdrawalRequest(
            id: w.id,
            userId: uid,
            // The v1 server captures the destination phone at request time.
            phone: w.phoneNumber ?? '',
            amount: w.amount.toDouble(),
            fee: 0,
            netAmount: w.amount.toDouble(),
            status: _statusOf(w.status),
            createdAt: w.createdAt ?? DateTime.now(),
          )).toList();
    } catch (_) {
      // History is non-critical; an empty list renders the empty-state card.
      return [];
    }
  }

  Future<String?> _walletRequestWithdrawal(String phone) async {
    try {
      final wallet = await WalletApiClient().fetchWallet();
      if (wallet.available <= 0) return 'No balance to withdraw';
      await WalletApiClient().requestWithdrawal(
        amount: wallet.available,
        phoneNumber: phone,
      );
      return null;
    } catch (e) {
      return 'Withdrawal failed: $e';
    }
  }

  static WithdrawalStatus _statusOf(String status) {
    switch (status) {
      case 'completed':
        return WithdrawalStatus.completed;
      case 'failed':
        return WithdrawalStatus.failed;
      default:
        // 'pending'/'processing': async payout still in flight.
        return WithdrawalStatus.pending;
    }
  }
}
