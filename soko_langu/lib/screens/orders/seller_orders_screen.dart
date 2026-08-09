import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import '../../extensions/context_tr.dart';
import '../../services/api_config.dart';
import '../../widgets/google_loading.dart';
import '../../widgets/order_status_config.dart';
import '../../utils/network_error.dart';
import '../../app/routes.dart';
import '../../theme/app_colors.dart';
import '../../widgets/ds/ds.dart';

class SellerOrdersScreen extends StatefulWidget {
  const SellerOrdersScreen({super.key});

  @override
  State<SellerOrdersScreen> createState() => _SellerOrdersScreenState();
}

class _SellerOrdersScreenState extends State<SellerOrdersScreen> {
  String _filter = 'all';
  String? _quotingOrderId;
  String? _dispatchingOrderId;
  Timer? _autoRefreshTimer;
  DateTime? _lastAutoRefresh;

  static const _filters = ['all', 'pending', 'awaiting_shipping_quote', 'awaiting_payment', 'escrow_hold', 'dispatched', 'delivered', 'completed', 'refunded'];

  static const _filterLabels = {
    'all': 'all',
    'pending': 'pending',
    'awaiting_shipping_quote': 'awaiting_shipping_quote_label',
    'awaiting_payment': 'awaiting_payment_label',
    'escrow_hold': 'escrow_hold_label',
    'dispatched': 'dispatched_label',
    'delivered': 'delivered',
    'completed': 'completed',
    'refunded': 'refunded',
  };

  @override
  void initState() {
    super.initState();
    // Poll the live stream every 5s so status changes appear without a manual
    // pull-to-refresh; the StreamBuilder rebuild re-emits the latest snapshots.
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      setState(() => _lastAutoRefresh = DateTime.now());
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
          _buildPendingOrdersSection(cs, user),
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
                  if ((doc.data() as Map)['deletedForSeller'] == true) return false;
                  if (_filter == 'all') return true;
                  final status = (doc.data() as Map)['status'] as String? ?? '';
                  return status == _filter;
                }).toList();

                return RefreshIndicator(
                  onRefresh: () async => setState(() {}),
                  child: CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(child: _buildStatsHeader(cs, snap.data!.docs)),
                      SliverToBoxAdapter(child: _buildFilterBar(cs, snap.data!.docs)),
                      if (docs.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: DsEmptyState(
                              icon: Icons.inbox_outlined,
                              title: context.tr('no_received_orders'),
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (_, i) {
                                final d = docs[i].data() as Map<String, dynamic>;
                                final txId = docs[i].id;
                                return _buildOrderCard(context, cs, d, txId);
                              },
                              childCount: docs.length,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsHeader(ColorScheme cs, List<QueryDocumentSnapshot> allDocs) {
    final visible = allDocs.where((d) => (d.data() as Map)['deletedForSeller'] != true).toList();
    final awaitingQuote = visible.where((d) => (d.data() as Map)['status'] == 'awaiting_shipping_quote').length;
    final needsAction = visible.where((d) {
      final s = (d.data() as Map)['status'] as String? ?? '';
      return s == 'awaiting_shipping_quote' || s == 'awaiting_payment' || s == 'escrow_hold' || s == 'paid_escrow_hold';
    }).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              cs.primary.withValues(alpha: 0.16),
              cs.tertiary.withValues(alpha: 0.06),
            ],
          ),
          border: Border.all(color: cs.primary.withValues(alpha: 0.14)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: cs.successGreen,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: cs.successGreen.withValues(alpha: 0.5), blurRadius: 6),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  context.tr('live_updates'),
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cs.successGreen),
                ),
                const SizedBox(width: 4),
                if (_lastAutoRefresh != null)
                  Text(
                    '· ${context.tr('last_updated')} ${_formatRelative(DateTime.now().difference(_lastAutoRefresh!))}',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _statCell(cs, Icons.rate_review_outlined, '$awaitingQuote', context.tr('awaiting_quotes'), cs.tertiary),
                ),
                Container(width: 1, height: 40, color: cs.primary.withValues(alpha: 0.14)),
                Expanded(
                  child: _statCell(cs, Icons.pending_actions_outlined, '$needsAction', context.tr('needs_action'), cs.trendingOrange),
                ),
                Container(width: 1, height: 40, color: cs.primary.withValues(alpha: 0.14)),
                Expanded(
                  child: _statCell(cs, Icons.receipt_long_outlined, '${visible.length}', context.tr('all_orders'), cs.onSurfaceVariant),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statCell(ColorScheme cs, IconData icon, String value, String label, Color color) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 5),
            Text(value, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: color)),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  String _formatRelative(Duration d) {
    if (d.inSeconds < 10) return context.tr('just_now');
    if (d.inMinutes < 1) return '${d.inSeconds}s';
    return '${d.inMinutes}m';
  }

  Widget _buildFilterBar(ColorScheme cs, List<QueryDocumentSnapshot> allDocs) {
    final visible = allDocs.where((d) => (d.data() as Map)['deletedForSeller'] != true).toList();
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _filters.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final key = _filters[i];
          final selected = _filter == key;
          final count = key == 'all' ? visible.length : visible.where((d) => (d.data() as Map)['status'] == key).length;
          return Center(
            child: DsChip(
              label: '${context.tr(_filterLabels[key]!)} ($count)',
              selected: selected,
              onTap: () => setState(() => _filter = key),
            ),
          );
        },
      ),
    );
  }

  Widget _buildOrderCard(BuildContext context, ColorScheme cs, Map<String, dynamic> d, String txId) {
    final status = d['status'] as String? ?? '';
    final productName = d['productName'] as String? ?? context.tr('product');
    final productImage = d['productImage'] as String? ?? '';
    final buyerName = d['buyerName'] as String? ?? '';
    final buyerId = d['buyerId'] as String? ?? '';
    final productPrice = (d['productPrice'] as num?)?.toDouble() ?? 0;
    final shippingCost = (d['shippingCost'] as num?)?.toDouble();
    final totalAmount = (d['totalAmount'] as num?)?.toDouble() ?? 0;
    final platformFee = (d['platformFee'] as num?)?.toDouble() ?? 0;
    final processingFee = (d['processingFee'] as num?)?.toDouble() ?? 0;
    final createdAt = d['createdAt'] as Timestamp?;
    final dateStr = createdAt != null
        ? DateFormat('dd/MM/yyyy HH:mm').format(createdAt.toDate())
        : '—';
    final statusInfo = orderStatusInfo(status, cs);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DsCard(
        radius: 20,
        padding: EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 4,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [statusInfo.color, statusInfo.color.withValues(alpha: 0.35)],
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
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
                                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: cs.onSurface),
                                    maxLines: 1, overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 3),
                                Text(dateStr,
                                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                              ],
                            ),
                          ),
                          OrderStatusBadge(status: status),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(height: 1, color: cs.primary.withValues(alpha: 0.08)),
                      const SizedBox(height: 10),
                      if (buyerName.isNotEmpty)
                        _infoRow(cs, Icons.person_outline, context.tr('buyer_label'), buyerName),
                      _infoRow(cs, Icons.receipt_outlined, context.tr('order_id'), txId),
                      _infoRow(cs, Icons.monetization_on_outlined, context.tr('product_price'),
                          'TZS ${NumberFormat('#,###').format(productPrice)}'),
                      if (shippingCost != null && shippingCost > 0)
                        _infoRow(cs, Icons.local_shipping_outlined, context.tr('shipping_cost'),
                            'TZS ${NumberFormat('#,###').format(shippingCost)}'),
                      if (platformFee > 0)
                        _infoRow(cs, Icons.percent_outlined, context.tr('soko_vibe_commission'),
                            'TZS ${NumberFormat('#,###').format(platformFee)}'),
                      if (processingFee > 0)
                        _infoRow(cs, Icons.receipt_long_outlined, context.tr('processing_fee'),
                            'TZS ${NumberFormat('#,###').format(processingFee)}'),
                      if (totalAmount > 0)
                        _infoRow(cs, Icons.payments_outlined, context.tr('total_payment'),
                            'TZS ${NumberFormat('#,###').format(totalAmount)}',
                            bold: true),
                      if (status == 'escrow_hold' || status == 'paid_escrow_hold') ...[
                        const SizedBox(height: 12),
                        DsButton(
                          label: context.tr('mark_shipped'),
                          icon: Icons.local_shipping_outlined,
                          height: 44,
                          loading: _dispatchingOrderId == txId,
                          onPressed: _dispatchingOrderId == txId
                              ? null
                              : () => _showDispatchDialog(txId, d),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          if (buyerId.isNotEmpty) ...[
                            Expanded(
                              child: DsButton(
                                label: context.tr('view_profile'),
                                icon: Icons.person_outline,
                                variant: DsButtonVariant.secondary,
                                height: 40,
                                onPressed: () => _viewBuyerProfile(buyerId),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: DsButton(
                              label: context.tr('delete_order'),
                              icon: Icons.delete_outline,
                              variant: DsButtonVariant.danger,
                              height: 40,
                              onPressed: () => _deleteOrder(txId),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
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
      // Soft-delete (flag) instead of a hard delete — the server owns the
      // transactions doc and needs it intact for the orders flow.
      await FirebaseFirestore.instance
          .collection('transactions')
          .doc(txId)
          .update({'deletedForSeller': true});
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

  Widget _buildPendingOrdersSection(ColorScheme cs, User user) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('orders')
          .where('sellerId', isEqualTo: user.uid)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final pending = snap.data!.docs.where((doc) {
          final s = (doc.data() as Map)['status'] as String? ?? '';
          return s == 'pending';
        }).toList();
        if (pending.isEmpty) return const SizedBox.shrink();

        pending.sort((a, b) {
          final ta = (a.data() as Map)['createdAt'];
          final tb = (b.data() as Map)['createdAt'];
          if (ta is Timestamp && tb is Timestamp) return tb.compareTo(ta);
          return 0;
        });

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  Icon(Icons.rate_review_outlined, size: 16, color: cs.tertiary),
                  const SizedBox(width: 6),
                  Text(context.tr('orders_needing_quote'),
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: cs.tertiary)),
                ],
              ),
            ),
            SizedBox(
              height: 132,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: pending.length,
                itemBuilder: (_, i) {
                  final d = pending[i].data() as Map<String, dynamic>;
                  final orderId = pending[i].id;
                  final productName = d['productName'] ?? 'Product';
                  final productImage = d['productImage'] as String? ?? '';
                  final buyerName = d['buyerName'] ?? '';
                  final region = d['region'] as String? ?? '';
                  final district = d['district'] as String? ?? '';

                  return Container(
                    width: 240,
                    margin: const EdgeInsets.only(right: 12),
                    child: DsCard(
                      radius: 16,
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  width: 36, height: 36,
                                  color: cs.surfaceContainerHighest,
                                  child: productImage.isNotEmpty
                                      ? CachedNetworkImage(imageUrl: productImage, fit: BoxFit.cover, width: 36, height: 36)
                                      : Icon(Icons.image, size: 16, color: cs.onSurfaceVariant),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(productName,
                                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: cs.onSurface),
                                    maxLines: 1, overflow: TextOverflow.ellipsis),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          if (buyerName.isNotEmpty)
                            Text('$buyerName', style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
                          if (region.isNotEmpty)
                            Text('$region, $district', style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
                          const Spacer(),
                          SizedBox(
                            width: double.infinity,
                            height: 34,
                            child: DsButton(
                              label: context.tr('place_quote'),
                              icon: Icons.send_rounded,
                              height: 34,
                              loading: _quotingOrderId == orderId,
                              onPressed: _quotingOrderId == orderId ? null : () => _showQuoteDialog(orderId, d),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  Future<void> _showQuoteDialog(String orderId, Map<String, dynamic> orderData) async {
    final shippingCtrl = TextEditingController();
    final busCtrl = TextEditingController();
    final plateCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final confirmed = await DsSheet.show<bool>(
      context: context,
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.tr('enter_shipping_cost'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            DsTextField(
              controller: shippingCtrl,
              label: context.tr('shipping_cost'),
              hint: 'TZS',
              prefixIcon: Icons.monetization_on_outlined,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            DsTextField(
              controller: busCtrl,
              label: context.tr('bus_name'),
              hint: 'Mf: Scandinavia, Kilimanjaro',
              prefixIcon: Icons.directions_bus,
            ),
            const SizedBox(height: 12),
            DsTextField(
              controller: plateCtrl,
              label: context.tr('plate_number'),
              hint: 'Mf: T 123 ABC',
              prefixIcon: Icons.directions_bus_filled_outlined,
            ),
            const SizedBox(height: 24),
            DsButton(
              label: context.tr('send_shipping_to_buyer'),
              icon: Icons.send_rounded,
              onPressed: () {
                final costText = shippingCtrl.text.trim();
                final cost = double.tryParse(costText);
                if (cost == null || cost <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(context.tr('enter_valid_shipping_cost'))),
                  );
                  return;
                }
                Navigator.pop(context, true);
              },
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    final cost = double.tryParse(shippingCtrl.text.trim()) ?? 0;
    if (cost <= 0) return;
    _submitQuote(orderId, orderData, cost, busCtrl.text.trim(), plateCtrl.text.trim());
  }

  Future<void> _submitQuote(String orderId, Map<String, dynamic> orderData, double cost, String busName, String plateNumber) async {
    HapticFeedback.lightImpact();
    setState(() => _quotingOrderId = orderId);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final token = await user.getIdToken();
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/orders/transition'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'orderId': orderId,
          'newStatus': 'quoted',
          'note': jsonEncode({
            'shippingCost': cost,
            'busName': busName,
            'plateNumber': plateNumber,
          }),
        }),
      );
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (resp.statusCode != 200 || data['success'] != true) {
        if (mounted) _showError(data['error'] ?? 'Failed to submit quote');
      } else {
        // Shipping details + status are synced to orders/{id} AND the
        // transactions/{id} mirror doc by the server in one place, so a failed
        // client-side write can't leave the two docs divergent.
        if (mounted) _showSuccess(context.tr('quote_sent_to_buyer'));
      }
    } catch (e) {
      if (mounted) _showError(translateError(e));
    }
    setState(() => _quotingOrderId = null);
  }

  Future<void> _showDispatchDialog(String txId, Map<String, dynamic> d) async {
    final busCtrl = TextEditingController();
    final plateCtrl = TextEditingController();
    final trackCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    final existingCost = (d['shippingCost'] as num?)?.toDouble() ?? 0;
    final costCtrl = TextEditingController(
      text: existingCost > 0 ? existingCost.toStringAsFixed(0) : '',
    );

    final confirmed = await DsSheet.show<bool>(
      context: context,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.tr('dispatch_title'),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          DsTextField(
            controller: busCtrl,
            label: context.tr('bus_name'),
            hint: 'Mf: Scandinavia, Kilimanjaro',
            prefixIcon: Icons.directions_bus,
          ),
          const SizedBox(height: 12),
          DsTextField(
            controller: plateCtrl,
            label: context.tr('plate_number'),
            hint: 'Mf: T 123 ABC',
            prefixIcon: Icons.directions_bus_filled_outlined,
          ),
          const SizedBox(height: 12),
          DsTextField(
            controller: trackCtrl,
            label: context.tr('tracking_number'),
            prefixIcon: Icons.qr_code,
          ),
          const SizedBox(height: 12),
          DsTextField(
            controller: noteCtrl,
            label: context.tr('dispatch_note'),
            prefixIcon: Icons.notes,
          ),
          if (existingCost <= 0) ...[
            const SizedBox(height: 12),
            DsTextField(
              controller: costCtrl,
              label: context.tr('shipping_cost'),
              hint: 'TZS',
              prefixIcon: Icons.monetization_on_outlined,
              keyboardType: TextInputType.number,
            ),
          ],
          const SizedBox(height: 24),
          DsButton(
            label: context.tr('mark_shipped'),
            icon: Icons.local_shipping_outlined,
            onPressed: () {
              if (busCtrl.text.trim().isEmpty || plateCtrl.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(context.tr('dispatch_required_fields'))),
                );
                return;
              }
              Navigator.pop(context, true);
            },
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final parsedCost = existingCost > 0 ? null : double.tryParse(costCtrl.text.trim());
    await _submitDispatch(
      txId,
      busCtrl.text.trim(),
      plateCtrl.text.trim(),
      trackCtrl.text.trim(),
      noteCtrl.text.trim(),
      parsedCost,
    );
  }

  Future<void> _submitDispatch(
    String txId,
    String busName,
    String plateNumber,
    String trackingNumber,
    String note,
    double? cost,
  ) async {
    setState(() => _dispatchingOrderId = txId);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final token = await user.getIdToken();

      // Persist a previously missing delivery cost before dispatching.
      if (cost != null && cost > 0) {
        await FirebaseFirestore.instance
            .collection('transactions')
            .doc(txId)
            .update({'shippingCost': cost});
      }

      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/escrow/dispatch'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'orderId': txId,
          'userId': user.uid,
          'busName': busName,
          'plateNumber': plateNumber,
          'trackingNumber': trackingNumber,
          'note': note,
        }),
      );
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (resp.statusCode != 200 || data['success'] != true) {
        if (mounted) _showError(data['error'] ?? 'Failed to mark shipped');
      } else {
        if (mounted) _showSuccess(context.tr('order_shipped_success'));
      }
    } catch (e) {
      if (mounted) _showError(translateError(e));
    }
    if (mounted) setState(() => _dispatchingOrderId = null);
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

  void _viewBuyerProfile(String buyerId) {
    if (!mounted) return;
    context.push('${AppRoutes.publicProfile}/$buyerId');
  }
}
