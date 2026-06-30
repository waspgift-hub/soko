import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../services/clickpesa_service.dart';
import '../../utils/phone_utils.dart';
import '../../extensions/context_tr.dart';
import '../../widgets/google_loading.dart';

class AdminAdRevenueScreen extends StatefulWidget {
  const AdminAdRevenueScreen({super.key});

  @override
  State<AdminAdRevenueScreen> createState() => _AdminAdRevenueScreenState();
}

class _AdminAdRevenueScreenState extends State<AdminAdRevenueScreen> {
  final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  final _phoneController = TextEditingController();
  bool _withdrawing = false;
  int _totalAdminCoins = 0;
  int _monthAdminCoins = 0;
  int _totalAdsWatched = 0;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadStats() async {
    const tzsPerView = 15;
    final totalAdsSnap = await FirebaseFirestore.instance
        .collection('ad_views')
        .count()
        .get();

    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final monthSnap = await FirebaseFirestore.instance
        .collection('ad_views')
        .where('timestamp', isGreaterThanOrEqualTo: monthStart)
        .count()
        .get();

    if (mounted) {
      setState(() {
        _totalAdsWatched = totalAdsSnap.count ?? 0;
        _totalAdminCoins = _totalAdsWatched * tzsPerView;
        _monthAdminCoins = (monthSnap.count ?? 0) * tzsPerView;
      });
    }
  }

  Future<void> _withdraw() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      _showError(context.tr('enter_phone_withdraw'));
      return;
    }
    final tzsAmount = _monthAdminCoins;
    if (tzsAmount < 2001) {
      _showError(context.tr('withdraw_min_amount'));
      return;
    }

    setState(() => _withdrawing = true);
    try {
                  final result = await ClickPesaService.adminWithdraw(
        userId: uid,
        amount: tzsAmount,
        phone: phone,
      );

      if (mounted) {
        _phoneController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${context.tr('withdrawal_success')} ${result['netAmount']} TZS → $phone'),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
        _loadStats();
      }
    } catch (e) {
      if (mounted) _showError(e.toString());
    } finally {
      if (mounted) setState(() => _withdrawing = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Theme.of(context).colorScheme.error),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nf = NumberFormat('#,###', 'en');
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('ad_revenue')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadStats,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            MediaQuery.of(context).padding.bottom + 16,
          ),
          children: [
            Card(
              elevation: 4,
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Icon(Icons.monetization_on, color: Theme.of(context).colorScheme.primary, size: 48),
                    const SizedBox(height: 8),
                    Text(
                      context.tr('total_earned_label'),
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                    ),
                    Text(
                      '${nf.format(_totalAdminCoins)} TZS',
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    Text(
                      '$_totalAdsWatched ${context.tr('total_ads_watched').toLowerCase()}',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6), fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('this_month'),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('${context.tr('earned')}:', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        Text('${nf.format(_monthAdminCoins)} TZS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Theme.of(context).colorScheme.primary)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '15 coins × ${_monthAdminCoins ~/ 15} ads',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6), fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('withdraw'),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 12),
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
                        onPressed: _monthAdminCoins >= 2001 && !_withdrawing ? _withdraw : null,
                        icon: _withdrawing
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: GoogleLoading(size: 18, strokeWidth: 2, color: Theme.of(context).colorScheme.surface),
                              )
                            : const Icon(Icons.send),
                        label: Text(
                          _withdrawing ? context.tr('withdrawal_processing') : context.tr('withdraw'),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          foregroundColor: Theme.of(context).colorScheme.surface,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                    if (_monthAdminCoins < 2001)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          context.tr('withdraw_min_amount'),
                          style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              context.tr('withdrawal_history'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('admin_withdrawals')
                  .where('userId', isEqualTo: uid)
                  .snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) return const GoogleLoadingPage();
                final docs = snap.data!.docs.toList()
                  ..sort((a, b) {
                    final ta = (a.data() as Map<String, dynamic>)['createdAt'];
                    final tb = (b.data() as Map<String, dynamic>)['createdAt'];
                    if (ta is Timestamp && tb is Timestamp) return tb.compareTo(ta);
                    return 0;
                  });
                if (docs.isEmpty) {
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Text(context.tr('no_withdrawals'), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6))),
                      ),
                    ),
                  );
                }
                return Column(
                  children: docs.map((doc) {
                    final d = doc.data() as Map<String, dynamic>;
                    final amount = (d['amount'] as num? ?? 0).toDouble();
                    final phone = d['phone'] as String? ?? '';
                    final status = d['status'] as String? ?? 'processing';
                    final ts = d['createdAt'] as Timestamp?;
                    final date = ts?.toDate() ?? DateTime.now();
                    final statusColors = {
                      'processing': Theme.of(context).colorScheme.tertiary,
                      'completed': Theme.of(context).colorScheme.primary,
                      'failed': Theme.of(context).colorScheme.error,
                    };
                    return Card(
                      child: ListTile(
                        leading: Icon(Icons.history, color: statusColors[status] ?? Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
                        title: Text('${nf.format(amount)} TZS → ${PhoneUtils.formatForDisplay(phone)}'),
                        subtitle: Text('${DateFormat('MMM dd, yyyy HH:mm').format(date)} • $status'),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
