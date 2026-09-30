import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/product_model.dart';
import '../../services/product_service.dart';
import '../../services/boost_service.dart';
import '../../extensions/context_tr.dart';
import '../../theme/app_colors.dart';
import '../../widgets/ds/ds.dart';
import '../../widgets/product_cached_image.dart';
import '../../widgets/commerce/payment_method_tile.dart';

/// Boost purchase screen: pick a product, pick a package, pay with mobile
/// money. The server activates the boost (product doc flips isBoosted) once
/// the ClickPesa webhook confirms the payment, so this screen only starts the
/// payment and renders the USSD/BillPay instructions.
class BoostProductScreen extends StatefulWidget {
  /// Optional preselect — when null (e.g. the seller dashboard quick action),
  /// the seller picks one of their own products first.
  final String? productId;
  final Product? product;

  const BoostProductScreen({super.key, this.productId, this.product});

  @override
  State<BoostProductScreen> createState() => _BoostProductScreenState();
}

class _TierInfo {
  final String key;
  final int price;
  final int days;
  const _TierInfo(this.key, this.price, this.days);
}

const _tiers = [
  _TierInfo('bronze', 1500, 3),
  _TierInfo('silver', 3000, 7),
  _TierInfo('gold', 10000, 30),
];

const _providers = [
  ('mpesa', 'M-Pesa'),
  ('tigo', 'Tigo Pesa'),
  ('airtel', 'Airtel Money'),
  ('halopesa', 'HaloPesa'),
  ('ezy', 'EzyPesa'),
  ('crdb', 'CRDB'),
];

class _BoostProductScreenState extends State<BoostProductScreen> {
  final ProductService _productService = ProductService();
  final TextEditingController _phoneCtrl = TextEditingController();

  bool _loadingProducts = true;
  List<Product> _mine = [];
  Product? _product;
  String _tier = 'silver';
  String _provider = 'mpesa';
  bool _useBillPay = false;
  bool _paying = false;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    if (user?.phoneNumber != null) {
      _phoneCtrl.text = user!.phoneNumber!;
    }
    _product = widget.product;
    _load();
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    // getMyProducts emits one list (v1 is HTTP, not a stream).
    _productService.getMyProducts().take(1).listen((products) {
      if (!mounted) return;
      setState(() {
        _mine = products;
        if (_product == null && widget.productId != null) {
          for (final p in _mine) {
            if (p.id == widget.productId) _product = p;
          }
        }
        _product ??= _mine.isNotEmpty ? _mine.first : null;
        _loadingProducts = false;
      });
    });
  }

  Future<void> _pickProduct() async {
    final picked = await showModalBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final cs = Theme.of(context).colorScheme;
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          builder: (context, scrollCtrl) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  context.tr('boost_pick_product'),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface,
                  ),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  controller: scrollCtrl,
                  itemCount: _mine.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final p = _mine[i];
                    final selected = _product?.id == p.id;
                    return ListTile(
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 48,
                          height: 48,
                          child: ProductCachedImage(
                            url: p.images.isNotEmpty ? p.images[0] : null,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(context.formatPriceInt(p.price.toInt(), currencyOverride: 'TZS')),
                      trailing: selected
                          ? Icon(Icons.check_circle, color: cs.primary)
                          : null,
                      onTap: () => Navigator.pop(context, p),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
    if (picked != null) setState(() => _product = picked);
  }

  _TierInfo get _tierInfo =>
      _tiers.firstWhere((t) => t.key == _tier, orElse: () => _tiers[1]);

  Future<void> _pay() async {
    final product = _product;
    if (product == null) return;
    final phone = _phoneCtrl.text.trim();
    if (phone.length < 9) {
      _showError(context.tr('boost_phone_hint'));
      return;
    }
    setState(() => _paying = true);
    try {
      final res = await BoostService.initBoostProduct(
        productId: product.id,
        productName: product.name,
        productImage: product.images.isNotEmpty ? product.images[0] : null,
        productPrice: product.price,
        tier: _tierInfo.key,
        phone: phone,
        paymentMethod: _useBillPay ? 'billpay' : 'ussd_push',
        provider: _provider,
      );
      if (!mounted) return;
      if (res['error'] != null) {
        _showError('${res['error']}');
        return;
      }
      if (_useBillPay) {
        _showBillPay(res);
      } else {
        _showUssdSent(res);
      }
    } catch (e) {
      if (mounted) _showError(context.trError(e));
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  void _showUssdSent(Map<String, dynamic> res) {
    final amount = (res['totalAmount'] ?? res['amount'] ?? _tierInfo.price).toString();
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary, size: 40),
        title: Text(context.tr('boost_complete')),
        content: Text(context.trParams('boost_push_sent', {'amount': amount})),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.tr('boost_done')),
          ),
        ],
      ),
    );
  }

  void _showBillPay(Map<String, dynamic> res) {
    final number = (res['billPayNumber'] ?? '').toString();
    final total = (res['totalAmount'] ?? res['amount'] ?? _tierInfo.price).toString();
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final cs = Theme.of(context).colorScheme;
        return AlertDialog(
          icon: Icon(Icons.receipt_long, color: cs.primary, size: 40),
          title: Text(context.tr('boost_receipt_title')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.trParams('boost_billpay_number', {'number': number}),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: cs.onSurface),
              ),
              const SizedBox(height: 12),
              Text(
                context.trParams('boost_billpay_instructions', {'amount': total}),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.tr('boost_done')),
            ),
          ],
        );
      },
    );
  }

  void _showError(String reason) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error, size: 40),
        title: Text(context.tr('boost_error').replaceAll('{reason}', '')),
        content: Text(reason),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.tr('boost_done')),
          ),
        ],
      ),
    );
  }

  Widget _tierCard(int index) {
    final tier = _tiers[index];
    final selected = _tier == tier.key;
    final isPopular = tier.key == 'silver';
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tier = tier.key),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? cs.primary.withValues(alpha: 0.08) : cs.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? cs.primary : cs.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              if (isPopular)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: cs.trendingOrange,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    context.tr('popular'),
                    style: TextStyle(color: cs.surface, fontSize: 9, fontWeight: FontWeight.bold),
                  ),
                ),
              Icon(
                tier.key == 'gold' ? Icons.workspace_premium : Icons.rocket_launch,
                color: selected ? cs.primary : cs.onSurfaceVariant,
                size: 26,
              ),
              const SizedBox(height: 6),
              Text(
                tier.key.toUpperCase(),
                style: TextStyle(fontWeight: FontWeight.w800, color: cs.onSurface, fontSize: 13),
              ),
              const SizedBox(height: 2),
              Text(
                context.formatPriceInt(tier.price, currencyOverride: 'TZS'),
                style: TextStyle(fontWeight: FontWeight.w800, color: cs.primary, fontSize: 13),
              ),
              const SizedBox(height: 2),
              Text(
                context.trParams('boost_days', {'count': '${tier.days}'}),
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final product = _product;
    final canPay = product != null && !_loadingProducts;

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('boost_screen_title'))),
      body: SafeArea(
        child: _loadingProducts
            ? const Center(child: CircularProgressIndicator())
            : product == null
                ? _EmptyState(cs: cs)
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // ── Mission statement ──
                      Text(context.tr('boost_screen_subtitle'),
                          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13, height: 1.4)),
                      const SizedBox(height: 20),

                      // ── Product ──
                      Text(context.tr('boost_choose_product'),
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: _mine.length > 1 ? _pickProduct : null,
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: cs.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: cs.outlineVariant),
                          ),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: SizedBox(
                                  width: 52,
                                  height: 52,
                                  child: ProductCachedImage(
                                    url: product.images.isNotEmpty ? product.images[0] : null,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(product.name,
                                        maxLines: 2, overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurface)),
                                    if (product.isBoostedValid)
                                      Text(context.tr('featured'),
                                          style: TextStyle(color: cs.primary, fontSize: 12, fontWeight: FontWeight.w700)),
                                  ],
                                ),
                              ),
                              if (_mine.length > 1)
                                Icon(Icons.expand_more, color: cs.onSurfaceVariant)
                              else
                                Icon(Icons.check_circle, color: cs.primary, size: 20),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ── Package ──
                      Text(context.tr('boost_package_title'),
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: cs.onSurface)),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < _tiers.length; i++) ...[
                            if (i > 0) const SizedBox(width: 10),
                            _tierCard(i),
                          ],
                        ],
                      ),
                      const SizedBox(height: 10),

                      // ── Benefits ──
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _benefitChip(cs, Icons.search, context.tr('boost_benefit1')),
                          _benefitChip(cs, Icons.workspace_premium, context.tr('boost_benefit2')),
                          _benefitChip(cs, Icons.visibility, context.tr('boost_benefit3')),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(context.tr('boost_package_note'),
                          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12, height: 1.4)),
                      const SizedBox(height: 20),

                      // ── Phone ──
                      TextField(
                        controller: _phoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          labelText: context.tr('boost_phone_label'),
                          hintText: context.tr('boost_phone_hint'),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          prefixIcon: const Icon(Icons.phone_android),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ── Provider ──
                      Text(context.tr('boost_provider_label'),
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final (key, label) in _providers)
                            ChoiceChip(
                              label: Text(label),
                              selected: _provider == key,
                              onSelected: (_) => setState(() => _provider = key),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // ── Method ──
                      Text(context.tr('boost_method_label'),
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
                      const SizedBox(height: 8),
                      PaymentMethodTile(
                        icon: Icons.smartphone,
                        label: context.tr('boost_method_ussd'),
                        selected: !_useBillPay,
                        onTap: () => setState(() => _useBillPay = false),
                      ),
                      const SizedBox(height: 8),
                      PaymentMethodTile(
                        icon: Icons.receipt_long,
                        label: context.tr('boost_method_billpay'),
                        selected: _useBillPay,
                        onTap: () => setState(() => _useBillPay = true),
                      ),
                      const SizedBox(height: 24),

                      DsButton(
                        label: context.trParams('boost_pay_now',
                            {'amount': context.formatPriceInt(_tierInfo.price, currencyOverride: 'TZS')}),
                        icon: Icons.bolt,
                        size: DsButtonSize.lg,
                        loading: _paying,
                        onPressed: canPay && !_paying ? _pay : null,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        context.trParams('boost_period_days', {'count': '${_tierInfo.days}'}),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _benefitChip(ColorScheme cs, IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: cs.primary),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: cs.onSurface, fontSize: 12)),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final ColorScheme cs;
  const _EmptyState({required this.cs});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined, size: 64, color: cs.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(context.tr('boost_no_products_title'),
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: cs.onSurface)),
            const SizedBox(height: 6),
            Text(context.tr('boost_no_products'),
                textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}