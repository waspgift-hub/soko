import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../extensions/context_tr.dart';
import '../../services/wishlist_service.dart';
import '../../services/product_service.dart';
import '../../models/product_model.dart';
import '../../app/routes.dart';
import '../../widgets/google_loading.dart';
import 'package:cached_network_image/cached_network_image.dart';

class WishlistScreen extends StatefulWidget {
  const WishlistScreen({super.key});

  @override
  State<WishlistScreen> createState() => _WishlistScreenState();
}

class _WishlistScreenState extends State<WishlistScreen> {
  final WishlistService _wishlistService = WishlistService();
  final ProductService _productService = ProductService();
  List<String> _wishlistIds = [];
  Map<String, Product?> _products = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
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
                      ).colorScheme.onSurface.withOpacity(0.4),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      context.tr('wishlist_empty'),
                      style: TextStyle(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.6),
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
                        ).colorScheme.primary.withOpacity(0.5),
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
                      subtitle: Text(
                        "${product.currency ?? 'TSh'} ${product.price.toStringAsFixed(0)}",
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
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
    );
  }
}

