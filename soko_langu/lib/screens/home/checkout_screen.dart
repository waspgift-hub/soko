import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/product_model.dart';
import '../../services/api_config.dart';
import '../../extensions/context_tr.dart';
import '../../app/routes.dart';
import '../../widgets/glass_container.dart';
import '../../utils/network_error.dart';

class CheckoutScreen extends StatefulWidget {
  final Product product;

  const CheckoutScreen({super.key, required this.product});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _regionCtrl = TextEditingController();
  final _districtCtrl = TextEditingController();
  final _streetCtrl = TextEditingController();
  final _landmarksCtrl = TextEditingController();
  bool _processing = false;

  @override
  void dispose() {
    _regionCtrl.dispose();
    _districtCtrl.dispose();
    _streetCtrl.dispose();
    _landmarksCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final p = widget.product;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('checkout')),
        centerTitle: true,
        backgroundColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
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
                      Text(context.formatPrice(p.price),
                          style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600, fontSize: 15)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          GlassContainer(
            blur: 16,
            opacity: isDark ? 0.08 : 0.05,
            borderRadius: 16,
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: cs.primary, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Unaweka agizo bila malipo. Muuzaji atakupa gharama ya usafirishaji, kisha utalipa.',
                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

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
          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _processing ? null : _submitOrder,
              icon: _processing
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send_rounded, size: 20),
              label: Text(
                _processing ? context.tr('sending') : context.tr('flow_place_order'),
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

  Future<void> _submitOrder() async {
    final region = _regionCtrl.text.trim();
    final district = _districtCtrl.text.trim();
    final street = _streetCtrl.text.trim();
    if (region.isEmpty || district.isEmpty || street.isEmpty) {
      _showError(context.tr('fill_full_address_error'));
      return;
    }

    setState(() => _processing = true);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) { _showError(context.tr('ingia_akaunti_kwanza')); setState(() => _processing = false); return; }

    try {
      final p = widget.product;
      final token = await user.getIdToken();
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/orders/create'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'buyerId': user.uid,
          'buyerName': user.displayName ?? '',
          'buyerPhone': user.phoneNumber ?? '',
          'sellerId': p.sellerId,
          'sellerName': p.sellerName,
          'productId': p.id,
          'productName': p.name,
          'productImage': p.images.isNotEmpty ? p.images.first : '',
          'productPrice': p.price,
          'region': region,
          'district': district,
          'street': street,
          'landmarks': _landmarksCtrl.text.trim(),
          'deliveryType': 'local',
        }),
      );

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (resp.statusCode != 200 || data['success'] != true) {
        _showError(data['error'] ?? 'Failed to create order');
        setState(() => _processing = false);
        return;
      }

      final orderData = data['order'] as Map<String, dynamic>;
      if (mounted) {
        setState(() => _processing = false);
        context.push('${AppRoutes.orderDetail}/${orderData['orderId']}', extra: orderData);
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
}
