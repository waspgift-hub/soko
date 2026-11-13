import 'dart:async';

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

  // ── Stream reuse ───────────────────────────────────────────
  //
  // Each `stream*` method is called from a `StreamBuilder.stream:` in build().
  // Returning a NEW stream object from build makes StreamBuilder unsubscribe and
  // resubscribe — and every resubscribe re-ran the work. `streamEarnings` and
  // `streamWithdrawals` were `Stream.fromFuture(...)`, so every rebuild issued a
  // fresh wallet HTTP request; `streamTransactions` opened a fresh Firestore
  // listener and re-ran a 100-document query. Three tabs x N rebuilds x a
  // network call each.
  //
  // Now each is memoised behind a broadcast controller that replays its last
  // value to a new subscriber, so the fetch happens once per refresh rather than
  // once per rebuild. Call `refresh()` to force new data.
  final StreamController<SellerEarningsData> _earningsCtrl =
      StreamController<SellerEarningsData>.broadcast();
  SellerEarningsData? _earningsLast;

  final StreamController<List<MarketplaceTransaction>> _transactionsCtrl =
      StreamController<List<MarketplaceTransaction>>.broadcast();
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _transactionsSub;
  List<MarketplaceTransaction>? _transactionsLast;

  final StreamController<List<WithdrawalRequest>> _withdrawalsCtrl =
      StreamController<List<WithdrawalRequest>>.broadcast();
  List<WithdrawalRequest>? _withdrawalsLast;

  String? _uidSeen;

  SellerEarningsService() {
    // A broadcast controller drops events while nobody listens, so the first
    // subscriber has to be what triggers the fetch. Without this the tab would
    // sit on "loading" forever the first time it was opened.
    _earningsCtrl.onListen = _loadEarnings;
    _withdrawalsCtrl.onListen = _loadWithdrawals;
  }

  Future<void> _loadEarnings() async {
    if (_earningsLast != null) return;
    final uid = _uid;
    if (uid == null) return;
    _earningsLast = await _walletEarnings(uid);
    if (!_earningsCtrl.isClosed) _earningsCtrl.add(_earningsLast!);
  }

  Future<void> _loadWithdrawals() async {
    if (_withdrawalsLast != null) return;
    final uid = _uid;
    if (uid == null) return;
    _withdrawalsLast = await _walletWithdrawals(uid);
    if (!_withdrawalsCtrl.isClosed) _withdrawalsCtrl.add(_withdrawalsLast!);
  }

  /// Drops cached data for a different (or signed-out) user. Without this, a
  /// logout/login as another seller would show the previous seller's balance.
  void _rebindIfUserChanged() {
    final uid = _uid;
    if (uid == _uidSeen) return;
    _uidSeen = uid;
    _earningsLast = null;
    _transactionsLast = null;
    _withdrawalsLast = null;
    _transactionsSub?.cancel();
    _transactionsSub = null;
  }

  Stream<SellerEarningsData> streamEarnings() {
    _rebindIfUserChanged();
    final uid = _uid;
    if (uid == null) return Stream.value(const SellerEarningsData());

    // Replay the last value immediately so a remounted widget never sits on
    // "loading" while the fetch is in flight.
    if (_earningsLast != null && !_earningsCtrl.hasListener) {
      scheduleMicrotask(() {
        if (!_earningsCtrl.isClosed) _earningsCtrl.add(_earningsLast!);
      });
    }
    return _earningsCtrl.stream;
  }

  Future<SellerEarningsData> getEarnings() async {
    final uid = _uid;
    if (uid == null) return const SellerEarningsData();
    final data = await _walletEarnings(uid);
    _earningsLast = data;
    return data;
  }

  Stream<List<MarketplaceTransaction>> streamTransactions() {
    _rebindIfUserChanged();
    final uid = _uid;
    if (uid == null) return Stream.value([]);

    // Open the Firestore listener once, not once per rebuild.
    _transactionsSub ??= _db
        .collection('transactions')
        .where('sellerId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .listen((snap) {
      final rows = snap.docs
          .map((doc) => MarketplaceTransaction.fromMap(doc.id, doc.data()))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _transactionsLast = rows;
      if (!_transactionsCtrl.isClosed) _transactionsCtrl.add(rows);
    }, onError: (_) {
      // Keep the last good rows on screen rather than blanking the tab.
    });

    if (_transactionsLast != null) {
      scheduleMicrotask(() {
        if (!_transactionsCtrl.isClosed) _transactionsCtrl.add(_transactionsLast!);
      });
    }
    return _transactionsCtrl.stream;
  }

  Stream<List<WithdrawalRequest>> streamWithdrawals() {
    _rebindIfUserChanged();
    final uid = _uid;
    if (uid == null) return Stream.value([]);

    if (_withdrawalsLast != null) {
      scheduleMicrotask(() {
        if (!_withdrawalsCtrl.isClosed) _withdrawalsCtrl.add(_withdrawalsLast!);
      });
    }
    return _withdrawalsCtrl.stream;
  }

  /// Forces new data on every cached stream. Called after a withdrawal request
  /// and on pull-to-refresh, so the user sees the effect of their own action
  /// without relying on a rebuild to trigger it.
  Future<void> refresh() async {
    _rebindIfUserChanged();
    final uid = _uid;
    if (uid == null) return;

    _earningsLast = await _walletEarnings(uid);
    if (!_earningsCtrl.isClosed) _earningsCtrl.add(_earningsLast!);

    _withdrawalsLast = await _walletWithdrawals(uid);
    if (!_withdrawalsCtrl.isClosed) _withdrawalsCtrl.add(_withdrawalsLast!);
  }

  /// Releases the Firestore listener. The service is a per-screen instance, so
  /// the screen owning it should call this from dispose().
  Future<void> dispose() async {
    await _transactionsSub?.cancel();
    _transactionsSub = null;
    await _earningsCtrl.close();
    await _transactionsCtrl.close();
    await _withdrawalsCtrl.close();
  }

  Future<String?> requestWithdrawal({
    required String phone,
    String? userName,
  }) async {
    final uid = _uid;
    if (uid == null) return 'Not logged in';
    final result = await _walletRequestWithdrawal(phone);
    // The request moves money, so the cached balance/withdrawal lists are now
    // stale. Refreshing here is what makes the new balance appear immediately
    // instead of waiting for a rebuild to re-run the fetch.
    await refresh();
    return result;
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
