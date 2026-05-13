import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../services/ad_revenue_service.dart';
import '../../services/wallet_service.dart';
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
  int _adViewsToday = 0;
  int _adViewsMonth = 0;

  @override
  void initState() {
    super.initState();
    if (uid.isNotEmpty) {
      _walletService.ensureWallet(uid);
      _loadCounts();
    }
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
                if (snap.hasError) {
                  return Center(
                    child: Text(
                      '${context.tr('error_loading_wallet')} ${snap.error}',
                      style: const TextStyle(color: Colors.red),
                    ),
                  );
                }
                if (!snap.hasData) {
                  return LoadingWidget(message: context.tr('loading'));
                }

                final data = switch (snap.data?.data()) {
                  Map<String, dynamic> m => m,
                  _ => <String, dynamic>{},
                };
                final balance = (data['balance'] as num? ?? 0).toDouble();
                final totalEarnings = (data['totalEarnings'] as num? ?? 0)
                    .toDouble();

                return ListView(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).padding.bottom + 16),
                  children: [
                    _buildBalanceCard(balance, totalEarnings),
                    const SizedBox(height: 16),
                    _buildStatsRow(),
                    const SizedBox(height: 16),
                    _buildSectionTitle(context.tr('recent_transactions')),
                    _buildTransactionsList(),
                  ],
                );
              },
            ),
    );
  }

  Widget _buildBalanceCard(double balance, double totalEarnings) {
    final nf = NumberFormat('#,###', 'en');
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              '${nf.format(balance)} TZS',
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            ),
            Text(
              context.tr('available_balance'),
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
            const SizedBox(height: 8),
            Text(
              '${context.tr('total_earned_label')} ${nf.format(totalEarnings)} TZS',
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
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
            return Card(
              child: ListTile(
                leading: Icon(
                  type == 'ad_share' ? Icons.trending_up : Icons.payment,
                  color: type == 'ad_share' ? Colors.green : Colors.orange,
                ),
                title: Text(desc.isEmpty ? type : desc),
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
      ),
    );
  }
}
