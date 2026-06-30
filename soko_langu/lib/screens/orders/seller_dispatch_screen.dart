import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import '../../services/api_config.dart';
import '../../extensions/context_tr.dart';
import '../../widgets/google_loading.dart';

class SellerDispatchScreen extends StatefulWidget {
  const SellerDispatchScreen({super.key});

  @override
  State<SellerDispatchScreen> createState() => _SellerDispatchScreenState();
}

class _SellerDispatchScreenState extends State<SellerDispatchScreen> {
  String? _dispatchingTxId;
  final _trackingCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  String? _receiptUrl;
  String? _photoUrl;

  Future<void> _dispatchOrder(String txId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _dispatchingTxId = txId);

    try {
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/escrow/dispatch'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'orderId': txId,
          'userId': user.uid,
          'trackingNumber': _trackingCtrl.text,
          'receiptUrl': _receiptUrl ?? '',
          'photoUrl': _photoUrl ?? '',
          'note': _noteCtrl.text,
        }),
      );

      final result = jsonDecode(resp.body);

      if (resp.statusCode == 200 && result['success'] == true) {
        _trackingCtrl.clear();
        _noteCtrl.clear();
        setState(() { _receiptUrl = null; _photoUrl = null; });
        if (mounted) _showSuccess('Bidhaa imesafirishwa!');
      } else {
        if (mounted) _showError(result['error'] ?? 'Failed to dispatch');
      }
    } catch (e) {
      if (mounted) _showError('Error: $e');
    }

    setState(() => _dispatchingTxId = null);
  }

  @override
  void dispose() {
    _trackingCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Tuma Bidhaa')),
        body: Center(child: Text(context.tr('login_required'))),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Tuma Bidhaa')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('transactions')
            .where('sellerId', isEqualTo: user.uid)
            .where('status', whereIn: ['escrow_hold', 'dispatched'])
            .snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: GoogleLoading());
          }

          final docs = snap.data!.docs
              .where((d) => (d.data() as Map)['status'] == 'escrow_hold')
              .toList();
          docs.sort((a, b) {
            final ta = (a.data() as Map)['createdAt'];
            final tb = (b.data() as Map)['createdAt'];
            if (ta is Timestamp && tb is Timestamp) return tb.compareTo(ta);
            return 0;
          });

          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.inventory_2_outlined, size: 64, color: cs.onSurfaceVariant),
                  const SizedBox(height: 16),
                  Text('Hakuna bidhaa zinazosubiri kusafirishwa',
                      style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (_, i) {
              final d = docs[i].data() as Map<String, dynamic>;
              final txId = docs[i].id;
              final productName = d['productName'] ?? 'Product';
              final price = (d['productPrice'] ?? 0).toDouble();
              final buyerPhone = d['buyerPhone'] ?? '';
              final buyerName = d['buyerName'] ?? '';

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.inventory_2, color: cs.tertiary, size: 20),
                          const SizedBox(width: 8),
                          Text('Inasubiri kusafirishwa',
                              style: TextStyle(color: cs.tertiary, fontWeight: FontWeight.w600, fontSize: 13)),
                          const Spacer(),
                          Text(context.formatPrice(price),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(productName, style: const TextStyle(fontSize: 15)),
                      if (buyerName.isNotEmpty)
                        Text('Mnunuzi: $buyerName',
                            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                      if (buyerPhone.isNotEmpty)
                        Text('Simu: $buyerPhone',
                            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                      const Divider(height: 20),
                      TextField(
                        controller: _trackingCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Namba ya Tracking (si lazima)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _noteCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Maelezo (si lazima)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                // In a real app, this would open image picker
                                setState(() => _receiptUrl = 'https://example.com/receipt.jpg');
                              },
                              icon: Icon(Icons.receipt, size: 18,
                                  color: _receiptUrl != null ? cs.primary : null),
                              label: Text(_receiptUrl != null ? 'Receipt ✓' : 'Pakia Receipt'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                setState(() => _photoUrl = 'https://example.com/photo.jpg');
                              },
                              icon: Icon(Icons.camera_alt, size: 18,
                                  color: _photoUrl != null ? cs.primary : null),
                              label: Text(_photoUrl != null ? 'Photo ✓' : 'Piga Picha'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _dispatchingTxId == txId
                              ? null
                              : () => _dispatchOrder(txId),
                          icon: _dispatchingTxId == txId
                              ? const SizedBox(width: 16, height: 16, child: GoogleLoading(size: 16, strokeWidth: 2))
                              : const Icon(Icons.local_shipping, size: 18),
                          label: Text(_dispatchingTxId == txId
                              ? 'Inasafirisha...'
                              : '✅ Tumia Bidhaa'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: cs.primary,
                            foregroundColor: cs.surface,
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Theme.of(context).colorScheme.error),
    );
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Theme.of(context).colorScheme.primary),
    );
  }
}
