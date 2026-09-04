import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../main.dart';
import '../../services/product_service.dart';
import '../../services/localization_service.dart';
import '../../services/flash_sale_service.dart';
import '../../services/follow_service.dart';
import '../../services/wishlist_service.dart';
import '../../models/product_model.dart';
import '../../models/flash_sale_model.dart';
import '../../widgets/feed/feed_post_card.dart';
import '../../widgets/feed/feed_tabs.dart';
import '../../widgets/ds/ds_empty_state.dart';
import '../../widgets/dynamic_banner.dart';
import '../../extensions/context_tr.dart';
import '../../widgets/google_loading.dart';
import '../../app/routes.dart';
import '../../screens/chat/chat_navigation.dart';

/// Social-commerce discovery feed: seller-led posts with big media,
/// social actions and direct commerce. Tabs filter one products stream.
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
  final FollowService _followService = FollowService();
  final WishlistService _wishlistService = WishlistService();
  Map<String, FlashSale> _flashSales = {};
  StreamSubscription? _flashSub;
  FeedTab _tab = FeedTab.forYou;
  Set<String> _followedIds = {};
  String _userLocation = '';

  @override
  void initState() {
    super.initState();
    _flashSub = _flashSaleService.getActiveFlashSalesMap().listen((map) {
      if (mounted) setState(() => _flashSales = map);
    });
    _loadMeta();
  }

  Future<void> _loadMeta() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final following =
          await _followService.getFollowing(user.uid).first;
      final ids = following
          .map((e) => (e['sellerId'] ?? e['uid'] ?? '').toString())
          .where((s) => s.isNotEmpty)
          .toSet();
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
          _followedIds = ids;
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
      case FeedTab.following:
        return all
            .where((p) => _followedIds.contains(p.sellerId))
            .toList();
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

  Future<void> _toggleLike(Product p, bool liked) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final ref = FirebaseFirestore.instance
          .collection('products')
          .doc(p.id);
      await ref.update({
        'likedBy': liked
            ? FieldValue.arrayUnion([user.uid])
            : FieldValue.arrayRemove([user.uid]),
      });
    } catch (_) {}
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
            onPressed: () => _showCurrencyPicker(context),
          ),
        ],
      ),
      body: Column(
        children: [
          FeedTabs(
            selected: _tab,
            onSelect: (t) => setState(() => _tab = t),
          ),
          Expanded(
            child: StreamBuilder<List<Product>>(
              stream: _productService.getProducts(),
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
                  onRefresh: () async =>
                      setState(() => _loadMeta()),
                  child: ListView.builder(
                    itemCount: items.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return const DynamicBanner();
                      }
                      final product = items[index - 1];
                      final flash = _flashSales[product.id];
                      final trendingBadge =
                          _tab == FeedTab.trending && index <= 3
                              ? context.tr('trending', 'TRENDING')
                              : null;
                      return FeedPostCard(
                        product: product,
                        badgeLabel: trendingBadge,
                        displayPrice: flash?.salePrice,
                        strikethroughPrice:
                            flash?.originalPrice,
                        onTap: () => _openProduct(product),
                        onBuy: () => _openProduct(product),
                        onChat: () =>
                            ChatNavigation.openSellerChat(
                          context,
                          product.sellerId,
                          product.sellerName,
                        ),
                        onComment: () => _openProduct(product),
                        onLike: (liked) =>
                            _toggleLike(product, liked),
                        onSave: (_) => _wishlistService
                            .toggle(product.id),
                        onFollow: (following) async {
                          if (following) {
                            await _followService
                                .follow(product.sellerId);
                          } else {
                            await _followService
                                .unfollow(product.sellerId);
                          }
                          _loadMeta();
                        },
                        onSellerTap: () => _openProduct(product),
                      );
                    },
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
            onPressed: () => setState(() {}),
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  Widget _emptyForTab(BuildContext context) {
    switch (_tab) {
      case FeedTab.following:
        return DsEmptyState(
          icon: Icons.people_outline,
          title: context.tr('follow_sellers_empty',
              'Follow sellers to see their latest products here.'),
          actionLabel: context.tr('discover_sellers', 'Discover Sellers'),
          onAction: () =>
              setState(() => _tab = FeedTab.forYou),
        );
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
