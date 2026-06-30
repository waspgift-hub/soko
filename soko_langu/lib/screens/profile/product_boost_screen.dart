import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import '../../models/product_model.dart';
import '../../models/boost_tier.dart';
import '../../services/boost_service.dart';
import '../../services/api_config.dart';
import '../../extensions/context_tr.dart';
import '../../widgets/google_loading.dart';
import '../../app/routes.dart';
import '../../theme/app_colors.dart';

class ProductBoostScreen extends StatefulWidget {
  final Product product;

  const ProductBoostScreen({super.key, required this.product});

  @override
  State<ProductBoostScreen> createState() => _ProductBoostScreenState();
}

class _ProductBoostScreenState extends State<ProductBoostScreen> {
  BoostTier? _selectedTier;
  bool _processing = false;

  final _nf = NumberFormat('#,###', 'en');

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final bgColor = Theme.of(context).colorScheme.surface;
    final cardBg = brightness == Brightness.dark
        ? Theme.of(context).colorScheme.surfaceContainerHigh
        : Theme.of(context).colorScheme.surface;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(context.tr('boost_product')),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _buildProductHeader(cardBg),
          const SizedBox(height: 24),
          _buildSectionTitle(context.tr('choose_boost_package')),
          const SizedBox(height: 16),
          _buildTierCard(BoostTier.bronze, cardBg, brightness),
          const SizedBox(height: 12),
          _buildTierCard(BoostTier.silver, cardBg, brightness),
          const SizedBox(height: 12),
          _buildTierCard(BoostTier.gold, cardBg, brightness),
          const SizedBox(height: 32),
          _buildPaymentButton(),
        ],
      ),
    );
  }

  Widget _buildProductHeader(Color cardBg) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 64,
              height: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              child: widget.product.images.isNotEmpty
                  ? Image.network(
                      widget.product.images.first,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Icon(Icons.image,
                          color: Theme.of(context).colorScheme.onSurfaceVariant),
                    )
                  : Icon(Icons.image, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.product.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  'TZS ${_nf.format(widget.product.price)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          if (widget.product.isBoostedValid)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.31)),
              ),
              child: Text(
                context.tr('active'),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 17,
      ),
    );
  }

  Widget _buildTierCard(BoostTier tier, Color cardBg, Brightness brightness) {
    final isSelected = _selectedTier == tier;
    final isDark = brightness == Brightness.dark;

    Color accentColor;
    IconData icon;
    switch (tier) {
      case BoostTier.bronze:
        accentColor = Theme.of(context).colorScheme.boostBronze;
        icon = Icons.emoji_events;
      case BoostTier.silver:
        accentColor = Theme.of(context).colorScheme.boostSilver;
        icon = Icons.workspace_premium;
      case BoostTier.gold:
        accentColor = Theme.of(context).colorScheme.boostGold;
        icon = Icons.verified;
    }

    return GestureDetector(
      onTap: _processing ? null : () => setState(() => _selectedTier = tier),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isSelected
              ? accentColor.withValues(alpha: 0.07)
              : cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? accentColor : Theme.of(context).colorScheme.surface.withValues(alpha: 0.06),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: accentColor, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        tier.displayName,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                          color: isDark ? Theme.of(context).colorScheme.surface : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.87),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${tier.durationDays} days',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: accentColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        'TZS ${_nf.format(tier.priceTzs)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 22,
                          color: accentColor,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '~TZS ${_nf.format(tier.pricePerDay.toInt())}/day',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Theme.of(context).colorScheme.onSurfaceVariant : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? accentColor : Colors.transparent,
                border: Border.all(
                  color: isSelected ? accentColor : Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Icon(Icons.check, size: 16, color: Theme.of(context).colorScheme.surface)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentButton() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        if (_selectedTier != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _selectedTier == BoostTier.gold
                    ? Theme.of(context).colorScheme.boostGold.withValues(alpha: 0.06)
                    : _selectedTier == BoostTier.silver
                        ? Theme.of(context).colorScheme.boostSilver.withValues(alpha: 0.06)
                        : Theme.of(context).colorScheme.boostBronze.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      context.tr('payment_after_continue'),
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Theme.of(context).colorScheme.onSurfaceVariant : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed:
                _selectedTier == null || _processing ? null : _processPayment,
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.successGreen,
              foregroundColor: Theme.of(context).colorScheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
            child: _processing
                ? const GoogleLoading(size: 20, strokeWidth: 2)
                : Text(
                    _selectedTier == null
                        ? context.tr('select_package')
                        : 'Continue — TZS ${_nf.format(_selectedTier!.priceTzs)}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Future<void> _processPayment() async {
    final tier = _selectedTier;
    if (tier == null) return;

    final phoneController = TextEditingController();
    final phone = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('phone_number')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${context.tr('boost_product')} "${widget.product.name}"\n${tier.displayName} — TZS ${_nf.format(tier.priceTzs)} / ${tier.durationDays} ${context.tr('days')}',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: context.tr('phone_number'),
                hintText: context.tr('phone_hint'),
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.phone_android),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, phoneController.text.trim()),
            child: Text(context.tr('pay_now')),
          ),
        ],
      ),
    );

    if (phone == null || phone.isEmpty) return;

    setState(() => _processing = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) _showError(context.tr('please_log_in_first'));
        return;
      }

      final result = await BoostService().initiateBoostPayment(
        productId: widget.product.id,
        tier: tier,
        phone: phone,
        userId: user.uid,
      );

      if (result == null || result['order_id'] == null) {
        if (mounted) _showError(context.tr('payment_initiation_failed'));
        return;
      }

      final orderId = result['order_id'] as String?;

      if (mounted) {
        _showProcessingDialog(orderId);
      }
    } catch (e) {
      if (mounted) _showError('Error: $e');
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  void _showProcessingDialog(String? orderId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return _PaymentDialog(
          orderId: orderId!,
          onSuccess: () {
            Navigator.pop(ctx);
            if (mounted) _onPaymentSuccess();
          },
          onError: (msg) {
            Navigator.pop(ctx);
            if (mounted) _showError(msg);
          },
        );
      },
    );
  }

  // ignore: unused_element
  Future<void> _retryPayment(String orderId) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final token = await user.getIdToken();
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/retry-payment'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'order_id': orderId}),
      );
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      if (resp.statusCode == 200 && body['status'] == 'completed') {
        // Success — the transaction is now completed
      } else {
        if (mounted) _showError(body['error'] as String? ?? context.tr('payment_not_confirmed'));
      }
    } catch (e) {
      debugPrint('retryPayment error: $e');
    }
  }

  Future<void> _onPaymentSuccess() async {
    // Boost the product immediately from client-side
    // so the user doesn't have to wait for the server webhook
    try {
      await BoostService().handleBoostPaymentSuccess(
        productId: widget.product.id,
        tier: _selectedTier!,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_selectedTier!.displayName} boost activated for ${_selectedTier!.durationDays} days!',
          ),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    } catch (e) {
      debugPrint('Client boost failed, server webhook will handle it: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr('boosting_will_complete'),
          ),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    }

    // Notify all users about this boost
    final user = FirebaseAuth.instance.currentUser;
    BoostService().notifyBoost(
      productId: widget.product.id,
      tierName: _selectedTier!.name,
      sellerId: user?.uid,
    );

    if (mounted) context.go(AppRoutes.sellerDashboard);
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Theme.of(context).colorScheme.error),
    );
  }
}

class _PaymentDialog extends StatefulWidget {
  final String orderId;
  final VoidCallback onSuccess;
  final void Function(String msg) onError;
  const _PaymentDialog({required this.orderId, required this.onSuccess, required this.onError});
  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  bool _timedOut = false;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 120), () {
      if (mounted) setState(() => _timedOut = true);
    });
  }

  Future<void> _retry() async {
    setState(() => _checking = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final token = await user.getIdToken();
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
      if (resp.statusCode == 200 && body['status'] == 'completed') {
        widget.onSuccess();
      } else {
        widget.onError(body['error'] as String? ?? 'Payment not confirmed yet');
      }
    } catch (e) {
      if (mounted) widget.onError(context.tr('network_error').replaceAll('{error}', '$e'));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('transactions')
          .doc(widget.orderId)
          .snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() as Map<String, dynamic>?;
        final status = data?['status'] as String? ?? 'pending';

        if (status == 'completed') {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            widget.onSuccess();
          });
          return AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, color: cs.primary, size: 64),
                const SizedBox(height: 16),
                Text(context.tr('payment_successful'),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(context.tr('product_now_boosted'),
                    style: const TextStyle(color: Colors.black54)),
              ],
            ),
          );
        }

        if (status == 'failed') {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            widget.onError(context.tr('payment_failed_try_again'));
          });
          return AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cancel, color: Colors.red, size: 64),
                const SizedBox(height: 16),
                Text(context.tr('payment_failed'),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
                _timedOut ? context.tr('payment_not_confirmed') : context.tr('processing_payment'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _timedOut
                    ? '${context.tr('check_phone_complete_payment')}\nOrder: ${widget.orderId}'
                    : context.tr('complete_payment_on_phone'),
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
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
                    label: Text(_checking ? context.tr('checking') : context.tr('check_payment_status')),
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
