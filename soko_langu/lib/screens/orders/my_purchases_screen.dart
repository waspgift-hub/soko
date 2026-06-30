import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import '../../services/api_config.dart';
import '../../extensions/context_tr.dart';
import '../../widgets/google_loading.dart';
import '../../widgets/ad_banner.dart';
import '../../utils/phone_utils.dart';

class MyPurchasesScreen extends StatefulWidget {
  const MyPurchasesScreen({super.key});

  @override
  State<MyPurchasesScreen> createState() => _MyPurchasesScreenState();
}

class _MyPurchasesScreenState extends State<MyPurchasesScreen> {
  String? _releasingTxId;
  String? _disputingTxId;

  Future<void> _confirmDelivery(String txId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _releasingTxId = txId);

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

    setState(() => _releasingTxId = null);
  }

  Future<void> _raiseDispute(String txId) async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Fungua Mgogoro'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Je, hukupata bidhaa? Eleza sababu na tutakagua.'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(
                labelText: 'Sababu',
                hintText: 'Sijapata mzigo...',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('cancel'))),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Fungua Mgogoro')),
        ],
      ),
    );
    if (confirmed != true) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _disputingTxId = txId);

    try {
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/escrow/dispute'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'orderId': txId,
          'userId': user.uid,
          'reason': reasonCtrl.text,
          'evidenceUrls': [],
        }),
      );

      final result = jsonDecode(resp.body);

      if (resp.statusCode == 200 && result['success'] == true) {
        _showSuccess('Mgogoro umefunguliwa. Admin atakagua.');
      } else {
        _showError(result['error'] ?? 'Failed to raise dispute');
      }
    } catch (e) {
      _showError('Error: $e');
    }

    setState(() => _disputingTxId = null);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
                  Icon(Icons.shopping_bag_outlined, size: 64, color: cs.onSurfaceVariant),
                  const SizedBox(height: 16),
                  Text(
                    context.tr('no_purchases_yet'),
                    style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant),
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
              final dispatchProof = d['dispatchProof'] as Map<String, dynamic>?;

              IconData statusIcon;
              Color statusColor;
              String statusText;
              bool canConfirm = false;
              bool canDispute = false;

              switch (status) {
                case 'escrow_hold':
                  statusIcon = Icons.lock;
                  statusColor = cs.tertiary;
                  statusText = 'Inasubiri muuzaji atume';
                  canDispute = true;
                  break;
                case 'dispatched':
                  statusIcon = Icons.local_shipping;
                  statusColor = Colors.orange;
                  statusText = 'Imesafirishwa — thibitisha upokeaji';
                  canConfirm = true;
                  canDispute = true;
                  break;
                case 'disputed':
                  statusIcon = Icons.gavel;
                  statusColor = Colors.red;
                  statusText = 'Mgogoro — Admin anakagua';
                  break;
                case 'delivery_confirmed':
                  statusIcon = Icons.how_to_vote;
                  statusColor = cs.secondary;
                  statusText = context.tr('confirmed_processing');
                  break;
                case 'delivered':
                  statusIcon = Icons.check_circle;
                  statusColor = cs.primary;
                  statusText = context.tr('completed');
                  break;
                case 'completed':
                  statusIcon = Icons.check_circle;
                  statusColor = cs.primary;
                  statusText = context.tr('completed');
                  break;
                case 'refunded':
                  statusIcon = Icons.money_off;
                  statusColor = cs.error;
                  statusText = context.tr('refunded');
                  break;
                case 'failed':
                  statusIcon = Icons.cancel;
                  statusColor = cs.error;
                  statusText = context.tr('failed');
                  break;
                default:
                  statusIcon = Icons.hourglass_empty;
                  statusColor = cs.onSurfaceVariant.withValues(alpha: 0.6);
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
                          Expanded(
                            child: Text(
                              statusText,
                              style: TextStyle(
                                color: statusColor,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
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
                            '${context.tr('phone_label')}${PhoneUtils.formatForDisplay(d['buyerPhone'] as String)}',
                            style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      if (dispatchProof != null && dispatchProof['dispatchedAt'] != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Tracking: ${dispatchProof['trackingNumber'] ?? '-'}',
                            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                          ),
                        ),
                      if (status == 'escrow_hold')
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Inasubiri muuzaji kusafirisha. Hatua inayofuata: usafirishaji.',
                            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                          ),
                        ),
                      if (canConfirm || canDispute)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Row(
                            children: [
                              if (canConfirm)
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: _releasingTxId == docs[i].id
                                        ? null
                                        : () => _confirmDelivery(docs[i].id),
                                    icon: _releasingTxId == docs[i].id
                                        ? const SizedBox(
                                            width: 16, height: 16,
                                            child: GoogleLoading(size: 16, strokeWidth: 2),
                                          )
                                        : const Icon(Icons.verified, size: 18),
                                    label: Text(
                                      _releasingTxId == docs[i].id
                                          ? context.tr('processing')
                                          : context.tr('confirm_receipt'),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: cs.primary,
                                      foregroundColor: cs.surface,
                                    ),
                                  ),
                                ),
                              if (canConfirm && canDispute) const SizedBox(width: 8),
                              if (canDispute)
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _disputingTxId == docs[i].id
                                        ? null
                                        : () => _raiseDispute(docs[i].id),
                                    icon: _disputingTxId == docs[i].id
                                        ? const SizedBox(
                                            width: 16, height: 16,
                                            child: GoogleLoading(size: 16, strokeWidth: 2),
                                          )
                                        : const Icon(Icons.gavel, size: 18),
                                    label: Text(
                                      _disputingTxId == docs[i].id
                                          ? context.tr('processing')
                                          : 'Sijapata mzigo',
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: cs.error,
                                      side: BorderSide(color: cs.error),
                                    ),
                                  ),
                                ),
                            ],
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
      bottomNavigationBar: const AdBanner(),
    );
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Theme.of(context).colorScheme.error));
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Theme.of(context).colorScheme.primary));
  }
}
