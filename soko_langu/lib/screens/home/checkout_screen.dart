import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../../models/product_model.dart';
import '../../services/flash_sale_service.dart';
import '../../services/notification_service.dart';
import '../../extensions/context_tr.dart';
import '../../app/routes.dart';
import '../../widgets/glass_container.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../utils/network_error.dart';

class CheckoutScreen extends StatefulWidget {
  final Product product;

  const CheckoutScreen({super.key, required this.product});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _phoneController = TextEditingController();
  final _regionCtrl = TextEditingController();
  final _districtCtrl = TextEditingController();
  final _streetCtrl = TextEditingController();
  final _landmarksCtrl = TextEditingController();
  bool _processing = false;
  double? _salePrice;

  double get _totalPrice => _salePrice ?? widget.product.price;
  double get _serviceFeePercent => 3.5;
  double get _serviceFee => _totalPrice * _serviceFeePercent / 100;
  double get _sellerReceives => _totalPrice;
  double get _totalWithFee => _totalPrice + _serviceFee;

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
    _regionCtrl.dispose();
    _districtCtrl.dispose();
    _streetCtrl.dispose();
    _landmarksCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = widget.product;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('checkout')),
        centerTitle: true,
        backgroundColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // Product glass card
          GlassContainer(
            blur: 20,
            opacity: isDark ? 0.12 : 0.08,
            borderRadius: 20,
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 64, height: 64,
                    color: cs.surfaceContainerHighest,
                    child: p.images.isNotEmpty
                        ? CachedNetworkImage(imageUrl: p.images.first, fit: BoxFit.cover, width: 64, height: 64)
                        : Icon(Icons.image, size: 28, color: cs.onSurfaceVariant),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: cs.onSurface), maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Text('${context.tr('quantity_prefix').replaceAll('{0}', '1')}${_salePrice != null ? context.formatPrice(_salePrice!) : context.formatPrice(p.price)}',
                          style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600, fontSize: 15)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Fee breakdown glass card
          Text(context.tr('payment_details'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: cs.onSurface)),
          const SizedBox(height: 12),
          GlassContainer(
            blur: 24,
            opacity: isDark ? 0.1 : 0.06,
            borderRadius: 20,
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _feeRow(cs, context.tr('product_price'), context.formatPrice(_totalPrice), cs.onSurface),
                const SizedBox(height: 8),
                _feeRow(cs, context.tr('service_fee_percent').replaceAll('{0}', '$_serviceFeePercent'), context.formatPrice(_serviceFee), cs.tertiary),
                const SizedBox(height: 8),
                Container(height: 1, color: cs.primary.withValues(alpha: 0.1)),
                const SizedBox(height: 10),
                _feeRow(cs, context.tr('mongike_fee'), 'Bure', Colors.green),
                const SizedBox(height: 10),
                Container(height: 1, color: cs.primary.withValues(alpha: 0.1)),
                const SizedBox(height: 10),
                _feeRow(cs, context.tr('total_payment'), context.formatPrice(_totalWithFee), cs.primary, bold: true),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [cs.primary.withValues(alpha: 0.06), cs.secondary.withValues(alpha: 0.04)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cs.primary.withValues(alpha: 0.1)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline, size: 14, color: cs.primary),
                          const SizedBox(width: 6),
                          Text(context.tr('payment_breakdown'),
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurface)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _feeRow(cs, context.tr('seller_receives_full'), context.formatPrice(_sellerReceives), cs.primary),
                      const SizedBox(height: 4),
                      _feeRow(cs, context.tr('service_fee_percent').replaceAll('{0}', '$_serviceFeePercent'), context.formatPrice(_serviceFee), cs.onSurfaceVariant),
                      const SizedBox(height: 4),
                      _feeRow(cs, context.tr('mongike_fee'), 'Bure', Colors.green),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.local_shipping_outlined, size: 12, color: cs.primary),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                context.tr('shipping_quote_info'),
                                style: TextStyle(fontSize: 10, color: cs.primary.withValues(alpha: 0.7)),
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
          const SizedBox(height: 20),

          // Delivery address
          Text(context.tr('shipping_address'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: cs.onSurface)),
          const SizedBox(height: 12),
          GlassContainer(
            blur: 16,
            opacity: isDark ? 0.08 : 0.05,
            borderRadius: 16,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(controller: _regionCtrl, decoration: InputDecoration(hintText: context.tr('region_hint'), border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, filled: true, fillColor: cs.surface.withValues(alpha: 0.5), isDense: true), textCapitalization: TextCapitalization.words, cursorColor: cs.primary),
                const SizedBox(height: 10),
                TextField(controller: _districtCtrl, decoration: InputDecoration(hintText: context.tr('district_hint'), border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, filled: true, fillColor: cs.surface.withValues(alpha: 0.5), isDense: true), textCapitalization: TextCapitalization.words, cursorColor: cs.primary),
                const SizedBox(height: 10),
                TextField(controller: _streetCtrl, decoration: InputDecoration(hintText: context.tr('street_hint'), border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, filled: true, fillColor: cs.surface.withValues(alpha: 0.5), isDense: true), textCapitalization: TextCapitalization.words, cursorColor: cs.primary),
                const SizedBox(height: 10),
                TextField(controller: _landmarksCtrl, decoration: InputDecoration(hintText: context.tr('landmarks_hint'), border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, filled: true, fillColor: cs.surface.withValues(alpha: 0.5), isDense: true), textCapitalization: TextCapitalization.words, cursorColor: cs.primary),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Phone
          Text(context.tr('phone'), style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14, color: cs.onSurface)),
          const SizedBox(height: 8),
          GlassContainer(
            blur: 16,
            opacity: isDark ? 0.08 : 0.05,
            borderRadius: 14,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                hintText: context.tr('phone_hint'),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                prefixIcon: Icon(Icons.phone_android, color: cs.primary, size: 20),
              ),
              style: TextStyle(color: cs.onSurface),
              cursorColor: cs.primary,
            ),
          ),
          const SizedBox(height: 16),

          // Info card
          GlassContainer(
            blur: 18,
            opacity: isDark ? 0.1 : 0.06,
            borderRadius: 16,
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: cs.secondary, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    context.tr('shipping_info_message'),
                    style: TextStyle(color: cs.secondary, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Submit button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _processing ? null : _submitOrder,
              icon: _processing
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send_rounded, size: 20),
              label: Text(_processing ? context.tr('sending') : context.tr('submit_shipping_request'),
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              style: ElevatedButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: cs.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () => context.pop(),
            icon: const Icon(Icons.arrow_back, size: 18),
            label: Text(context.tr('cancel')),
          ),
        ],
      ),
    );
  }

  Widget _feeRow(ColorScheme cs, String label, String value, Color valueColor, {bool bold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant, fontWeight: bold ? FontWeight.w600 : FontWeight.w400)),
        Text(value, style: TextStyle(fontSize: 15, fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: valueColor)),
      ],
    );
  }

  Future<void> _submitOrder() async {
    final phone = _phoneController.text.trim();
    final region = _regionCtrl.text.trim();
    final district = _districtCtrl.text.trim();
    final street = _streetCtrl.text.trim();

    if (phone.isEmpty) { _showError(context.tr('enter_phone_error')); return; }
    final phoneDigits = phone.replaceAll(RegExp(r'\D'), '');
    final normalizedPhone = phoneDigits.startsWith('0')
        ? '255${phoneDigits.substring(1)}'
        : phoneDigits.startsWith('255')
            ? phoneDigits
            : '255$phoneDigits';
    if (region.isEmpty || district.isEmpty || street.isEmpty) { _showError(context.tr('fill_full_address_error')); return; }

    setState(() => _processing = true);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) { _showError(context.tr('ingia_akaunti_kwanza')); setState(() => _processing = false); return; }

    try {
      final p = widget.product;
      final activeFs = await FlashSaleService().streamFlashSaleByProductId(p.id).first;
      if (activeFs != null && activeFs.isExpired) { _showError(context.tr('flash_sale_expired')); setState(() => _processing = false); return; }

      final orderId = 'q${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}${user.uid.substring(0, 4)}';

      await FirebaseFirestore.instance.collection('transactions').doc(orderId).set({
        'type': 'purchase',
        'productId': p.id,
        'productName': p.name,
        'sellerId': p.sellerId,
        'sellerName': p.sellerName,
        'buyerPhone': normalizedPhone,
        'buyerId': user.uid,
        'buyerName': user.displayName ?? '',
        'productPrice': _totalPrice,
        'mongikeFee': 180,
        'serviceFeePercent': _serviceFeePercent,
        'deliveryAddress': {
          'region': region,
          'district': district,
          'street': street,
          'landmarks': _landmarksCtrl.text.trim(),
        },
        'status': 'awaiting_shipping_quote',
        'paymentMethod': 'Mongike',
        'createdAt': FieldValue.serverTimestamp(),
      });

      try {
        NotificationService().sendNotification(
          userId: p.sellerId,
          title: context.tr('new_order_title'),
          body: context.tr('new_order_body')
              .replaceAll('{0}', user.displayName ?? context.tr('customer'))
              .replaceAll('{1}', p.name),
          data: {'type': 'order', 'transactionId': orderId},
        );
      } catch (_) {}

      if (mounted) {
        setState(() => _processing = false);
        _showSuccess(context.tr('order_submitted_success'));
        context.go(AppRoutes.myPurchases);
      }
    } catch (e) {
      final friendly = translateError(e);
      _showError(friendly);
      setState(() => _processing = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Theme.of(context).colorScheme.error));
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Theme.of(context).colorScheme.primary));
  }
}
