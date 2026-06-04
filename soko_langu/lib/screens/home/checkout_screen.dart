import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import '../../models/product_model.dart';
import '../../services/payment_service.dart';
import '../../services/fraud_prevention_service.dart';
import '../../services/mongike_service.dart';
import '../../services/flash_sale_service.dart';
import '../../services/api_config.dart';
import '../../extensions/context_tr.dart';
import '../../app/routes.dart';
import '../../widgets/google_loading.dart';
import '../../theme/app_colors.dart';

class CheckoutScreen extends StatefulWidget {
  final Product product;

  const CheckoutScreen({super.key, required this.product});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _phoneController = TextEditingController();
  final _paymentService = PaymentService();
  bool _processing = false;
  double? _salePrice;

  double get _totalPrice => _salePrice ?? widget.product.price;

  @override
  void initState() {
    super.initState();
    _loadFlashSale();
  }

  Future<void> _loadFlashSale() async {
    final fs = await FlashSaleService()
        .streamFlashSaleByProductId(widget.product.id)
        .first;
    if (fs != null && mounted) {
      setState(() => _salePrice = fs.salePrice);
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = widget.product;
    final breakdown = _paymentService.calculateFees(_totalPrice);

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('checkout')), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            width: 56,
                            height: 56,
                            color: cs.surfaceContainerHighest,
                            child: p.images.isNotEmpty
                                ? Image.network(
                                    p.images.first,
                                    fit: BoxFit.cover,
                                  )
                                : Icon(
                                    Icons.image,
                                    size: 28,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'x1  ${_salePrice != null ? context.formatPrice(_salePrice!) : context.formatPrice(p.price)}',
                                style: TextStyle(
                                  color: cs.onSurface.withValues(alpha: 0.59),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            context.tr('payment_details'),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          _detailRow(context.tr('total_price'), context.formatPrice(_totalPrice), cs),
          _detailRow(
            context.tr('mongike_fee'),
            '- ${context.formatPrice(breakdown.processingFee)}',
            cs,
            valueColor: cs.error,
          ),
          _detailRow(
            context.tr('soko_commission'),
            '- ${context.formatPrice(breakdown.platformFee)}',
            cs,
            valueColor: cs.error,
          ),
          _detailRow(
            context.tr('payout_fee'),
            '- ${context.formatPrice(breakdown.payoutFee)}',
            cs,
            valueColor: cs.error,
          ),
          const Divider(height: 24),
          _detailRow(
            context.tr('seller_receives'),
            context.formatPrice(breakdown.sellerReceives),
            cs,
            valueColor: cs.primary,
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.secondary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.secondary.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: cs.secondary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.tr('you_pay_seller_receives').replaceAll('{0}', context.formatPrice(_totalPrice)).replaceAll('{1}', context.formatPrice(breakdown.sellerReceives)),
                    style: TextStyle(color: cs.secondary, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            context.tr('your_phone_number'),
            style: TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 14,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              hintText: context.tr('phone_hint'),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              prefixIcon: const Icon(Icons.phone_android),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _processing ? null : _processPayment,
              icon: _processing
                  ? const GoogleLoading(size: 20, strokeWidth: 2)
                  : const Icon(Icons.lock),
              label: Text(
                _processing
                    ? context.tr('processing')
                    : context.tr('pay').replaceAll('{0}', context.formatPrice(_totalPrice)),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: cs.successGreen,
                foregroundColor: cs.surface,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: _processing ? null : () => context.pop(),
            icon: const Icon(Icons.arrow_back, size: 18),
            label: Text(context.tr('cancel')),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(
    String label,
    String value,
    ColorScheme cs, {
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: cs.onSurface.withValues(alpha: 0.67), fontSize: 14),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _processPayment() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      _showError(context.tr('enter_phone'));
      return;
    }

    setState(() => _processing = true);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showError(context.tr('ingia_akaunti_kwanza'));
      setState(() => _processing = false);
      return;
    }

    try {
      final p = widget.product;

      // Re-validate flash sale expiry before payment
      final activeFs = await FlashSaleService()
          .streamFlashSaleByProductId(p.id)
          .first;
      if (activeFs != null && activeFs.isExpired) {
        _showError(context.tr('flash_sale_expired'));
        setState(() => _processing = false);
        return;
      }

      await FraudPreventionService().checkSuspiciousTransaction(
        buyerId: user.uid,
        sellerId: p.sellerId,
        sellerName: p.sellerName,
        amount: _totalPrice,
      );
      final result = await MongikeService.initiateMarketplacePayment(
        productPrice: _totalPrice,
        productName: p.name,
        productId: p.id,
        sellerId: p.sellerId,
        sellerName: p.sellerName,
        email: user.email ?? '',
        phone: phone,
        buyerId: user.uid,
      );

      if (result == null || result['order_id'] == null) {
        final errMsg =
            result?['error'] as String? ??
            context.tr('failed_payment_init');
        _showError(errMsg);
        setState(() => _processing = false);
        return;
      }

      final orderId = result['order_id'] as String;

      if (!mounted) return;
      _showPaymentDialog(orderId, user);
    } catch (e) {
      _showError(context.tr('payment_error').replaceAll('{0}', e.toString()));
      setState(() => _processing = false);
    }
  }

  void _showPaymentDialog(String orderId, User user) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return _PaymentPendingDialog(
          orderId: orderId,
          user: user,
          onSuccess: (o, u) => _onPaymentSuccess(o, u, ctx),
          onTimeout: () {
            if (mounted) setState(() => _processing = false);
          },
        );
      },
    );
  }

  Future<void> _onPaymentSuccess(
    String orderId,
    User user,
    BuildContext dialogContext,
  ) async {
    final cs = Theme.of(context).colorScheme;
    Navigator.pop(dialogContext);

    if (mounted) {
      setState(() => _processing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('purchase_successful')),
          backgroundColor: cs.primary,
        ),
      );
      context.go(AppRoutes.home);
    }
  }

  void _showError(String msg) {
    final cs = Theme.of(context).colorScheme;
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: cs.error));
  }
}

class _PaymentPendingDialog extends StatefulWidget {
  final String orderId;
  final User user;
  final void Function(String orderId, User user) onSuccess;
  final VoidCallback onTimeout;
  const _PaymentPendingDialog({
    required this.orderId,
    required this.user,
    required this.onSuccess,
    required this.onTimeout,
  });
  @override
  State<_PaymentPendingDialog> createState() => _PaymentPendingDialogState();
}

class _PaymentPendingDialogState extends State<_PaymentPendingDialog> {
  bool _timedOut = false;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    // After 120s, show timeout message so user isn't stuck forever
    Future.delayed(const Duration(seconds: 120), () {
      if (mounted) setState(() => _timedOut = true);
    });
  }

  Future<void> _retry() async {
    setState(() => _checking = true);
    try {
      final token = await widget.user.getIdToken();
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/retry-payment'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'order_id': widget.orderId}),
      );
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (resp.statusCode == 200 && (body['status'] == 'completed' || body['status'] == 'escrow_hold')) {
        widget.onSuccess(widget.orderId, widget.user);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(body['error'] as String? ?? 'Payment not confirmed yet'), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Network error: $e'), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('transactions')
          .doc(widget.orderId)
          .snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() as Map<String, dynamic>?;
        final status = data?['status'] as String? ?? 'pending';

        if (status == 'completed' || status == 'escrow_hold') {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            widget.onSuccess(widget.orderId, widget.user);
          });
          return AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.check_circle,
                  color: Theme.of(context).colorScheme.primary,
                  size: 64,
                ),
                const SizedBox(height: 16),
                Text(
                  context.tr('payment_successful'),
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          );
        }

        if (status == 'failed') {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            widget.onTimeout();
          });
          return AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.cancel,
                  color: Theme.of(context).colorScheme.error,
                  size: 64,
                ),
                const SizedBox(height: 16),
                Text(
                  context.tr('payment_failed'),
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          );
        }

        return AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!_timedOut) ...[
                const GoogleLoading(size: 24, strokeWidth: 2),
                const SizedBox(height: 20),
              ],
              Text(
                _timedOut
                    ? context.tr('payment_confirm_pending')
                    : context.tr('processing_payment'),
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _timedOut
                    ? context.tr('check_phone_ussd_mongike').replaceAll('{0}', widget.orderId)
                    : context
                          .tr('complete_payment_mongike')
                          .replaceAll('{0}', widget.orderId),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
              if (_timedOut) ...[
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _checking ? null : _retry,
                    icon: _checking
                        ? const SizedBox(width: 20, height: 20, child: GoogleLoading(size: 20, strokeWidth: 2))
                        : const Icon(Icons.refresh, size: 18),
                    label: Text(_checking ? 'Checking...' : 'Check Payment Status'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () {
                      widget.onTimeout();
                      Navigator.pop(context);
                    },
                    child: Text(context.tr('close')),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
