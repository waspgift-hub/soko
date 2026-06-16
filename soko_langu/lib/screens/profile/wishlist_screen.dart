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
import '../../widgets/ad_banner.dart';
import 'package:cached_network_image/cached_network_image.dart';

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
      appBar: AppBar(title: Text(context.tr('wishlist'))),
      body: SafeArea(
        child: _loading
            ? const GoogleLoadingPage()
            : _wishlistIds.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.favorite_border,
                      size: 64,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      context.tr('wishlist_empty'),
                      style: TextStyle(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.6),
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () => context.push('/'),
                      icon: const Icon(Icons.shopping_bag),
                      label: Text(context.tr('start_shopping')),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _wishlistIds.length,
                itemBuilder: (context, index) {
                  final id = _wishlistIds[index];
                  final product = _products[id];
                  if (product == null) return const SizedBox.shrink();
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.5),
                        width: 1.5,
                      ),
                    ),
                    child: ListTile(
                      leading: product.images.isNotEmpty
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: CachedNetworkImage(
                                imageUrl: product.images.first,
                                width: 60,
                                height: 60,
                                fit: BoxFit.cover,
                              ),
                            )
                          : Container(
                              width: 60,
                              height: 60,
                              color: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                              child: const Icon(Icons.image),
                            ),
                      title: Text(
                        product.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: _buildWishlistPrice(context, product),
                      trailing: IconButton(
                        icon: Icon(Icons.delete, color: Theme.of(context).colorScheme.error),
                        onPressed: () => _remove(id),
                      ),
                      onTap: () => context.push(
                        '${AppRoutes.productDetail}/${product.id}',
                        extra: product,
                      ),
                    ),
                  );
                },
              ),
      ),
      bottomNavigationBar: const AdBanner(),
    );
  }

  Widget _buildWishlistPrice(BuildContext context, Product product) {
    final fs = _flashSales[product.id];
    if (fs == null) {
      return Text(context.formatPrice(product.price));
    }
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          margin: const EdgeInsets.only(right: 6),
          decoration: BoxDecoration(
            color: Colors.red.shade600,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            '-${fs.discountPercent}%',
            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
          ),
        ),
        Text(context.formatPrice(fs.salePrice), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
        const SizedBox(width: 6),
        Text(context.formatPrice(product.price), style: TextStyle(decoration: TextDecoration.lineThrough, color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
      ],
    );
  }
}
