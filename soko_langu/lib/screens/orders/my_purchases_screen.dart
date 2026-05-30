import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import '../../services/api_config.dart';
import '../../extensions/context_tr.dart';
import '../../widgets/google_loading.dart';

class MyPurchasesScreen extends StatefulWidget {
  const MyPurchasesScreen({super.key});

  @override
  State<MyPurchasesScreen> createState() => _MyPurchasesScreenState();
}

class _MyPurchasesScreenState extends State<MyPurchasesScreen> {
  bool _releasing = false;

  Future<void> _confirmDelivery(String txId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _releasing = true);

    try {
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/escrow/release'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'orderId': txId, 'userId': user.uid}),
      );

      final result = jsonDecode(resp.body);

      if (resp.statusCode == 200 && result['success'] == true) {
        _showSuccess(context.tr('delivery_confirmed_msg'));
      } else {
        _showError(result['error'] ?? context.tr('confirm_failed_msg'));
      }
    } catch (e) {
      _showError('${context.tr('confirm_failed_msg')}: $e');
    }

    setState(() => _releasing = false);
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: Text(context.tr('my_purchases'))),
        body: Center(child: Text(context.tr('login_required'))),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('my_purchases'))),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('transactions')
            .where('buyerId', isEqualTo: user.uid)
            .snapshots(),
        builder: (context, snap) {
          if (snap.hasError || !snap.hasData) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.shopping_bag_outlined, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    context.tr('no_purchases_yet'),
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),
                ],
              ),
            );
          }

          final docs = snap.data!.docs;
          docs.sort((a, b) {
            final ta = (a.data() as Map)['createdAt'];
            final tb = (b.data() as Map)['createdAt'];
            if (ta is Timestamp && tb is Timestamp) return tb.compareTo(ta);
            return 0;
          });
          if (docs.isEmpty) {
            return Center(child: Text(context.tr('no_purchases_yet')));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (_, i) {
              final d = docs[i].data() as Map<String, dynamic>;
              final status = d['status'] as String? ?? 'pending';
              final productName = d['productName'] as String? ?? 'Product';
              final price = (d['productPrice'] ?? 0).toDouble();

              IconData statusIcon;
              Color statusColor;
              String statusText;
              bool canConfirm = false;

              switch (status) {
                case 'escrow_hold':
                  statusIcon = Icons.lock;
                  statusColor = Colors.orange;
                  statusText = context.tr('pending_confirmation');
                  canConfirm = true;
                  break;
                case 'delivery_confirmed':
                  statusIcon = Icons.how_to_vote;
                  statusColor = Colors.blue;
                  statusText = context.tr('confirmed_processing');
                  break;
                case 'delivered':
                  statusIcon = Icons.check_circle;
                  statusColor = Colors.green;
                  statusText = context.tr('completed');
                  break;
                case 'completed':
                  statusIcon = Icons.check_circle;
                  statusColor = Colors.green;
                  statusText = context.tr('completed');
                  break;
                case 'failed':
                  statusIcon = Icons.cancel;
                  statusColor = Colors.red;
                  statusText = context.tr('failed');
                  break;
                default:
                  statusIcon = Icons.hourglass_empty;
                  statusColor = Colors.grey;
                  statusText = context.tr('pending');
              }

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(statusIcon, color: statusColor, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            statusText,
                            style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            context.formatPrice(price.toDouble()),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(productName, style: const TextStyle(fontSize: 15)),
                      if (d['buyerPhone'] != null &&
                          (d['buyerPhone'] as String).isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '${context.tr('phone_label')}${d['buyerPhone']}',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                        ),
                      if (canConfirm)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _releasing
                                  ? null
                                  : () => _confirmDelivery(docs[i].id),
                              icon: _releasing
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: GoogleLoading(
                                        size: 16, strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.verified, size: 18),
                              label: Text(
                                _releasing
                                    ? context.tr('processing')
                                    : context.tr('confirm_receipt'),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green.shade600,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.green));
  }
}
