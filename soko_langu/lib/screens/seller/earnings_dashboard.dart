import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../services/ad_revenue_service.dart';
import '../../services/wallet_service.dart';
import '../../services/mongike_service.dart';
import '../../shared/loading_widget.dart';
import '../../extensions/context_tr.dart';

class EarningsDashboard extends StatefulWidget {
  const EarningsDashboard({super.key});

  @override
  State<EarningsDashboard> createState() => _EarningsDashboardState();
}

class _EarningsDashboardState extends State<EarningsDashboard> {
  final WalletService _walletService = WalletService();
  final AdRevenueService _adRevenueService = AdRevenueService();
  final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  final _phoneController = TextEditingController();
  bool _withdrawing = false;
  int _adViewsToday = 0;
  int _adViewsMonth = 0;
  StreamSubscription<DocumentSnapshot>? _userSub;
  double _sellerBalance = 0;

  @override
  void initState() {
    super.initState();
    if (uid.isNotEmpty) {
      _walletService.ensureWallet(uid);
      _loadCounts();
      _userSub = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .snapshots()
          .listen((snap) {
        if (snap.exists && mounted) {
          setState(() {
            _sellerBalance =
                (snap.data()?['sellerBalance'] as num? ?? 0).toDouble();
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _userSub?.cancel();
    super.dispose();
  }

  Future<void> _loadCounts() async {
    final today = await _adRevenueService.getAdViewsCountToday(uid);
    final month = await _adRevenueService.getAdViewsCountThisMonth(uid);
    if (mounted) {
      setState(() {
        _adViewsToday = today;
        _adViewsMonth = month;
      });
    }
  }

  Future<void> _withdraw() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      _showError(context.tr('enter_phone_withdraw'));
      return;
    }
    if (_sellerBalance < 2001) {
      _showError(context.tr('withdraw_min_amount'));
      return;
    }

    setState(() => _withdrawing = true);
    try {
      await MongikeService.sellerWithdraw(
        userId: uid,
        amount: _sellerBalance.round(),
        phone: phone,
      );
      if (mounted) {
        _phoneController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('withdrawal_success'))),
        );
      }
    } catch (e) {
      if (mounted) _showError(e.toString());
    } finally {
      if (mounted) setState(() => _withdrawing = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Revenue')),
      body: SafeArea(
        child: uid.isEmpty
            ? const Center(child: Text('Not logged in'))
            : StreamBuilder<DocumentSnapshot>(
                stream: _walletService.streamWallet(uid),
                builder: (context, snap) {
                  final data = switch (snap.data?.data()) {
                    Map<String, dynamic> m => m,
                    _ => <String, dynamic>{},
                  };
                  final adBalance =
                      (data['balance'] as num? ?? 0).toDouble();
                  final totalEarnings =
                      (data['totalEarnings'] as num? ?? 0).toDouble();

                  return ListView(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      16,
                      16,
                      MediaQuery.of(context).padding.bottom + 16,
                    ),
                    children: [
                      _buildSellerBalanceCard(),
                      const SizedBox(height: 12),
                      _buildAdBalanceCard(adBalance, totalEarnings),
                      const SizedBox(height: 16),
                      _buildWithdrawSection(),
                      const SizedBox(height: 16),
                      _buildStatsRow(),
                      const SizedBox(height: 16),
                      _buildSectionTitle(context.tr('recent_transactions')),
                      _buildTransactionsList(),
                      const SizedBox(height: 16),
                      _buildSectionTitle(context.tr('withdrawal_history')),
                      _buildWithdrawalHistory(),
                    ],
                  );
                },
              ),
      ),
    );
  }

  Widget _buildSellerBalanceCard() {
    final nf = NumberFormat('#,###', 'en');
    return Card(
      elevation: 4,
      color: Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              context.tr('seller_balance'),
              style: TextStyle(color: Colors.green.shade700, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              '${nf.format(_sellerBalance)} TZS',
              style: const TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdBalanceCard(double balance, double totalEarnings) {
    final nf = NumberFormat('#,###', 'en');
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.monetization_on, color: Colors.orange.shade600),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('ad_revenue'),
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                  Text(
                    '${nf.format(balance)} TZS',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '${context.tr('total_sales')} ${nf.format(totalEarnings)} TZS',
              style: TextStyle(color: Colors.grey[500], fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWithdrawSection() {
    final canWithdraw = _sellerBalance >= 2001;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('enter_phone_withdraw'),
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                hintText: context.tr('withdraw_phone_hint'),
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.phone_android),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed:
                    canWithdraw && !_withdrawing ? _withdraw : null,
                icon: _withdrawing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send),
                label: Text(
                  _withdrawing
                      ? context.tr('withdrawal_processing')
                      : context.tr('withdraw'),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            if (!canWithdraw)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  context.tr('withdraw_min_amount'),
                  style: TextStyle(color: Colors.red[400], fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsRow() {
    final nf = NumberFormat('#,###', 'en');
    return Row(
      children: [
        Expanded(
          child: _statTile(
            context.tr('todays_views'),
            nf.format(_adViewsToday),
            Icons.visibility,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _statTile(
            context.tr('this_month'),
            nf.format(_adViewsMonth),
            Icons.visibility,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _statTile(context.tr('rev_share'), '40%', Icons.percent),
        ),
      ],
    );
  }

  Widget _statTile(String label, String value, IconData icon) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(icon, color: Colors.blueGrey, size: 20),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Text(
              label,
              style: TextStyle(color: Colors.grey[600], fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildTransactionsList() {
    if (uid.isEmpty) return const SizedBox.shrink();
    return StreamBuilder<QuerySnapshot>(
      stream: _walletService.getTransactions(uid),
      builder: (context, snap) {
        if (snap.hasError) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text(
                  context.tr('error_loading_transactions'),
                  style: TextStyle(color: Colors.red[400]),
                ),
              ),
            ),
          );
        }
        if (!snap.hasData) {
          return LoadingWidget(message: context.tr('loading'));
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text(
                  context.tr('no_transactions'),
                  style: TextStyle(color: Colors.grey[500]),
                ),
              ),
            ),
          );
        }
        return Column(
          children: docs.map((doc) {
            final d = doc.data() as Map<String, dynamic>;
            final amount = (d['amount'] as num? ?? 0).toDouble();
            final ts = d['timestamp'] as Timestamp?;
            final date = ts?.toDate() ?? DateTime.now();
            final type = d['type'] as String? ?? '';
            final desc = d['description'] as String? ?? '';
            final nf = NumberFormat('#,###', 'en');
            final isSale = type == 'sale';
            return Card(
              child: ListTile(
                leading: Icon(
                  isSale ? Icons.shopping_bag : Icons.trending_up,
                  color: isSale ? Colors.green : Colors.orange,
                ),
                title: Text(
                  desc.isEmpty
                      ? (isSale
                          ? context.tr('sell')
                          : context.tr('ad_revenue'))
                      : desc,
                ),
                subtitle: Text(DateFormat('MMM dd, yyyy').format(date)),
                trailing: Text(
                  '+${nf.format(amount)} TZS',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildWithdrawalHistory() {
    if (uid.isEmpty) return const SizedBox.shrink();
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('withdrawals')
          .where('userId', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'Error loading withdrawals',
                  style: TextStyle(color: Colors.red[400]),
                ),
              ),
            ),
          );
        }
        if (!snap.hasData) {
          return LoadingWidget(message: context.tr('loading'));
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text(
                  context.tr('no_withdrawals'),
                  style: TextStyle(color: Colors.grey[500]),
                ),
              ),
            ),
          );
        }
        return Column(
          children: docs.map((doc) {
            final d = doc.data() as Map<String, dynamic>;
            final amount = (d['amount'] as num? ?? 0).toDouble();
            final netAmount = (d['netAmount'] as num? ?? 0).toDouble();
            final phone = d['phone'] as String? ?? '';
            final ts = d['createdAt'] as Timestamp?;
            final date = ts?.toDate() ?? DateTime.now();
            final nf = NumberFormat('#,###', 'en');
            return Card(
              child: ListTile(
                leading: const Icon(Icons.check_circle, color: Colors.green),
                title: Text('${nf.format(netAmount)} TZS → $phone'),
                subtitle: Text(DateFormat('MMM dd, yyyy HH:mm').format(date)),
                trailing: Text(
                  '-${nf.format(amount)} TZS',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}
