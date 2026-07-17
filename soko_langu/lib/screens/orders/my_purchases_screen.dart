import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../../services/api_config.dart';
import '../../services/mongike_service.dart';
import '../../services/sms_notification_service.dart';
import '../../extensions/context_tr.dart';
import '../../app/routes.dart';
import '../../theme/app_colors.dart';
import '../chat/chat_navigation.dart';
import '../../widgets/google_loading.dart';
import 'package:go_router/go_router.dart';

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

  Future<void> _payForOrder(String txId, Map<String, dynamic> d) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _payingTxId = txId);
    try {
      final productPrice = (d['productPrice'] as num?)?.toDouble() ?? 0;
      final shippingCost = (d['shippingCost'] as num?)?.toDouble() ?? 0;
      final productName = d['productName'] as String? ?? 'Product';
      final productId = d['productId'] as String? ?? '';
      final sellerId = d['sellerId'] as String? ?? '';
      final sellerName = d['sellerName'] as String? ?? '';
      final result = await MongikeService.initiateMarketplacePayment(
        productPrice: productPrice, productName: productName,
        productId: productId, sellerId: sellerId, sellerName: sellerName,
        email: user.email ?? '', phone: d['buyerPhone'] as String? ?? '',
        buyerId: user.uid, deliveryType: 'local',
        shippingCost: shippingCost, existingTransactionId: txId,
      );
      if (result['order_id'] == null) {
        final errMsg = result['error'] as String? ?? 'Failed to initiate payment';
        _showError(errMsg);
        setState(() => _payingTxId = null);
        return;
      }
      if (mounted) _showSuccess('Angalia simu yako — weka PIN kukamilisha malipo.');
    } catch (e) {
      _showError('Payment error: $e');
    }
    setState(() => _payingTxId = null);
  }

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
        final txDoc = await FirebaseFirestore.instance.collection('transactions').doc(txId).get();
        if (txDoc.exists) {
          final tx = txDoc.data()!;
          final sellerId = tx['sellerId'] as String? ?? '';
          final grandTotal = ((tx['totalAmount'] as num?)?.toDouble() ?? 0);
          if (sellerId.isNotEmpty) {
            final sellerDoc = await FirebaseFirestore.instance.collection('users').doc(sellerId).get();
            final sellerPhone = sellerDoc.data()?['phone'] as String?;
            if (sellerPhone != null && sellerPhone.isNotEmpty) {
              SmsNotificationService.notifyEscrowReleased(sellerPhone: sellerPhone, grandTotal: grandTotal.toStringAsFixed(0), orderId: txId);
            }
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

  Future<void> _raiseDispute(String txId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Fungua Mgogoro?'),
        content: const Text('Hii itaarifu admin kukagua muamala huu.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('cancel'))),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Fungua')),
        ],
      ),
    );
    if (confirmed != true) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _disputingTxId = txId);
    try {
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/dispute/create'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'orderId': txId, 'userId': user.uid}),
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

  Future<void> _cancelOrder(String txId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ghairi Oda?'),
        content: const Text('Hii itarudisha hela yako yote kupitia Mongike. Hakikisha hujapokea mzigo.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('cancel'))),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white), child: const Text('Ndiyo, Ghairi')),
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
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'orderId': txId, 'userId': user.uid}),
      );
      final result = jsonDecode(resp.body);
      if (resp.statusCode == 200 && result['success'] == true) {
        _showSuccess('Oda imeghairiwa. Hela yako imerudishwa.');
      } else {
        _showError(result['error'] ?? 'Failed to cancel order');
      }
    } catch (e) {
      _showError('Error: $e');
    }
    setState(() => _cancellingTxId = null);
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Theme.of(context).colorScheme.error));
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Theme.of(context).colorScheme.primary));
  }

  String _escrowLabel(String status) {
    switch (status) {
      case 'paid_escrow_held': case 'escrow_hold': return 'Secured in Escrow';
      case 'dispatched': return 'Dispatched';
      case 'delivered': case 'delivery_confirmed': case 'completed': return 'Delivered & Completed';
      case 'failed': return 'Failed';
      case 'refunded': return 'Refunded';
      default: return 'Pending';
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
      appBar: AppBar(
        title: Text(context.tr('my_purchases')),
        centerTitle: true,
        actions: [
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
          if (snap.hasError || !snap.hasData) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.shopping_bag_outlined, size: 64, color: cs.onSurfaceVariant),
                  const SizedBox(height: 16),
                  Text(context.tr('no_purchases_yet'), style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant)),
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
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            itemCount: docs.length,
            itemBuilder: (_, i) => _OrderGlassCard(
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
              escrowLabel: _escrowLabel,
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
  final String Function(String) escrowLabel;

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
    required this.escrowLabel,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final status = data['status'] as String? ?? 'pending';
    final productName = data['productName'] as String? ?? 'Product';
    final price = (data['productPrice'] ?? 0).toDouble();
    final shippingCost = (data['shippingCost'] as num?)?.toDouble();
    final totalAmount = (data['totalAmount'] as num?)?.toDouble() ?? price;
    final createdAt = data['createdAt'];
    final dateStr = createdAt is Timestamp
        ? DateFormat('dd MMM yyyy').format(createdAt.toDate())
        : '';
    final sellerName = data['sellerName'] as String? ?? '';
    final paymentMethod = data['paymentMethod'] as String? ?? 'Mongike';

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 40, sigmaY: 40),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [cs.surface.withValues(alpha: 0.15), cs.surfaceContainerLow.withValues(alpha: 0.1)]
                    : [Colors.white.withValues(alpha: 0.85), Colors.white.withValues(alpha: 0.7)],
              ),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: isDark ? 0.15 : 0.2),
                width: 0.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: cs.primary.withValues(alpha: 0.06),
                  blurRadius: 32,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(context, cs, productName, sellerName, dateStr, docId),
                  const SizedBox(height: 16),
                  _OrderStatusTimeline(status: status, cs: cs),
                  const SizedBox(height: 16),
                  _buildInfoChips(cs, price, shippingCost, totalAmount, paymentMethod),
                  const SizedBox(height: 16),
                  _buildActions(context, cs, status, price, shippingCost, totalAmount),
                  if (status == 'delivered' || status == 'delivery_confirmed' || status == 'completed')
                    _buildReceiptCard(cs, isDark),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ColorScheme cs, String productName, String sellerName, String date, String orderId) {
    final sellerId = data['sellerId'] as String? ?? '';
    final buyerName = data['buyerName'] as String? ?? '';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.primary.withValues(alpha: 0.15), width: 0.5),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: Container(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
              child: Icon(Icons.image_rounded, color: cs.onSurfaceVariant.withValues(alpha: 0.3)),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                productName,
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: cs.onSurface),
                maxLines: 1, overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(Icons.store_rounded, size: 11, color: cs.primary),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: sellerId.isNotEmpty
                        ? () => ChatNavigation.openSellerChat(context, sellerId, sellerName)
                        : null,
                    child: Row(
                      children: [
                        Text(sellerName, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                        if (sellerId.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          Icon(Icons.chat_outlined, size: 10, color: cs.primary),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (buyerName.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    children: [
                      Icon(Icons.person_outline, size: 11, color: cs.secondary),
                      const SizedBox(width: 4),
                      Text(buyerName,
                          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
              const SizedBox(height: 2),
              Text('#$orderId', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant.withValues(alpha: 0.6))),
              if (date.isNotEmpty)
                Text(date, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant.withValues(alpha: 0.6))),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoChips(ColorScheme cs, double price, double? shipping, double total, String method) {
    final platformFee = (data['platformFee'] as num?)?.toDouble() ?? (data['sokoLanguCommission'] as num?)?.toDouble() ?? 0;
    final processingFee = (data['processingFee'] as num?)?.toDouble() ?? 0;
    final sellerReceives = (data['sellerReceives'] as num?)?.toDouble() ?? 0;

    final chips = <Widget>[
      _chip(cs, '${_nf(price.toInt())} TZS', Icons.sell_outlined, cs.primary),
      if (shipping != null) _chip(cs, '${_nf(shipping.toInt())} TZS', Icons.local_shipping_outlined, cs.secondary),
      _chip(cs, '${_nf(total.toInt())} TZS', Icons.receipt_outlined, cs.tertiary),
      _chip(cs, method, Icons.payment_outlined, cs.whatsappGreen),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(spacing: 6, runSpacing: 6, children: chips),
        if (platformFee > 0 || processingFee > 0 || sellerReceives > 0) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.12)),
            ),
            child: Column(
              children: [
                if (processingFee > 0)
                  _feeRow(cs, Icons.monetization_on_outlined, 'Ada ya usindikaji',
                      '${_nf(processingFee.toInt())} TZS', cs.onSurfaceVariant),
                if (platformFee > 0)
                  _feeRow(cs, Icons.percent_outlined, 'Soko Vibe commission',
                      '-${_nf(platformFee.toInt())} TZS', cs.tertiary),
                if (sellerReceives > 0) ...[
                  const Divider(height: 16),
                  _feeRow(cs, Icons.account_balance_wallet_outlined, 'Muuzaji anapokea',
                      '${_nf(sellerReceives.toInt())} TZS', cs.successGreen),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _feeRow(ColorScheme cs, IconData icon, String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 14, color: valueColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ),
          Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: valueColor)),
        ],
      ),
    );
  }

  Widget _chip(ColorScheme cs, String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.15), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context, ColorScheme cs, String status, double price, double? shipping, double total) {
    final canPay = status == 'awaiting_payment';
    final canConfirm = status == 'delivered' || status == 'dispatched';
    final canDispute = status == 'paid_escrow_held' || status == 'escrow_hold' || status == 'dispatched' || status == 'delivered';
    final canCancel = status == 'paid_escrow_held' || status == 'escrow_hold';

    return Column(
      children: [
        if (canPay)
          SizedBox(
            width: double.infinity, height: 48,
            child: ElevatedButton.icon(
              onPressed: payingTxId == docId ? null : () => onPay(docId, data),
              icon: payingTxId == docId
                  ? const GoogleLoading(size: 20, strokeWidth: 2)
                  : const Icon(Icons.payment, size: 18),
              label: Text(payingTxId == docId ? 'Inalipa...' : 'Lipa ${_nf(total)} TZS'),
              style: ElevatedButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: cs.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
            ),
          ),
        if (canConfirm)
          SizedBox(
            width: double.infinity, height: 48,
            child: ElevatedButton.icon(
              onPressed: releasingTxId == docId ? null : () => onConfirm(docId),
              icon: releasingTxId == docId
                  ? const GoogleLoading(size: 20, strokeWidth: 2)
                  : const Icon(Icons.verified, size: 18),
              label: Text(releasingTxId == docId ? 'Inathibitisha...' : context.tr('confirm_receipt')),
              style: ElevatedButton.styleFrom(
                backgroundColor: cs.successGreen,
                foregroundColor: cs.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
            ),
          ),
        if (status == 'awaiting_shipping_quote')
          SizedBox(
            width: double.infinity, height: 48,
            child: ElevatedButton.icon(
              onPressed: null,
              icon: const Icon(Icons.hourglass_empty, size: 18),
              label: const Text('Inasuburi Muuzaji'),
              style: ElevatedButton.styleFrom(
                backgroundColor: cs.surfaceContainerHighest.withValues(alpha: 0.3),
                foregroundColor: cs.onSurfaceVariant,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
            ),
          ),
        if (canDispute || canCancel)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                if (canDispute)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: disputingTxId == docId ? null : () => onDispute(docId),
                      icon: disputingTxId == docId
                      ? const GoogleLoading(size: 16, strokeWidth: 2)
                      : const Icon(Icons.gavel, size: 16),
                      label: Text('Mgogoro'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: cs.error,
                        side: BorderSide(color: cs.error.withValues(alpha: 0.3)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                if (canDispute && canCancel) const SizedBox(width: 8),
                if (canCancel)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: cancellingTxId == docId ? null : () => onCancel(docId),
                      icon: cancellingTxId == docId
                      ? const GoogleLoading(size: 16, strokeWidth: 2)
                      : const Icon(Icons.money_off, size: 16),
                      label: const Text('Ghairi'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: cs.error,
                        side: BorderSide(color: cs.error.withValues(alpha: 0.3)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildReceiptCard(ColorScheme cs, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [cs.surface.withValues(alpha: 0.2), cs.surfaceContainerLow.withValues(alpha: 0.12)]
                : [cs.primary.withValues(alpha: 0.04), cs.secondary.withValues(alpha: 0.04)],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cs.primary.withValues(alpha: 0.1), width: 0.5),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.receipt_long_rounded, color: cs.primary, size: 20),
                const SizedBox(width: 8),
                Text('Stakabadhi', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: cs.onSurface)),
                const Spacer(),
                Icon(Icons.download_rounded, color: cs.primary, size: 18),
                const SizedBox(width: 12),
                Icon(Icons.share_rounded, color: cs.primary, size: 18),
              ],
            ),
            const SizedBox(height: 12),
            _receiptRow(cs, 'Order ID', docId, cs.onSurfaceVariant),
            _receiptRow(cs, 'Jumla', '${_nf(totalAmount.toInt())} TZS', cs.primary),
            if (data['shippingCost'] != null)
              _receiptRow(cs, 'Usafirishaji', '${_nf((data['shippingCost'] as num).toInt())} TZS', cs.onSurfaceVariant),
            _receiptRow(cs, 'Malipo', paymentMethod, cs.onSurfaceVariant),
            _receiptRow(cs, 'Hali', escrowLabel(status), cs.successGreen),
          ],
        ),
      ),
    );
  }

  Widget _receiptRow(ColorScheme cs, String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: valueColor)),
        ],
      ),
    );
  }

  String _nf(num n) {
    return NumberFormat('#,###', 'en').format(n);
  }

  String get paymentMethod => data['paymentMethod'] as String? ?? 'Mongike';
  String get status => data['status'] as String? ?? 'pending';
  double get totalAmount => (data['totalAmount'] as num?)?.toDouble() ?? (data['productPrice'] as num?)?.toDouble() ?? 0;
}

class _OrderStatusTimeline extends StatelessWidget {
  final String status;
  final ColorScheme cs;

  const _OrderStatusTimeline({required this.status, required this.cs});

  @override
  Widget build(BuildContext context) {
    final steps = _buildSteps();
    final current = _currentIndex();

    return Column(
      children: List.generate(steps.length, (i) {
        final s = steps[i];
        final active = i <= current;
        final glowing = i == current;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 28, height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active ? s.color : cs.surfaceContainerHighest.withValues(alpha: 0.3),
                  boxShadow: glowing
                      ? [BoxShadow(color: s.color.withValues(alpha: 0.4), blurRadius: 12, spreadRadius: 1)]
                      : [],
                ),
                child: Icon(s.icon, size: 14, color: active ? cs.surface : cs.onSurfaceVariant.withValues(alpha: 0.4)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: glowing ? FontWeight.w700 : FontWeight.w500,
                        color: active ? cs.onSurface : cs.onSurfaceVariant.withValues(alpha: 0.5),
                      ),
                    ),
                    if (glowing && current < _totalSteps() - 1)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 600),
                        margin: const EdgeInsets.only(top: 2),
                        width: double.infinity, height: 2,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [s.color.withValues(alpha: 0.5), s.color.withValues(alpha: 0.1)],
                          ),
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  int _totalSteps() => _buildSteps().length;

  int _currentIndex() {
    switch (status) {
      case 'pending': return 0;
      case 'awaiting_shipping_quote': return 1;
      case 'awaiting_payment': return 2;
      case 'paid_escrow_held': case 'escrow_hold': return 3;
      case 'dispatched': return 4;
      case 'delivered': case 'delivery_confirmed': return 5;
      case 'completed': return 6;
      case 'refunded': return 6;
      case 'failed': case 'cancelled': return -1;
      default: return 0;
    }
  }

  List<_TimelineStep> _buildSteps() {
    return [
      _TimelineStep('Imepokelewa', Icons.access_time_rounded, cs.onSurfaceVariant),
      _TimelineStep('Gharama ya Usafirishaji', Icons.local_shipping_outlined, Colors.orange),
      _TimelineStep('Inasuburi Malipo', Icons.account_balance_wallet_outlined, Colors.blue),
      _TimelineStep('Kwenye Escrow', Icons.verified_user_outlined, Colors.purple),
      _TimelineStep('Imesafirishwa', Icons.inventory_2_outlined, cs.successGreen),
      _TimelineStep('Imethibitishwa', Icons.check_circle_outline, cs.successGreen),
      _TimelineStep('Imekamilika', Icons.check_circle_rounded, cs.successGreen),
    ];
  }
}

class _TimelineStep {
  final String label;
  final IconData icon;
  final Color color;
  const _TimelineStep(this.label, this.icon, this.color);
}
