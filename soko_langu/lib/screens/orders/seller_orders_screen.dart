import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../theme/app_colors.dart';
import '../../extensions/context_tr.dart';
import '../../widgets/google_loading.dart';
import '../../widgets/glass_container.dart';
import '../../utils/network_error.dart';

class SellerOrdersScreen extends StatefulWidget {
  const SellerOrdersScreen({super.key});

  @override
  State<SellerOrdersScreen> createState() => _SellerOrdersScreenState();
}

class _SellerOrdersScreenState extends State<SellerOrdersScreen> {
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: Text(context.tr('received_orders'))),
        body: Center(child: Text(context.tr('login_required'))),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('received_orders')),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        children: [
          _buildFilterBar(cs, isDark),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('transactions')
                  .where('sellerId', isEqualTo: user.uid)
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text('${context.tr('error')}: ${snap.error}'),
                    ),
                  );
                }
                if (!snap.hasData) {
                  return const Center(child: GoogleLoading());
                }

                var docs = snap.data!.docs.where((doc) {
                  if (_filter == 'all') return true;
                  final status = (doc.data() as Map)['status'] as String? ?? '';
                  return status == _filter;
                }).toList();

                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.inbox_outlined, size: 72,
                            color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
                        const SizedBox(height: 16),
                        Text(context.tr('no_received_orders'),
                            style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant)),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  itemCount: docs.length,
                  itemBuilder: (_, i) {
                    final d = docs[i].data() as Map<String, dynamic>;
                    final txId = docs[i].id;
                    final status = d['status'] as String? ?? '';
                    final productName = d['productName'] as String? ?? context.tr('product');
                    final productImage = d['productImage'] as String? ?? '';
                    final buyerName = d['buyerName'] as String? ?? '';
                    final buyerId = d['buyerId'] as String? ?? '';
                    final productPrice = (d['productPrice'] as num?)?.toDouble() ?? 0;
                    final shippingCost = (d['shippingCost'] as num?)?.toDouble();
                    final totalAmount = (d['totalAmount'] as num?)?.toDouble() ?? 0;
                    final createdAt = d['createdAt'] as Timestamp?;
                    final dateStr = createdAt != null
                        ? DateFormat('dd/MM/yyyy HH:mm').format(createdAt.toDate())
                        : '—';

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: GlassContainer(
                        blur: 24,
                        opacity: isDark ? 0.1 : 0.06,
                        borderRadius: 20,
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    width: 48, height: 48,
                                    color: cs.surfaceContainerHighest,
                                    child: productImage.isNotEmpty
                                        ? CachedNetworkImage(imageUrl: productImage, fit: BoxFit.cover, width: 48, height: 48)
                                        : Icon(Icons.image, size: 20, color: cs.onSurfaceVariant),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(productName,
                                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: cs.onSurface),
                                          maxLines: 1, overflow: TextOverflow.ellipsis),
                                      const SizedBox(height: 2),
                                      Text(dateStr,
                                          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                                    ],
                                  ),
                                ),
                                _statusChip(cs, status),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Container(height: 1, color: cs.primary.withValues(alpha: 0.08)),
                            const SizedBox(height: 10),
                            if (buyerName.isNotEmpty)
                              _infoRow(cs, Icons.person, context.tr('buyer_label'), buyerName),
                            _infoRow(cs, Icons.receipt, context.tr('order_id'), txId),
                            _infoRow(cs, Icons.monetization_on, context.tr('product_price'),
                                'TZS ${NumberFormat('#,###').format(productPrice)}'),
                            if (shippingCost != null && shippingCost > 0)
                              _infoRow(cs, Icons.local_shipping, context.tr('shipping_cost'),
                                  'TZS ${NumberFormat('#,###').format(shippingCost)}'),
                            if (totalAmount > 0)
                              _infoRow(cs, Icons.payments, context.tr('total_payment'),
                                  'TZS ${NumberFormat('#,###').format(totalAmount)}',
                                  bold: true),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                if (buyerId.isNotEmpty)
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () => _viewBuyerProfile(buyerId),
                                      icon: const Icon(Icons.person, size: 16),
                                      label: Text(context.tr('view_profile'),
                                          style: const TextStyle(fontSize: 13)),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: cs.primary,
                                        side: BorderSide(color: cs.primary.withValues(alpha: 0.3)),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        padding: const EdgeInsets.symmetric(vertical: 8),
                                      ),
                                    ),
                                  ),
                                if (buyerId.isNotEmpty) const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => _deleteOrder(txId),
                                    icon: const Icon(Icons.delete_outline, size: 16),
                                    label: Text(context.tr('delete_order'),
                                        style: const TextStyle(fontSize: 13)),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: cs.error,
                                      side: BorderSide(color: cs.error.withValues(alpha: 0.3)),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
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

  Widget _buildFilterBar(ColorScheme cs, bool isDark) {
    final filters = ['all', 'pending', 'awaiting_shipping_quote', 'awaiting_payment', 'escrow_hold', 'dispatched', 'delivered', 'completed', 'refunded'];
    final labels = {
      'all': context.tr('all'),
      'pending': context.tr('pending'),
      'awaiting_shipping_quote': context.tr('awaiting_shipping_quote_label'),
      'awaiting_payment': context.tr('awaiting_payment_label'),
      'escrow_hold': 'Escrow Hold',
      'paid_escrow_held': 'Escrow Hold',
      'dispatched': context.tr('dispatched_label'),
      'delivered': context.tr('delivered'),
      'completed': context.tr('completed'),
      'refunded': context.tr('refunded'),
    };

    return Container(
      height: 48,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final key = filters[i];
          final selected = _filter == key;
          return GestureDetector(
            onTap: () => setState(() => _filter = key),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: selected ? cs.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: selected ? cs.primary : cs.primary.withValues(alpha: 0.3)),
              ),
              child: Center(
                child: Text(
                  labels[key] ?? key,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? cs.surface : cs.onSurface,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _statusChip(ColorScheme cs, String status) {
    Color chipColor;
    switch (status) {
      case 'awaiting_shipping_quote':
      case 'awaiting_payment':
        chipColor = cs.tertiary;
        break;
      case 'escrow_hold':
      case 'paid_escrow_held':
        chipColor = Colors.orange;
        break;
      case 'dispatched':
        chipColor = Colors.blue;
        break;
      case 'delivered':
      case 'completed':
        chipColor = cs.successGreen;
        break;
      case 'refunded':
      case 'cancelled':
        chipColor = cs.error;
        break;
      default:
        chipColor = cs.onSurfaceVariant;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: chipColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(status.replaceAll('_', ' '),
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: chipColor)),
    );
  }

  Widget _infoRow(ColorScheme cs, IconData icon, String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Text('$label: ', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
          Expanded(
            child: Text(value,
                style: TextStyle(fontSize: 13, color: cs.onSurface, fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteOrder(String txId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('delete_product')),
        content: Text(context.tr('delete_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('cancel'))),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr('delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await FirebaseFirestore.instance.collection('transactions').doc(txId).delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('product_deleted'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${context.tr('error')}: ${translateError(e)}')),
        );
      }
    }
  }

  void _viewBuyerProfile(String buyerId) {
    // Navigate to the buyer's public profile
    // The route is '/public-profile' with buyerId as extra or path param
    try {
      // Use go_router if available
      final router = Router.of(context);
      // We'll just show a snackbar for now since public profile navigation differs
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Buyer ID: $buyerId')),
      );
    } catch (_) {}
  }
}
