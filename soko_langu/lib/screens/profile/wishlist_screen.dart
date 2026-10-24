import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../extensions/context_tr.dart';
import '../../services/wishlist_service.dart';
import '../../services/product_service.dart';
import '../../services/flash_sale_service.dart';
import '../../models/product_model.dart';
import '../../models/flash_sale_model.dart';
import '../../app/routes.dart';
import '../../widgets/google_loading.dart';
import '../../widgets/ds/ds_empty_state.dart';
import '../../widgets/animations/soko_animated_illustration.dart';
import '../../widgets/product_cached_image.dart';
import '../../services/ads/ad_config.dart';
import '../../widgets/ads/ad_slot.dart';

class WishlistScreen extends StatefulWidget {
  const WishlistScreen({super.key});

  @override
  State<WishlistScreen> createState() => _WishlistScreenState();
}

class _WishlistScreenState extends State<WishlistScreen> {
  final WishlistService _wishlistService = WishlistService();
  final ProductService _productService = ProductService();
  final FlashSaleService _flashSaleService = FlashSaleService();
  List<String> _wishlistIds = [];
  Map<String, Product?> _products = {};
  Map<String, FlashSale> _flashSales = {};
  bool _loading = true;
  StreamSubscription? _flashSub;

  @override
  void initState() {
    super.initState();
    _load();
    _flashSub = _flashSaleService.getActiveFlashSalesMap().listen((map) {
      if (mounted) setState(() => _flashSales = map);
    });
  }

  @override
  void dispose() {
    _flashSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final ids = await _wishlistService.getWishlist();
    setState(() => _wishlistIds = ids);
    for (final id in ids) {
      final product = await _productService.getProductById(id);
      _products[id] = product;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _remove(String id) async {
    await _wishlistService.remove(id);
    setState(() {
      _wishlistIds.remove(id);
      _products.remove(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _wishlistIds.isEmpty
              ? context.tr('wishlist')
              : '${context.tr('wishlist')} (${_wishlistIds.length})',
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const GoogleLoadingPage()
            : _wishlistIds.isEmpty
            ? Center(
                child: DsEmptyState(
                  icon: Icons.favorite_border,
                  artwork: const SokoAnimatedIllustration(SokoIllustration.emptyWishlist, size: 96),
                  title: context.tr('wishlist_empty'),
                  actionLabel: context.tr('start_shopping'),
                  onAction: () => context.push('/'),
                ),
              )
            : LayoutBuilder(
                builder: (context, c) {
                  // Two columns on a phone, more as the window widens. A
                  // single-column list of 60dp thumbnails wasted most of the
                  // screen and made saved items hard to scan.
                  final columns = c.maxWidth >= 900
                      ? 4
                      : c.maxWidth >= 600
                      ? 3
                      : 2;
                  return GridView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      // 0.72 keeps a product photo from being cropped so
                      // tightly that the listing becomes unrecognisable.
                      childAspectRatio: 0.72,
                    ),
                    itemCount: _wishlistIds.length,
                    itemBuilder: (context, index) {
                      final id = _wishlistIds[index];
                      final product = _products[id];
                      if (product == null) return const SizedBox.shrink();
                      return _WishlistCard(
                        product: product,
                        flashSale: _flashSales[product.id],
                        onTap: () => context.push(
                          '${AppRoutes.productDetail}/${product.id}',
                          extra: product,
                        ),
                        onRemove: () => _remove(id),
                      );
                    },
                  );
                },
              ),
      ),
      bottomNavigationBar: const AdSlot(
        placement: AdPlacement.wishlistFooter,
        variant: AdSlotVariant.pinnedFooter,
      ),
    );
  }
}

/// One saved product in the wishlist grid.
///
/// Flat by construction: a tonal surface with no border and no elevation. The
/// previous row drew a 1.5px primary-coloured outline around every item, which
/// made the whole screen look like a stack of alert boxes rather than a
/// shopping list.
class _WishlistCard extends StatelessWidget {
  const _WishlistCard({
    required this.product,
    required this.onTap,
    required this.onRemove,
    this.flashSale,
  });

  final Product product;
  final FlashSale? flashSale;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final onSale = flashSale != null && flashSale!.salePrice > 0;

    return Material(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (product.images.isNotEmpty)
                    ProductCachedImage(url: product.images.first, fit: BoxFit.cover)
                  else
                    ColoredBox(
                      color: cs.surfaceContainerHighest,
                      child: Icon(Icons.image_outlined, color: cs.onSurfaceVariant),
                    ),
                  Positioned(top: 6, right: 6, child: _RemoveButton(onTap: onRemove)),
                  if (onSale)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: cs.error,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '-${flashSale!.discountPercent.toStringAsFixed(0)}%',
                          style: TextStyle(
                            color: cs.onError,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    product.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    product.sellerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          context.formatPrice(onSale ? flashSale!.salePrice : product.price),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: onSale ? cs.error : cs.primary,
                          ),
                        ),
                      ),
                      if (onSale) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            context.formatPrice(product.price),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurfaceVariant,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small heart toggle used to un-save an item.
///
/// A neutral chip rather than a red trash icon: removing something from a saved
/// list is not a destructive act, and a full-bleed error-red icon made every
/// card look like it was about to be deleted.
class _RemoveButton extends StatelessWidget {
  const _RemoveButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface.withValues(alpha: 0.92),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(Icons.favorite_rounded, size: 18, color: cs.primary),
        ),
      ),
    );
  }
}
