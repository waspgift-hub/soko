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
      final existingStatus = d['status'] as String? ?? '';
      if (existingStatus == 'completed' || existingStatus == 'delivered' || existingStatus == 'delivery_confirmed') {
        _showSuccess(context.tr('order_already_paid'));
        setState(() => _payingTxId = null);
        return;
      }

      final productPrice = (d['productPrice'] as num?)?.toDouble() ?? 0;
      final shippingCost = (d['shippingCost'] as num?)?.toDouble() ?? 0;
      final productName = d['productName'] as String? ?? context.tr('product');
      final productId = d['productId'] as String? ?? '';
      final sellerId = d['sellerId'] as String? ?? '';
      final sellerName = d['sellerName'] as String? ?? '';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('preparing_payment_wait')),
          backgroundColor: Theme.of(context).colorScheme.primary,
          duration: const Duration(seconds: 2),
        ),
      );

      final result = await MongikeService.initiateMarketplacePayment(
        productPrice: productPrice, productName: productName,
        productId: productId, sellerId: sellerId, sellerName: sellerName,
        email: user.email ?? '', phone: d['buyerPhone'] as String? ?? '',
        buyerId: user.uid, deliveryType: 'local',
        shippingCost: shippingCost, existingTransactionId: txId,
      );

      if (result['order_id'] == null) {
        final errMsg = result['error'] as String? ?? context.tr('payment_initiation_failed');
        _showError(errMsg);
        setState(() => _payingTxId = null);
        return;
      }

      if (mounted) _showSuccess(context.tr('check_phone_enter_pin'));
    } catch (e) {
      _showError('${context.tr('payment_error')}: $e');
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
        title: Text(context.tr('dispute_title')),
        content: Text(context.tr('dispute_notify_admin')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('cancel'))),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text(context.tr('open'))),
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
        _showSuccess(context.tr('dispute_opened_msg'));
      } else {
        _showError(result['error'] ?? context.tr('dispute_failed'));
      }
    } catch (e) {
      _showError('${context.tr('error')}: $e');
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
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('cancel'))),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white), child: Text(context.tr('yes_cancel'))),
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
        _showSuccess(context.tr('order_cancelled_refunded'));
      } else {
        _showError(result['error'] ?? context.tr('cancel_order_failed'));
      }
    } catch (e) {
      _showError('${context.tr('error')}: $e');
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
      case 'paid_escrow_held': case 'escrow_hold': return context.tr('secured_in_escrow');
      case 'dispatched': return context.tr('dispatched_label');
      case 'delivered': case 'delivery_confirmed': case 'completed': return context.tr('delivered_and_completed');
      case 'failed': return context.tr('failed');
      case 'refunded': return context.tr('refunded');
      default: return context.tr('pending');
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
    final productName = data['productName'] as String? ?? context.tr('product');
    final price = (data['productPrice'] ?? 0).toDouble();
    final shippingCost = (data['shippingCost'] as num?)?.toDouble();
    final totalAmount = (data['totalAmount'] as num?)?.toDouble() ?? price;
    final createdAt = data['createdAt'];
    final dateStr = createdAt is Timestamp
        ? DateFormat('dd MMM yyyy HH:mm').format(createdAt.toDate())
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
                  _buildInfoChips(context, cs, price, shippingCost, totalAmount, paymentMethod),
                  const SizedBox(height: 16),
                  _buildActions(context, cs, status, price, shippingCost, totalAmount),
                  if (status == 'delivered' || status == 'delivery_confirmed' || status == 'completed')
                    _buildReceiptCard(context, cs, isDark),
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
    final productImage = data['productImage'] as String? ?? '';
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
            child: productImage.isNotEmpty
                ? Image.network(productImage, fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
                      child: Icon(Icons.image_rounded, color: cs.onSurfaceVariant.withValues(alpha: 0.3)),
                    ))
                : Container(
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
                maxLines: 2, overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.person_outline, size: 12, color: cs.secondary),
                  const SizedBox(width: 4),
                  Text(context.tr('seller') + ': ', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                  GestureDetector(
                    onTap: sellerId.isNotEmpty
                        ? () => ChatNavigation.openSellerChat(context, sellerId, sellerName)
                        : null,
                    child: Row(
                      children: [
                        Text(sellerName, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.primary)),
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
                  padding: const EdgeInsets.only(top: 3),
                  child: Row(
                    children: [
                      Icon(Icons.person, size: 12, color: cs.tertiary),
                      const SizedBox(width: 4),
                      Text(context.tr('buyer') + ': ', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                      Text(buyerName, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurface)),
                    ],
                  ),
                ),
              const SizedBox(height: 3),
              Row(
                children: [
                  Icon(Icons.tag, size: 11, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
                  const SizedBox(width: 4),
                  Text('#$orderId', style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant.withValues(alpha: 0.6))),
                  if (date.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    Icon(Icons.access_time, size: 11, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
                    const SizedBox(width: 4),
                    Text(date, style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant.withValues(alpha: 0.6))),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoChips(BuildContext context, ColorScheme cs, double price, double? shipping, double total, String method) {
    final platformFee = (data['platformFee'] as num?)?.toDouble() ?? (data['sokoLanguCommission'] as num?)?.toDouble() ?? 0;
    final processingFee = (data['processingFee'] as num?)?.toDouble() ?? 0;
    final sellerReceives = (data['sellerReceives'] as num?)?.toDouble() ?? 0;
    final buyerPhone = data['buyerPhone'] as String? ?? '';
    final sellerPhone = data['sellerPhone'] as String? ?? '';
    final deliveryAddress = data['deliveryAddress'] as Map<String, dynamic>?;
    final dispatchProof = data['dispatchProof'] as Map<String, dynamic>?;
    final buyerName = data['buyerName'] as String? ?? '';

    final chips = <Widget>[
      _chip(cs, '${_nf(price.toInt())} TZS', Icons.sell_outlined, cs.primary, context.tr('product_price')),
      if (shipping != null) _chip(cs, '${_nf(shipping.toInt())} TZS', Icons.local_shipping_outlined, cs.secondary, context.tr('shipping_label')),
      _chip(cs, '${_nf(total.toInt())} TZS', Icons.receipt_outlined, cs.tertiary, context.tr('total')),
      _chip(cs, method, Icons.payment_outlined, cs.whatsappGreen, context.tr('payment_method')),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(spacing: 6, runSpacing: 6, children: chips),
        const SizedBox(height: 14),
        // Order details section
        _detailSection(cs, context.tr('order_details'), [
          _detailRow(cs, context.tr('buyer_label'), buyerName, Icons.person_outline),
          if (buyerPhone.isNotEmpty) _detailRow(cs, context.tr('phone'), buyerPhone, Icons.phone_outlined),
          if (sellerPhone.isNotEmpty) _detailRow(cs, context.tr('seller_phone'), sellerPhone, Icons.phone_outlined),
        ]),
        // Delivery address
        if (deliveryAddress != null) ...[
          const SizedBox(height: 10),
          _detailSection(cs, context.tr('shipping_address'), [
            if (deliveryAddress['region'] != null)
              _detailRow(cs, context.tr('region'), deliveryAddress['region'] as String, Icons.location_on_outlined),
            if (deliveryAddress['district'] != null)
              _detailRow(cs, context.tr('district'), deliveryAddress['district'] as String, Icons.map_outlined),
            if (deliveryAddress['street'] != null)
              _detailRow(cs, context.tr('street'), deliveryAddress['street'] as String, Icons.signpost_outlined),
            if (deliveryAddress['landmarks'] != null)
              _detailRow(cs, context.tr('landmarks'), deliveryAddress['landmarks'] as String, Icons.landscape_outlined),
          ]),
        ],
        // Dispatch details
        if (dispatchProof != null) ...[
          const SizedBox(height: 10),
          _detailSection(cs, context.tr('shipping_details'), [
            if (dispatchProof['courierName'] != null)
              _detailRow(cs, context.tr('courier_company_name'), dispatchProof['courierName'] as String, Icons.local_shipping_outlined),
            if (dispatchProof['trackingNumber'] != null)
              _detailRow(cs, context.tr('tracking_number'), dispatchProof['trackingNumber'] as String, Icons.qr_code_outlined),
            if (dispatchProof['driverPhone'] != null)
              _detailRow(cs, context.tr('driver_phone'), dispatchProof['driverPhone'] as String, Icons.phone_outlined),
            if (dispatchProof['notes'] != null)
              _detailRow(cs, context.tr('additional_notes'), dispatchProof['notes'] as String, Icons.notes_outlined),
          ]),
        ],
        // Fee breakdown
        if (platformFee > 0 || processingFee > 0 || sellerReceives > 0) ...[
          const SizedBox(height: 10),
          _detailSection(cs, context.tr('payment_breakdown'), [
            if (platformFee > 0)
              _detailRow(cs, context.tr('soko_commission'), '-${_nf(platformFee.toInt())} TZS', Icons.percent_outlined, valueColor: cs.tertiary),
            if (processingFee > 0)
              _detailRow(cs, context.tr('processing_fee'), '${_nf(processingFee.toInt())} TZS', Icons.monetization_on_outlined, valueColor: cs.onSurfaceVariant),
            if (sellerReceives > 0) ...[
              const SizedBox(height: 4),
              Container(height: 1, color: cs.outlineVariant.withValues(alpha: 0.2)),
              const SizedBox(height: 4),
              _detailRow(cs, context.tr('seller_receives'), '${_nf(sellerReceives.toInt())} TZS', Icons.account_balance_wallet_outlined, valueColor: cs.successGreen),
            ],
          ]),
        ],
      ],
    );
  }

  Widget _detailSection(ColorScheme cs, String title, List<Widget> rows) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cs.primary, letterSpacing: 0.5)),
          const SizedBox(height: 10),
          ...rows,
        ],
      ),
    );
  }

  Widget _detailRow(ColorScheme cs, String label, String value, IconData icon, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
          const SizedBox(width: 8),
          SizedBox(width: 80, child: Text(label, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant))),
          Expanded(
            child: Text(value, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: valueColor ?? cs.onSurface)),
          ),
        ],
      ),
    );
  }

  Widget _chip(ColorScheme cs, String label, IconData icon, Color color, String tooltip) {
    return Tooltip(
      message: tooltip,
      child: Container(
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
              label: Text(payingTxId == docId ? context.tr('paying_label') : context.tr('pay_amount_tzs').replaceAll('{0}', _nf(total))),
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
              label: Text(releasingTxId == docId ? context.tr('confirming_label') : context.tr('confirm_receipt')),
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
              label: Text(context.tr('waiting_for_seller_label')),
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
                      label: Text(context.tr('dispute_button')),
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
                      label: Text(context.tr('cancel')),
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

  Widget _buildReceiptCard(BuildContext context, ColorScheme cs, bool isDark) {
    final status = data['status'] as String? ?? 'pending';
    final paymentMethod = data['paymentMethod'] as String? ?? 'Mongike';
    final productPrice = (data['productPrice'] as num?)?.toDouble() ?? 0;
    final shippingCost = (data['shippingCost'] as num?)?.toDouble() ?? 0;
    final mongikeFee = (data['processingFee'] as num?)?.toDouble() ?? 0;
    final totalAmount = (data['totalAmount'] as num?)?.toDouble() ?? productPrice;
    final buyerName = data['buyerName'] as String? ?? '';
    final buyerPhone = data['buyerPhone'] as String? ?? '';
    final createdAt = data['createdAt'];
    final dateStr = createdAt is Timestamp
        ? DateFormat('dd/MM/yyyy HH:mm').format(createdAt.toDate())
        : '';

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [cs.surface.withValues(alpha: 0.2), cs.surfaceContainerLow.withValues(alpha: 0.12)]
                : [cs.primary.withValues(alpha: 0.04), cs.secondary.withValues(alpha: 0.04)],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: cs.primary.withValues(alpha: 0.1), width: 0.5),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.receipt_long_rounded, color: cs.primary, size: 22),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.tr('purchase_receipt'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: cs.onSurface)),
                    const SizedBox(height: 2),
                    Text('#$docId', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                  ],
                ),
                const Spacer(),
                Icon(Icons.download_rounded, color: cs.primary, size: 20),
                const SizedBox(width: 14),
                Icon(Icons.share_rounded, color: cs.primary, size: 20),
              ],
            ),
            const SizedBox(height: 16),
            Container(height: 1, color: cs.outlineVariant.withValues(alpha: 0.2)),
            const SizedBox(height: 16),
            _receiptRow(cs, context.tr('receipt_date'), dateStr, cs.onSurfaceVariant),
            _receiptRow(cs, context.tr('product_price'), '${_nf(productPrice.toInt())} TZS', cs.onSurfaceVariant),
            if (shippingCost > 0)
              _receiptRow(cs, context.tr('shipping_cost'), '${_nf(shippingCost.toInt())} TZS', cs.secondary),
            if (mongikeFee > 0)
              _receiptRow(cs, context.tr('mongike_fee_label'), '${_nf(mongikeFee.toInt())} TZS', cs.tertiary),
            Container(height: 1, color: cs.outlineVariant.withValues(alpha: 0.15), margin: const EdgeInsets.symmetric(vertical: 6)),
            _receiptRow(cs, context.tr('receipt_total'), '${_nf(totalAmount.toInt())} TZS', cs.primary),
            const SizedBox(height: 12),
            if (buyerName.isNotEmpty)
              _receiptRow(cs, context.tr('buyer_label'), buyerName, cs.onSurfaceVariant),
            if (buyerPhone.isNotEmpty)
              _receiptRow(cs, context.tr('phone'), buyerPhone, cs.onSurfaceVariant),
            _receiptRow(cs, context.tr('payment_method'), paymentMethod, cs.onSurfaceVariant),
            _receiptRow(cs, context.tr('order_status'), escrowLabel(status), _statusColor(status, cs)),
          ],
        ),
      ),
    );
  }

  Color _statusColor(String status, ColorScheme cs) {
    switch (status) {
      case 'completed': case 'delivered': case 'delivery_confirmed': return cs.successGreen;
      case 'paid_escrow_held': case 'escrow_hold': return Colors.purple;
      case 'dispatched': return Colors.orange;
      case 'failed': case 'cancelled': case 'refunded': return cs.error;
      default: return cs.onSurfaceVariant;
    }
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
    final steps = _buildSteps(context);
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
                    if (glowing && current < _totalSteps(context) - 1)
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

  int _totalSteps(BuildContext context) => _buildSteps(context).length;

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

  List<_TimelineStep> _buildSteps(BuildContext context) {
    return [
      _TimelineStep(context.tr('step_received'), Icons.access_time_rounded, cs.onSurfaceVariant),
      _TimelineStep(context.tr('step_shipping_quote'), Icons.local_shipping_outlined, Colors.orange),
      _TimelineStep(context.tr('waiting_payment'), Icons.account_balance_wallet_outlined, Colors.blue),
      _TimelineStep(context.tr('step_in_escrow'), Icons.verified_user_outlined, Colors.purple),
      _TimelineStep(context.tr('shipped'), Icons.inventory_2_outlined, cs.successGreen),
      _TimelineStep(context.tr('confirmed'), Icons.check_circle_outline, cs.successGreen),
      _TimelineStep(context.tr('completed'), Icons.check_circle_rounded, cs.successGreen),
    ];
  }
}

class _TimelineStep {
  final String label;
  final IconData icon;
  final Color color;
  const _TimelineStep(this.label, this.icon, this.color);
}
