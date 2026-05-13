import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../extensions/context_tr.dart';

class StreamerEarningsScreen extends StatelessWidget {
  const StreamerEarningsScreen({super.key});

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
                final raw =
                    (snap.data?.data()
                        as Map<String, dynamic>?)?['streamerEarnings'] ??
                    0;
                final earnings = (raw as num).toInt();
                final totalGifts = (earnings * 100 / 70).round();
                const feePlatform = 2000;
                const feeMongike = 2000;
                const feeTotal = feePlatform + feeMongike;
                final netPayout = earnings > feeTotal ? earnings - feeTotal : 0;

                final now = DateTime.now();
                final nextMonth = DateTime(now.year, now.month + 1, 1);
                final daysLeft = nextMonth.difference(now).inDays;

                return Card(
                  color: Colors.amber[50],
                  margin: const EdgeInsets.all(16),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.monetization_on,
                          color: Colors.amber,
                          size: 48,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          context.tr('total_gifts_earned'),
                          style: TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'TZS $totalGifts',
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.amber,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.amber[200]!),
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    context.tr('next_payout'),
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    '$daysLeft days',
                                    style: const TextStyle(color: Colors.amber),
                                  ),
                                ],
                              ),
                              const Divider(height: 16),
                              _row(
                                context.tr('your_earnings_70'),
                                'TZS $earnings',
                              ),
                              const Divider(height: 8),
                              _row(
                                context.tr('platform_fee'),
                                '− TZS $feePlatform',
                              ),
                              _row(
                                context.tr('mongike_fee'),
                                '− TZS $feeMongike',
                              ),
                              const Divider(height: 16),
                              _row(
                                context.tr('you_receive'),
                                'TZS $netPayout',
                                bold: true,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                earnings > feeTotal
                                    ? context.tr('payout_end_month')
                                    : context.tr('min_payout'),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: earnings > feeTotal
                                      ? Colors.green
                                      : Colors.orange[700],
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
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
                    return Center(
                      child: Text(
                        context.tr('no_gifts'),
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: gifts.length,
                    itemBuilder: (_, i) {
                      final d = gifts[i].data() as Map<String, dynamic>;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: Text(
                            d['giftEmoji'] ?? '🎁',
                            style: const TextStyle(fontSize: 28),
                          ),
                          title: Text(
                            '${d['fromName'] ?? 'Someone'} sent ${d['giftName'] ?? 'a gift'}',
                          ),
                          subtitle: Text(
                            'TZS ${d['streamerEarning'] ?? 0} earned',
                          ),
                          trailing: Text(
                            'x${d['coinCost'] ?? 0} coins',
                            style: const TextStyle(color: Colors.amber),
                          ),
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
          Text(
            value,
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
