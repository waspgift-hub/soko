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
  bool _sweepStarted = false;

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

  /// Hides (or, for an already-hidden listing, re-shows) a product.
  Future<void> _hideProduct(Product product) async {
    if (!product.isActive) {
      try {
        await _productService.setProductVisibility(product.id, visible: true);
        await _productService.scheduleReappear(product.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.tr('product_unhidden', 'Bidhaa imeonekana tena'))),
          );
        }
      } catch (e) {
        if (mounted) _showFailed(context.tr('delete_failed', 'Imeshindikana'), e);
      }
      return;
    }

    final period = await showDialog<Duration>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(context.tr('hide_product', 'Ficha bidhaa')),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, const Duration(hours: 24)),
            child: Text(context.tr('hide_for_24h', 'Ficha kwa saa 24')),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, const Duration(days: 7)),
            child: Text(context.tr('hide_for_7d', 'Ficha kwa siku 7')),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, Duration.zero),
            child: Text(context.tr('hide_until_unhide', 'Ficha hadi nirudishe mwenyewe')),
          ),
        ],
      ),
    );
    if (period == null) return;

    try {
      await _productService.setProductVisibility(product.id, visible: false);
      await _productService.scheduleReappear(
        product.id,
        at: period > Duration.zero ? DateTime.now().add(period) : null,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(period > Duration.zero
                ? context.tr('product_hidden_until', 'Bidhaa imefichwa kwa muda')
                : context.tr('product_hidden', 'Bidhaa imefichwa')),
          ),
        );
      }
    } catch (e) {
      if (mounted) _showFailed(context.tr('delete_failed', 'Imeshindikana'), e);
    }
  }

  void _showFailed(String label, Object e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label: $e')),
    );
  }

  /// Re-publishes any listing whose hidden-for-period window has elapsed.
  /// Runs once per screen visit so a timed lock restores without server work.
  void _maybeSweep(List<Product> products) {
    if (_sweepStarted) return;
    final now = DateTime.now();
    final due =
        products.where((p) => p.hiddenUntil != null && !p.hiddenUntil!.isAfter(now)).toList();
    if (due.isEmpty) {
      _sweepStarted = true;
      return;
    }
    _sweepStarted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      for (final p in due) {
        try {
          await _productService.setProductVisibility(p.id, visible: true);
          await _productService.scheduleReappear(p.id);
        } catch (e) {
          debugPrint('auto-restore failed for ${p.id}: $e');
        }
      }
    });
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
              leading: Icon(
                product.isActive ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              ),
              title: Text(product.isActive
                  ? context.tr('hide_product', 'Ficha bidhaa')
                  : context.tr('unhide_product', 'Onyesha tena')),
              onTap: () { Navigator.pop(ctx); _hideProduct(product); },
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
                tooltip: context.tr('add'),
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
                _maybeSweep(products);
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
                    return Stack(
                      children: [
                        GestureDetector(
                          onLongPress: () => _showOptions(product),
                          child: ProductCard(
                            product: product,
                            onTap: () => context.push('${AppRoutes.productDetail}/${product.id}', extra: product),
                          ),
                        ),
                        Positioned(
                          top: 6,
                          right: 6,
                          child: GestureDetector(
                            onTap: () => _showOptions(product),
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Icon(
                                Icons.more_horiz,
                                size: 18,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ],
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
