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
import '../../widgets/boost_receipt_card.dart';
import '../../widgets/payment_banner.dart';
import '../../widgets/glass_container.dart';
import '../../app/routes.dart';
import '../../theme/app_colors.dart';
import '../../widgets/premium_background.dart';
import '../../utils/network_error.dart';
import 'package:cached_network_image/cached_network_image.dart';

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
    final cs = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final cardBg = brightness == Brightness.dark
        ? cs.surface.withValues(alpha: 0.08)
        : cs.surface.withValues(alpha: 0.88);

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(context.tr('boost_product')),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [brightness == Brightness.dark ? Colors.black : Colors.white, cs.surface],
          ),
        ),
        child: SafeArea(
          top: true,
          child: ListView(
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
          ),
        ),
    );
  }

  Widget _buildProductHeader(Color cardBg) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.08),
        ),
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
                  ? CachedNetworkImage(
                      imageUrl: widget.product.images.first,
                      fit: BoxFit.cover, width: 64, height: 64,
                      errorWidget: (_, _, _) => Icon(
                        Icons.image,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    )
                  : Icon(
                      Icons.image,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
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
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.31),
                ),
              ),
              child: Text(
                context.tr('active'),
                style: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.7),
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
      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
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
          color: isSelected ? accentColor.withValues(alpha: 0.07) : cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? accentColor
                : Theme.of(context).colorScheme.surface.withValues(alpha: 0.06),
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
                          color: isDark
                              ? Theme.of(context).colorScheme.surface
                              : Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.87),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${tier.durationDays} ${context.tr('days')}',
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
                          color: isDark
                              ? Theme.of(context).colorScheme.onSurfaceVariant
                              : Theme.of(context).colorScheme.onSurfaceVariant,
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
                  color: isSelected
                      ? accentColor
                      : Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Icon(
                      Icons.check,
                      size: 16,
                      color: Theme.of(context).colorScheme.surface,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentButton() {
    final cs2 = Theme.of(context).colorScheme;
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
                    ? Theme.of(
                        context,
                      ).colorScheme.boostGold.withValues(alpha: 0.06)
                    : _selectedTier == BoostTier.silver
                    ? Theme.of(
                        context,
                      ).colorScheme.boostSilver.withValues(alpha: 0.06)
                    : Theme.of(
                        context,
                      ).colorScheme.boostBronze.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _selectedTier == BoostTier.gold
                      ? Theme.of(
                          context,
                        ).colorScheme.boostGold.withValues(alpha: 0.3)
                      : _selectedTier == BoostTier.silver
                      ? Theme.of(
                          context,
                        ).colorScheme.boostSilver.withValues(alpha: 0.3)
                      : Theme.of(
                          context,
                        ).colorScheme.boostBronze.withValues(alpha: 0.3),
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
                  _summaryRow(
                    context.tr('plan'),
                    _selectedTier!.displayName,
                    Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 4),
                  _summaryRow(
                    context.tr('duration'),
                    '${_selectedTier!.durationDays} ${context.tr('days')}',
                    Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 4),
                  _summaryRow(
                    context.tr('total'),
                    'TZS ${_nf.format(_selectedTier!.priceTzs)}',
                    Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 14,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          context.tr('payment_after_continue'),
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark
                                ? Theme.of(context).colorScheme.onSurfaceVariant
                                : Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        if (_processing)
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: () {
                RealtimePaymentBanner.dismiss();
                setState(() => _processing = false);
              },
              icon: const Icon(Icons.close, size: 20),
              label: Text(context.tr('cancel')),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
            ),
          ),
        if (!_processing)
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _selectedTier == null ? null : _processPayment,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.successGreen,
                foregroundColor: Theme.of(context).colorScheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              child: Text(
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
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton.icon(
            onPressed: () => context.pop(),
            icon: const Icon(Icons.close, size: 18),
            label: Text(context.tr('cancel')),
            style: OutlinedButton.styleFrom(
              foregroundColor: cs2.onSurfaceVariant,
              side: BorderSide(color: cs2.outlineVariant),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
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
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: valueColor,
          ),
        ),
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
        final errMsg = result?['error'] as String? ?? context.tr('payment_initiation_failed');
        if (mounted) {
          PaymentBanner.show(
            context: context,
            type: PaymentBannerType.failed,
            title: context.tr('payment_failed'),
            subtitle: errMsg,
          );
        }
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
            if (mounted) {
              PaymentBanner.show(
                context: context,
                type: PaymentBannerType.success,
                title: context.tr('payment_successful'),
              );
              _onPaymentSuccess();
            }
          },
          onError: (msg) {
            if (mounted) {
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
      if (mounted) {
        PaymentBanner.show(
          context: context,
          type: PaymentBannerType.failed,
          title: context.tr('payment_failed'),
          subtitle: translateError(e),
        );
      }
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
    final expiry = DateTime.now().add(
      Duration(days: _selectedTier!.durationDays),
    );
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
        title: Text(context.tr('boost_complete')),
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
      SnackBar(
        content: Text(msg),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }
}

/// Glassmorphic payment phone-input dialog.
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
          borderRadius: BorderRadius.circular(32),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 56, sigmaY: 56),
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? [
                          cs.surface.withValues(alpha: 0.75),
                          cs.surfaceContainerLow.withValues(alpha: 0.55),
                        ]
                      : [
                          cs.surface.withValues(alpha: 0.95),
                          cs.surfaceContainerLow.withValues(alpha: 0.82),
                        ],
                ),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(
                  color: cs.primary.withValues(alpha: isDark ? 0.12 : 0.15),
                  width: 0.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: cs.primary.withValues(alpha: 0.15),
                    blurRadius: 56,
                    offset: const Offset(0, 28),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            cs.primary.withValues(alpha: 0.15),
                            cs.primary.withValues(alpha: 0.05),
                          ],
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.payment_rounded,
                        color: cs.primary,
                        size: 34,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    context.tr('phone_number'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                      color: isDark ? Colors.white : cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 14),
                  GlassContainer(
                    borderRadius: 16,
                    opacity: isDark ? 0.15 : 0.1,
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      '"$productName"\n$tierName — $price / $duration',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.85)
                            : cs.onSurface.withValues(alpha: 0.8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                      child: Container(
                        decoration: BoxDecoration(
                          color: cs.surface.withValues(
                            alpha: isDark ? 0.08 : 0.04,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: cs.primary.withValues(alpha: 0.08),
                            width: 0.5,
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 2,
                        ),
                        child: TextField(
                          controller: phoneController,
                          keyboardType: TextInputType.phone,
                          decoration: InputDecoration(
                            hintText: context.tr('phone_hint'),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            prefixIcon: Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Icon(
                                Icons.phone_android_rounded,
                                color: cs.primary,
                                size: 22,
                              ),
                            ),
                            prefixIconConstraints: const BoxConstraints(
                              minWidth: 44,
                              minHeight: 0,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 16,
                            ),
                          ),
                          style: TextStyle(
                            fontSize: 16,
                            color: isDark ? Colors.white : cs.onSurface,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
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
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: cs.primary.withValues(alpha: 0.3),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            onPressed: () =>
                                Navigator.pop(ctx, phoneController.text.trim()),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: cs.primary,
                              foregroundColor: cs.surface,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              elevation: 0,
                            ),
                            child: Text(
                              context.tr('pay_now'),
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                          ),
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
