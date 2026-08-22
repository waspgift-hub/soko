import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../../models/transaction_model.dart';
import '../../services/api_config.dart';
import '../../services/clickpesa_service.dart';
import '../../services/rating_service.dart';
import '../../services/profanity_filter.dart';
import '../../extensions/context_tr.dart';
import '../../app/routes.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import '../chat/chat_navigation.dart';
import '../../widgets/payment_banner.dart';
import '../../widgets/payment_result_dialog.dart';
import '../../widgets/soko_vibe_loading.dart';
import '../../widgets/order_status_config.dart';
import 'package:go_router/go_router.dart';
import '../../widgets/product_cached_image.dart';

class MyPurchasesScreen extends StatefulWidget {
  const MyPurchasesScreen({super.key});

  @override
  State<MyPurchasesScreen> createState() => _MyPurchasesScreenState();
}

class _MyPurchasesScreenState extends State<MyPurchasesScreen> {
  String? _releasingTxId;
  String? _disputingTxId;
  String? _payingTxId;
  String? _cancellingTxId;
  String _selectedFilter = 'all';
  bool _isInitialLoad = true;
  bool _isSelectionMode = false;
  final Set<String> _selectedIds = {};
  bool _isDeletingSelected = false;
  List<QueryDocumentSnapshot> _currentDocs = [];
  Timer? _autoRefreshTimer;
  DateTime? _lastAutoRefresh;

  static const _filters = ['all', 'pending', 'active', 'completed', 'failed'];

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  List<QueryDocumentSnapshot> _filterDocs(List<QueryDocumentSnapshot> docs) {
    docs = docs
        .where((d) => (d.data() as Map)['deletedForBuyer'] != true)
        .toList();
    if (_selectedFilter == 'all') return docs;
    return docs.where((d) {
      final s = (d.data() as Map)['status'] as String? ?? '';
      switch (_selectedFilter) {
        case 'pending':
          return s == 'pending' ||
              s == 'awaiting_shipping_quote' ||
              s == 'awaiting_payment';
        case 'active':
          return s == 'paid_escrow_held' ||
              s == 'escrow_hold' ||
              s == 'dispatched' ||
              s == 'delivered';
        case 'completed':
          return s == 'completed' || s == 'delivery_confirmed';
        case 'failed':
          return s == 'failed' || s == 'cancelled' || s == 'refunded';
        default:
          return true;
      }
    }).toList();
  }

  Future<void> _payForOrder(String txId, Map<String, dynamic> d) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _payingTxId = txId);

    try {
      final existingStatus = d['status'] as String? ?? '';
      if (existingStatus == 'completed' ||
          existingStatus == 'delivered' ||
          existingStatus == 'delivery_confirmed') {
        if (mounted) {
          PaymentBanner.show(
            context: context,
            type: PaymentBannerType.success,
            title: context.tr('order_already_paid'),
          );
        }
        if (mounted) setState(() => _payingTxId = null);
        return;
      }

      final productPrice = (d['productPrice'] as num?)?.toDouble() ?? 0;
      final shippingCost = (d['shippingCost'] as num?)?.toDouble() ?? 0;
      final productName = d['productName'] as String? ?? context.tr('product');
      final productId = d['productId'] as String? ?? '';
      final sellerId = d['sellerId'] as String? ?? '';
      final sellerName = d['sellerName'] as String? ?? '';

      final result = await ClickPesaService.initiateMarketplacePayment(
        productPrice: productPrice,
        productName: productName,
        productId: productId,
        sellerId: sellerId,
        sellerName: sellerName,
        email: user.email ?? '',
        phone: d['buyerPhone'] as String? ?? '',
        buyerId: user.uid,
        deliveryType: 'local',
        existingTransactionId: txId,
        paymentMethod: 'ussd_push',
        shippingCost: shippingCost,
      );

      if (result == null || result['order_id'] == null) {
        final errMsg =
            result?['error'] as String? ??
            context.tr('payment_initiation_failed');
        if (mounted) {
          PaymentBanner.show(
            context: context,
            type: PaymentBannerType.failed,
            title: context.tr('payment_failed'),
            subtitle: errMsg,
          );
        }
        if (mounted) setState(() => _payingTxId = null);
        return;
      }

      if (mounted) {
        RealtimePaymentBanner.show(
          context: context,
          orderId: result['order_id'] as String,
          successStatuses: ['escrow_hold', 'paid_escrow_held'],
          processingTitle: context.tr('processing_payment'),
          processingSubtitle: context.tr('check_phone_enter_pin'),
          successTitle: context.tr('payment_successful'),
          failedTitle: context.tr('payment_failed'),
          onSuccess: () {
            if (mounted) {
              final paidAmount = (d['totalAmount'] as num?)?.toDouble() ?? productPrice;
              PaymentBanner.show(
                context: context,
                type: PaymentBannerType.success,
                title: context.tr('payment_successful'),
                amount: 'TZS ${NumberFormat('#,###', 'en').format(paidAmount)}',
              );
              setState(() {});
            }
          },
          onError: (msg) {
              if (mounted) {
                PaymentResult.show(
                  context: context,
                  success: false,
                  errorMessage: msg,
                );
              }
            },
          );
      }
    } catch (e) {
      if (mounted) {
        PaymentBanner.show(
          context: context,
          type: PaymentBannerType.failed,
          title: context.tr('payment_failed'),
          subtitle: context.trError(e),
        );
      }
    }
    if (mounted) setState(() => _payingTxId = null);
  }

  Future<void> _confirmDelivery(String txId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _releasingTxId = txId);
    try {
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/escrow/release'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${await user.getIdToken()}',
        },
        body: jsonEncode({'orderId': txId, 'userId': user.uid}),
      );
      final result = jsonDecode(resp.body);
      if (resp.statusCode == 200 && result['success'] == true) {
        _showSuccess(context.tr('delivery_confirmed_msg'));
        final txDoc = await FirebaseFirestore.instance
            .collection('transactions')
            .doc(txId)
            .get();
        if (txDoc.exists) {
          final tx = txDoc.data()!;
          final sellerId = tx['sellerId'] as String? ?? '';
          final productId = tx['productId'] as String? ?? '';
          final productName = tx['productName'] as String? ?? '';
          if (mounted && sellerId.isNotEmpty && productId.isNotEmpty) {
            _showSellerRatingDialog(txId, sellerId, productId, productName);
          }
        }
      } else {
        _showError(result['error'] ?? context.tr('confirm_failed_msg'));
      }
    } catch (e) {
      _showError('${context.tr('confirm_failed_msg')}: $e');
    }
    setState(() => _releasingTxId = null);
  }

  void _showSellerRatingDialog(
    String txId,
    String sellerId,
    String productId,
    String productName,
  ) {
    double rating = 5;
    final commentCtrl = TextEditingController();
    final user = FirebaseAuth.instance.currentUser;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(context.tr('rate_seller')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  context.tr('rate_seller_desc').replaceAll('{0}', productName),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (i) {
                    final star = i + 1;
                    return IconButton(
                      icon: Icon(
                        star <= rating ? Icons.star : Icons.star_border,
                        color: Colors.amber,
                        size: 36,
                      ),
                      onPressed: () =>
                          setDialogState(() => rating = star.toDouble()),
                    );
                  }),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: commentCtrl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: context.tr('review_hint'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(context.tr('skip')),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final commentText = commentCtrl.text.trim();
                if (commentText.isNotEmpty) {
                  final check = await ProfanityFilter().check(commentText);
                  if (!check.clean) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(check.message ?? 'Profanity detected'), backgroundColor: Theme.of(context).colorScheme.error),
                      );
                    }
                    return;
                  }
                }
                await RatingService().submitReview(
                  productId: productId,
                  sellerId: sellerId,
                  userId: user?.uid ?? '',
                  userName: user?.displayName ?? user?.email ?? context.tr('anonymous', 'Anonymous'),
                  userImage: user?.photoURL,
                  rating: rating,
                  comment: commentText,
                  isVerifiedPurchase: true,
                );
                if (mounted) _showSuccess(context.tr('rating_submitted'));
              },
              child: Text(context.tr('submit')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _raiseDispute(String txId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('dispute_title')),
        content: Text(context.tr('dispute_notify_admin')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr('open')),
          ),
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
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${await user.getIdToken()}',
        },
        body: jsonEncode({'orderId': txId, 'userId': user.uid}),
      );
      final result = jsonDecode(resp.body);
      if (resp.statusCode == 200 && result['success'] == true) {
        _showSuccess(context.tr('dispute_opened_msg'));
      } else {
        _showError(result['error'] ?? context.tr('dispute_failed'));
      }
    } catch (e) {
      _showError(context.trError(e));
    }
    setState(() => _disputingTxId = null);
  }

  Future<void> _cancelOrder(String txId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('cancel_order_title')),
        content: Text(context.tr('cancel_order_refund_message')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text(context.tr('yes_cancel')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _cancellingTxId = txId);
    try {
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/escrow/cancel'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${await user.getIdToken()}',
        },
        body: jsonEncode({'orderId': txId, 'userId': user.uid}),
      );
      final result = jsonDecode(resp.body);
      if (resp.statusCode == 200 && result['success'] == true) {
        _showSuccess(context.tr('order_cancelled_refunded'));
      } else {
        _showError(result['error'] ?? context.tr('cancel_order_failed'));
      }
    } catch (e) {
      _showError(context.trError(e));
    }
    setState(() => _cancellingTxId = null);
  }

  Future<void> _deleteOrder(String txId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('delete_order_title')),
        content: Text(context.tr('delete_order_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text(context.tr('yes_delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await FirebaseFirestore.instance
          .collection('transactions')
          .doc(txId)
          .update({'deletedForBuyer': true});
      if (mounted) _showSuccess(context.tr('order_deleted'));
    } catch (e) {
      if (mounted) _showError(context.trError(e));
    }
  }

  Future<void> _deleteSelectedOrders() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('delete_orders_title')),
        content: Text('${context.tr('delete_orders_confirm')} ${_selectedIds.length}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text(context.tr('yes_delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _isDeletingSelected = true);
    try {
      final batch = FirebaseFirestore.instance.batch();
      for (final id in _selectedIds) {
        batch.update(
          FirebaseFirestore.instance.collection('transactions').doc(id),
          {'deletedForBuyer': true},
        );
      }
      await batch.commit();
      setState(() {
        _selectedIds.clear();
        _isSelectionMode = false;
        _isDeletingSelected = false;
      });
      if (mounted) _showSuccess(context.tr('orders_deleted'));
    } catch (e) {
      setState(() => _isDeletingSelected = false);
      if (mounted) _showError(context.trError(e));
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  Widget _buildFilterChips(
    ColorScheme cs,
    List<QueryDocumentSnapshot> allDocs,
  ) {
    final visible = allDocs
        .where((d) => (d.data() as Map)['deletedForBuyer'] != true)
        .toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: _filters.map((f) {
          final selected = _selectedFilter == f;
          final count = f == 'all' ? visible.length : _filterCount(visible, f);
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              selected: selected,
              label: Text(
                '${context.tr(f)} ($count)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              onSelected: (_) => setState(() => _selectedFilter = f),
              visualDensity: VisualDensity.compact,
              selectedColor: cs.primary.withValues(alpha: 0.15),
              checkmarkColor: cs.primary,
              side: BorderSide(
                color: selected
                    ? cs.primary
                    : cs.outlineVariant.withValues(alpha: 0.3),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildStatsHeader(
    ColorScheme cs,
    List<QueryDocumentSnapshot> allDocs,
  ) {
    final visible = allDocs
        .where((d) => (d.data() as Map)['deletedForBuyer'] != true)
        .toList();
    final active = visible.where((d) {
      final s = (d.data() as Map)['status'] as String? ?? '';
      return s == 'pending' ||
          s == 'awaiting_shipping_quote' ||
          s == 'awaiting_payment' ||
          s == 'quoted' ||
          s == 'paid_escrow_hold' ||
          s == 'escrow_hold' ||
          s == 'dispatched' ||
          s == 'delivered';
    }).length;
    final completed = visible.where((d) {
      final s = (d.data() as Map)['status'] as String? ?? '';
      return s == 'completed' || s == 'delivery_confirmed';
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
            if (_lastAutoRefresh != null)
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: cs.successGreen,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: cs.successGreen.withValues(alpha: 0.5),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    context.tr('live_updates'),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: cs.successGreen,
                    ),
                  ),
                  const SizedBox(width: 4),
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
                  child: _statCell(
                    cs,
                    Icons.inventory_2_outlined,
                    '$active',
                    context.tr('active_orders'),
                    cs.primary,
                  ),
                ),
                Container(
                  width: 1,
                  height: 40,
                  color: cs.primary.withValues(alpha: 0.14),
                ),
                Expanded(
                  child: _statCell(
                    cs,
                    Icons.check_circle_outline,
                    '$completed',
                    context.tr('completed_orders'),
                    cs.successGreen,
                  ),
                ),
                Container(
                  width: 1,
                  height: 40,
                  color: cs.primary.withValues(alpha: 0.14),
                ),
                Expanded(
                  child: _statCell(
                    cs,
                    Icons.shopping_bag_outlined,
                    '${visible.length}',
                    context.tr('all_orders'),
                    cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statCell(
    ColorScheme cs,
    IconData icon,
    String value,
    String label,
    Color color,
  ) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 5),
            Text(
              value,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: cs.onSurfaceVariant,
          ),
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

  int _filterCount(List<QueryDocumentSnapshot> docs, String filter) {    return docs.where((d) {
      final s = (d.data() as Map)['status'] as String? ?? '';
      switch (filter) {
        case 'pending':
          return s == 'pending' ||
              s == 'awaiting_shipping_quote' ||
              s == 'awaiting_payment';
        case 'active':
          return s == 'paid_escrow_held' ||
              s == 'escrow_hold' ||
              s == 'dispatched' ||
              s == 'delivered';
        case 'completed':
          return s == 'completed' || s == 'delivery_confirmed';
        case 'failed':
          return s == 'failed' || s == 'cancelled' || s == 'refunded';
        default:
          return true;
      }
    }).length;
  }

  Widget _buildEmptyState(ColorScheme cs, List<QueryDocumentSnapshot> allDocs) {
    final hasOrders = allDocs.isNotEmpty;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasOrders
                ? Icons.filter_list_off_rounded
                : Icons.shopping_bag_outlined,
            size: 64,
            color: cs.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            hasOrders
                ? context.tr('no_orders_this_filter')
                : context.tr('no_purchases_yet'),
            style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant),
          ),
          if (!hasOrders) ...[
            const SizedBox(height: 8),
            Text(
              context.tr('start_shopping_hint'),
              style: TextStyle(
                fontSize: 13,
                color: cs.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => context.go(AppRoutes.home),
              icon: const Icon(Icons.storefront_outlined, size: 18),
              label: Text(context.tr('browse_products')),
              style: ElevatedButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: cs.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSkeleton(ColorScheme cs) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      itemCount: 4,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Container(
          height: 200,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Center(
            child: SokoVibeThreeDotLoader(size: 36, dotSize: 8),
          ),
        ),
      ),
    );
  }

  String _escrowLabel(String status) {
    switch (status) {
      case 'paid_escrow_held':
      case 'escrow_hold':
        return context.tr('secured_in_escrow');
      case 'dispatched':
        return context.tr('dispatched_label');
      case 'delivered':
      case 'delivery_confirmed':
      case 'completed':
        return context.tr('delivered_and_completed');
      case 'failed':
        return context.tr('failed');
      case 'refunded':
        return context.tr('refunded');
      default:
        return context.tr('pending');
    }
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
      bottomNavigationBar: _isSelectionMode && _selectedIds.isNotEmpty
          ? SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                decoration: BoxDecoration(
                  color: cs.surface,
                  border: Border(
                    top: BorderSide(
                      color: cs.outlineVariant.withValues(alpha: 0.2),
                    ),
                  ),
                ),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _isDeletingSelected ? null : _deleteSelectedOrders,
                    icon: _isDeletingSelected
                        ? SokoVibeThreeDotLoader(
                            size: 18,
                            dotSize: 4.5,
                            color: cs.surface,
                          )
                        : const Icon(Icons.delete_outline, size: 20),
                    label: Text(
                      _isDeletingSelected
                          ? context.tr('deleting_label')
                          : '${context.tr('delete_selected')} (${_selectedIds.length})',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cs.error,
                      foregroundColor: cs.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ),
            )
          : null,
      appBar: AppBar(
        title: Text(_isSelectionMode
            ? '${_selectedIds.length} ${context.tr('selected')}'
            : context.tr('my_purchases')),
        centerTitle: true,
        leading: _isSelectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() {
                  _isSelectionMode = false;
                  _selectedIds.clear();
                }),
              )
            : null,
        actions: _isSelectionMode
            ? [
                TextButton(
                  onPressed: _currentDocs.isEmpty || _selectedIds.length == _currentDocs.length
                      ? () => setState(() => _selectedIds.clear())
                      : () => setState(() => _selectedIds.addAll(_currentDocs.map((d) => d.id))),
                  child: Text(_currentDocs.isNotEmpty && _selectedIds.length == _currentDocs.length
                      ? context.tr('deselect_all')
                      : context.tr('select_all')),
                ),
              ]
            : [
                TextButton.icon(
                  onPressed: () => setState(() => _isSelectionMode = true),
                  icon: const Icon(Icons.checklist, size: 18),
                  label: Text(context.tr('select')),
                ),
                TextButton.icon(
                  onPressed: () => context.go(AppRoutes.home),
                  icon: const Icon(Icons.storefront_outlined, size: 18),
                  label: Text(context.tr('home')),
                ),
              ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('transactions')
            .where('buyerId', isEqualTo: user.uid)
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting &&
              _isInitialLoad) {
            return _buildSkeleton(cs);
          }
          _isInitialLoad = false;

          if (snap.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, size: 48, color: cs.error),
                  const SizedBox(height: 12),
                  Text(
                    context.tr('loading_error'),
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: () => setState(() => _isInitialLoad = true),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: Text(context.tr('retry')),
                  ),
                ],
              ),
            );
          }

          final allDocs = snap.data?.docs ?? [];
          allDocs.sort((a, b) {
            final ta = (a.data() as Map)['createdAt'];
            final tb = (b.data() as Map)['createdAt'];
            if (ta is Timestamp && tb is Timestamp) return tb.compareTo(ta);
            return 0;
          });

          final docs = _filterDocs(allDocs);
          _currentDocs = docs;

            return RefreshIndicator(
            onRefresh: () async {
              setState(() => _isInitialLoad = true);
              await Future.delayed(const Duration(milliseconds: 300));
              if (mounted) setState(() => _isInitialLoad = false);
            },
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _buildStatsHeader(cs, allDocs)),
                SliverToBoxAdapter(child: _buildFilterChips(cs, allDocs)),
                if (docs.isEmpty)
                  SliverFillRemaining(child: _buildEmptyState(cs, allDocs))
                else
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => _OrderGlassCard(
                        key: ValueKey(docs[i].id),
                        data: docs[i].data() as Map<String, dynamic>,
                        docId: docs[i].id,
                        releasingTxId: _releasingTxId,
                        disputingTxId: _disputingTxId,
                        payingTxId: _payingTxId,
                        cancellingTxId: _cancellingTxId,
                        onPay: _payForOrder,
                        onConfirm: _confirmDelivery,
                        onDispute: _raiseDispute,
                        onCancel: _cancelOrder,
                        onDelete: _deleteOrder,
                        escrowLabel: _escrowLabel,
                        isSelectionMode: _isSelectionMode,
                        isSelected: _selectedIds.contains(docs[i].id),
                        onToggleSelect: () => setState(() {
                          if (_selectedIds.contains(docs[i].id)) {
                            _selectedIds.remove(docs[i].id);
                          } else {
                            _selectedIds.add(docs[i].id);
                          }
                        }),
                      ),
                      childCount: docs.length,
                    ),
                  ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: _isSelectionMode && _selectedIds.isNotEmpty ? 80 : 32,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _OrderGlassCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String docId;
  final String? releasingTxId;
  final String? disputingTxId;
  final String? payingTxId;
  final String? cancellingTxId;
  final Function(String, Map<String, dynamic>) onPay;
  final Function(String) onConfirm;
  final Function(String) onDispute;
  final Function(String) onCancel;
  final Function(String) onDelete;
  final String Function(String) escrowLabel;
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback onToggleSelect;

  const _OrderGlassCard({
    super.key,
    required this.data,
    required this.docId,
    this.releasingTxId,
    this.disputingTxId,
    this.payingTxId,
    this.cancellingTxId,
    required this.onPay,
    required this.onConfirm,
    required this.onDispute,
    required this.onCancel,
    required this.onDelete,
    required this.escrowLabel,
    this.isSelectionMode = false,
    this.isSelected = false,
    required this.onToggleSelect,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isBoost = data['type'] == 'boost';
    final status = data['status'] as String? ?? 'pending';
    final productName = data['productName'] as String? ?? context.tr('product');
    final productImage = data['productImage'] as String? ?? '';
    final price = (data['productPrice'] ?? 0).toDouble();
    final shippingCost = (data['shippingCost'] as num?)?.toDouble();
    final totalAmount = (data['totalAmount'] as num?)?.toDouble() ?? price;
    final platformFee = (data['platformFee'] as num?)?.toDouble() ?? (price * 0.035);
    final processingFee = (data['processingFee'] as num?)?.toDouble() ?? getUssdPushFee(price);
    final paymentMethod = data['paymentMethod'] as String? ?? 'ClickPesa';
    final sellerName = data['sellerName'] as String? ?? '';
    final sellerId = data['sellerId'] as String? ?? '';
    final createdAt = data['createdAt'];
    final dateStr = createdAt is Timestamp
        ? DateFormat('dd MMM yyyy HH:mm').format(createdAt.toDate())
        : '';
    final productId = data['productId'] as String? ?? '';

    if (isBoost) {
      return _buildBoostCard(
        context,
        cs,
        productImage,
        productName,
        price,
        status,
        docId,
        dateStr,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: isSelectionMode ? onToggleSelect : () =>
            context.push('${AppRoutes.orderDetail}/$docId', extra: data),
        borderRadius: BorderRadius.circular(24),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            color: cs.surface.withValues(alpha: 0.5),
            border: Border.all(
              color: isSelected
                  ? cs.primary
                  : cs.outlineVariant.withValues(alpha: 0.1),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Stack(
                children: [
                  // Status accent rail (left edge)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: Container(
                      width: 4,
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.horizontal(
                          right: Radius.circular(4),
                        ),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            orderStatusInfo(status, cs).color,
                            orderStatusInfo(status, cs).color.withValues(alpha: 0.35),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isSelectionMode)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(0, 8, 12, 0),
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: Transform.scale(
                                scale: 1.1,
                                child: Checkbox(
                                  value: isSelected,
                                  onChanged: (_) => onToggleSelect(),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  activeColor: cs.primary,
                                ),
                              ),
                            ),
                          ),
                        _buildTopSection(
                          context,
                          cs,
                          productImage,
                          productName,
                          price,
                          status,
                          docId,
                        ),
                        Divider(
                          height: 1,
                          indent: 16,
                          endIndent: 16,
                          color: cs.outlineVariant.withValues(alpha: 0.1),
                        ),
                        _buildMidSection(
                          context,
                          cs,
                          docId,
                          dateStr,
                          sellerName,
                          sellerId,
                          paymentMethod,
                          status,
                          productId,
                        ),
                        Divider(
                          height: 1,
                          indent: 16,
                          endIndent: 16,
                          color: cs.outlineVariant.withValues(alpha: 0.1),
                        ),
                        _buildActions(
                          context,
                          cs,
                          status,
                          price,
                          shippingCost,
                          totalAmount,
                          platformFee: platformFee,
                          processingFee: processingFee,
                        ),
                        if (status == 'delivered' ||
                            status == 'delivery_confirmed' ||
                            status == 'confirmed' ||
                            status == 'completed')
                          _buildReceiptCard(
                            context,
                            cs,
                            status,
                            Theme.of(context).brightness == Brightness.dark,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
        ),
      ),
    );
  }

  Widget _buildBoostCard(
    BuildContext context,
    ColorScheme cs,
    String image,
    String name,
    double price,
    String status,
    String orderId,
    String dateStr,
  ) {
    final tier = data['tier'] as String? ?? '';
    final isCompleted = status == 'completed';
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: isSelectionMode
            ? onToggleSelect
            : isCompleted
                ? () => context.push(AppRoutes.boostReceipt, extra: data)
                : null,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            color: cs.boostGold.withValues(alpha: isSelected ? 0.12 : 0.06),
            border: Border.all(
              color: isSelected
                  ? cs.primary
                  : cs.boostGold.withValues(alpha: 0.2),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isSelectionMode)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(0, 8, 12, 0),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Transform.scale(
                          scale: 1.1,
                          child: Checkbox(
                            value: isSelected,
                            onChanged: (_) => onToggleSelect(),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                            activeColor: cs.primary,
                          ),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                    child: Row(
                      children: [
                        Icon(
                          Icons.rocket_launch_rounded,
                          size: 18,
                          color: cs.boostGold,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          context.tr('boost_product'),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: cs.boostGold,
                          ),
                        ),
                        const Spacer(),
                        _statusBadge(context, cs, status),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            width: 56,
                            height: 56,
                            color: cs.surfaceContainerHighest,
                            child: image.isNotEmpty
                                ? ProductCachedImage(
                                    url: image,
                                    width: 56,
                                    height: 56,
                                    fit: BoxFit.cover,
                                  )
                                : Icon(
                                    Icons.image,
                                    color: cs.onSurfaceVariant.withValues(
                                      alpha: 0.3,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: cs.onSurface,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              if (tier.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: cs.boostGold.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    tier,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: cs.boostGold,
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 4),
                              Text(
                                'TZS ${_nf(price.toInt())}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                  color: cs.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isCompleted) ...[
                    const Divider(height: 1, indent: 14, endIndent: 14),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                      child: Row(
                        children: [
                          Icon(Icons.receipt_long_rounded,
                              size: 16, color: cs.primary),
                          const SizedBox(width: 6),
                          Text(
                            context.tr('view_receipt'),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: cs.primary,
                            ),
                          ),
                          const Spacer(),
                          Icon(Icons.chevron_right,
                              size: 18, color: cs.primary),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
        ),
      ),
    );
  }

  Widget _buildTopSection(
    BuildContext context,
    ColorScheme cs,
    String image,
    String name,
    double price,
    String status,
    String orderId,
  ) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Hero(
            tag: 'order_img_$orderId',
            child: Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.15),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: image.isNotEmpty
                    ? ProductCachedImage(
                        url: image,
                        width: 68,
                        height: 68,
                        fit: BoxFit.cover,
                      )
                    : _imgPlaceholder(cs),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: cs.onSurface,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      'TZS ${_nf(price.toInt())}',
                      style: AppTypography.amount(cs.primary).copyWith(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 10),
                    _statusBadge(context, cs, status),
                  ],
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            size: 22,
            color: cs.onSurfaceVariant.withValues(alpha: 0.4),
          ),
        ],
      ),
    );
  }

  Widget _imgPlaceholder(ColorScheme cs) {
    return Container(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
      child: Icon(
        Icons.image_rounded,
        color: cs.onSurfaceVariant.withValues(alpha: 0.3),
      ),
    );
  }

  Widget _statusBadge(BuildContext context, ColorScheme cs, String status) {
    return OrderStatusBadge(status: status, compact: true);
  }

  Widget _buildMidSection(
    BuildContext context,
    ColorScheme cs,
    String orderId,
    String date,
    String sellerName,
    String sellerId,
    String method,
    String status,
    String productId,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _infoChip(
                cs,
                Icons.tag_rounded,
                '#$orderId',
                cs.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              _infoChip(
                cs,
                Icons.access_time_rounded,
                date,
                cs.onSurfaceVariant,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (sellerId.isNotEmpty)
                GestureDetector(
                  onTap: () => ChatNavigation.openSellerChat(
                    context,
                    sellerId,
                    sellerName,
                  ),
                  child: _infoChip(
                    cs,
                    Icons.chat_outlined,
                    sellerName,
                    cs.primary,
                  ),
                ),
              const SizedBox(width: 8),
              _infoChip(cs, Icons.payment_outlined, method, cs.secondary),
              const Spacer(),
              _CompactTimeline(status: status, cs: cs),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoChip(ColorScheme cs, IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentSummary(
    BuildContext context,
    ColorScheme cs,
    double price,
    double? shipping,
    double total,
    String method, {
    double platformFee = 0,
    double processingFee = 0,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          _summaryRow(
            context,
            cs,
            context.tr('product_price'),
            _nf(price.toInt()),
            cs.onSurface,
          ),
          _summaryRow(
            context,
            cs,
            context.tr('processing_fee'),
            _nf(processingFee.toInt()),
            cs.tertiary,
          ),
          _summaryRow(
            context,
            cs,
            context.tr('soko_vibe_commission'),
            _nf(platformFee.toInt()),
            cs.tertiary,
          ),
          if (shipping != null && shipping > 0)
            _summaryRow(
              context,
              cs,
              context.tr('shipping_cost'),
              _nf(shipping.toInt()),
              cs.secondary,
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Divider(
              height: 1,
              color: cs.outlineVariant.withValues(alpha: 0.2),
            ),
          ),
          _summaryRow(
            context,
            cs,
            context.tr('receipt_total'),
            _nf(total.toInt()),
            cs.primary,
            bold: true,
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(
    BuildContext context,
    ColorScheme cs,
    String label,
    String value,
    Color valueColor, {
    bool bold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: cs.onSurfaceVariant,
              fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          Text(
            'TZS $value',
            style: TextStyle(
              fontSize: 14,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(
    BuildContext context,
    ColorScheme cs,
    String status,
    double price,
    double? shipping,
    double total, {
    double platformFee = 0,
    double processingFee = 0,
  }) {
    final canPay = status == 'awaiting_payment';
    final canConfirm = status == 'delivered' || status == 'dispatched';
    final canDispute =
        status == 'paid_escrow_held' ||
        status == 'escrow_hold' ||
        status == 'dispatched' ||
        status == 'delivered';
    final canCancel = status == 'paid_escrow_held' || status == 'escrow_hold';
    final canDelete =
        status == 'pending' ||
        status == 'failed' ||
        status == 'awaiting_payment' ||
        status == 'awaiting_shipping_quote';

    final actions = <Widget>[];
    if (canPay)
      actions.add(
        _buildActionBtn(
          context,
          cs,
          Icons.payment,
          context.tr('pay_amount_tzs').replaceAll('{0}', _nf(total)),
          payingTxId == docId ? null : () => onPay(docId, data),
          cs.primary,
          payingTxId == docId,
        ),
      );
    if (canConfirm)
      actions.add(
        _buildActionBtn(
          context,
          cs,
          Icons.verified,
          context.tr('confirm_receipt'),
          releasingTxId == docId ? null : () => onConfirm(docId),
          cs.successGreen,
          releasingTxId == docId,
        ),
      );
    if (status == 'awaiting_shipping_quote')
      actions.add(
        _buildActionBtn(
          context,
          cs,
          Icons.hourglass_empty,
          context.tr('waiting_for_seller_label'),
          null,
          cs.onSurfaceVariant,
          false,
          disabled: true,
        ),
      );
    if (canDispute)
      actions.add(
        _buildActionBtn(
          context,
          cs,
          Icons.gavel,
          context.tr('dispute_button'),
          disputingTxId == docId ? null : () => onDispute(docId),
          cs.error,
          disputingTxId == docId,
          outlined: true,
        ),
      );
    if (canCancel)
      actions.add(
        _buildActionBtn(
          context,
          cs,
          Icons.money_off,
          context.tr('cancel'),
          cancellingTxId == docId ? null : () => onCancel(docId),
          cs.error,
          cancellingTxId == docId,
          outlined: true,
        ),
      );
    if (canDelete)
      actions.add(
        _buildActionBtn(
          context,
          cs,
          Icons.delete_outline,
          context.tr('delete_order'),
          () => onDelete(docId),
          cs.error,
          false,
          outlined: true,
        ),
      );

    if (actions.isEmpty) return const SizedBox.shrink();

    final showPaymentSummary = total > 0 || (shipping != null && shipping > 0);
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          if (showPaymentSummary) ...[
            _buildPaymentSummary(
              context,
              cs,
              price,
              shipping,
              total,
    data['paymentMethod'] as String? ?? 'ClickPesa',
    platformFee: platformFee,
    processingFee: processingFee,
            ),
            const SizedBox(height: 12),
          ],
          ...actions.map(
            (a) => Padding(padding: const EdgeInsets.only(bottom: 8), child: a),
          ),
        ],
      ),
    );
  }

  Widget _buildActionBtn(
    BuildContext context,
    ColorScheme cs,
    IconData icon,
    String label,
    VoidCallback? onTap,
    Color color,
    bool isLoading, {
    bool outlined = false,
    bool disabled = false,
  }) {
    final effectiveOnTap = disabled ? null : onTap;
    if (outlined) {
      return SizedBox(
        width: double.infinity,
        height: 44,
        child: OutlinedButton.icon(
          onPressed: effectiveOnTap,
          icon: isLoading
              ? SokoVibeThreeDotLoader(
                  size: 16,
                  dotSize: 4,
                  color: color,
                )
              : Icon(icon, size: 16),
          label: Text(isLoading ? context.tr('processing_label') : label),
          style: OutlinedButton.styleFrom(
            foregroundColor: color,
            side: BorderSide(color: color.withValues(alpha: 0.3)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: ElevatedButton.icon(
        onPressed: effectiveOnTap,
        icon: isLoading
            ? SokoVibeThreeDotLoader(
                size: 16,
                dotSize: 4,
                color: Colors.white,
              )
            : Icon(icon, size: 16),
        label: Text(isLoading ? context.tr('processing_label') : label),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: cs.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
      ),
    );
  }

  Widget _buildReceiptCard(
    BuildContext context,
    ColorScheme cs,
    String status,
    bool isDark,
  ) {
    final paymentMethod = data['paymentMethod'] as String? ?? 'ClickPesa';
    final productPrice = (data['productPrice'] as num?)?.toDouble() ?? 0;
    final shippingCost = (data['shippingCost'] as num?)?.toDouble() ?? 0;
    final clickpesaFee = (data['processingFee'] as num?)?.toDouble() ?? 0;
    final platformFee = (data['platformFee'] as num?)?.toDouble() ?? (productPrice * 0.035);
    final totalAmount =
        (data['totalAmount'] as num?)?.toDouble() ?? productPrice;
    final buyerName = data['buyerName'] as String? ?? '';
    final buyerPhone = data['buyerPhone'] as String? ?? '';
    final createdAt = data['createdAt'];
    final dateStr = createdAt is Timestamp
        ? DateFormat('dd/MM/yyyy HH:mm').format(createdAt.toDate())
        : '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cs.primary.withValues(alpha: 0.08)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.receipt_long_rounded, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  context.tr('purchase_receipt'),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: cs.onSurface,
                  ),
                ),
                const Spacer(),
                Icon(Icons.download_rounded, size: 18, color: cs.primary),
              ],
            ),
            const SizedBox(height: 12),
            Divider(
              height: 1,
              color: cs.outlineVariant.withValues(alpha: 0.15),
            ),
            const SizedBox(height: 10),
            _receiptRow(cs, context.tr('receipt_date'), dateStr),
            _receiptRow(
              cs,
              context.tr('product_price'),
              'TZS ${_nf(productPrice.toInt())}',
            ),
            if (shippingCost > 0)
              _receiptRow(
                cs,
                context.tr('shipping_cost'),
                'TZS ${_nf(shippingCost.toInt())}',
                valueColor: cs.secondary,
              ),
            _receiptRow(
              cs,
              context.tr('soko_vibe_commission'),
              'TZS ${_nf(platformFee.toInt())}',
              valueColor: cs.tertiary,
            ),
            _receiptRow(
              cs,
              context.tr('processing_fee'),
              'TZS ${_nf(clickpesaFee.toInt())}',
              valueColor: cs.tertiary,
            ),
            Divider(
              height: 1,
              color: cs.outlineVariant.withValues(alpha: 0.15),
            ),
            const SizedBox(height: 6),
            _receiptRow(
              cs,
              context.tr('receipt_total'),
              'TZS ${_nf(totalAmount.toInt())}',
              valueColor: cs.primary,
              bold: true,
            ),
            if (buyerName.isNotEmpty || buyerPhone.isNotEmpty)
              const SizedBox(height: 8),
            if (buyerName.isNotEmpty)
              _receiptRow(cs, context.tr('buyer_label'), buyerName),
            if (buyerPhone.isNotEmpty)
              _receiptRow(cs, context.tr('phone'), buyerPhone),
            _receiptRow(cs, context.tr('payment_method'), paymentMethod),
            _receiptRow(
              cs,
              context.tr('order_status'),
              escrowLabel(status),
              valueColor: _statusColor(status, cs),
            ),
          ],
        ),
      ),
    );
  }

  Color _statusColor(String status, ColorScheme cs) {
    return orderStatusInfo(status, cs).color;
  }

  Widget _receiptRow(
    ColorScheme cs,
    String label,
    String value, {
    Color? valueColor,
    bool bold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
              color: valueColor ?? cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  String _nf(num n) => NumberFormat('#,###', 'en').format(n);
}

class _CompactTimeline extends StatelessWidget {
  final String status;
  final ColorScheme cs;
  const _CompactTimeline({required this.status, required this.cs});

  @override
  Widget build(BuildContext context) {
    final steps = _buildSteps();
    final current = _currentIndex();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(steps.length, (i) {
        final active = i <= current;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active
                    ? steps[i].color
                    : cs.surfaceContainerHighest.withValues(alpha: 0.4),
                boxShadow: i == current
                    ? [
                        BoxShadow(
                          color: steps[i].color.withValues(alpha: 0.5),
                          blurRadius: 6,
                        ),
                      ]
                    : [],
              ),
            ),
            if (i < steps.length - 1)
              Container(
                width: 10,
                height: 2,
                color: i < current
                    ? steps[i].color
                    : cs.surfaceContainerHighest.withValues(alpha: 0.2),
              ),
          ],
        );
      }),
    );
  }

  int _currentIndex() {
    switch (status) {
      case 'pending':
        return 0;
      case 'awaiting_shipping_quote':
        return 1;
      case 'awaiting_payment':
        return 2;
      case 'paid_escrow_held':
      case 'escrow_hold':
        return 3;
      case 'dispatched':
        return 4;
      case 'delivered':
      case 'delivery_confirmed':
        return 5;
      case 'completed':
        return 6;
      default:
        return 0;
    }
  }

  List<_TimelineStep> _buildSteps() {
    return [
      _TimelineStep('', Icons.access_time_rounded, cs.onSurfaceVariant),
      _TimelineStep('', Icons.local_shipping_outlined, Colors.orange),
      _TimelineStep('', Icons.account_balance_wallet_outlined, Colors.blue),
      _TimelineStep('', Icons.verified_user_outlined, Colors.purple),
      _TimelineStep('', Icons.inventory_2_outlined, cs.successGreen),
      _TimelineStep('', Icons.check_circle_outline, cs.successGreen),
      _TimelineStep('', Icons.check_circle_rounded, cs.successGreen),
    ];
  }
}

class _TimelineStep {
  final String label;
  final IconData icon;
  final Color color;
  const _TimelineStep(this.label, this.icon, this.color);
}
