import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../extensions/context_tr.dart';
import '../../services/mongike_service.dart';

class StreamerEarningsScreen extends StatefulWidget {
  const StreamerEarningsScreen({super.key});

  @override
  State<StreamerEarningsScreen> createState() => _StreamerEarningsScreenState();
}

class _StreamerEarningsScreenState extends State<StreamerEarningsScreen> {
  final _phoneController = TextEditingController();
  bool _withdrawing = false;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _withdraw(int amount) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    if (_phoneController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('enter_phone_mpesa'))),
      );
      return;
    }

    setState(() => _withdrawing = true);
    try {
      await MongikeService.initiateWithdrawal(
        userId: uid,
        amount: amount,
        phone: _phoneController.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('withdrawal_success'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${context.tr('error')}: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _withdrawing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('streamer_earnings'))),
      body: SafeArea(
        child: Column(
          children: [
            StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .snapshots(),
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final data = snap.data?.data() as Map<String, dynamic>?;
                final raw = data?['streamerEarnings'] ?? 0;
                final earnings = (raw as num).toInt();
                final totalGifts = (earnings * 100 / 70).round();
                const feeMongike = 2000;
                final netPayout = earnings > feeMongike ? earnings - feeMongike : 0;

                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
                            width: 1.5,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              const Icon(Icons.monetization_on, color: Colors.amber, size: 48),
                              const SizedBox(height: 8),
                              Text(context.tr('total_gifts_earned'), style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                              const SizedBox(height: 4),
                              Text('TZS $totalGifts', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.amber)),
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.3)),
                                ),
                                child: Column(
                                  children: [
                                    _row(context.tr('your_earnings_70'), 'TZS $earnings'),
                                    const Divider(height: 8),
                                    _row(context.tr('mongike_fee'), '− TZS $feeMongike'),
                                    const Divider(height: 16),
                                    _row(context.tr('you_receive'), 'TZS $netPayout', bold: true),
                                    const SizedBox(height: 8),
                                    if (netPayout > 0)
                                      Text(context.tr('withdraw_available'),
                                        style: const TextStyle(fontSize: 11, color: Colors.green),
                                        textAlign: TextAlign.center,
                                      )
                                    else
                                      Text(context.tr('min_withdraw'),
                                        style: const TextStyle(fontSize: 11, color: Colors.orange),
                                        textAlign: TextAlign.center,
                                      ),
                                  ],
                                ),
                              ),
                              if (netPayout > 0) ...[
                                const SizedBox(height: 16),
                                TextField(
                                  controller: _phoneController,
                                  keyboardType: TextInputType.phone,
                                  decoration: InputDecoration(
                                    labelText: context.tr('enter_phone_mpesa'),
                                    border: const OutlineInputBorder(),
                                    prefixIcon: const Icon(Icons.phone),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  height: 48,
                                  child: ElevatedButton.icon(
                                    onPressed: _withdrawing ? null : () => _withdraw(earnings),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                    icon: _withdrawing
                                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                        : const Icon(Icons.send),
                                    label: Text(_withdrawing ? context.tr('processing') : context.tr('withdraw_now')),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('live_gifts')
                    .where('streamerId', isEqualTo: uid)
                    .orderBy('createdAt', descending: true)
                    .snapshots(),
                builder: (ctx, snap) {
                  final gifts = snap.data?.docs ?? [];
                  if (gifts.isEmpty) {
                    return Center(child: Text(context.tr('no_gifts'), style: TextStyle(color: Colors.grey[500])));
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: gifts.length,
                    itemBuilder: (_, i) {
                      final d = gifts[i].data() as Map<String, dynamic>;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: Text(d['giftEmoji'] ?? '🎁', style: const TextStyle(fontSize: 28)),
                          title: Text('${d['fromName'] ?? 'Someone'} sent ${d['giftName'] ?? 'a gift'}'),
                          subtitle: Text('TZS ${d['streamerEarning'] ?? 0} earned'),
                          trailing: Text('x${d['coinCost'] ?? 0} coins', style: const TextStyle(color: Colors.amber)),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
          Text(value, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal, fontSize: 13)),
        ],
      ),
    );
  }
}

