import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import '../../models/product_model.dart';
import '../../services/flash_sale_service.dart';
import '../../services/notification_service.dart';
import '../../services/api_config.dart';
import '../../extensions/context_tr.dart';
import '../../app/routes.dart';
import '../../widgets/glass_container.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../utils/network_error.dart';
import '../../services/clickpesa_service.dart';
import '../../widgets/payment_banner.dart';
import '../../widgets/payment_result_dialog.dart';

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
  double _walletBalance = 0;
  bool _walletLoading = true;
  String _selectedMethod = 'ussd_push';
  List<Map<String, dynamic>> _methods = [];
  bool _methodsLoading = true;
  double _gatewayFee = 0;

  double get _totalPrice => _salePrice ?? widget.product.price;

  double get _serviceFeePercent => 3.5;
  double get _serviceFee => _totalPrice * _serviceFeePercent / 100;

  double get _sellerReceives => _totalPrice;
  double get _totalWithFee => _totalPrice + _serviceFee + _gatewayFee;
  bool get _walletSufficient => _walletBalance >= _totalWithFee;

  bool get _needsPhone => _selectedMethod == 'ussd_push' || _selectedMethod == 'billpay';

  @override
  void initState() {
    super.initState();
    _loadFlashSale();
    _loadWalletBalance();
    _loadMethods();
  }

  Future<void> _loadFlashSale() async {
    final fs = await FlashSaleService()
        .streamFlashSaleByProductId(widget.product.id)
        .first;
    if (fs != null && mounted) {
      setState(() => _salePrice = fs.salePrice);
      _fetchGatewayFee();
    }
  }

  Future<void> _loadWalletBalance() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) { setState(() => _walletLoading = false); return; }
    try {
      final resp = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/wallet/balance/${user.uid}'),
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        _walletBalance = (data['balance'] as num?)?.toDouble() ?? 0;
      }
    } catch (_) {}
    setState(() => _walletLoading = false);
  }

  Future<void> _loadMethods() async {
    try {
      final resp = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/payment-methods'),
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        _methods = (data['methods'] as List?)
            ?.map((e) => e as Map<String, dynamic>)
            .toList() ?? [];
        if (_methods.isNotEmpty && _methods.any((m) => m['id'] == _selectedMethod) == false) {
          _selectedMethod = _methods.first['id'] as String? ?? 'ussd_push';
        }
      }
    } catch (_) {}
    setState(() => _methodsLoading = false);
    _fetchGatewayFee();
  }

  Future<void> _fetchGatewayFee() async {
    try {
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/gateway-fee'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'method': _selectedMethod,
          'amount': _totalPrice.round(),
        }),
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        if (mounted) setState(() => _gatewayFee = (data['fee'] as num).toDouble());
      }
    } catch (_) {}
  }

  IconData _methodIcon(String id) {
    switch (id) {
      case 'wallet': return Icons.account_balance_wallet;
      case 'ussd_push': return Icons.phone_android;
      case 'billpay': return Icons.receipt_long;
      default: return Icons.payment;
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
                _feeRow(cs, context.tr('processing_fee'), '${_gatewayFee.toInt()} TZS', cs.secondary),
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
                      _feeRow(cs, context.tr('processing_fee'), '${_gatewayFee.toInt()} TZS', cs.secondary),
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

          // Payment method selection
          Text(context.tr('payment_method'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: cs.onSurface)),
          const SizedBox(height: 12),
          GlassContainer(
            blur: 16,
            opacity: isDark ? 0.08 : 0.05,
            borderRadius: 16,
            padding: const EdgeInsets.all(16),
            child: _methodsLoading
                ? const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(strokeWidth: 2)))
                : Column(
                    children: _methods.map((m) {
                      final id = m['id'] as String? ?? '';
                      final name = m['name'] as String? ?? id;
                      final nameSw = m['nameSw'] as String? ?? name;
                      final selected = _selectedMethod == id;
                      final feeLabel = m['feeLabel'] as String? ?? '';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            setState(() => _selectedMethod = id);
                            _fetchGatewayFee();
                          },
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: selected ? cs.primary : Colors.transparent, width: 1.5),
                              color: selected ? cs.primary.withValues(alpha: 0.06) : Colors.transparent,
                            ),
                            child: Row(
                              children: [
                                Icon(_methodIcon(id), color: selected ? cs.primary : cs.onSurfaceVariant, size: 26),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(name,
                                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: selected ? cs.primary : cs.onSurface)),
                                      if (id == 'wallet' && !_walletLoading)
                                        Text('${context.tr('wallet_balance')}: TZS ${_walletBalance.toStringAsFixed(0)}',
                                          style: TextStyle(fontSize: 11, color: _walletSufficient ? Colors.green : cs.error)),
                                      if (feeLabel.isNotEmpty && id != 'wallet')
                                        Text(feeLabel,
                                          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                                    ],
                                  ),
                                ),
                                Text(selected ? '✓' : '',
                                  style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700, fontSize: 16)),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
          ),
          const SizedBox(height: 20),

          // Phone (only for methods that need it)
          if (_needsPhone) ...[
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
          ],

          // Info card
          GlassContainer(
            blur: 18,
            opacity: isDark ? 0.1 : 0.06,
            borderRadius: 16,
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(_selectedMethod == 'wallet' ? Icons.account_balance_wallet : Icons.info_outline, color: cs.secondary, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _selectedMethod == 'wallet'
                        ? context.tr('wallet_payment_info')
                        : 'Ada ya gateway: TZS ${_gatewayFee.toInt()} + Commission ${_serviceFeePercent}% = Jumla TZS ${_totalWithFee.toInt()}',
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
                  : Icon(_selectedMethod == 'wallet' ? Icons.account_balance_wallet : Icons.send_rounded, size: 20),
              label: Text(
                _processing
                    ? context.tr('sending')
                    : _selectedMethod == 'wallet'
                        ? context.tr('pay_with_wallet').replaceAll('{0}', 'TZS ${_totalWithFee.toStringAsFixed(0)}')
                        : 'Lipa TZS ${_totalWithFee.toInt()}',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              style: ElevatedButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: cs.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
            ),
          ),
          if (_selectedMethod == 'wallet' && !_walletSufficient && !_walletLoading)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                context.tr('wallet_insufficient'),
                style: TextStyle(color: cs.error, fontSize: 13),
                textAlign: TextAlign.center,
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
    final region = _regionCtrl.text.trim();
    final district = _districtCtrl.text.trim();
    final street = _streetCtrl.text.trim();

    String normalizedPhone = '';
    if (_needsPhone) {
      final phone = _phoneController.text.trim();
      if (phone.isEmpty) { _showError(context.tr('enter_phone_error')); return; }
      final phoneDigits = phone.replaceAll(RegExp(r'\D'), '');
      normalizedPhone = phoneDigits.startsWith('0')
          ? '255${phoneDigits.substring(1)}'
          : phoneDigits.startsWith('255')
              ? phoneDigits
              : '255$phoneDigits';
    }
    if (region.isEmpty || district.isEmpty || street.isEmpty) { _showError(context.tr('fill_full_address_error')); return; }

    setState(() => _processing = true);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) { _showError(context.tr('ingia_akaunti_kwanza')); setState(() => _processing = false); return; }

    try {
      final p = widget.product;
      final activeFs = await FlashSaleService().streamFlashSaleByProductId(p.id).first;
      if (activeFs != null && activeFs.isExpired) { _showError(context.tr('flash_sale_expired')); setState(() => _processing = false); return; }

      if (_selectedMethod == 'wallet') {
        if (!_walletSufficient) {
          _showError(context.tr('wallet_insufficient'));
          setState(() => _processing = false);
          return;
        }

        final resp = await http.post(
          Uri.parse('${ApiConfig.baseUrl}/api/wallet/purchase'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'buyerId': user.uid,
            'buyerName': user.displayName ?? '',
            'productId': p.id,
            'productName': p.name,
            'productImage': p.images.isNotEmpty ? p.images.first : '',
            'productPrice': _totalPrice,
            'sellerId': p.sellerId,
            'sellerName': p.sellerName,
            'processingFee': _gatewayFee,
            'serviceFeePercent': _serviceFeePercent,
            'totalAmount': _totalWithFee,
            'region': region,
            'district': district,
            'street': street,
            'landmarks': _landmarksCtrl.text.trim(),
            'paymentMethod': _selectedMethod,
          }),
        );

        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        if (resp.statusCode != 200 || data['success'] != true) {
          _showError(data['error'] ?? context.tr('wallet_purchase_failed'));
          setState(() => _processing = false);
          return;
        }

        try {
          NotificationService().sendNotification(
            userId: p.sellerId,
            title: context.tr('new_order_title'),
            body: context.tr('new_order_body')
                .replaceAll('{0}', user.displayName ?? context.tr('customer'))
                .replaceAll('{1}', p.name),
            data: {'type': 'order', 'transactionId': data['orderId'] ?? ''},
          );
        } catch (_) {}

        if (mounted) {
          setState(() => _processing = false);
          _showSuccess(context.tr('order_submitted_success'));
          context.go(AppRoutes.myPurchases);
        }
      } else {
        final email = user.email ?? '';
        final result = await ClickPesaService.initiateMarketplacePayment(
          productPrice: _totalPrice.toDouble(),
          productName: p.name,
          productId: p.id,
          sellerId: p.sellerId,
          sellerName: p.sellerName,
          email: email,
          phone: normalizedPhone,
          buyerId: user.uid,
          buyerName: user.displayName ?? '',
          deliveryType: 'local',
        );

        if (result == null || result['order_id'] == null) {
          final errMsg = result?['error'] as String? ?? context.tr('payment_initiation_failed');
          _showError(errMsg);
          setState(() => _processing = false);
          return;
        }

        final orderId = result['order_id'] as String;

        await FirebaseFirestore.instance.collection('transactions').doc(orderId).update({
          'deliveryAddress': {
            'region': region,
            'district': district,
            'street': street,
            'landmarks': _landmarksCtrl.text.trim(),
          },
          'paymentMethod': _selectedMethod,
          'buyerPhone': normalizedPhone,
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
          RealtimePaymentBanner.show(
            context: context,
            orderId: orderId,
            successStatuses: ['escrow_hold', 'paid_escrow_held'],
            processingTitle: context.tr('processing_payment'),
            processingSubtitle: context.tr('check_phone_enter_pin'),
            successTitle: context.tr('payment_successful'),
            failedTitle: context.tr('payment_failed'),
            onSuccess: () {
              if (mounted) context.go(AppRoutes.myPurchases);
            },
            onError: (msg) {
              if (mounted) {
                PaymentResult.show(
                  context: context,
                  success: false,
                  errorMessage: msg,
                );
              }
            },
          );
        }
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
