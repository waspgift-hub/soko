import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../services/mongike_service.dart';
import '../../extensions/context_tr.dart';

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
    final adminSnap = await FirebaseFirestore.instance
        .collection('admin_ad_revenue')
        .count()
        .get();
    final totalCoins = adminSnap.count ?? 0;

    final now = DateTime.now();
    final monthSnap = await FirebaseFirestore.instance
        .collection('admin_ad_revenue')
        .where('payoutMonth', isEqualTo: '${now.month}_${now.year}')
        .count()
        .get();

    final totalAdsSnap = await FirebaseFirestore.instance
        .collection('viewer_ad_views')
        .count()
        .get();

    if (mounted) {
      setState(() {
        _totalAdminCoins = totalCoins * 15;
        _monthAdminCoins = monthSnap.count! * 15;
        _totalAdsWatched = totalAdsSnap.count ?? 0;
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
      final result = await MongikeService.adminWithdraw(
        userId: uid,
        amount: tzsAmount,
        phone: phone,
      );

      if (result == null) throw Exception('Withdrawal failed');

      if (mounted) {
        _phoneController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${context.tr('withdrawal_success')} ${result['netAmount']} TZS → $phone'),
            backgroundColor: const Color(0xFF2D6A4F),
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
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
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
              color: const Color(0xFF2D6A4F).withValues(alpha: 0.1),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Icon(Icons.monetization_on, color: Color(0xFF2D6A4F), size: 48),
                    const SizedBox(height: 8),
                    Text(
                      context.tr('total_earned_label'),
                      style: TextStyle(color: Colors.grey[600], fontSize: 13),
                    ),
                    Text(
                      '${nf.format(_totalAdminCoins)} TZS',
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2D6A4F),
                      ),
                    ),
                    Text(
                      '$_totalAdsWatched ${context.tr('total_ads_watched').toLowerCase()}',
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
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
                        Text('${context.tr('earned')}:', style: TextStyle(color: Colors.grey[600])),
                        Text('${nf.format(_monthAdminCoins)} TZS', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.green)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '15 coins × ${_monthAdminCoins ~/ 15} ads',
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
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
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.send),
                        label: Text(
                          _withdrawing ? context.tr('withdrawal_processing') : context.tr('withdraw'),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2D6A4F),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                    if (_monthAdminCoins < 2001)
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
            ),
            const SizedBox(height: 16),
            Text(
              context.tr('withdrawal_history'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .collection('admin_withdrawals')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Text(context.tr('no_withdrawals'), style: TextStyle(color: Colors.grey[500])),
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
                      'processing': Colors.orange,
                      'completed': Colors.green,
                      'failed': Colors.red,
                    };
                    return Card(
                      child: ListTile(
                        leading: Icon(Icons.history, color: statusColors[status] ?? Colors.grey),
                        title: Text('${nf.format(amount)} TZS → $phone'),
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
