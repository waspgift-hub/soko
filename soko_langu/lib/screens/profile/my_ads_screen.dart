import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../services/product_service.dart';
import '../../models/product_model.dart';
import '../../providers/product_feed_provider.dart';
import '../../extensions/context_tr.dart';
import '../../app/routes.dart';
import '../../widgets/google_loading.dart';
import '../../widgets/product_card.dart';

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
        context.read<ProductFeedProvider>().removeProduct(product.id);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('product_deleted'))));
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

  void _showOptions(Product product) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, margin: const EdgeInsets.only(top: 12), decoration: BoxDecoration(color: Theme.of(ctx).colorScheme.onSurfaceVariant.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(2))),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(context.tr('edit')),
              onTap: () { Navigator.pop(ctx); _editProduct(product); },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
              title: Text(context.tr('delete'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
              onTap: () { Navigator.pop(ctx); _deleteProduct(product); },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnap) {
        final user = authSnap.data ?? FirebaseAuth.instance.currentUser;
        if (user == null) {
          if (authSnap.connectionState == ConnectionState.waiting) {
            return const Scaffold(body: GoogleLoadingPage());
          }
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
                        Icon(Icons.sell_outlined, size: 64, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4)),
                        const SizedBox(height: 16),
                        Text(context.tr('no_ads'), style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 16)),
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
                    crossAxisCount: 2,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 0.68,
                  ),
                  itemCount: products.length,
                  itemBuilder: (context, index) {
                    final product = products[index];
                    return GestureDetector(
                      onLongPress: () => _showOptions(product),
                      child: ProductCard(
                        product: product,
                        onTap: () => context.push('${AppRoutes.productDetail}/${product.id}', extra: product),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }
}
