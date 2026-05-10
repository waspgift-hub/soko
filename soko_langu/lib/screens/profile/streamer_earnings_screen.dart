import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class StreamerEarningsScreen extends StatelessWidget {
  const StreamerEarningsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('Streamer Earnings')),
      body: Column(
        children: [
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(uid)
                .snapshots(),
            builder: (ctx, snap) {
              final earnings =
                  (snap.data?.data()
                      as Map<String, dynamic>?)?['streamerEarnings'] ??
                  0;
              final netPayout = (earnings as int) > 4000 ? earnings - 4000 : 0;

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
                      const Text(
                        'Total Gifts Earned',
                        style: TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'TZS $earnings',
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
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Next Payout',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  '$daysLeft days',
                                  style: const TextStyle(color: Colors.amber),
                                ),
                              ],
                            ),
                            const Divider(height: 16),
                            _row('Your Earnings', 'TZS $earnings'),
                            _row('Platform Fee (TZS 2,000)', '− TZS 2,000'),
                            _row('Mongike Fee (TZS 2,000)', '− TZS 2,000'),
                            const Divider(height: 16),
                            _row('You Receive', 'TZS $netPayout', bold: true),
                            const SizedBox(height: 8),
                            Text(
                              earnings > 4000
                                  ? 'Payout processed at end of month'
                                  : 'Minimum TZS 4,000 required for payout',
                              style: TextStyle(
                                fontSize: 11,
                                color: earnings > 4000
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
                      'No gifts received yet',
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
