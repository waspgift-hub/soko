import 'package:flutter/material.dart';
import '../../extensions/context_tr.dart';
import '../../services/wishlist_service.dart';
import '../../services/product_service.dart';
import '../../models/product_model.dart';
import '../home/product_detail.dart';

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
            ? const Center(child: CircularProgressIndicator())
            : _wishlistIds.isEmpty
            ? Center(
                child: Text(
                  context.tr('wishlist_empty'),
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.6),
                    fontSize: 16,
                  ),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _wishlistIds.length,
                itemBuilder: (context, index) {
                  final id = _wishlistIds[index];
                  final product = _products[id];
                  if (product == null) return const SizedBox.shrink();
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      leading: product.images.isNotEmpty
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                product.images.first,
                                width: 60,
                                height: 60,
                                fit: BoxFit.cover,
                              ),
                            )
                          : Container(
                              width: 60,
                              height: 60,
                              color: Colors.grey[200],
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
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ProductDetailPage(product: product),
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
