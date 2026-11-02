import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import '../../app/routes.dart';
import '../../models/product_model.dart';
import '../../services/api_config.dart';
import '../../utils/phone_utils.dart';
import '../tokens.dart';
import '../widgets/ui_button.dart';

class CheckoutV2Screen extends StatefulWidget {
  const CheckoutV2Screen({super.key, required this.product});

  final Product product;

  @override
  State<CheckoutV2Screen> createState() => _CheckoutV2ScreenState();
}

class _CheckoutV2ScreenState extends State<CheckoutV2Screen> {
  final _region = TextEditingController();
  final _district = TextEditingController();
  final _street = TextEditingController();
  final _phone = TextEditingController();
  int _qty = 1;
  bool _mobileMoney = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _region.dispose();
    _district.dispose();
    _street.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _error = 'Ingia akaunti kwanza.');
      return;
    }
    if (_region.text.trim().isEmpty || _district.text.trim().isEmpty || _street.text.trim().isEmpty) {
      setState(() => _error = 'Jaza anwani kamili.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final p = widget.product;
      final token = await user.getIdToken();
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/orders/create'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({
          'buyerId': user.uid,
          'buyerName': user.displayName ?? '',
          'buyerPhone': _phone.text.trim().isNotEmpty ? PhoneUtils.toE164(_phone.text.trim()) : (user.phoneNumber ?? ''),
          'sellerId': p.sellerId,
          'sellerName': p.sellerName,
          'productId': p.id,
          'productName': p.name,
          'productImage': p.images.isNotEmpty ? p.images.first : '',
          'productPrice': (p.price * _qty).round(),
          'quantity': _qty,
          'region': _region.text.trim(),
          'district': _district.text.trim(),
          'street': _street.text.trim(),
          'deliveryType': 'standard',
          'preferredPaymentMethod': _mobileMoney ? 'mobile_money' : 'cash',
        }),
      ).timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (resp.statusCode != 200 || data['success'] != true) {
        setState(() => _error = data['error']?.toString() ?? 'Imeshindikana kuunda agizo.');
        return;
      }
      final orderId = data['orderId']?.toString() ?? data['id']?.toString() ?? '';
      if (orderId.isNotEmpty) {
        context.go('${AppRoutes.orderDetail}/$orderId');
      } else {
        context.go(AppRoutes.myPurchases);
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Mtandao: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    return Scaffold(
      appBar: AppBar(title: const Text('Malipo')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(UiSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(p.name, style: Theme.of(context).textTheme.titleMedium),
            Text('TSh ${p.price.round()} x $_qty', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: UiSpace.md),
            Row(
              children: [
                const Text('Kiasi:'),
                const SizedBox(width: UiSpace.sm),
                IconButton(onPressed: _qty > 1 ? () => setState(() => _qty--) : null, icon: const Icon(Icons.remove)),
                Text('$_qty'),
                IconButton(onPressed: () => setState(() => _qty++), icon: const Icon(Icons.add)),
              ],
            ),
            const SizedBox(height: UiSpace.md),
            TextField(controller: _region, decoration: const InputDecoration(labelText: 'Mkoa', border: OutlineInputBorder())),
            const SizedBox(height: UiSpace.sm),
            TextField(controller: _district, decoration: const InputDecoration(labelText: 'Wilaya', border: OutlineInputBorder())),
            const SizedBox(height: UiSpace.sm),
            TextField(controller: _street, decoration: const InputDecoration(labelText: 'Mtaa / Nyumba', border: OutlineInputBorder())),
            const SizedBox(height: UiSpace.sm),
            TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Simu', border: OutlineInputBorder())),
            const SizedBox(height: UiSpace.md),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Mobile money')),
                ButtonSegment(value: false, label: Text('Pesa taslimu')),
              ],
              selected: {_mobileMoney},
              onSelectionChanged: (s) => setState(() => _mobileMoney = s.first),
            ),
            if (_error != null) ...[
              const SizedBox(height: UiSpace.md),
              Text(_error!, style: const TextStyle(color: UiColors.danger)),
            ],
            const SizedBox(height: UiSpace.lg),
            UiPrimaryButton(label: 'Thibitisha agizo', onPressed: _submit, busy: _busy),
          ],
        ),
      ),
    );
  }
}
