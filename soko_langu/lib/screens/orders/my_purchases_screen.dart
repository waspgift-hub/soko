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
  String? _refundingTxId;
  final Set<String> _autoReleased = {};

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

  Future<void> _requestRefund(String txId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('request_refund')),
        content: Text(context.tr('refund_warning')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('cancel'))),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text(context.tr('yes_refund'))),
        ],
      ),
    );
    if (confirmed != true) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _refundingTxId = txId);

    try {
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/escrow/refund'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'orderId': txId, 'userId': user.uid}),
      );

      final result = jsonDecode(resp.body);

      if (resp.statusCode == 200 && result['success'] == true) {
        _showSuccess(result['message'] ?? context.tr('refund_sent'));
      } else {
        _showError(result['error'] ?? context.tr('refund_failed'));
      }
    } catch (e) {
      _showError('${context.tr('refund_failed')}: $e');
    }

    setState(() => _refundingTxId = null);
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
          // Auto-release expired escrow transactions
          for (final doc in docs) {
            final data = doc.data() as Map<String, dynamic>;
            if (data['status'] != 'escrow_hold') continue;
            if (_autoReleased.contains(doc.id)) continue;
            final expiresAt = data['escrowExpiresAt'] as Timestamp?;
            if (expiresAt == null) continue;
            if (DateTime.now().isAfter(expiresAt.toDate())) {
              _autoReleased.add(doc.id);
              _confirmDelivery(doc.id);
            }
          }
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
                  statusColor = cs.tertiary;
                  statusText = context.tr('pending_confirmation');
                  canConfirm = true;
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
                            '${context.tr('phone_label')}${PhoneUtils.formatForDisplay(d['buyerPhone'] as String)}',
                            style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      if (canConfirm)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Row(
                            children: [
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
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _refundingTxId == docs[i].id
                                      ? null
                                      : () => _requestRefund(docs[i].id),
                                  icon: _refundingTxId == docs[i].id
                                      ? const SizedBox(
                                          width: 16, height: 16,
                                          child: GoogleLoading(size: 16, strokeWidth: 2),
                                        )
                                      : const Icon(Icons.money_off, size: 18),
                                  label: Text(
                                    _refundingTxId == docs[i].id
                                        ? context.tr('processing')
                                        : context.tr('not_received_item'),
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
