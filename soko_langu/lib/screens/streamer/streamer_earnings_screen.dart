import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../services/mongike_service.dart';
import '../../extensions/context_tr.dart';

class StreamerEarningsScreen extends StatefulWidget {
  const StreamerEarningsScreen({super.key});

  @override
  State<StreamerEarningsScreen> createState() => _StreamerEarningsScreenState();
}

class _StreamerEarningsScreenState extends State<StreamerEarningsScreen> {
  final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  final _phoneController = TextEditingController();
  bool _withdrawing = false;
  int _totalEarnings = 0;
  int _totalGifts = 0;

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
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    final total = (userDoc.data()?['streamerEarnings'] ?? 0) as int;

    final giftsSnap = await FirebaseFirestore.instance
        .collection('live_gifts')
        .where('streamerId', isEqualTo: uid)
        .count()
        .get();

    if (mounted) {
      setState(() {
        _totalEarnings = total;
        _totalGifts = giftsSnap.count ?? 0;
      });
    }
  }

  Future<void> _withdraw() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      _showError(context.tr('enter_phone_withdraw'));
      return;
    }
    if (_totalEarnings < 4000) {
      _showError(context.tr('min_payout'));
      return;
    }

    setState(() => _withdrawing = true);
    try {
      final result = await MongikeService.streamerWithdraw(
        userId: uid,
        amount: _totalEarnings,
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
    final now = DateTime.now();
    final daysLeft = DateTime(now.year, now.month + 1, 0).day - now.day;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('streamer_earnings')),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadStats),
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
              color: Colors.amber[50],
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Icon(Icons.card_giftcard, color: Colors.amber, size: 48),
                    const SizedBox(height: 8),
                    Text(
                      context.tr('total_gifts_earned'),
                      style: TextStyle(color: Colors.grey[600], fontSize: 13),
                    ),
                    Text(
                      '${nf.format(_totalEarnings)} TZS',
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: Colors.amber,
                      ),
                    ),
                    Text(
                      '$_totalGifts ${context.tr('sent_gift').toLowerCase()}',
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
                  children: [
                    _infoRow(context.tr('your_earnings_70'), '${nf.format(_totalEarnings)} TZS', Colors.green),
                    const Divider(),
                    _infoRow(context.tr('next_payout'), '$daysLeft ${context.tr('days')}', Colors.blue),
                    const Divider(),
                    _infoRow(context.tr('min_payout'), 'TZS 4,000', Colors.orange),
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
                        hintText: context.tr('enter_phone_withdraw'),
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.phone_android),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _totalEarnings >= 4000 && !_withdrawing ? _withdraw : null,
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
                    if (_totalEarnings < 4000)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          context.tr('min_payout'),
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
                  .collection('streamer_withdrawals')
                  .where('userId', isEqualTo: uid)
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
                    final netAmount = (d['netAmount'] as num? ?? 0).toDouble();
                    final fee = (d['fee'] as num? ?? 0).toDouble();
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
                        title: Text('${nf.format(netAmount)} TZS → $phone'),
                        subtitle: Text(
                          '${DateFormat('MMM dd, yyyy HH:mm').format(date)} • $status\n'
                          'Jumla: ${nf.format(amount)} - Ada: ${nf.format(fee)}',
                        ),
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

  Widget _infoRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 14)),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: color)),
        ],
      ),
    );
  }
}
