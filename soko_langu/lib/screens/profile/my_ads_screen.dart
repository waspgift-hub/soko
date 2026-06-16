import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import '../../services/product_service.dart';
import '../../models/product_model.dart';
import '../../extensions/context_tr.dart';
import '../../app/routes.dart';
import '../../widgets/google_loading.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../utils/responsive.dart';

class MyAdsScreen extends StatefulWidget {
  const MyAdsScreen({super.key});

  @override
  State<MyAdsScreen> createState() => _MyAdsScreenState();
}

class _MyAdsScreenState extends State<MyAdsScreen> {
  final ProductService _productService = ProductService();

  Future<void> _deleteProduct(Product product) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('delete_product')),
        content: Text(context.tr('delete_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('cancel')),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr('delete')),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await _productService.deleteProduct(product.id);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.tr('product_deleted'))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("${context.tr('delete_failed')}: $e")),
        );
      }
    }
  }

  Future<void> _editProduct(Product product) async {
    await context.push(AppRoutes.addProduct, extra: product);
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(body: Center(child: Text(context.tr('login_required'))));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('my_ads')),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => context.push(AppRoutes.addProduct),
          ),
        ],
      ),
      body: SafeArea(
        child: StreamBuilder<List<Product>>(
          stream: _productService.getMyProducts(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const GoogleLoadingPage();
            }
            final products = snapshot.data ?? [];
            if (products.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.sell_outlined,
                      size: 64,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      context.tr('no_ads'),
                      style: TextStyle(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.6),
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () => context.push(AppRoutes.addProduct),
                      icon: const Icon(Icons.add),
                      label: Text(context.tr('sell_product')),
                    ),
                  ],
                ),
              );
            }
            return GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: Responsive.gridColumns(context),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: Responsive.cardAspectRatio(context),
              ),
              itemCount: products.length,
              itemBuilder: (context, index) {
                final product = products[index];
                return GestureDetector(
                  onTap: () => context.push(
                    '${AppRoutes.productDetail}/${product.id}',
                    extra: product,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Stack(
                            children: [
                              product.images.isNotEmpty
                                  ? CachedNetworkImage(
                                      imageUrl: product.images.first,
                                      fit: BoxFit.cover,
                                      width: double.infinity,
                                    )
                                  : Container(
                                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                      child: const Center(
                                        child: Icon(Icons.image),
                                      ),
                                    ),
                              Positioned(
                                top: 4,
                                right: 4,
                                child: PopupMenuButton<String>(
                                  onSelected: (value) {
                                    if (value == 'edit') _editProduct(product);
                                    if (value == 'delete') {
                                      _deleteProduct(product);
                                    }
                                  },
                                  itemBuilder: (ctx) => [
                                    PopupMenuItem(
                                      value: 'edit',
                                      child: Text(context.tr('edit')),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Text(context.tr('delete')),
                                    ),
                                  ],
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Icon(
                                      Icons.more_vert,
                                      color: Theme.of(context).colorScheme.surface,
                                      size: 18,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                product.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                "${context.currencySymbol()}${product.price.toStringAsFixed(0)}",
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
