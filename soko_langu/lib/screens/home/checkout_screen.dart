import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import '../../models/product_model.dart';
import '../../services/flash_sale_service.dart';
import '../../services/payment_service.dart';
import '../../services/api_config.dart';
import '../../extensions/context_tr.dart';
import '../../app/routes.dart';
import '../../widgets/google_loading.dart';
import '../../widgets/payment_banner.dart';

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

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('checkout')), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 56, height: 56,
                      color: cs.surfaceContainerHighest,
                      child: p.images.isNotEmpty
                          ? Image.network(p.images.first, fit: BoxFit.cover)
                          : Icon(Icons.image, size: 28, color: cs.onSurfaceVariant),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text('x1  ${_salePrice != null ? context.formatPrice(_salePrice!) : context.formatPrice(p.price)}',
                            style: TextStyle(color: cs.onSurface.withValues(alpha: 0.59), fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('Anwani ya Usafirishaji', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: cs.onSurface)),
          const SizedBox(height: 12),
          TextField(controller: _regionCtrl, decoration: const InputDecoration(labelText: 'Mkoa / Region', border: OutlineInputBorder(), isDense: true), textCapitalization: TextCapitalization.words),
          const SizedBox(height: 10),
          TextField(controller: _districtCtrl, decoration: const InputDecoration(labelText: 'Wilaya / District', border: OutlineInputBorder(), isDense: true), textCapitalization: TextCapitalization.words),
          const SizedBox(height: 10),
          TextField(controller: _streetCtrl, decoration: const InputDecoration(labelText: 'Mtaa / Street', border: OutlineInputBorder(), isDense: true), textCapitalization: TextCapitalization.words),
          const SizedBox(height: 10),
          TextField(controller: _landmarksCtrl, decoration: const InputDecoration(labelText: 'Alama za Jirani / Landmarks', border: OutlineInputBorder(), isDense: true), textCapitalization: TextCapitalization.words),
          const SizedBox(height: 20),
          Text('Namba ya Simu', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14, color: cs.onSurface)),
          const SizedBox(height: 8),
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(hintText: context.tr('phone_hint'), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), prefixIcon: const Icon(Icons.phone_android)),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: cs.secondary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: cs.secondary.withValues(alpha: 0.3))),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: cs.secondary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Muuzaji atatoa gharama ya usafirishaji. Utalipa jumla ya bidhaa + usafirishaji baada ya kukubaliana.',
                    style: TextStyle(color: cs.secondary, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _processing ? null : _submitOrder,
              icon: _processing ? const GoogleLoading(size: 20, strokeWidth: 2) : const Icon(Icons.send),
              label: Text(_processing ? 'Inatuma...' : 'Tuma Ombi la Usafirishaji'),
              style: ElevatedButton.styleFrom(backgroundColor: cs.primary, foregroundColor: cs.surface, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
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
    final phone = _phoneController.text.trim();
    final region = _regionCtrl.text.trim();
    final district = _districtCtrl.text.trim();
    final street = _streetCtrl.text.trim();

    if (phone.isEmpty) { _showError('Tafadhali ingiza namba ya simu'); return; }
    final phoneDigits = phone.replaceAll(RegExp(r'\D'), '');
    final normalizedPhone = phoneDigits.startsWith('0')
        ? '255${phoneDigits.substring(1)}'
        : phoneDigits.startsWith('255')
            ? phoneDigits
            : '255$phoneDigits';
    if (region.isEmpty || district.isEmpty || street.isEmpty) { _showError('Tafadhali jaza anwani kamili (Mkoa, Wilaya, Mtaa)'); return; }

    setState(() => _processing = true);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) { _showError(context.tr('ingia_akaunti_kwanza')); setState(() => _processing = false); return; }

    try {
      final p = widget.product;
      final activeFs = await FlashSaleService().streamFlashSaleByProductId(p.id).first;
      if (activeFs != null && activeFs.isExpired) { _showError(context.tr('flash_sale_expired')); setState(() => _processing = false); return; }

      final orderId = await PaymentService().processTransaction(
        buyerId: user.uid,
        buyerName: user.displayName ?? '',
        buyerPhone: normalizedPhone,
        sellerId: p.sellerId,
        sellerName: p.sellerName,
        productId: p.id,
        productName: p.name,
        productPrice: _totalPrice,
      );

      // Save delivery address separately since processTransaction doesn't include it
      await FirebaseFirestore.instance.collection('transactions').doc(orderId).update({
        'deliveryAddress': {
          'region': region,
          'district': district,
          'street': street,
          'landmarks': _landmarksCtrl.text.trim(),
        },
        'status': 'awaiting_shipping_quote',
        'paymentMethod': 'Mongike',
      });

      // Notify seller about new order
      try {
        final resp = await http.post(
          Uri.parse('${ApiConfig.baseUrl}/api/send-notification'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'userId': p.sellerId,
            'title': 'Order Mpya Imewasilishwa!',
            'body': '${user.displayName ?? 'Mnunuzi'} anataka kununua ${p.name}. '
                'Ingiza gharama ya usafirishaji.',
            'data': {'type': 'order', 'transactionId': orderId},
          }),
        );
        if (resp.statusCode != 200) {
          debugPrint('sendNotification failed: ${_tryParseServerError(resp)}');
        }
      } catch (e) {
        debugPrint('sendNotification error: $e');
      }

      if (mounted) {
        setState(() => _processing = false);
        RealtimePaymentBanner.show(
          context: context,
          orderId: orderId,
          successStatuses: ['awaiting_shipping_quote'],
          processingTitle: 'Inachakata ombi lako...',
          successTitle: 'Ombi Limetumwa!',
          successSubtitle: 'Muuzaji atakupa gharama ya usafirishaji.',
          failedTitle: 'Ombi Limeshindikana',
          onSuccess: () => context.go(AppRoutes.myPurchases),
        );
      }
    } catch (e) {
      setState(() => _processing = false);
      _showError('Hitilafu: $e');
    }
  }

  /// Detects Express/Render HTML error pages and returns a user-friendly message.
  String _tryParseServerError(http.Response resp) {
    final body = resp.body;
    if (body.startsWith('<html') || body.contains('<!DOCTYPE')) {
      return 'Server error (${resp.statusCode}). Tafadhali jaribu tena baadaye.';
    }
    try {
      final decoded = jsonDecode(body);
      return decoded['error'] ?? decoded['message'] ?? 'Unknown error';
    } on FormatException {
      return 'Server error (${resp.statusCode}). Tafadhali jaribu tena.';
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Theme.of(context).colorScheme.error));
  }


}
