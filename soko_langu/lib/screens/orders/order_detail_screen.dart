import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import '../../extensions/context_tr.dart';
import '../../services/api_config.dart';
import '../../services/sms_notification_service.dart';
import '../../app/routes.dart';
import '../../theme/app_colors.dart';
import '../chat/chat_navigation.dart';
import '../../widgets/google_loading.dart';
import 'package:cached_network_image/cached_network_image.dart';

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
  late AnimationController _slideController;
  late Animation<Offset> _slideAnim;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnim;
  Timer? _countdownTimer;
  Duration? _remaining;
  bool _isLoading = true;
  String? _releasingTxId;
  String? _disputingTxId;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _slideController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
    );
    _fadeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);

    _startCountdown();
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) {
        setState(() => _isLoading = false);
        _slideController.forward();
        _fadeController.forward();
      }
    });
  }

  void _startCountdown() {
    final est = d['estimatedDelivery'] as Timestamp?;
    if (est != null) {
      _updateRemaining(est);
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) => _updateRemaining(est));
    }
  }

  void _updateRemaining(Timestamp est) {
    final diff = est.toDate().difference(DateTime.now());
    if (mounted) setState(() => _remaining = diff.isNegative ? Duration.zero : diff);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _slideController.dispose();
    _fadeController.dispose();
    _countdownTimer?.cancel();
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

  String _formatCountdown(Duration d) {
    if (d.isNegative || d == Duration.zero) return '—';
    final days = d.inDays;
    final hours = d.inHours.remainder(24);
    final mins = d.inMinutes.remainder(60);
    if (days > 0) return '${days}d ${hours}h ${mins}m';
    if (hours > 0) return '${hours}h ${mins}m';
    return '${mins}m';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isLoading) return _buildLoadingSkeleton(context, cs, isDark);

    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(
        position: _slideAnim,
        child: Scaffold(
          appBar: AppBar(
            title: Text(context.tr('order_details')),
            centerTitle: true,
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_new_rounded, size: 18),
              onPressed: () => context.pop(),
            ),
          ),
          extendBodyBehindAppBar: true,
          body: Stack(
            children: [
              _buildBackgroundGradient(cs, isDark),
              Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      children: [
                        _buildProductCard(context, cs, isDark),
                        const SizedBox(height: 20),
                        _buildTimeline(context, cs),
                        const SizedBox(height: 20),
                        _buildPaymentSummary(context, cs),
                        const SizedBox(height: 20),
                        _buildOrderInfo(context, cs),
                        if (d['deliveryAddress'] != null) ...[
                          const SizedBox(height: 20),
                          _buildAddressCard(context, cs, isDark),
                        ],
                        if (d['dispatchProof'] != null) ...[
                          const SizedBox(height: 20),
                          _buildDispatchInfo(context, cs),
                        ],
                        const SizedBox(height: 20),
                        _buildFeeBreakdown(context, cs),
                        const SizedBox(height: 20),
                        _buildActions(context, cs),
                        const SizedBox(height: 80),
                      ],
                    ),
                  ),
                  _buildBottomBar(context, cs),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBackgroundGradient(ColorScheme cs, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? [cs.surface, cs.surfaceContainerLow.withValues(alpha: 0.5)]
              : [const Color(0xFFF8F9FE), Colors.white],
        ),
      ),
    );
  }

  Widget _buildLoadingSkeleton(BuildContext context, ColorScheme cs, bool isDark) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('order_details')),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _skeletonCard(cs, 320),
          const SizedBox(height: 20),
          _skeletonCard(cs, 260),
          const SizedBox(height: 20),
          _skeletonCard(cs, 200),
          const SizedBox(height: 20),
          _skeletonCard(cs, 180),
        ],
      ),
    );
  }

  Widget _skeletonCard(ColorScheme cs, double h) {
    return Container(
      height: h,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(24),
      ),
      child: const Center(child: GoogleLoading(size: 32, strokeWidth: 3)),
    );
  }

  Widget _glassContainer({
    required Widget child,
    required ColorScheme cs,
    EdgeInsets padding = const EdgeInsets.all(20),
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 40, sigmaY: 40),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                cs.surface.withValues(alpha: 0.15),
                cs.surfaceContainerLow.withValues(alpha: 0.08),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.1)),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _sectionHeader(ColorScheme cs, IconData icon, String label, {Widget? trailing}) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: cs.primary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: cs.onSurface)),
        ),
        ?trailing,
      ],
    );
  }

  // ── Product Card ──
  Widget _buildProductCard(BuildContext context, ColorScheme cs, bool isDark) {
    final productName = d['productName'] as String? ?? context.tr('product');
    final productImage = d['productImage'] as String? ?? '';
    final sellerName = d['sellerName'] as String? ?? '';
    final sellerId = d['sellerId'] as String? ?? '';
    final sellerAvatar = d['sellerAvatar'] as String? ?? '';
    final createdAt = d['createdAt'];
    final dateStr = createdAt is Timestamp
        ? DateFormat('dd MMM yyyy HH:mm').format(createdAt.toDate())
        : '';

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
              if (productImage.isNotEmpty)
                Hero(
                  tag: 'order_img_${widget.docId}',
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                    child: Stack(
                      children: [
                        CachedNetworkImage(imageUrl: productImage,
                          width: double.infinity, height: 220, fit: BoxFit.cover,
                          errorWidget: (_, _, _) => Container(height: 220, color: cs.surfaceContainerHighest,
                            child: Icon(Icons.image_rounded, size: 48, color: cs.onSurfaceVariant.withValues(alpha: 0.3))),
                        ),
                        Positioned(
                          bottom: 0, left: 0, right: 0,
                          child: Container(
                            height: 60,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [Colors.black.withValues(alpha: 0.4), Colors.transparent],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
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
                          child: Text(productName, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: cs.onSurface),
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
                          backgroundImage: sellerAvatar.isNotEmpty ? NetworkImage(sellerAvatar) : null,
                          backgroundColor: cs.primary.withValues(alpha: 0.12),
                          child: sellerAvatar.isEmpty && sellerName.isNotEmpty
                              ? Text(sellerName[0].toUpperCase(),
                                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: cs.primary))
                              : null,
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
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: () => ChatNavigation.openSellerChat(context, sellerId, sellerName),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: cs.whatsappGreen.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.chat_outlined, size: 14, color: cs.whatsappGreen),
                                    const SizedBox(width: 4),
                                    Text(context.tr('chat'), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.whatsappGreen)),
                                  ],
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
                        Flexible(
                          child: Text('#${widget.docId.length > 12 ? widget.docId.substring(0, 12) : widget.docId}',
                            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant.withValues(alpha: 0.6))),
                        ),
                        const SizedBox(width: 16),
                        Icon(Icons.access_time, size: 13, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
                        const SizedBox(width: 4),
                        Text(dateStr, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant.withValues(alpha: 0.6))),
                      ],
                    ),
                    if (_remaining != null && !_remaining!.isNegative && _remaining!.inSeconds > 0) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.orange.withValues(alpha: 0.15)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.timer_outlined, size: 13, color: Colors.orange),
                            const SizedBox(width: 5),
                            Text('${context.tr('delivery_countdown')}: ${_formatCountdown(_remaining!)}',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.orange)),
                          ],
                        ),
                      ),
                    ],
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
            Container(
              width: 6, height: 6,
              decoration: BoxDecoration(
                color: color, shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 4)],
              ),
            ),
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

    return _glassContainer(
      cs: cs,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(cs, Icons.timeline_rounded, context.tr('order_status')),
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
                          builder: (context, _) {
                            final size = isCurrent ? 28.0 : 24.0;
                            return Container(
                              width: size, height: size,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: active ? step.color : cs.surfaceContainerHighest.withValues(alpha: 0.3),
                                border: isCurrent ? Border.all(color: step.color.withValues(alpha: 0.5), width: 2) : null,
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
                            );
                          },
                        ),
                        if (i < steps.length - 1)
                          Expanded(
                            child: Container(
                              width: 2,
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              decoration: BoxDecoration(
                                gradient: active && i < current
                                    ? LinearGradient(
                                        colors: [step.color.withValues(alpha: 0.6), steps[i + 1].color.withValues(alpha: 0.6)],
                                      )
                                    : i == current
                                        ? LinearGradient(
                                            colors: [step.color.withValues(alpha: 0.6), cs.outlineVariant.withValues(alpha: 0.15)],
                                          )
                                        : null,
                                color: !active || i >= current ? cs.outlineVariant.withValues(alpha: 0.15) : null,
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
    );
  }

  // ── Payment Summary ──
  Widget _buildPaymentSummary(BuildContext context, ColorScheme cs) {
    final price = (d['productPrice'] ?? 0).toDouble();
    final shippingCost = (d['shippingCost'] as num?)?.toDouble();
    final totalAmount = (d['totalAmount'] as num?)?.toDouble() ?? price;
    final paymentMethod = d['paymentMethod'] as String? ?? 'Mongike';
    final platformFee = (d['platformFee'] as num?)?.toDouble() ?? (d['sokoLanguCommission'] as num?)?.toDouble() ?? 0;
    final processingFee = (d['processingFee'] as num?)?.toDouble() ?? 0;
    final discount = (d['discount'] as num?)?.toDouble();
    final txId = d['transactionId'] as String? ?? d['mpesaTransactionId'] as String? ?? '';

    return _glassContainer(
      cs: cs,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(cs, Icons.receipt_outlined, context.tr('payment_summary')),
          const SizedBox(height: 16),
          _summaryRow(cs, context.tr('product_price'), '${_nf(price.toInt())} TZS', cs.onSurface),
          if (shippingCost != null && shippingCost > 0) ...[
            const SizedBox(height: 10),
            _summaryRow(cs, context.tr('shipping_cost'), '${_nf(shippingCost.toInt())} TZS', cs.secondary),
          ],
          if (discount != null && discount > 0) ...[
            const SizedBox(height: 10),
            _summaryRow(cs, context.tr('discount'), '-${_nf(discount.toInt())} TZS', cs.successGreen),
          ],
          if (platformFee > 0) ...[
            const SizedBox(height: 10),
            _summaryRow(cs, context.tr('service_fee'), '+${_nf(platformFee.toInt())} TZS', cs.tertiary),
          ],
          if (processingFee > 0) ...[
            const SizedBox(height: 10),
            _summaryRow(cs, context.tr('processing_fee'), '${_nf(processingFee.toInt())} TZS', cs.onSurfaceVariant),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, thickness: 1),
          ),
          _summaryRow(cs, context.tr('total'), '${_nf(totalAmount.toInt())} TZS', cs.primary, bold: true),
          const SizedBox(height: 14),
          Row(
            children: [
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
                    Text(paymentMethod, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.whatsappGreen)),
                  ],
                ),
              ),
              const Spacer(),
              if (txId.isNotEmpty)
                _copyButton(cs, txId, context.tr('transaction_id_label')),
            ],
          ),
          if (txId.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.fingerprint, size: 12, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text('${context.tr('transaction_id_label')}: ${txId.length > 16 ? '...${txId.substring(txId.length - 12)}' : txId}',
                    style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant.withValues(alpha: 0.5))),
                ),
              ],
            ),
          ],
          if (status == 'paid_escrow_hold' || status == 'escrow_hold' || status == 'dispatched') ...[
            const SizedBox(height: 10),
            Row(
              children: [
                _miniBadge(cs, Icons.verified_user_rounded, context.tr('escrow_status'), Colors.purple),
                const SizedBox(width: 8),
                if (status == 'paid_escrow_hold' || status == 'escrow_hold')
                  _miniBadge(cs, Icons.check_circle_rounded, context.tr('payment_verified'), cs.successGreen),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _miniBadge(ColorScheme cs, IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: color)),
        ],
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
  Widget _buildOrderInfo(BuildContext context, ColorScheme cs) {
    final buyerName = d['buyerName'] as String? ?? '';
    final buyerPhone = d['buyerPhone'] as String? ?? '';
    final buyerEmail = d['buyerEmail'] as String? ?? '';
    final paymentMethod = d['paymentMethod'] as String? ?? 'Mongike';
    final txId = d['transactionId'] as String? ?? d['mpesaTransactionId'] as String? ?? '';

    final info = <_InfoRowData>[
      _InfoRowData(Icons.person_outline, context.tr('buyer_label'), buyerName, null),
      if (buyerPhone.isNotEmpty) _InfoRowData(Icons.phone_outlined, context.tr('phone'), buyerPhone, Icons.copy_rounded),
      if (buyerEmail.isNotEmpty) _InfoRowData(Icons.email_outlined, context.tr('email'), buyerEmail, Icons.copy_rounded),
      _InfoRowData(Icons.payment_outlined, context.tr('payment_method'), paymentMethod, null),
      _InfoRowData(Icons.tag, context.tr('order_id'), '#${widget.docId}', Icons.copy_rounded),
      if (txId.isNotEmpty)
        _InfoRowData(Icons.fingerprint, context.tr('transaction_id_label'),
            txId.length > 20 ? '...${txId.substring(txId.length - 16)}' : txId, Icons.copy_rounded),
    ];

    return _glassContainer(
      cs: cs,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(cs, Icons.info_outline_rounded, context.tr('order_information')),
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
                        HapticFeedback.lightImpact();
                        Clipboard.setData(ClipboardData(text: row.value.replaceFirst('#', '')));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(context.tr('copied_to_clipboard')),
                            duration: const Duration(seconds: 1),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
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
    );
  }

  Widget _copyButton(ColorScheme cs, String text, String label) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          HapticFeedback.lightImpact();
          Clipboard.setData(ClipboardData(text: text));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.tr('copied_to_clipboard')),
              duration: const Duration(seconds: 1),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(Icons.copy_rounded, size: 14, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
        ),
      ),
    );
  }

  // ── Shipping Address ──
  Widget _buildAddressCard(BuildContext context, ColorScheme cs, bool isDark) {
    final address = d['deliveryAddress'] as Map<String, dynamic>?;
    if (address == null) return const SizedBox.shrink();

    final region = address['region'] as String?;
    final district = address['district'] as String?;
    final ward = address['ward'] as String?;
    final street = address['street'] as String?;
    final houseNumber = address['houseNumber'] as String? ?? address['house_number'] as String?;
    final landmarks = address['landmarks'] as String?;

    return _glassContainer(
      cs: cs,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            cs, Icons.location_on_rounded, context.tr('shipping_address'),
            trailing: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(context.tr('feature_coming_soon')), behavior: SnackBarBehavior.floating),
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
          ),
          const SizedBox(height: 16),
          if (region != null) _addressRow(cs, Icons.location_city_outlined, context.tr('region'), region),
          if (district != null) _addressRow(cs, Icons.map_outlined, context.tr('district'), district),
          if (ward != null) _addressRow(cs, Icons.layers_outlined, context.tr('ward'), ward),
          if (street != null) _addressRow(cs, Icons.signpost_outlined, context.tr('street'), street),
          if (houseNumber != null && houseNumber.isNotEmpty) _addressRow(cs, Icons.home_outlined, context.tr('house_number'), houseNumber),
          if (landmarks != null) _addressRow(cs, Icons.landscape_outlined, context.tr('landmarks'), landmarks),
        ],
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
  Widget _buildDispatchInfo(BuildContext context, ColorScheme cs) {
    final dispatch = d['dispatchProof'] as Map<String, dynamic>?;
    if (dispatch == null) return const SizedBox.shrink();

    final courier = dispatch['courierName'] as String?;
    final tracking = dispatch['trackingNumber'] as String?;
    final driverPhone = dispatch['driverPhone'] as String?;
    final notes = dispatch['notes'] as String?;
    final courierLogo = dispatch['courierLogo'] as String?;

    return _glassContainer(
      cs: cs,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(cs, Icons.local_shipping_outlined, context.tr('shipping_details'),
            trailing: _buildLiveStatus(cs),
          ),
          const SizedBox(height: 16),
          if (courier != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  if (courierLogo != null && courierLogo.isNotEmpty)
                    Container(
                      width: 28, height: 28,
                      margin: const EdgeInsets.only(right: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.1)),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: Image.network(courierLogo, fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Icon(Icons.local_shipping, size: 14, color: cs.primary)),
                      ),
                    )
                  else
                    Container(
                      width: 28, height: 28,
                      margin: const EdgeInsets.only(right: 10),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.local_shipping, size: 14, color: cs.primary.withValues(alpha: 0.7)),
                    ),
                  SizedBox(width: 80, child: Text(context.tr('courier_company_name'), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant))),
                  Expanded(child: Text(courier, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface))),
                ],
              ),
            ),
          if (tracking != null) _addressRow(cs, Icons.qr_code_outlined, context.tr('tracking_number'), tracking),
          if (driverPhone != null) _addressRow(cs, Icons.phone_outlined, context.tr('driver_phone'), driverPhone),
          if (notes != null) _addressRow(cs, Icons.notes_outlined, context.tr('additional_notes'), notes),
        ],
      ),
    );
  }

  Widget _buildLiveStatus(ColorScheme cs) {
    if (status != 'dispatched') return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (context, _) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: _pulseAnim.value * 0.2),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.green.withValues(alpha: _pulseAnim.value * 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 5, height: 5,
              decoration: BoxDecoration(
                color: Colors.green, shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.green.withValues(alpha: _pulseAnim.value * 0.6), blurRadius: 4)],
              ),
            ),
            const SizedBox(width: 4),
            Text(context.tr('track_shipment'), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Colors.green)),
          ],
        ),
      ),
    );
  }

  // ── Fee Breakdown ──
  Widget _buildFeeBreakdown(BuildContext context, ColorScheme cs) {
    final platformFee = (d['platformFee'] as num?)?.toDouble() ?? (d['sokoLanguCommission'] as num?)?.toDouble() ?? 0;
    final processingFee = (d['processingFee'] as num?)?.toDouble() ?? 0;
    final sellerReceives = (d['sellerReceives'] as num?)?.toDouble() ?? 0;

    if (platformFee <= 0 && processingFee <= 0 && sellerReceives <= 0) return const SizedBox.shrink();

    return _glassContainer(
      cs: cs,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(cs, Icons.account_balance_wallet_outlined, context.tr('payment_breakdown')),
          const SizedBox(height: 16),
          if (platformFee > 0) ...[
            _summaryRow(cs, context.tr('service_fee'), '+${_nf(platformFee.toInt())} TZS', cs.tertiary),
            const SizedBox(height: 10),
          ],
          if (processingFee > 0) ...[
            _summaryRow(cs, context.tr('processing_fee'), '${_nf(processingFee.toInt())} TZS', cs.onSurfaceVariant),
            const SizedBox(height: 10),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1, thickness: 1),
          ),
          _summaryRow(cs, context.tr('seller_receives'), '${_nf(sellerReceives.toInt())} TZS', cs.successGreen, bold: true),
        ],
      ),
    );
  }

  // ── Actions ──
  Widget _buildActions(BuildContext context, ColorScheme cs) {
    final canConfirm = status == 'delivered' || status == 'dispatched';
    final canDispute = status == 'paid_escrow_hold' || status == 'escrow_hold' || status == 'dispatched' || status == 'delivered';
    final canCancel = status == 'paid_escrow_hold' || status == 'escrow_hold';

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
              colors: [
                cs.surface.withValues(alpha: 0.15), cs.surfaceContainerLow.withValues(alpha: 0.08),
              ],
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
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
  Widget _buildBottomBar(BuildContext context, ColorScheme cs) {
    final sellerId = d['sellerId'] as String? ?? '';
    final sellerName = d['sellerName'] as String? ?? '';

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
          colors: [cs.surface.withValues(alpha: 0.95), cs.surface],
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
                    onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(context.tr('feature_coming_soon')), behavior: SnackBarBehavior.floating),
                    ),
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
        if (mounted) {
          HapticFeedback.mediumImpact();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(context.tr('delivery_confirmed_msg')),
            behavior: SnackBarBehavior.floating,
          ));
        }
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
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(result['error'] ?? context.tr('confirm_failed_msg')),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${context.tr('confirm_failed_msg')}: $e'),
        behavior: SnackBarBehavior.floating,
      ));
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
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.tr('dispute_opened_msg')),
          behavior: SnackBarBehavior.floating,
        ));
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(result['error'] ?? context.tr('dispute_failed')),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${context.tr('error')}: $e'),
        behavior: SnackBarBehavior.floating,
      ));
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
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: Text(context.tr('yes_cancel')),
          ),
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
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.tr('order_cancelled_refunded')),
          behavior: SnackBarBehavior.floating,
        ));
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(result['error'] ?? context.tr('cancel_order_failed')),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${context.tr('error')}: $e'),
        behavior: SnackBarBehavior.floating,
      ));
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
