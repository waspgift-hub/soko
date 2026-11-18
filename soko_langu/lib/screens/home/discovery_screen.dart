import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/product_service.dart';
import '../../services/flash_sale_service.dart';
import '../../models/product_model.dart';
import '../../models/flash_sale_model.dart';
import '../../widgets/feed/feed_tabs.dart';
import '../../widgets/product_card.dart';
import '../../widgets/ds/ds_empty_state.dart';
import '../../widgets/ds/ds_skeleton.dart';
import '../../widgets/animations/soko_animated_illustration.dart';
import '../../widgets/dynamic_banner.dart';
import '../../widgets/currency_sheet.dart';
import '../../extensions/context_tr.dart';
import '../../utils/responsive.dart';
import '../../app/routes.dart';

/// Discovery marketplace: product cards in a 2-column grid, tabs filter the
/// same products stream. Follow controls live on the profile of each seller.
class DiscoveryScreen extends StatefulWidget {
  const DiscoveryScreen({super.key});

  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  final ProductService _productService = ProductService();
  final FlashSaleService _flashSaleService = FlashSaleService();
  Map<String, FlashSale> _flashSales = {};
  StreamSubscription? _flashSub;
  FeedTab _tab = FeedTab.forYou;
  String _userLocation = '';
  Stream<List<Product>>? _productStream;

  @override
  void initState() {
    super.initState();
    _flashSub = _flashSaleService.getActiveFlashSalesMap().listen((map) {
      if (mounted) setState(() => _flashSales = map);
    });
    _productStream = _productService.getProducts();
    _loadMeta();
  }

  /// Re-subscribes the product stream so pull-to-refresh actually re-queries
  /// instead of only reloading the user's location.
  void _reloadProducts() {
    setState(() => _productStream = _productService.getProducts());
  }

  Future<void> _refresh() async {
    _reloadProducts();
    await _loadMeta();
  }

  Future<void> _loadMeta() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      String location = '';
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        location = (doc.data()?['location'] ?? '').toString();
      } catch (_) {}
      if (mounted) {
        setState(() {
          _userLocation = location;
        });
      }
    } catch (_) {}
  }

  void _showCurrencyPicker(BuildContext context) => CurrencySheet.show(context);

  List<Product> _forTab(List<Product> all) {
    switch (_tab) {
      case FeedTab.nearby:
        final q = _userLocation.trim().toLowerCase();
        if (q.isEmpty) return [];
        return all.where((p) {
          final loc = '${p.district} ${p.location}'.toLowerCase();
          return loc.contains(q) || q.contains(p.district.toLowerCase());
        }).toList();
      case FeedTab.trending:
        final list = List<Product>.from(all);
        list.sort(
          (a, b) => (b.viewCount + b.soldCount * 3).compareTo(a.viewCount + a.soldCount * 3),
        );
        return list;
      case FeedTab.forYou:
        final list = List<Product>.from(all);
        list.shuffle();
        return list;
    }
  }

  void _openProduct(Product p) {
    context.push('${AppRoutes.productDetail}/${p.id}', extra: p);
  }

  @override
  void dispose() {
    _flashSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('discovery')),
        actions: [
          IconButton(
            icon: const Icon(Icons.monetization_on_outlined),
            tooltip: context.tr('change_currency'),
            onPressed: () => _showCurrencyPicker(context),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Product>>(
              stream: _productStream,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return _loadingGrid(context);
                }
                if (snap.hasError) {
                  return _errorState(context, snap.error!);
                }
                final items = _forTab(snap.data ?? []);
                if (items.isEmpty) return _emptyForTab(context);
                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      const SliverToBoxAdapter(child: DynamicBanner()),
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          12,
                          8,
                          12,
                          MediaQuery.paddingOf(context).bottom + 96,
                        ),
                        sliver: SliverGrid(
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: Responsive.gridColumns(context),
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                            childAspectRatio: Responsive.cardAspectRatio(context),
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final product = items[index];
                              return ProductCard(
                                product: product,
                                onTap: () => _openProduct(product),
                                flashSale: _flashSales[product.id],
                              );
                            },
                            childCount: items.length,
                            // Stateless tiles: no value in keeping them alive
                            // off-screen in a long feed.
                            addAutomaticKeepAlives: false,
                          ),
                        ),
                      ),

                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _loadingGrid(BuildContext context) {
    // A skeleton grid keeps the layout stable between the first frame and the
    // data — a full-screen spinner reset the scroll position and made the tab
    // feel slower than it is.
    final cs = Theme.of(context).colorScheme;
    return CustomScrollView(
      physics: const NeverScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: Responsive.gridColumns(context),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: Responsive.cardAspectRatio(context),
            ),
            delegate: SliverChildBuilderDelegate(
              (_, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const DsSkeleton(width: 120, height: 12),
                  const SizedBox(height: 6),
                  const DsSkeleton(width: 70, height: 10),
                ],
              ),
              childCount: 6,
            ),
          ),
        ),
      ],
    );
  }

  Widget _errorState(BuildContext context, Object error) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 56,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 14),
            Text(
              context.trError(error, feature: 'discovery', screen: 'Discovery'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              // Re-subscribing is what actually retries the query; a bare
              // setState left the failed stream in place and the button did
              // nothing visible.
              onPressed: _reloadProducts,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(context.tr('try_again')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyForTab(BuildContext context) {
    switch (_tab) {
      case FeedTab.nearby:
        if (_userLocation.isEmpty) {
          return DsEmptyState(
            icon: Icons.location_off_outlined,
            title: context.tr('set_location_title', 'Set your location to see nearby products.'),
            actionLabel: context.tr('set_location', 'Set Location'),
            onAction: () => context.push(AppRoutes.editProfile),
            artwork: const SokoAnimatedIllustration(SokoIllustration.emptyLocation, size: 96),
          );
        }
        return DsEmptyState(
          icon: Icons.location_on_outlined,
          title: context.tr('no_nearby', 'No products near you yet.'),
          actionLabel: context.tr('explore_marketplace', 'Explore Marketplace'),
          onAction: () => setState(() => _tab = FeedTab.forYou),
          artwork: const SokoAnimatedIllustration(SokoIllustration.emptyLocation, size: 96),
        );
      case FeedTab.trending:
      case FeedTab.forYou:
        return DsEmptyState(
          icon: Icons.inventory_2_outlined,
          title: context.tr('no_products'),
          actionLabel: context.tr('explore_marketplace', 'Explore Marketplace'),
          onAction: () => setState(() => _tab = FeedTab.forYou),
          artwork: const SokoAnimatedIllustration(SokoIllustration.emptyProducts, size: 96),
        );
    }
  }
}
