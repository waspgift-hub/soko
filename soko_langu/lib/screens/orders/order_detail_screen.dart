import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import '../../extensions/context_tr.dart';
import '../../services/api_config.dart';
import '../../services/mongike_service.dart';
import '../../services/sms_notification_service.dart';
import '../../app/routes.dart';
import '../../theme/app_colors.dart';
import '../chat/chat_navigation.dart';
import '../../widgets/google_loading.dart';
import 'receipt_screen.dart';

class OrderDetailScreen extends StatefulWidget {
  final String docId;
  final Map<String, dynamic> data;

  const OrderDetailScreen({super.key, required this.docId, required this.data});

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;
  String? _releasingTxId;
  String? _disputingTxId;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Map<String, dynamic> get d => widget.data;
  String get status => d['status'] as String? ?? 'pending';

  String _nf(num n) => NumberFormat('#,###', 'en').format(n);

  int _currentStep() {
    switch (status) {
      case 'pending': return 0;
      case 'awaiting_shipping_quote': return 1;
      case 'awaiting_payment': return 2;
      case 'paid_escrow_hold': case 'escrow_hold': return 3;
      case 'dispatched': return 4;
      case 'delivered': case 'delivery_confirmed': return 5;
      case 'completed': return 6;
      default: return 0;
    }
  }

  Color _statusColor(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    switch (status) {
      case 'completed': case 'delivered': case 'delivery_confirmed': return cs.successGreen;
      case 'paid_escrow_hold': case 'escrow_hold': return Colors.purple;
      case 'dispatched': return Colors.orange;
      case 'failed': case 'cancelled': case 'refunded': return cs.error;
      default: return cs.primary;
    }
  }

  String _statusLabel(BuildContext context) {
    switch (status) {
      case 'paid_escrow_hold': case 'escrow_hold': return context.tr('secured_in_escrow');
      case 'dispatched': return context.tr('dispatched_label');
      case 'delivered': case 'delivery_confirmed': case 'completed': return context.tr('delivered_and_completed');
      case 'failed': return context.tr('failed');
      case 'refunded': return context.tr('refunded');
      case 'cancelled': return context.tr('cancelled');
      default: return context.tr('pending');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final productName = d['productName'] as String? ?? context.tr('product');
    final productImage = d['productImage'] as String? ?? '';
    final sellerName = d['sellerName'] as String? ?? '';
    final sellerId = d['sellerId'] as String? ?? '';
    final createdAt = d['createdAt'];
    final dateStr = createdAt is Timestamp
        ? DateFormat('dd MMM yyyy HH:mm').format(createdAt.toDate())
        : '';
    final price = (d['productPrice'] ?? 0).toDouble();
    final shippingCost = (d['shippingCost'] as num?)?.toDouble();
    final totalAmount = (d['totalAmount'] as num?)?.toDouble() ?? price;
    final paymentMethod = d['paymentMethod'] as String? ?? 'Mongike';
    final buyerName = d['buyerName'] as String? ?? '';
    final buyerPhone = d['buyerPhone'] as String? ?? '';
    final sellerPhone = d['sellerPhone'] as String? ?? '';
    final deliveryAddress = d['deliveryAddress'] as Map<String, dynamic>?;
    final dispatchProof = d['dispatchProof'] as Map<String, dynamic>?;
    final platformFee = (d['platformFee'] as num?)?.toDouble() ?? (d['sokoLanguCommission'] as num?)?.toDouble() ?? 0;
    final processingFee = (d['processingFee'] as num?)?.toDouble() ?? 0;
    final sellerReceives = (d['sellerReceives'] as num?)?.toDouble() ?? 0;
    final productId = d['productId'] as String? ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('order_details')),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                _buildProductCard(context, cs, isDark, productName, productImage, sellerName, sellerId, dateStr),
                const SizedBox(height: 20),
                _buildTimeline(context, cs),
                const SizedBox(height: 20),
                _buildPaymentSummary(context, cs, price, shippingCost, totalAmount, paymentMethod, platformFee, processingFee),
                const SizedBox(height: 20),
                _buildOrderInfo(context, cs, buyerName, buyerPhone, paymentMethod),
                if (deliveryAddress != null) ...[
                  const SizedBox(height: 20),
                  _buildAddressCard(context, cs, isDark, deliveryAddress),
                ],
                if (dispatchProof != null) ...[
                  const SizedBox(height: 20),
                  _buildDispatchInfo(context, cs, dispatchProof),
                ],
                const SizedBox(height: 20),
                if (platformFee > 0 || processingFee > 0 || sellerReceives > 0)
                  _buildFeeBreakdown(context, cs, platformFee, processingFee, sellerReceives),
                const SizedBox(height: 20),
                _buildActions(context, cs),
                const SizedBox(height: 80),
              ],
            ),
          ),
          _buildBottomBar(context, cs, sellerId, sellerName),
        ],
      ),
    );
  }

  // ── Product Card ──
  Widget _buildProductCard(BuildContext context, ColorScheme cs, bool isDark, String name, String image, String sellerName, String sellerId, String date) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 40, sigmaY: 40),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [cs.surface.withValues(alpha: 0.2), cs.surfaceContainerLow.withValues(alpha: 0.12)]
                  : [Colors.white.withValues(alpha: 0.9), Colors.white.withValues(alpha: 0.75)],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: isDark ? 0.15 : 0.2), width: 0.5),
            boxShadow: [
              BoxShadow(color: cs.primary.withValues(alpha: 0.06), blurRadius: 40, offset: const Offset(0, 12)),
            ],
          ),
          child: Column(
            children: [
              if (image.isNotEmpty)
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                child: Image.network(image, width: double.infinity, height: 220, fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(height: 220, color: cs.surfaceContainerHighest,
                    child: Icon(Icons.image_rounded, size: 48, color: cs.onSurfaceVariant.withValues(alpha: 0.3))),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(name, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: cs.onSurface),
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        ),
                        const SizedBox(width: 12),
                        _buildStatusBadge(context),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: cs.primary.withValues(alpha: 0.12),
                          child: Text(sellerName.isNotEmpty ? sellerName[0].toUpperCase() : '?',
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: cs.primary)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(sellerName, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: cs.onSurface)),
                              Text(context.tr('seller'), style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                            ],
                          ),
                        ),
                        if (sellerId.isNotEmpty)
                          Container(
                            decoration: BoxDecoration(color: cs.whatsappGreen.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: () => ChatNavigation.openSellerChat(context, sellerId, sellerName),
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  child: Icon(Icons.chat_outlined, size: 18, color: Color(0xFF25D366)),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(Icons.tag, size: 13, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
                        const SizedBox(width: 4),
                        Text('#${widget.docId}', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant.withValues(alpha: 0.6))),
                        const SizedBox(width: 16),
                        Icon(Icons.access_time, size: 13, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
                        const SizedBox(width: 4),
                        Text(date, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant.withValues(alpha: 0.6))),
                      ],
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

  Widget _buildStatusBadge(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = _statusColor(context);
    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (context, child) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: _pulseAnim.value * 0.2),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: _pulseAnim.value * 0.4), width: 1),
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: _pulseAnim.value * 0.15), blurRadius: 12, spreadRadius: 1),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 4)])),
            const SizedBox(width: 6),
            Text(_statusLabel(context), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
          ],
        ),
      ),
    );
  }

  // ── Animated Timeline ──
  Widget _buildTimeline(BuildContext context, ColorScheme cs) {
    final steps = [
      _TimelineStepData(context.tr('step_received'), Icons.access_time_rounded, cs.onSurfaceVariant),
      _TimelineStepData(context.tr('step_shipping_quote'), Icons.local_shipping_outlined, Colors.orange),
      _TimelineStepData(context.tr('waiting_payment'), Icons.account_balance_wallet_outlined, Colors.blue),
      _TimelineStepData(context.tr('step_in_escrow'), Icons.verified_user_outlined, Colors.purple),
      _TimelineStepData(context.tr('shipped'), Icons.inventory_2_outlined, cs.successGreen),
      _TimelineStepData(context.tr('confirmed'), Icons.check_circle_outline, cs.successGreen),
      _TimelineStepData(context.tr('completed'), Icons.check_circle_rounded, cs.successGreen),
    ];
    final current = _currentStep();

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 40, sigmaY: 40),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                cs.surface.withValues(alpha: 0.15), cs.surfaceContainerLow.withValues(alpha: 0.08),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                    child: Icon(Icons.timeline_rounded, size: 16, color: cs.primary),
                  ),
                  const SizedBox(width: 10),
                  Text(context.tr('order_status'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: cs.onSurface)),
                ],
              ),
              const SizedBox(height: 20),
              ...List.generate(steps.length, (i) {
                final step = steps[i];
                final active = i <= current;
                final isCurrent = i == current;
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 32,
                        child: Column(
                          children: [
                            AnimatedBuilder(
                              animation: _pulseAnim,
                              builder: (context, _) => Container(
                                width: isCurrent ? 28 : 24,
                                height: isCurrent ? 28 : 24,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: active ? step.color : cs.surfaceContainerHighest.withValues(alpha: 0.3),
                                  boxShadow: isCurrent
                                      ? [BoxShadow(color: step.color.withValues(alpha: _pulseAnim.value * 0.5), blurRadius: 12, spreadRadius: 2)]
                                      : active
                                          ? [BoxShadow(color: step.color.withValues(alpha: 0.2), blurRadius: 6)]
                                          : [],
                                ),
                                child: Icon(
                                  active ? Icons.check_rounded : Icons.circle_outlined,
                                  size: isCurrent ? 14 : 12,
                                  color: active ? cs.surface : cs.onSurfaceVariant.withValues(alpha: 0.4),
                                ),
                              ),
                            ),
                            if (i < steps.length - 1)
                              Expanded(
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 400),
                                  width: 2,
                                  margin: const EdgeInsets.symmetric(vertical: 4),
                                  decoration: BoxDecoration(
                                    gradient: active
                                        ? LinearGradient(
                                            colors: [step.color.withValues(alpha: 0.6), steps[i + 1].color.withValues(alpha: i + 1 <= current ? 0.6 : 0.1)],
                                          )
                                        : null,
                                    color: !active ? cs.outlineVariant.withValues(alpha: 0.15) : null,
                                    borderRadius: BorderRadius.circular(1),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(bottom: i < steps.length - 1 ? 20 : 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Text(step.label,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                                    color: active ? cs.onSurface : cs.onSurfaceVariant.withValues(alpha: 0.4),
                                  ),
                                ),
                              ),
                              if (isCurrent)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: AnimatedBuilder(
                                    animation: _pulseAnim,
                                    builder: (context, _) => Container(
                                      height: 2,
                                      width: 60 * _pulseAnim.value,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [step.color.withValues(alpha: 0.6), step.color.withValues(alpha: 0.05)],
                                        ),
                                        borderRadius: BorderRadius.circular(1),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  // ── Payment Summary ──
  Widget _buildPaymentSummary(BuildContext context, ColorScheme cs, double price, double? shipping, double total, String method, double platformFee, double processingFee) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 40, sigmaY: 40),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                cs.surface.withValues(alpha: 0.15), cs.surfaceContainerLow.withValues(alpha: 0.08),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                    child: Icon(Icons.receipt_outlined, size: 16, color: cs.primary),
                  ),
                  const SizedBox(width: 10),
                  Text(context.tr('payment_summary'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: cs.onSurface)),
                ],
              ),
              const SizedBox(height: 16),
              _summaryRow(cs, context.tr('product_price'), '${_nf(price.toInt())} TZS', cs.onSurface),
              if (shipping != null && shipping > 0) ...[
                const SizedBox(height: 10),
                _summaryRow(cs, context.tr('shipping_cost'), '${_nf(shipping.toInt())} TZS', cs.secondary),
              ],
              if (platformFee > 0) ...[
                const SizedBox(height: 10),
                _summaryRow(cs, context.tr('soko_commission'), '-${_nf(platformFee.toInt())} TZS', cs.tertiary),
              ],
              if (processingFee > 0) ...[
                const SizedBox(height: 10),
                _summaryRow(cs, context.tr('processing_fee'), '${_nf(processingFee.toInt())} TZS', cs.onSurfaceVariant),
              ],
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(height: 1, thickness: 1),
              ),
              _summaryRow(cs, context.tr('total'), '${_nf(total.toInt())} TZS', cs.primary, bold: true),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: cs.whatsappGreen.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.whatsappGreen.withValues(alpha: 0.15)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.payment, size: 14, color: cs.whatsappGreen),
                    const SizedBox(width: 6),
                    Text(method, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.whatsappGreen)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summaryRow(ColorScheme cs, String label, String value, Color valueColor, {bool bold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant, fontWeight: bold ? FontWeight.w600 : FontWeight.w400)),
        Text(value, style: TextStyle(fontSize: 15, fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: valueColor)),
      ],
    );
  }

  // ── Order Information ──
  Widget _buildOrderInfo(BuildContext context, ColorScheme cs, String buyerName, String buyerPhone, String method) {
    final info = <_InfoRowData>[
      _InfoRowData(Icons.person_outline, context.tr('buyer_label'), buyerName, null),
      if (buyerPhone.isNotEmpty) _InfoRowData(Icons.phone_outlined, context.tr('phone'), buyerPhone, Icons.copy_rounded),
      _InfoRowData(Icons.payment_outlined, context.tr('payment_method'), method, null),
      _InfoRowData(Icons.tag, context.tr('order_id'), '#${widget.docId}', Icons.copy_rounded),
    ];

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 40, sigmaY: 40),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [cs.surface.withValues(alpha: 0.15), cs.surfaceContainerLow.withValues(alpha: 0.08)],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                    child: Icon(Icons.info_outline_rounded, size: 16, color: cs.primary),
                  ),
                  const SizedBox(width: 10),
                  Text(context.tr('order_information'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: cs.onSurface)),
                ],
              ),
              const SizedBox(height: 16),
              ...info.map((row) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(row.icon, size: 16, color: cs.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(row.label, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                          const SizedBox(height: 2),
                          Text(row.value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
                        ],
                      ),
                    ),
                    if (row.actionIcon != null)
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () {
                            final text = row == info.last ? widget.docId : buyerPhone;
                            if (text.isNotEmpty) {
                              // Copy to clipboard
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(context.tr('copied_to_clipboard')), duration: const Duration(seconds: 1)),
                              );
                            }
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Icon(row.actionIcon, size: 16, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
                          ),
                        ),
                      ),
                  ],
                ),
              )),
            ],
          ),
        ),
      ),
    );
  }

  // ── Shipping Address ──
  Widget _buildAddressCard(BuildContext context, ColorScheme cs, bool isDark, Map<String, dynamic> address) {
    final region = address['region'] as String?;
    final district = address['district'] as String?;
    final street = address['street'] as String?;
    final landmarks = address['landmarks'] as String?;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 40, sigmaY: 40),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [cs.surface.withValues(alpha: 0.15), cs.surfaceContainerLow.withValues(alpha: 0.08)],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                    child: Icon(Icons.location_on_rounded, size: 16, color: cs.primary),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(context.tr('shipping_address'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: cs.onSurface)),
                  ),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(context.tr('feature_coming_soon'))),
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.map_outlined, size: 14, color: cs.primary),
                            const SizedBox(width: 4),
                            Text(context.tr('view_map'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.primary)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (region != null) _addressRow(cs, Icons.location_city_outlined, context.tr('region'), region),
              if (district != null) _addressRow(cs, Icons.map_outlined, context.tr('district'), district),
              if (street != null) _addressRow(cs, Icons.signpost_outlined, context.tr('street'), street),
              if (landmarks != null) _addressRow(cs, Icons.landscape_outlined, context.tr('landmarks'), landmarks),
            ],
          ),
        ),
      ),
    );
  }

  Widget _addressRow(ColorScheme cs, IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 14, color: cs.primary.withValues(alpha: 0.7)),
          ),
          const SizedBox(width: 10),
          SizedBox(width: 80, child: Text(label, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant))),
          Expanded(child: Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface))),
        ],
      ),
    );
  }

  // ── Dispatch Info ──
  Widget _buildDispatchInfo(BuildContext context, ColorScheme cs, Map<String, dynamic> dispatch) {
    final courier = dispatch['courierName'] as String?;
    final tracking = dispatch['trackingNumber'] as String?;
    final driverPhone = dispatch['driverPhone'] as String?;
    final notes = dispatch['notes'] as String?;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 40, sigmaY: 40),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [cs.surface.withValues(alpha: 0.15), cs.surfaceContainerLow.withValues(alpha: 0.08)],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.local_shipping_outlined, size: 16, color: Colors.orange),
                  ),
                  const SizedBox(width: 10),
                  Text(context.tr('shipping_details'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: cs.onSurface)),
                ],
              ),
              const SizedBox(height: 16),
              if (courier != null) _addressRow(cs, Icons.business_outlined, context.tr('courier_company_name'), courier),
              if (tracking != null) _addressRow(cs, Icons.qr_code_outlined, context.tr('tracking_number'), tracking),
              if (driverPhone != null) _addressRow(cs, Icons.phone_outlined, context.tr('driver_phone'), driverPhone),
              if (notes != null) _addressRow(cs, Icons.notes_outlined, context.tr('additional_notes'), notes),
            ],
          ),
        ),
      ),
    );
  }

  // ── Fee Breakdown ──
  Widget _buildFeeBreakdown(BuildContext context, ColorScheme cs, double platformFee, double processingFee, double sellerReceives) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 40, sigmaY: 40),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [cs.surface.withValues(alpha: 0.15), cs.surfaceContainerLow.withValues(alpha: 0.08)],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: cs.tertiary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                    child: Icon(Icons.account_balance_wallet_outlined, size: 16, color: cs.tertiary),
                  ),
                  const SizedBox(width: 10),
                  Text(context.tr('payment_breakdown'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: cs.onSurface)),
                ],
              ),
              const SizedBox(height: 16),
              _summaryRow(cs, context.tr('soko_commission'), '-${_nf(platformFee.toInt())} TZS', cs.tertiary),
              const SizedBox(height: 10),
              _summaryRow(cs, context.tr('processing_fee'), '${_nf(processingFee.toInt())} TZS', cs.onSurfaceVariant),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(height: 1, thickness: 1),
              ),
              _summaryRow(cs, context.tr('seller_receives'), '${_nf(sellerReceives.toInt())} TZS', cs.successGreen, bold: true),
            ],
          ),
        ),
      ),
    );
  }

  // ── Actions ──
  Widget _buildActions(BuildContext context, ColorScheme cs) {
    final canConfirm = status == 'delivered' || status == 'dispatched';
    final canDispute = status == 'paid_escrow_hold' || status == 'escrow_hold' || status == 'dispatched' || status == 'delivered';
    final canCancel = status == 'paid_escrow_hold' || status == 'escrow_hold';
    final user = FirebaseAuth.instance.currentUser;

    if (!canConfirm && !canDispute && !canCancel) return const SizedBox.shrink();

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 40, sigmaY: 40),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [cs.surface.withValues(alpha: 0.15), cs.surfaceContainerLow.withValues(alpha: 0.08)],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.1)),
          ),
          child: Column(
            children: [
              if (canConfirm)
                SizedBox(
                  width: double.infinity, height: 50,
                  child: ElevatedButton.icon(
                    onPressed: _releasingTxId == widget.docId ? null : () => _confirmDelivery(widget.docId),
                    icon: _releasingTxId == widget.docId
                        ? const GoogleLoading(size: 20, strokeWidth: 2)
                        : const Icon(Icons.verified, size: 20),
                    label: Text(_releasingTxId == widget.docId ? context.tr('confirming_label') : context.tr('confirm_receipt')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cs.successGreen,
                      foregroundColor: cs.surface,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                  ),
                ),
              if (canDispute || canCancel) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (canDispute)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _disputingTxId == widget.docId ? null : () => _raiseDispute(widget.docId),
                          icon: _disputingTxId == widget.docId
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
                    if (canDispute && canCancel) const SizedBox(width: 10),
                    if (canCancel)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _cancelOrder(widget.docId),
                          icon: const Icon(Icons.money_off, size: 16),
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
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Bottom Bar ──
  Widget _buildBottomBar(BuildContext context, ColorScheme cs, String sellerId, String sellerName) {
    return Container(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.15))),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            cs.surface.withValues(alpha: 0.95),
            cs.surface,
          ],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cs.whatsappGreen,
                    foregroundColor: cs.surface,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.chat_outlined, size: 18),
                  onPressed: sellerId.isNotEmpty
                      ? () => ChatNavigation.openSellerChat(context, sellerId, sellerName)
                      : null,
                  label: Text(context.tr('contact_seller'), style: const TextStyle(fontSize: 13)),
                ),
              ),
            ),
            if (status == 'dispatched') ...[
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cs.primary,
                      foregroundColor: cs.surface,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.track_changes_outlined, size: 18),
                    onPressed: () {},
                    label: Text(context.tr('track_shipment'), style: const TextStyle(fontSize: 13)),
                  ),
                ),
              ),
            ],
            const SizedBox(width: 8),
            SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: cs.primary,
                  side: BorderSide(color: cs.primary.withValues(alpha: 0.3)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                icon: const Icon(Icons.download_rounded, size: 18),
                onPressed: () => context.push('${AppRoutes.receipt}/${widget.docId}'),
                label: const Text('PDF', style: TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Action Handlers ──
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
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('delivery_confirmed_msg'))));
        final txDoc = await FirebaseFirestore.instance.collection('transactions').doc(txId).get();
        if (txDoc.exists) {
          final tx = txDoc.data()!;
          final sid = tx['sellerId'] as String? ?? '';
          final grandTotal = ((tx['totalAmount'] as num?)?.toDouble() ?? 0);
          if (sid.isNotEmpty) {
            final sDoc = await FirebaseFirestore.instance.collection('users').doc(sid).get();
            final sPhone = sDoc.data()?['phone'] as String?;
            if (sPhone != null && sPhone.isNotEmpty) {
              SmsNotificationService.notifyEscrowReleased(sellerPhone: sPhone, grandTotal: grandTotal.toStringAsFixed(0), orderId: txId);
            }
          }
        }
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['error'] ?? context.tr('confirm_failed_msg'))));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${context.tr('confirm_failed_msg')}: $e')));
    }
    if (mounted) setState(() => _releasingTxId = null);
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
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('dispute_opened_msg'))));
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['error'] ?? context.tr('dispute_failed'))));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${context.tr('error')}: $e')));
    }
    if (mounted) setState(() => _disputingTxId = null);
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
    try {
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/escrow/cancel'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'orderId': txId, 'userId': user.uid}),
      );
      final result = jsonDecode(resp.body);
      if (resp.statusCode == 200 && result['success'] == true) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('order_cancelled_refunded'))));
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['error'] ?? context.tr('cancel_order_failed'))));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${context.tr('error')}: $e')));
    }
  }
}

class _TimelineStepData {
  final String label;
  final IconData icon;
  final Color color;
  const _TimelineStepData(this.label, this.icon, this.color);
}

class _InfoRowData {
  final IconData icon;
  final String label;
  final String value;
  final IconData? actionIcon;
  const _InfoRowData(this.icon, this.label, this.value, this.actionIcon);
}