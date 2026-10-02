import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../main.dart';
import '../../services/product_service.dart';
import '../../services/localization_service.dart';
import '../../services/flash_sale_service.dart';
import '../../models/product_model.dart';
import '../../models/flash_sale_model.dart';
import '../../widgets/feed/feed_tabs.dart';
import '../../widgets/product_card.dart';
import '../../widgets/ds/ds_empty_state.dart';
import '../../widgets/dynamic_banner.dart';
import '../../extensions/context_tr.dart';
import '../../widgets/google_loading.dart';
import '../../app/routes.dart';
import '../../widgets/ads/ad_slot.dart';
import '../../services/ads/ad_config.dart';

/// Discovery marketplace: product cards in a 2-column grid, tabs filter the
/// same products stream. Follow controls live on the profile of each seller.
class DiscoveryScreen extends StatefulWidget {
  const DiscoveryScreen({super.key});

  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen>
    with AutomaticKeepAliveClientMixin {
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
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        location = (doc.data()?['location'] ?? '').toString();
      } catch (_) {}
      if (mounted) {
        setState(() {
          _userLocation = location;
        });
      }
    } catch (_) {}
  }

  void _showCurrencyPicker(BuildContext context) {
    final config = AppConfig.of(context);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                context.tr('select_currency'),
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            ...LocalizationService.supportedCurrencies.entries.map(
              (e) => ListTile(
                title: Text("${e.value['name']} (${e.value['symbol']})"),
                trailing: config.currencyCode == e.key
                    ? Icon(Icons.check,
                        color: Theme.of(context).colorScheme.primary)
                    : null,
                onTap: () {
                  LocalizationService().setCurrency(e.key);
                  config.onSetCurrency(e.key);
                  Navigator.pop(ctx);
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  List<Product> _forTab(List<Product> all) {
    switch (_tab) {
      case FeedTab.nearby:
        final q = _userLocation.trim().toLowerCase();
        if (q.isEmpty) return [];
        return all.where((p) {
          final loc =
              '${p.district} ${p.location}'.toLowerCase();
          return loc.contains(q) || q.contains(p.district.toLowerCase());
        }).toList();
      case FeedTab.trending:
        final list = List<Product>.from(all);
        list.sort((a, b) =>
            (b.viewCount + b.soldCount * 3)
                .compareTo(a.viewCount + a.soldCount * 3));
        return list;
      case FeedTab.forYou:
        final list = List<Product>.from(all);
        list.sort((a, b) {
          if (a.isBoosted != b.isBoosted) {
            return a.isBoosted ? -1 : 1;
          }
          return b.viewCount.compareTo(a.viewCount);
        });
        return list;
    }
  }

  void _openProduct(Product p) {
    context.push(
      '${AppRoutes.productDetail}/${p.id}',
      extra: p,
    );
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
          // Sticky header with precise spacing — prevents cramped chips
          Container(
            color: Theme.of(context).colorScheme.surface,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: FeedTabs(selected: _tab, onSelect: (t) => setState(() => _tab = t)),
          ),
          Container(height: 1, color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.08)),
          Expanded(
            child: StreamBuilder<List<Product>>(
              stream: _productStream,
              builder: (context, snap) {
                if (snap.connectionState ==
                    ConnectionState.waiting) {
                  return const GoogleLoadingPage();
                }
                if (snap.hasError) {
                  return _errorState(context, snap.error.toString());
                }
                final items = _forTab(snap.data ?? []);
                if (items.isEmpty) return _emptyForTab(context);
                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(12, 12, 12, 4),
                          child: DynamicBanner(),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                        sliver: SliverGrid(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                            childAspectRatio: 0.62,
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
                          ),
                        ),
                      ),
                      // Footer placement only. Discovery already leads with a
                      // first-party DynamicBanner, so a second in-feed ad here
                      // would make the screen feel ad-heavy.
                      const SliverToBoxAdapter(
                        child: AdSlot(
                          placement: AdPlacement.homeFeedFooter,
                          variant: AdSlotVariant.feedGap,
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

  Widget _errorState(BuildContext context, String err) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off,
              size: 64,
              color:
                  Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(
            err.contains('permission-denied')
                ? context.tr('permission_denied')
                : err.contains('UNAVAILABLE')
                    ? context.tr('no_network')
                    : context.tr('please_try_again'),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            // Re-subscribing is what actually retries the query; a bare
            // setState left the failed stream in place and the button did
            // nothing visible.
            onPressed: _reloadProducts,
            child: Text(context.tr('try_again')),
          ),
        ],
      ),
    );
  }

  Widget _emptyForTab(BuildContext context) {
    switch (_tab) {
      case FeedTab.nearby:
        if (_userLocation.isEmpty) {
          return DsEmptyState(
            icon: Icons.location_off_outlined,
            title: context.tr('set_location_title',
                'Set your location to see nearby products.'),
            actionLabel:
                context.tr('set_location', 'Set Location'),
            onAction: () =>
                context.push(AppRoutes.editProfile),
          );
        }
        return DsEmptyState(
          icon: Icons.location_on_outlined,
          title: context.tr(
              'no_nearby', 'No products near you yet.'),
          actionLabel: context.tr(
              'explore_marketplace', 'Explore Marketplace'),
          onAction: () =>
              setState(() => _tab = FeedTab.forYou),
        );
      case FeedTab.trending:
      case FeedTab.forYou:
        return DsEmptyState(
          icon: Icons.inventory_2_outlined,
          title: context.tr('no_products'),
          actionLabel: context.tr(
              'explore_marketplace', 'Explore Marketplace'),
          onAction: () =>
              setState(() => _tab = FeedTab.forYou),
        );
    }
  }
}
