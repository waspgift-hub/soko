import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../models/product_model.dart';
import '../../models/boost_tier.dart';
import '../../services/boost_service.dart';
import '../../extensions/context_tr.dart';
import '../../services/sms_notification_service.dart';
import '../../models/boost_receipt.dart';
import '../../models/payment_model.dart';
import '../../widgets/google_loading.dart';
import '../../widgets/boost_receipt_card.dart';
import '../../widgets/payment_banner.dart';
import '../../widgets/glass_container.dart';
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
                border: Border.all(
                  color: _selectedTier == BoostTier.gold
                      ? Theme.of(context).colorScheme.boostGold.withValues(alpha: 0.3)
                      : _selectedTier == BoostTier.silver
                          ? Theme.of(context).colorScheme.boostSilver.withValues(alpha: 0.3)
                          : Theme.of(context).colorScheme.boostBronze.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('order_summary'),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _summaryRow(context.tr('plan'), _selectedTier!.displayName, Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(height: 4),
                  _summaryRow(context.tr('duration'), '${_selectedTier!.durationDays} ${context.tr('days')}', Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(height: 4),
                  _summaryRow(context.tr('total'), 'TZS ${_nf.format(_selectedTier!.priceTzs)}', Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.info_outline, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          context.tr('payment_after_continue'),
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Theme.of(context).colorScheme.onSurfaceVariant : Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
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
                        : '${context.tr("proceed_to_checkout")} — TZS ${_nf.format(_selectedTier!.priceTzs)}',
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

  Widget _summaryRow(String label, String value, Color valueColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: valueColor)),
      ],
    );
  }

  Future<void> _processPayment() async {
    final tier = _selectedTier;
    if (tier == null) return;

    final phoneController = TextEditingController();
    final phone = await _GlassPaymentDialog.show(
      context: context,
      productName: widget.product.name,
      tierName: tier.displayName,
      price: 'TZS ${_nf.format(tier.priceTzs)}',
      duration: '${tier.durationDays} ${context.tr('days')}',
      phoneController: phoneController,
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

      if (mounted && orderId != null) {
        RealtimePaymentBanner.show(
          context: context,
          orderId: orderId,
          successStatuses: ['completed'],
          processingTitle: context.tr('processing_payment'),
          successTitle: context.tr('payment_successful'),
          failedTitle: context.tr('payment_failed'),
          onSuccess: () {
            if (mounted) _onPaymentSuccess();
          },
          onError: (msg) {
            if (mounted) {
              _showError(msg);
              PaymentBanner.show(
                context: context,
                type: PaymentBannerType.failed,
                title: context.tr('payment_failed'),
                subtitle: msg,
              );
            }
          },
        );
      }
    } catch (e) {
      if (mounted) _showError('Error: $e');
    } finally {
      if (mounted) setState(() => _processing = false);
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
    } catch (e) {
      debugPrint('Client boost failed, server webhook will handle it: $e');
    }

    // Notify all users about this boost
    final user = FirebaseAuth.instance.currentUser;
    BoostService().notifyBoost(
      productId: widget.product.id,
      tierName: _selectedTier!.name,
      sellerId: user?.uid,
    );

    // SMS seller about boost payment (server also sends via callback)
    final sellerPhone = widget.product.sellerPhone ?? '';
    final expiry = DateTime.now().add(Duration(days: _selectedTier!.durationDays));
    if (sellerPhone.isNotEmpty) {
      SmsNotificationService.notifyBoostPaid(
        sellerPhone: sellerPhone,
        amountPaid: _selectedTier!.priceTzs.toString(),
        boostExpiryDate: DateFormat('dd/MM/yyyy').format(expiry),
      );
    }

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Boost Imekamilika'),
        content: SingleChildScrollView(
          child: BoostReceiptCard(
            receipt: BoostReceipt(
              boostTransactionId: '',
              sellerName: widget.product.sellerName,
              productId: widget.product.id,
              boostPackageName: _selectedTier!.displayName,
              amountPaid: _selectedTier!.priceTzs.toDouble(),
              paymentMethod: 'Mongike',
              timestamp: DateTime.now(),
              boostExpiryDate: expiry,
              paymentStatus: PaymentStatus.completed,
            ),
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (mounted) context.go(AppRoutes.sellerDashboard);
            },
            child: Text(context.tr('continue')),
          ),
        ],
      ),
    );
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Theme.of(context).colorScheme.error),
    );
  }
}

/// Glassmorphic payment phone-input dialog with frosted glass effect.
class _GlassPaymentDialog {
  static Future<String?> show({
    required BuildContext context,
    required String productName,
    required String tierName,
    required String price,
    required String duration,
    required TextEditingController phoneController,
  }) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return showDialog<String>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? [cs.surface.withValues(alpha: 0.85), cs.surfaceContainerLow.withValues(alpha: 0.7)]
                      : [Colors.white.withValues(alpha: 0.92), Colors.white.withValues(alpha: 0.8)],
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Colors.white.withValues(alpha: isDark ? 0.1 : 0.25),
                  width: 0.5,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.tr('phone_number'),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: isDark ? Colors.white : cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 12),
                  GlassContainer(
                    borderRadius: 12,
                    opacity: isDark ? 0.12 : 0.08,
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      '"$productName"\n$tierName — $price / $duration',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white.withValues(alpha: 0.85) : cs.onSurface.withValues(alpha: 0.8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  GlassContainer(
                    borderRadius: 12,
                    opacity: isDark ? 0.08 : 0.05,
                    child: TextField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: context.tr('phone_number'),
                        hintText: context.tr('phone_hint'),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        prefixIcon: Icon(Icons.phone_android, color: cs.primary),
                        filled: false,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: Text(context.tr('cancel')),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, phoneController.text.trim()),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: cs.primary,
                            foregroundColor: cs.surface,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: Text(context.tr('pay_now')),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}


