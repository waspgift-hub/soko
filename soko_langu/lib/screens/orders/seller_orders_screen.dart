import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../widgets/product_cached_image.dart';
import 'package:go_router/go_router.dart';
import '../../extensions/context_tr.dart';
import '../../widgets/soko_vibe_states.dart';
import '../../widgets/order_status_config.dart';
import '../../models/order_statuses.dart';
import '../../app/routes.dart';
import '../../theme/app_colors.dart';
import '../../widgets/ds/ds.dart';
import '../../widgets/animations/soko_animated_art.dart';

class SellerOrdersScreen extends StatefulWidget {
  const SellerOrdersScreen({super.key});

  @override
  State<SellerOrdersScreen> createState() => _SellerOrdersScreenState();
}

class _SellerOrdersScreenState extends State<SellerOrdersScreen> {
  String _filter = 'all';
  int _refreshKey = 0;
  Timer? _autoRefreshTimer;
  DateTime? _lastAutoRefresh;
  Timer? _ticker;
  int _now = DateTime.now().millisecondsSinceEpoch;

  static const _filters = [
    'all',
    'pending',
    'awaiting_shipping_quote',
    'awaiting_payment',
    'escrow_hold',
    'dispatched',
    'delivered',
    'completed',
    'refunded',
    'expired',
    'in_transit',
    'inspection_period',
    'disputed',
  ];

  static const _filterLabels = {
    'all': 'all',
    'pending': 'pending',
    'awaiting_shipping_quote': 'awaiting_shipping_quote_label',
    'awaiting_payment': 'awaiting_payment_label',
    'escrow_hold': 'in_escrow_label',
    'dispatched': 'dispatched_label',
    'delivered': 'delivered',
    'completed': 'completed',
    'refunded': 'refunded',
    'expired': 'expired',
    'in_transit': 'in_transit_label',
    'inspection_period': 'inspection_period_label',
    'disputed': 'disputed_label',
  };

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now().millisecondsSinceEpoch);
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _ticker?.cancel();
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
              key: ValueKey('seller_orders_$_refreshKey'),
              stream: FirebaseFirestore.instance
                  .collection('transactions')
                  .where('sellerId', isEqualTo: user.uid)
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return SokoVibeErrorState(
                    message: context.trError(snap.error),
                    onRetry: () => setState(() => _refreshKey++),
                  );
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                try {
                  return _buildOrderList(cs, snap.data!.docs);
                } catch (e) {
                  // One malformed document must not blank the whole screen.
                  return SokoVibeErrorState(
                    message: context.trError(e),
                    onRetry: () => setState(() => _refreshKey++),
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderList(ColorScheme cs, List<QueryDocumentSnapshot> docs) {
    final visible = docs.where((doc) {
      if ((doc.data() as Map)['deletedForSeller'] == true) return false;
      if (_filter == 'all') return true;
      final status = (doc.data() as Map)['status'] as String? ?? '';
      return status == _filter;
    }).toList();

    return RefreshIndicator(
      onRefresh: () async => setState(() {}),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _buildStatsHeader(cs, docs)),
          SliverToBoxAdapter(child: _buildFilterBar(cs, docs)),
          if (visible.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: DsEmptyState(
                  icon: Icons.inbox_outlined,
                  artwork: const EmptyOrdersArt(),
                  title: context.tr('no_received_orders'),
                  centered: false,
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) {
                    final d = visible[i].data() as Map<String, dynamic>;
                    final txId = visible[i].id;
                    return _buildOrderCard(context, cs, d, txId);
                  },
                  childCount: visible.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatsHeader(ColorScheme cs, List<QueryDocumentSnapshot> allDocs) {
    final visible = allDocs.where((d) => (d.data() as Map)['deletedForSeller'] != true).toList();
    final awaitingQuote = visible.where((d) {
      final s = (d.data() as Map)['status'] as String? ?? '';
      return const {
        OrderStatus.awaitingShippingQuote,
        OrderStatus.pendingShippingFee,
        OrderStatus.shippingFeeSubmitted,
        OrderStatus.shippingFeeReview,
      }.contains(s);
    }).length;
    final needsAction = visible.where((d) {
      final s = (d.data() as Map)['status'] as String? ?? '';
      return const {
        OrderStatus.awaitingShippingQuote,
        OrderStatus.pendingShippingFee,
        OrderStatus.awaitingPayment,
        OrderStatus.awaitingEscrowPayment,
        OrderStatus.paymentPending,
        OrderStatus.escrowHold,
        OrderStatus.paidEscrowHold,
        OrderStatus.readyToDispatch,
        OrderStatus.inEscrow,
        OrderStatus.disputed,
      }.contains(s);
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
                                  ? ProductCachedImage(url: productImage, width: 48, height: 48, fit: BoxFit.cover)
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
                      if (_sellerDisputeInfo(d) != null) ...[
                        _buildSellerDisputeBanner(cs, d),
                        const SizedBox(height: 10),
                      ],
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
                      _buildSellerTimers(cs, d),
                      if (_sellerShippingQuote(d) != null) ...[
                        const SizedBox(height: 6),
                        _buildSellerVerdictChip(cs, d),
                      ],
                      if (status == 'escrow_hold' ||
                          status == 'paid_escrow_hold' ||
                          status == 'in_escrow' ||
                          status == 'ready_to_dispatch') ...[
                        const SizedBox(height: 12),
                        DsButton(
                          label: context.tr('mark_shipped'),
                          icon: Icons.local_shipping_outlined,
                          height: 44,
                          onPressed: () => context.push(AppRoutes.sellerDispatch),
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
                          if (status == 'delivered' ||
                              status == 'completed' ||
                              status == 'delivery_confirmed' ||
                              status == 'confirmed' ||
                              const {
                                OrderStatus.walletCredited,
                                OrderStatus.payoutPending,
                                OrderStatus.payoutComplete,
                              }.contains(status)) ...[
                            Expanded(
                              child: DsButton(
                                label: context.tr('view_receipt'),
                                icon: Icons.receipt_long_outlined,
                                variant: DsButtonVariant.secondary,
                                height: 40,
                                onPressed: () =>
                                    context.push('${AppRoutes.receipt}/$txId'),
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

  Map<String, dynamic>? _sellerShippingQuote(Map<String, dynamic> d) {
    final q = d['shippingQuote'];
    if (q is Map<String, dynamic>) return q;
    if (q is Map) return Map<String, dynamic>.from(q);
    return null;
  }

  Map<String, dynamic>? _sellerDisputeInfo(Map<String, dynamic> d) {
    final di = d['disputeInfo'];
    if (di is Map<String, dynamic>) return di;
    if (di is Map) return Map<String, dynamic>.from(di);
    return null;
  }

  DateTime? _asDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  String _msLeft(DateTime? deadline) {
    if (deadline == null) return '';
    final diff = deadline.difference(DateTime.fromMillisecondsSinceEpoch(_now));
    if (diff.isNegative) return '00:00:00';
    String two(int n) => n.toString().padLeft(2, '0');
    if (diff.inDays >= 1) {
      return '${diff.inDays}d ${two(diff.inHours % 24)}:${two(diff.inMinutes % 60)}:${two(diff.inSeconds % 60)}';
    }
    return '${two(diff.inHours)}:${two(diff.inMinutes % 60)}:${two(diff.inSeconds % 60)}';
  }

  /// Live countdowns the seller cares about: when escrow auto-releases to them
  /// (48h after dispatch) and how long the buyer has left to inspect.
  Widget _buildSellerTimers(ColorScheme cs, Map<String, dynamic> d) {
    final status = d['status'] as String? ?? '';
    final inTransit = const {
      'dispatched', 'in_transit', 'out_for_delivery', 'delivery_attempted',
    }.contains(status);
    final inspecting = const {
      'delivered', 'inspection_period', 'otp_pending',
    }.contains(status);
    final autoDead = inTransit
        ? (_asDate(d['autoReleaseDeadline']) ??
            (_asDate(d['dispatchedAt'])?.add(const Duration(hours: 48))))
        : null;
    final inspectDead = inspecting ? _asDate(d['inspectionDeadline']) : null;
    if (autoDead == null && inspectDead == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          if (autoDead != null)
            _timerChip(cs, Icons.timer_outlined,
                '${context.tr('auto_release_countdown_hint')}  ${_msLeft(autoDead)}'),
          if (inspectDead != null)
            _timerChip(cs, Icons.access_time_filled,
                '${context.tr('inspection_deadline_hint')}  ${_msLeft(inspectDead)}'),
        ],
      ),
    );
  }

  Widget _timerChip(ColorScheme cs, IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: cs.primary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(text,
                style: TextStyle(fontSize: 11.5, color: cs.onSurface),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  /// Same shipping-quote verdict the buyer sees, on the seller side too.
  Widget _buildSellerVerdictChip(ColorScheme cs, Map<String, dynamic> d) {
    final q = _sellerShippingQuote(d)!;
    final verdict = (q['verdict'] as String? ?? 'NORMAL').toUpperCase();
    final reason = q['reason']?.toString() ?? '';
    final tier = q['distanceTier']?.toString() ?? '';
    final (icon, color, label) = switch (verdict) {
      'BLOCKED' => (
          Icons.block,
          cs.error,
          context.tr('verdict_blocked'),
        ),
      'REVIEW_REQUIRED' => (
          Icons.warning_amber_rounded,
          cs.brandWarning,
          context.tr('verdict_review_required'),
        ),
      _ => (
          Icons.check_circle_outline,
          cs.successGreen,
          context.tr('verdict_normal'),
        ),
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                tier.isNotEmpty && reason.isNotEmpty && verdict != 'NORMAL'
                    ? '$label • $tier • $reason'
                    : label,
                style: TextStyle(
                    fontSize: 11.5,
                    color: color,
                    fontWeight: FontWeight.w700,
                    height: 1.2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Compact open-case banner for the seller: what the buyer claimed, how many
  /// photos, and the resolution status once an admin decides.
  Widget _buildSellerDisputeBanner(ColorScheme cs, Map<String, dynamic> d) {
    final info = _sellerDisputeInfo(d)!;
    final resolved = info['resolved'] == true;
    final resolution = info['resolution']?.toString() ?? 'released_to_seller';
    final reason = info['reason']?.toString() ?? '';
    final evidenceCount = info['evidenceUrls'] is List
        ? (info['evidenceUrls'] as List).length
        : 0;
    final color = resolved ? cs.successGreen : cs.error;
    final title = resolved
        ? context.tr('dispute_resolution_label') +
            (resolution == 'refunded_to_buyer'
                ? context.tr('dispute_refunded')
                : context.tr('dispute_released'))
        : context.tr('dispute_case_title');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(resolved ? Icons.gavel_outlined : Icons.gavel, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(title,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: color)),
              ),
            ],
          ),
          if (reason.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(reason,
                style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withValues(alpha: 0.8),
                    height: 1.3)),
          ],
          if (evidenceCount > 0) ...[
            const SizedBox(height: 2),
            Text('${context.tr('dispute_evidence_label')} • $evidenceCount',
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          ],
        ],
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
          SnackBar(content: Text('${context.tr('error')}: ${context.trError(e)}')),
        );
      }
    }
  }

  Widget _buildPendingOrdersSection(ColorScheme cs, User user) {
    return StreamBuilder<QuerySnapshot>(
      key: ValueKey('seller_pending_orders_$_refreshKey'),
      stream: FirebaseFirestore.instance
          .collection('orders')
          .where('sellerId', isEqualTo: user.uid)
          .orderBy('createdAt', descending: true)
          .limit(150)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          // Surfacing the failure here keeps the section from silently
          // disappearing (which read as a blank top half of the screen).
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
            child: Row(
              children: [
                Icon(Icons.error_outline, size: 18, color: cs.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.trError(snap.error),
                    style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _refreshKey++),
                  child: Text(context.tr('retry')),
                ),
              ],
            ),
          );
        }
        if (!snap.hasData) return const SizedBox.shrink();
        final pending = snap.data!.docs.where((doc) {
          final data = doc.data() as Map;
          final s = data['status'] as String? ?? '';
          final shippingCost = (data['shippingCost'] as num?)?.toDouble() ?? 0;
          return s == 'pending' && shippingCost <= 0;
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
                  final productName = d['productName'] ?? context.tr('product');
                  final productImage = d['productImage'] as String? ?? '';
                  final buyerName = d['buyerName'] ?? '';
                  final region = d['region'] as String? ?? '';
                  final district = d['district'] as String? ?? '';
                  final ward = d['ward'] as String? ?? '';

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
                                      ? ProductCachedImage(url: productImage, width: 36, height: 36, fit: BoxFit.cover)
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
                            Text('$region, $district${ward.isNotEmpty ? ', $ward' : ''}',
                                style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
                          const Spacer(),
                          SizedBox(
                            width: double.infinity,
                            height: 34,
                            child: DsButton(
                              label: context.tr('place_quote'),
                              icon: Icons.send_rounded,
                              height: 34,
                              onPressed: () => context.push(AppRoutes.sellerQuote),
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

  void _viewBuyerProfile(String buyerId) {
    if (!mounted) return;
    context.push('${AppRoutes.publicProfile}/$buyerId');
  }
}
