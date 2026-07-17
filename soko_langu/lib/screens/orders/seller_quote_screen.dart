import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/notification_service.dart';
import '../../widgets/glass_container.dart';
import '../../extensions/context_tr.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/google_loading.dart';

class SellerQuoteScreen extends StatefulWidget {
  const SellerQuoteScreen({super.key});

  @override
  State<SellerQuoteScreen> createState() => _SellerQuoteScreenState();
}

class _SellerQuoteScreenState extends State<SellerQuoteScreen> {
  final _shippingCostCtrl = TextEditingController();
  String? _quotingTxId;

  @override
  void dispose() {
    _shippingCostCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitQuote(String txId, String buyerId, String productName) async {
    final costText = _shippingCostCtrl.text.trim();
    final cost = double.tryParse(costText);
    if (cost == null || cost <= 0) {
      _showError('Tafadhali ingiza gharama sahihi ya usafirishaji');
      return;
    }

    setState(() => _quotingTxId = txId);

    try {
      await FirebaseFirestore.instance.collection('transactions').doc(txId).update({
        'shippingCost': cost,
        'totalAmount': FieldValue.increment(cost),
        'status': 'awaiting_payment',
      });

      NotificationService().sendNotification(
        userId: buyerId,
        title: 'Gharama ya Usafirishaji Imewekwa!',
        body: 'Muuzaji ameweka gharama ya usafirishaji TZS ${cost.toStringAsFixed(0)}. Lipa sasa.',
        data: {'type': 'shipping_quote', 'transactionId': txId},
      );

      _shippingCostCtrl.clear();
      if (mounted) _showSuccess('Gharama ya usafirishaji imetumwa kwa mnunuzi');
    } catch (e) {
      if (mounted) _showError('Hitilafu: $e');
    }

    setState(() => _quotingTxId = null);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Gharama ya Usafirishaji')),
        body: Center(child: Text(context.tr('login_required'))),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gharama ya Usafirishaji'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('transactions')
            .where('sellerId', isEqualTo: user.uid)
            .where('status', isEqualTo: 'awaiting_shipping_quote')
            .snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: GoogleLoading());
          }

          final docs = snap.data!.docs;
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
                  Icon(Icons.inbox_outlined, size: 72, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
                  const SizedBox(height: 16),
                  Text('Hakuna ombi la gharama ya usafirishaji',
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
              final productPrice = (d['productPrice'] as num?)?.toDouble() ?? 0;
              final buyerName = d['buyerName'] ?? '';
              final buyerId = d['buyerId'] ?? '';
              final addr = d['deliveryAddress'] as Map<String, dynamic>?;

              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: GlassContainer(
                  blur: 24,
                  opacity: isDark ? 0.1 : 0.06,
                  borderRadius: 22,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: cs.tertiary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.receipt_long, size: 14, color: cs.tertiary),
                                const SizedBox(width: 6),
                                Text('Ombi Mpya', style: TextStyle(fontSize: 12, color: cs.tertiary, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(productName, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: cs.onSurface)),
                      const SizedBox(height: 6),
                      _detailRow(cs, 'Mnunuzi', buyerName),
                      _detailRow(cs, 'Bei ya Bidhaa', context.formatPrice(productPrice)),
                      if (addr != null)
                        _detailRow(cs, 'Anwani', '${addr['region'] ?? ''}, ${addr['district'] ?? ''}, ${addr['street'] ?? ''}'),
                      if (addr?['landmarks'] != null)
                        _detailRow(cs, 'Alama', addr!['landmarks'] as String? ?? ''),

                      const SizedBox(height: 16),
                      Container(height: 1, color: cs.primary.withValues(alpha: 0.1)),
                      const SizedBox(height: 16),

                      Text('Weka Gharama ya Usafirishaji',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: cs.onSurface)),
                      const SizedBox(height: 12),

                      TextField(
                        controller: _shippingCostCtrl,
                        keyboardType: TextInputType.number,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: cs.onSurface),
                        decoration: InputDecoration(
                          prefixText: 'TZS ',
                          prefixStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: cs.primary),
                          hintText: '0',
                          filled: true,
                          fillColor: cs.surface.withValues(alpha: 0.3),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: cs.primary, width: 1.5),
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: _quotingTxId == txId
                              ? null
                              : () => _submitQuote(txId, buyerId, productName),
                          icon: _quotingTxId == txId
                              ? const GoogleLoading(size: 20, strokeWidth: 2)
                              : const Icon(Icons.send_rounded, size: 20),
                          label: Text(_quotingTxId == txId ? 'Inatuma...' : 'Tuma Gharama kwa Mnunuzi',
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: cs.primary,
                            foregroundColor: cs.surface,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 0,
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

  Widget _detailRow(ColorScheme cs, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text('$label: ', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
          Expanded(child: Text(value, style: TextStyle(fontSize: 13, color: cs.onSurface, fontWeight: FontWeight.w500))),
        ],
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
