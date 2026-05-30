import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../main.dart';
import '../../services/product_service.dart';
import '../../services/localization_service.dart';
import '../../models/product_model.dart';
import '../../widgets/product_card.dart';
import '../../widgets/trending_carousel.dart';
import '../../widgets/ad_banner.dart';
import '../../extensions/context_tr.dart';
import '../../widgets/google_loading.dart';
import '../../app/routes.dart';

class DiscoveryScreen extends StatefulWidget {
  const DiscoveryScreen({super.key});

  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen> {
  final ProductService _productService = ProductService();

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
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            ...LocalizationService.supportedCurrencies.entries.map(
              (e) => ListTile(
                title: Text("${e.value['name']} (${e.value['symbol']})"),
                trailing: config.currencyCode == e.key
                    ? const Icon(Icons.check, color: Colors.green)
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

  @override
  Widget build(BuildContext context) {
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
      body: StreamBuilder<List<Product>>(
        stream: _productService.getProducts(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const GoogleLoadingPage();
          }
          if (snap.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inventory_2,
                      size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    context.tr('no_products'),
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            );
          }
          final products = snap.data ?? [];
          if (products.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inventory_2,
                      size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    context.tr('no_products'),
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            );
          }
          return CustomScrollView(
            slivers: [
              const SliverToBoxAdapter(child: TrendingCarousel()),
              SliverPadding(
                padding: const EdgeInsets.all(12),
                sliver: SliverGrid(
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.72,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final product = products[index];
                      return ProductCard(
                        product: product,
                        onTap: () => context.push(
                          '${AppRoutes.productDetail}/${product.id}',
                          extra: product,
                        ),
                      );
                    },
                    childCount: products.length,
                  ),
                ),
              ),
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(12, 12, 12, 24),
                  child: AdBanner(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
