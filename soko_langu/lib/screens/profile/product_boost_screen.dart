import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../models/product_model.dart';
import '../../models/boost_tier.dart';
import '../../services/boost_service.dart';
import '../../extensions/context_tr.dart';
import '../../widgets/google_loading.dart';
import '../../app/routes.dart';

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
    final bgColor = brightness == Brightness.dark
        ? const Color(0xFF0D1117)
        : const Color(0xFFF8F9FA);
    final cardBg = brightness == Brightness.dark
        ? const Color(0xFF161B22)
        : Colors.white;

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
          _buildSectionTitle('Choose your boost package'),
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
        border: Border.all(color: Colors.white.withAlpha(20)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 64,
              height: 64,
              color: Colors.grey.shade800,
              child: widget.product.images.isNotEmpty
                  ? Image.network(
                      widget.product.images.first,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Icon(Icons.image,
                          color: Colors.grey),
                    )
                  : const Icon(Icons.image, color: Colors.grey),
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
                color: Colors.green.shade600.withAlpha(30),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.green.shade600.withAlpha(80)),
              ),
              child: Text(
                'Active',
                style: TextStyle(
                  color: Colors.green.shade400,
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
        accentColor = const Color(0xFFCD7F32);
        icon = Icons.emoji_events;
      case BoostTier.silver:
        accentColor = const Color(0xFF9E9E9E);
        icon = Icons.workspace_premium;
      case BoostTier.gold:
        accentColor = const Color(0xFFFFD700);
        icon = Icons.verified;
    }

    return GestureDetector(
      onTap: _processing ? null : () => setState(() => _selectedTier = tier),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isSelected
              ? accentColor.withAlpha(18)
              : cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? accentColor : Colors.white.withAlpha(15),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: accentColor.withAlpha(30),
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
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: accentColor.withAlpha(40),
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
                          color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
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
                  color: isSelected ? accentColor : Colors.grey.shade500,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
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
                    ? const Color(0xFFFFD700).withAlpha(15)
                    : _selectedTier == BoostTier.silver
                        ? const Color(0xFF9E9E9E).withAlpha(15)
                        : const Color(0xFFCD7F32).withAlpha(15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 18, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'You will be prompted to complete payment via Mongike after tapping continue.',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
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
              backgroundColor: const Color(0xFF065535),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
            child: _processing
                ? const GoogleLoading(size: 20, strokeWidth: 2)
                : Text(
                    _selectedTier == null
                        ? 'Select a package'
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
        if (mounted) _showError('Please log in first');
        return;
      }

      final result = await BoostService().initiateBoostPayment(
        productId: widget.product.id,
        tier: tier,
        phone: phone,
        userId: user.uid,
      );

      if (result == null || result['order_id'] == null) {
        if (mounted) _showError('Payment initiation failed');
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
        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('transactions')
              .doc(orderId)
              .snapshots(),
          builder: (context, snap) {
            final data = snap.data?.data() as Map<String, dynamic>?;
            final status = data?['status'] as String? ?? 'pending';

            if (status == 'completed') {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                Navigator.pop(ctx);
                if (mounted) _onPaymentSuccess();
              });
              return const AlertDialog(
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 64),
                    SizedBox(height: 16),
                    Text('Payment Successful!',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    SizedBox(height: 8),
                    Text('Your product is now boosted.',
                        style: TextStyle(color: Colors.grey)),
                  ],
                ),
              );
            }

            if (status == 'failed') {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                Navigator.pop(ctx);
                if (mounted) _showError('Payment failed. Try again.');
              });
              return const AlertDialog(
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cancel, color: Colors.red, size: 64),
                    SizedBox(height: 16),
                    Text('Payment Failed',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
              );
            }

            return AlertDialog(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const GoogleLoading(size: 24, strokeWidth: 2),
                  const SizedBox(height: 20),
                  const Text(
                    'Processing Payment...',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Complete payment on your phone via Mongike.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _onPaymentSuccess() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${_selectedTier!.displayName} boost activated for ${_selectedTier!.durationDays} days!',
        ),
        backgroundColor: Colors.green.shade600,
      ),
    );
    context.go(AppRoutes.sellerDashboard);
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }
}
