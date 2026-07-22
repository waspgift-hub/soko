import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import '../../extensions/context_tr.dart';
import '../../services/api_config.dart';
import '../../services/sms_notification_service.dart';
import '../../app/routes.dart';
import '../../theme/app_colors.dart';
import '../chat/chat_navigation.dart';
import '../../widgets/google_loading.dart';
import '../../utils/network_error.dart';

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
  Timer? _countdownTimer;
  Duration? _remaining;
  bool _isLoading = true;
  String? _releasingTxId;
  String? _disputingTxId;
  bool _showAllDetails = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _startCountdown();
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) setState(() => _isLoading = false);
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
    if (d.isNegative || d == Duration.zero) return '\u2014';
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

    if (_isLoading) return _buildSkeleton(context, cs);

    return Scaffold(
      body: Stack(
        children: [
          _buildBackground(cs),
          Column(
            children: [
              _buildHeader(context, cs),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  children: [
                    _buildHeroSection(context, cs),
                    const SizedBox(height: 16),
                    _buildQuickInfoRow(context, cs),
                    const SizedBox(height: 16),
                    _buildTimeline(context, cs),
                    const SizedBox(height: 16),
                    _buildPaymentCard(context, cs),
                    const SizedBox(height: 12),
                    _buildDetailsSection(context, cs),
                    if (d['deliveryAddress'] != null || d['dispatchProof'] != null || _hasFees()) ...[
                      const SizedBox(height: 12),
                      _buildExpandableDetails(context, cs),
                    ],
                    const SizedBox(height: 12),
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
    );
  }

  Widget _buildSkeleton(BuildContext context, ColorScheme cs) {
    return Scaffold(
      body: Column(
        children: [
          Container(height: 300, color: cs.surfaceContainerHighest.withValues(alpha: 0.3)),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: List.generate(4, (_) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Container(
                  height: 120, 
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Center(child: GoogleLoading(size: 24, strokeWidth: 2.5)),
                ),
              )),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackground(ColorScheme cs) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [cs.surface, cs.surfaceContainerLow.withValues(alpha: 0.3)],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ColorScheme cs) {
    return Container(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 8),
      child: Row(
        children: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: cs.surface.withValues(alpha: 0.8),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: cs.onSurface),
            ),
            onPressed: () => context.pop(),
          ),
          const Spacer(),
          Text(context.tr('order_details'),
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: cs.onSurface)),
          const Spacer(),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildHeroSection(BuildContext context, ColorScheme cs) {
    final productName = d['productName'] as String? ?? context.tr('product');
    final productImage = d['productImage'] as String? ?? '';
    final price = (d['productPrice'] ?? 0).toDouble();
    final totalAmount = (d['totalAmount'] as num?)?.toDouble() ?? price;
    final orderIdDisplay = widget.docId.length > 12 ? '#...${widget.docId.substring(widget.docId.length - 8)}' : '#${widget.docId}';

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Stack(
        children: [
          productImage.isNotEmpty
              ? CachedNetworkImage(imageUrl: productImage,
                  width: double.infinity, height: 220, fit: BoxFit.cover,
                  errorWidget: (_, _, _) => _heroPlaceholder(cs, productName))
              : _heroPlaceholder(cs, productName),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withValues(alpha: 0.75)],
                ),
              ),
            ),
          ),
          Positioned(
            top: 12, right: 12,
            child: _statusPill(context, cs),
          ),
          Positioned(
            bottom: 16, left: 16, right: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(productName,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text('TZS ${_nf(totalAmount.toInt())}',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.greenAccent)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(orderIdDisplay,
                        style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.8))),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroPlaceholder(ColorScheme cs, String name) {
    return Container(
      width: double.infinity, height: 220,
      color: cs.primary.withValues(alpha: 0.1),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shopping_bag_outlined, size: 48, color: cs.primary.withValues(alpha: 0.3)),
            const SizedBox(height: 8),
            Text(name, style: TextStyle(color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _statusPill(BuildContext context, ColorScheme cs) {
    final color = _statusColor(context);
    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (context, _) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: _pulseAnim.value * 0.4), blurRadius: 12, spreadRadius: 1),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6, height: 6,
              decoration: BoxDecoration(
                color: Colors.white, shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.white.withValues(alpha: 0.6), blurRadius: 4)],
              ),
            ),
            const SizedBox(width: 6),
            Text(_statusLabel(context),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickInfoRow(BuildContext context, ColorScheme cs) {
    final sellerName = d['sellerName'] as String? ?? '';
    final sellerId = d['sellerId'] as String? ?? '';
    final createdAt = d['createdAt'];
    final dateStr = createdAt is Timestamp
        ? DateFormat('dd MMM yyyy').format(createdAt.toDate())
        : '';
    final paymentMethod = d['paymentMethod'] as String? ?? 'Mongike';

    return Row(
      children: [
        Expanded(
          child: _infoTile(
            cs,
            icon: Icons.person_outline,
            label: context.tr('seller'),
            value: sellerName,
            onTap: sellerId.isNotEmpty ? () => ChatNavigation.openSellerChat(context, sellerId, sellerName) : null,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _infoTile(
            cs,
            icon: Icons.calendar_today_outlined,
            label: context.tr('date'),
            value: dateStr,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _infoTile(
            cs,
            icon: Icons.payment_outlined,
            label: context.tr('payment'),
            value: paymentMethod,
          ),
        ),
      ],
    );
  }

  Widget _infoTile(ColorScheme cs, {required IconData icon, required String label, required String value, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surface.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 4)),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: cs.primary),
            const SizedBox(height: 6),
            Text(label, style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant)),
            const SizedBox(height: 2),
            Text(value, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurface),
              maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeline(BuildContext context, ColorScheme cs) {
    final steps = [
      _StepData(context.tr('step_received'), Icons.access_time_rounded, cs.onSurfaceVariant),
      _StepData(context.tr('step_shipping_quote'), Icons.local_shipping_outlined, Colors.orange),
      _StepData(context.tr('waiting_payment'), Icons.account_balance_wallet_outlined, Colors.blue),
      _StepData(context.tr('step_in_escrow'), Icons.verified_user_outlined, Colors.purple),
      _StepData(context.tr('shipped'), Icons.inventory_2_outlined, cs.successGreen),
      _StepData(context.tr('confirmed'), Icons.check_circle_outline, cs.successGreen),
      _StepData(context.tr('completed'), Icons.check_circle_rounded, cs.successGreen),
    ];
    final current = _currentStep();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.timeline_rounded, size: 16, color: cs.primary),
              const SizedBox(width: 8),
              Text(context.tr('order_status'),
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: cs.onSurface)),
              const Spacer(),
              if (_remaining != null && !_remaining!.isNegative && _remaining!.inSeconds > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.timer_outlined, size: 12, color: Colors.orange),
                      const SizedBox(width: 4),
                      Text(_formatCountdown(_remaining!),
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.orange)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 80,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: steps.length,
              separatorBuilder: (_, _) => _timelineConnector(cs, current, steps),
              itemBuilder: (_, i) {
                final step = steps[i];
                final active = i <= current;
                final isCurrent = i == current;
                return _timelineStep(step, active, isCurrent, i, current, cs);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _timelineConnector(ColorScheme cs, int current, List<_StepData> steps) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        width: 20, height: 2,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              current < steps.length ? steps[current].color.withValues(alpha: 0.4) : cs.outlineVariant,
              cs.outlineVariant.withValues(alpha: 0.2),
            ],
          ),
          borderRadius: BorderRadius.circular(1),
        ),
      ),
    );
  }

  Widget _timelineStep(_StepData step, bool active, bool isCurrent, int i, int current, ColorScheme cs) {
    return SizedBox(
      width: 56,
      child: Column(
        children: [
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (context, _) {
              final size = isCurrent ? 36.0 : 32.0;
              return Container(
                width: size, height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active ? step.color : cs.surfaceContainerHighest.withValues(alpha: 0.3),
                  border: isCurrent ? Border.all(color: step.color.withValues(alpha: 0.6), width: 2.5) : null,
                  boxShadow: isCurrent
                      ? [BoxShadow(color: step.color.withValues(alpha: _pulseAnim.value * 0.5), blurRadius: 10)]
                      : active ? [BoxShadow(color: step.color.withValues(alpha: 0.2), blurRadius: 4)] : [],
                ),
                child: Icon(
                  active ? Icons.check_rounded : Icons.circle_outlined,
                  size: isCurrent ? 16 : 13,
                  color: active ? cs.surface : cs.onSurfaceVariant.withValues(alpha: 0.3),
                ),
              );
            },
          ),
          const SizedBox(height: 6),
          Text(step.label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
              color: active ? cs.onSurface : cs.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            textAlign: TextAlign.center,
            maxLines: 2, overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentCard(BuildContext context, ColorScheme cs) {
    final price = (d['productPrice'] ?? 0).toDouble();
    final shippingCost = (d['shippingCost'] as num?)?.toDouble();
    final totalAmount = (d['totalAmount'] as num?)?.toDouble() ?? price;
    final paymentMethod = d['paymentMethod'] as String? ?? 'Mongike';
    final platformFee = (d['platformFee'] as num?)?.toDouble() ?? (d['sokoLanguCommission'] as num?)?.toDouble() ?? 0;
    final processingFee = (d['processingFee'] as num?)?.toDouble() ?? 0;
    final discount = (d['discount'] as num?)?.toDouble();
    final txId = d['transactionId'] as String? ?? d['mpesaTransactionId'] as String? ?? '';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.receipt_outlined, size: 16, color: cs.primary),
              ),
              const SizedBox(width: 10),
              Text(context.tr('payment_summary'),
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: cs.onSurface)),
            ],
          ),
          const SizedBox(height: 16),
          _payRow(cs, context.tr('product_price'), 'TZS ${_nf(price.toInt())}', null),
          if (shippingCost != null && shippingCost > 0)
            _payRow(cs, context.tr('shipping_cost'), 'TZS ${_nf(shippingCost.toInt())}', cs.secondary),
          if (discount != null && discount > 0)
            _payRow(cs, context.tr('discount'), '-TZS ${_nf(discount.toInt())}', cs.successGreen),
          if (platformFee > 0)
            _payRow(cs, context.tr('service_fee'), '+TZS ${_nf(platformFee.toInt())}', cs.tertiary),
          if (processingFee > 0)
            _payRow(cs, context.tr('processing_fee'), 'TZS ${_nf(processingFee.toInt())}', cs.onSurfaceVariant),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(height: 1),
          ),
          _payRow(cs, context.tr('total'), 'TZS ${_nf(totalAmount.toInt())}', cs.primary, bold: true),
          const SizedBox(height: 12),
          Row(
            children: [
              _miniChip(cs, Icons.payment, paymentMethod, cs.whatsappGreen),
              const Spacer(),
              if (txId.isNotEmpty)
                _copyBtn(cs, txId, context.tr('transaction_id_label')),
            ],
          ),
          if (txId.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.fingerprint, size: 11, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text('${context.tr('transaction_id_label')}: ...${txId.length > 12 ? txId.substring(txId.length - 12) : txId}',
                    style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant.withValues(alpha: 0.5))),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _payRow(ColorScheme cs, String label, String value, Color? valueColor, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant, fontWeight: bold ? FontWeight.w600 : FontWeight.w400)),
          Text(value, style: TextStyle(fontSize: 14, fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: valueColor ?? cs.onSurface)),
        ],
      ),
    );
  }

  Widget _buildDetailsSection(BuildContext context, ColorScheme cs) {
    final buyerName = d['buyerName'] as String? ?? '';
    final buyerPhone = d['buyerPhone'] as String? ?? '';
    final buyerEmail = d['buyerEmail'] as String? ?? '';
    final sellerName = d['sellerName'] as String? ?? '';
    final sellerId = d['sellerId'] as String? ?? '';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.person_outline, size: 16, color: cs.primary),
              ),
              const SizedBox(width: 10),
              Text(context.tr('order_information'),
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: cs.onSurface)),
              const Spacer(),
              if (sellerId.isNotEmpty)
                GestureDetector(
                  onTap: () => ChatNavigation.openSellerChat(context, sellerId, sellerName),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: cs.whatsappGreen.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.chat_outlined, size: 13, color: cs.whatsappGreen),
                        const SizedBox(width: 4),
                        Text(context.tr('chat'), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: cs.whatsappGreen)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          _detailRow(cs, Icons.person_outline, context.tr('buyer_label'), buyerName),
          if (buyerPhone.isNotEmpty)
            _detailRow(cs, Icons.phone_outlined, context.tr('phone'), buyerPhone, copyable: true),
          if (buyerEmail.isNotEmpty)
            _detailRow(cs, Icons.email_outlined, context.tr('email'), buyerEmail, copyable: true),
          _detailRow(cs, Icons.person_outline, context.tr('seller'), sellerName),
          _detailRow(cs, Icons.tag, context.tr('order_id'), widget.docId, copyable: true),
        ],
      ),
    );
  }

  Widget _detailRow(ColorScheme cs, IconData icon, String label, String value, {bool copyable = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 15, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
          const SizedBox(width: 10),
          SizedBox(width: 80, child: Text(label, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant))),
          Expanded(
            child: Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface)),
          ),
          if (copyable)
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(context.tr('copied_to_clipboard')), duration: const Duration(seconds: 1), behavior: SnackBarBehavior.floating),
                );
              },
              child: Icon(Icons.copy_rounded, size: 14, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
            ),
        ],
      ),
    );
  }

  Widget _buildExpandableDetails(BuildContext context, ColorScheme cs) {
    final address = d['deliveryAddress'] as Map<String, dynamic>?;
    final dispatch = d['dispatchProof'] as Map<String, dynamic>?;
    final hasAddress = address != null;
    final hasDispatch = dispatch != null;
    final hasFees = _hasFees();

    if (!hasAddress && !hasDispatch && !hasFees) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 4)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_showAllDetails ? Icons.expand_less : Icons.expand_more, size: 16, color: cs.primary),
          ),
          title: Text(context.tr('more_details'),
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: cs.onSurface)),
          children: [
            if (hasAddress) ...[
              Row(
                children: [
                  Icon(Icons.location_on_outlined, size: 15, color: cs.primary.withValues(alpha: 0.7)),
                  const SizedBox(width: 8),
                  Text(context.tr('shipping_address'),
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: cs.onSurface)),
                ],
              ),
              const SizedBox(height: 8),
              if (address['region'] != null) _addrRow(cs, context.tr('region'), address['region'] as String),
              if (address['district'] != null) _addrRow(cs, context.tr('district'), address['district'] as String),
              if (address['ward'] != null) _addrRow(cs, context.tr('ward'), address['ward'] as String),
              if (address['street'] != null) _addrRow(cs, context.tr('street'), address['street'] as String),
              if (address['houseNumber'] != null) _addrRow(cs, context.tr('house_number'), address['houseNumber'] as String),
              if (address['landmarks'] != null) _addrRow(cs, context.tr('landmarks'), address['landmarks'] as String),
              const SizedBox(height: 12),
            ],
            if (hasDispatch) ...[
              Row(
                children: [
                  Icon(Icons.local_shipping_outlined, size: 15, color: cs.primary.withValues(alpha: 0.7)),
                  const SizedBox(width: 8),
                  Text(context.tr('shipping_details'),
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: cs.onSurface)),
                ],
              ),
              const SizedBox(height: 8),
              if (dispatch['courierName'] != null) _addrRow(cs, context.tr('courier_company_name'), dispatch['courierName'] as String),
              if (dispatch['trackingNumber'] != null) _addrRow(cs, context.tr('tracking_number'), dispatch['trackingNumber'] as String),
              if (dispatch['driverPhone'] != null) _addrRow(cs, context.tr('driver_phone'), dispatch['driverPhone'] as String),
              if (dispatch['notes'] != null) _addrRow(cs, context.tr('additional_notes'), dispatch['notes'] as String),
              const SizedBox(height: 12),
            ],
            if (hasFees) ...[
              Row(
                children: [
                  Icon(Icons.account_balance_wallet_outlined, size: 15, color: cs.primary.withValues(alpha: 0.7)),
                  const SizedBox(width: 8),
                  Text(context.tr('payment_breakdown'),
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: cs.onSurface)),
                ],
              ),
              const SizedBox(height: 8),
              _buildFeeRows(cs),
            ],
          ],
        ),
      ),
    );
  }

  bool _hasFees() {
    final platformFee = (d['platformFee'] as num?)?.toDouble() ?? (d['sokoLanguCommission'] as num?)?.toDouble() ?? 0;
    final processingFee = (d['processingFee'] as num?)?.toDouble() ?? 0;
    final sellerReceives = (d['sellerReceives'] as num?)?.toDouble() ?? 0;
    return platformFee > 0 || processingFee > 0 || sellerReceives > 0;
  }

  Widget _buildFeeRows(ColorScheme cs) {
    final platformFee = (d['platformFee'] as num?)?.toDouble() ?? (d['sokoLanguCommission'] as num?)?.toDouble() ?? 0;
    final processingFee = (d['processingFee'] as num?)?.toDouble() ?? 0;
    final sellerReceives = (d['sellerReceives'] as num?)?.toDouble() ?? 0;
    final children = <Widget>[];
    if (platformFee > 0) {
      children.add(_addrRow(cs, context.tr('service_fee'), '+TZS ${_nf(platformFee.toInt())}'));
    }
    if (processingFee > 0) {
      children.add(_addrRow(cs, context.tr('processing_fee'), 'TZS ${_nf(processingFee.toInt())}'));
    }
    if (sellerReceives > 0) {
      children.add(const SizedBox(height: 4));
      children.add(Container(height: 1, color: cs.outlineVariant.withValues(alpha: 0.2)));
      children.add(const SizedBox(height: 4));
      children.add(_addrRow(cs, context.tr('seller_receives'), 'TZS ${_nf(sellerReceives.toInt())}', bold: true));
    }
    return Column(children: children);
  }

  Widget _addrRow(ColorScheme cs, String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(width: 100, child: Text(label, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant))),
          Expanded(child: Text(value, style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.w700 : FontWeight.w600, color: cs.onSurface))),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context, ColorScheme cs) {
    final canConfirm = status == 'delivered' || status == 'dispatched';
    final canDispute = status == 'paid_escrow_hold' || status == 'escrow_hold' || status == 'dispatched' || status == 'delivered';
    final canCancel = status == 'paid_escrow_hold' || status == 'escrow_hold';

    if (!canConfirm && !canDispute && !canCancel) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          if (canConfirm)
            SizedBox(
              width: double.infinity, height: 48,
              child: ElevatedButton.icon(
                onPressed: _releasingTxId == widget.docId ? null : () => _confirmDelivery(widget.docId),
                icon: _releasingTxId == widget.docId
                    ? const GoogleLoading(size: 20, strokeWidth: 2)
                    : const Icon(Icons.verified, size: 20),
                label: Text(_releasingTxId == widget.docId ? context.tr('confirming_label') : context.tr('confirm_receipt')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: cs.successGreen,
                  foregroundColor: cs.surface,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _miniChip(ColorScheme cs, IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }

  Widget _copyBtn(ColorScheme cs, String text, String label) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        Clipboard.setData(ClipboardData(text: text));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('copied_to_clipboard')), duration: const Duration(seconds: 1), behavior: SnackBarBehavior.floating),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: cs.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(Icons.copy_rounded, size: 14, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
      ),
    );
  }

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
        color: cs.surface,
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 46,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cs.whatsappGreen,
                    foregroundColor: cs.surface,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.chat_outlined, size: 17),
                  onPressed: sellerId.isNotEmpty
                      ? () => ChatNavigation.openSellerChat(context, sellerId, sellerName)
                      : null,
                  label: Text(context.tr('contact_seller'), style: const TextStyle(fontSize: 12)),
                ),
              ),
            ),
            if (status == 'dispatched') ...[
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: cs.primary,
                      side: BorderSide(color: cs.primary.withValues(alpha: 0.3)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.track_changes_outlined, size: 17),
                    onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(context.tr('feature_coming_soon')), behavior: SnackBarBehavior.floating),
                    ),
                    label: Text(context.tr('track'), style: const TextStyle(fontSize: 12)),
                  ),
                ),
              ),
            ],
            const SizedBox(width: 8),
            SizedBox(
              height: 46,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: cs.primary,
                  side: BorderSide(color: cs.primary.withValues(alpha: 0.3)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.receipt_outlined, size: 17),
                onPressed: () => context.push('${AppRoutes.receipt}/${widget.docId}'),
                label: Text(context.tr('receipt'), style: const TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ),
      ),
    );
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
        content: Text(translateError(e)),
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
        content: Text(translateError(e)),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }
}

class _StepData {
  final String label;
  final IconData icon;
  final Color color;
  const _StepData(this.label, this.icon, this.color);
}
