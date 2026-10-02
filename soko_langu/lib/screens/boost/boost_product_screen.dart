import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../extensions/context_tr.dart';
import '../../models/product_model.dart';
import '../../services/boost_service.dart';
import '../../services/product_service.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/ds/ds.dart';
import '../../widgets/product_cached_image.dart';
import 'boost_tiers.dart';
import 'widgets/boost_checkout_bar.dart';
import 'widgets/boost_hero_panel.dart';
import 'widgets/boost_payment_section.dart';
import 'widgets/boost_reach_panel.dart';
import 'widgets/boost_result_overlays.dart';
import 'widgets/boost_tier_card.dart';
import 'widgets/boost_value_prop_grid.dart';

/// Boost purchase screen.
///
/// Three questions in order, because that is the order a seller actually asks
/// them: *what do I get* (hero + value props), *how much for how long* (package
/// cards + reach estimate), *how do I pay* (payment card + sticky bar). The
/// server activates the boost once the ClickPesa webhook clears, so this screen
/// only starts the payment and reports what the server said.
class BoostProductScreen extends StatefulWidget {
  /// Optional preselect — when null (e.g. the seller dashboard quick action),
  /// the seller picks one of their own products first.
  final String? productId;
  final Product? product;

  const BoostProductScreen({super.key, this.productId, this.product});

  @override
  State<BoostProductScreen> createState() => _BoostProductScreenState();
}

class _BoostProductScreenState extends State<BoostProductScreen> {
  final ProductService _productService = ProductService();
  final TextEditingController _phoneCtrl = TextEditingController();

  bool _loadingProducts = true;
  List<Product> _mine = [];
  Product? _product;

  BoostTier _tier = BoostTier.byKey(BoostTier.silverKey);
  String _provider = 'mpesa';
  BoostPayMethod _method = BoostPayMethod.ussd;
  bool _phoneAttempted = false;

  bool _paying = false;

  @override
  void initState() {
    super.initState();
    final phone = FirebaseAuth.instance.currentUser?.phoneNumber;
    if (phone != null) _phoneCtrl.text = phone;
    _product = widget.product;
    _load();
    _phoneCtrl.addListener(_onPhoneChanged);
  }

  @override
  void dispose() {
    _phoneCtrl.removeListener(_onPhoneChanged);
    _phoneCtrl.dispose();
    super.dispose();
  }

  bool get _phoneValid =>
      _phoneCtrl.text.replaceAll(RegExp(r'\D'), '').length >= 9;

  String? get _phoneError =>
      _phoneAttempted && !_phoneValid ? context.tr('boost_phone_invalid') : null;

  void _onPhoneChanged() {
    if (_phoneAttempted) setState(() {});
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
    // DsSheet scrolls its own child, which would fight the sheet's grabber for
    // the same drag, so the picker drives a draggable sheet instead.
    final picked = await showModalBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ProductPicker(
        products: _mine,
        selectedId: _product?.id,
      ),
    );
    if (picked != null && mounted) setState(() => _product = picked);
  }

  Future<void> _pay() async {
    final product = _product;
    if (product == null || _paying) return;

    setState(() => _phoneAttempted = true);
    final phone = _phoneCtrl.text.trim();
    if (phone.replaceAll(RegExp(r'\D'), '').length < 9) return;

    setState(() => _paying = true);
    try {
      final res = await BoostService.initBoostProduct(
        productId: product.id,
        productName: product.name,
        productImage: product.images.isNotEmpty ? product.images[0] : null,
        productPrice: product.price,
        tier: _tier.key,
        phone: phone,
        paymentMethod: _method == BoostPayMethod.billpay ? 'billpay' : 'ussd_push',
        provider: _provider,
      );
      if (!mounted) return;
      if (res['error'] != null) {
        _showError('${res['error']}');
        return;
      }
      if (_method == BoostPayMethod.billpay) {
        // BillPay settles against a control number out-of-band, so there is
        // nothing to poll yet — hand over the instructions and stay honest.
        await _showBillPay(res);
        return;
      }

      // USSD push is confirmable: the seller approves on their phone within a
      // few seconds, so poll the webhook before claiming the boost went live.
      final orderId = (res['order_id'] ?? res['orderId'] ?? '').toString();
      if (orderId.isEmpty) {
        _showStillPending();
        return;
      }

      final settled = await _waitWithProgress(orderId);
      if (!mounted || settled == null) return;
      switch (settled) {
        case BoostService.boostPaid:
          await _showSuccess(product);
        case BoostService.boostFailed:
          _showError(context.tr('boost_payment_failed'));
        default:
          _showStillPending();
      }
    } catch (e) {
      if (mounted) _showError(context.trError(e));
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  /// Runs the webhook poll behind [BoostProgressOverlay]. Returns null when the
  /// seller chose to check back later, which must not fall through to an error.
  Future<String?> _waitWithProgress(String orderId) async {
    unawaited(
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          builder: (_) => BoostProgressOverlay(
            tier: _tier,
            methodLabel: _method == BoostPayMethod.billpay
                ? context.tr('boost_pay_billpay')
                : context.tr('boost_pay_ussd'),
          ),
          fullscreenDialog: true,
        ),
      ),
    );
    // Let the overlay paint before the first poll locks the frame.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    final outcome = await BoostService.waitForSettlement(orderId);
    if (!mounted) return null;
    Navigator.of(context, rootNavigator: true).pop();
    return outcome;
  }

  Future<void> _showSuccess(Product product) async {
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => BoostSuccessOverlay(
          productName: product.name,
          tier: _tier,
        ),
        fullscreenDialog: true,
      ),
    );
    if (!mounted) return;
    setState(() => _product = null);
  }

  Future<void> _showBillPay(Map<String, dynamic> res) async {
    final number = (res['billPayNumber'] ?? '').toString();
    await DsSheet.show<void>(
      context: context,
      content: BoostBillPaySheet(controlNumber: number, tier: _tier),
    );
  }

  void _showStillPending() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final cs = Theme.of(context).colorScheme;
        return AlertDialog(
          icon: Icon(Icons.hourglass_top_rounded, color: cs.tertiary, size: 40),
          title: Text(context.tr('boost_still_pending_title')),
          content: Text(context.tr('boost_still_pending_local')),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                context.push(AppRoutes.myAds);
              },
              child: Text(context.tr('boost_view_my_boosts')),
            ),
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
        icon: Icon(
          Icons.error_outline_rounded,
          color: Theme.of(context).colorScheme.error,
          size: 40,
        ),
        title: Text(context.tr('boost_error_title')),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('boost_screen_title')),
        centerTitle: false,
      ),
      body: SafeArea(
        bottom: false,
        child: _loadingProducts
            ? const Center(child: DsLoadingDots())
            : _product == null
                ? const _NoProducts()
                : ListView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.s4,
                      AppSpacing.s2,
                      AppSpacing.s4,
                      AppSpacing.s8,
                    ),
                    children: [
                      BoostHeroPanel(
                        product: _product,
                        canSwitchProduct: _mine.length > 1,
                        onTapProduct: _pickProduct,
                      ),
                      const SizedBox(height: AppSpacing.s6),
                      _SectionLabel(
                        title: context.tr('boost_section_why'),
                        caption: context.tr('boost_section_why_caption'),
                      ),
                      const SizedBox(height: AppSpacing.s3),
                      const BoostValuePropGrid(),
                      const SizedBox(height: AppSpacing.s7),
                      _SectionLabel(
                        title: context.tr('boost_section_package'),
                        caption: context.tr('boost_package_note'),
                      ),
                      const SizedBox(height: AppSpacing.s3),
                      for (final tier in BoostTier.all)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.s3),
                          child: BoostTierCard(
                            tier: tier,
                            selected: tier.key == _tier.key,
                            onTap: () => setState(() => _tier = tier),
                          ),
                        ),
                      const SizedBox(height: AppSpacing.s2),
                      BoostReachPanel(tier: _tier),
                      const SizedBox(height: AppSpacing.s7),
                      BoostPaymentSection(
                        phoneController: _phoneCtrl,
                        method: _method,
                        provider: _provider,
                        phoneError: _phoneError,
                        onMethodChanged: (m) => setState(() => _method = m),
                        onProviderChanged: (p) => setState(() => _provider = p),
                      ),
                    ],
                  ),
      ),
      bottomNavigationBar: _product == null
          ? null
          : BoostCheckoutBar(
              tier: _tier,
              paying: _paying,
              enabled: !_loadingProducts,
              onPay: _pay,
            ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title, required this.caption});

  final String title;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: scheme.onSurface,
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          caption,
          style: TextStyle(
            color: scheme.onSurfaceVariant,
            fontSize: 12,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _ProductPicker extends StatelessWidget {
  const _ProductPicker({required this.products, required this.selectedId});

  final List<Product> products;
  final String? selectedId;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (context, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppRadius2.xxl),
          ),
        ),
        child: Column(
          children: [
            const SizedBox(height: AppSpacing.s3),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.s6,
                AppSpacing.s4,
                AppSpacing.s6,
                AppSpacing.s2,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      context.tr('boost_pick_product'),
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    context.trParams('boost_products_owned', {
                      'count': '${products.length}',
                    }),
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.s6,
                  AppSpacing.s2,
                  AppSpacing.s6,
                  AppSpacing.s6,
                ),
                itemCount: products.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final p = products[i];
                  final selected = selectedId == p.id;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: ProductCachedImage(
                          url: p.images.isNotEmpty ? p.images[0] : null,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    title: Text(
                      p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      context.formatPriceInt(
                        p.price.toInt(),
                        currencyOverride: 'TZS',
                      ),
                    ),
                    trailing: selected
                        ? Icon(
                            Icons.check_circle_rounded,
                            color: scheme.primary,
                          )
                        : null,
                    onTap: () => Navigator.pop(context, p),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoProducts extends StatelessWidget {
  const _NoProducts();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.inventory_2_outlined,
                size: 40,
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.s4),
            Text(
              context.tr('boost_no_products_title'),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: AppSpacing.s2),
            Text(
              context.tr('boost_no_products'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
            const SizedBox(height: AppSpacing.s5),
            DsButton(
              label: context.tr('add_product_first'),
              icon: Icons.add_rounded,
              variant: DsButtonVariant.secondary,
              fullWidth: false,
              onPressed: () => context.push(AppRoutes.addProduct),
            ),
          ],
        ),
      ),
    );
  }
}