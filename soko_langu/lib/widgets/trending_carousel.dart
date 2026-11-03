import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'product_card.dart';
import '../services/product_service.dart';
import '../services/flash_sale_service.dart';
import '../services/widget_service.dart';
import '../models/product_model.dart';
import '../models/flash_sale_model.dart';
import '../extensions/context_tr.dart';
import '../app/routes.dart';
import '../theme/app_colors.dart';

class TrendingCarousel extends StatefulWidget {
  const TrendingCarousel({super.key});

  @override
  State<TrendingCarousel> createState() => _TrendingCarouselState();
}

class _TrendingCarouselState extends State<TrendingCarousel> {
  final FlashSaleService _flashSaleService = FlashSaleService();
  final ProductService _productService = ProductService();
  Map<String, FlashSale> _flashSales = {};
  StreamSubscription? _flashSub;
  late Stream<List<Product>> _featuredStream;

  @override
  void initState() {
    super.initState();
    _featuredStream = _productService.getFeaturedProducts();
    _flashSub = _flashSaleService.getActiveFlashSalesMap().listen((map) {
      if (mounted) setState(() => _flashSales = map);
    });
  }

  @override
  void dispose() {
    _flashSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Product>>(
      stream: _featuredStream,
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.isEmpty) {
          return const SizedBox.shrink();
        }
        final products = snap.data!;
        WidgetService.updateFlashSales(products: products, flashSales: _flashSales);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  Icon(Icons.trending_up, color: Theme.of(context).colorScheme.trendingOrange, size: 20),
                  const SizedBox(width: 6),
                  Text(
                    context.tr('trending'),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.85),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${products.length} ${context.tr('products').toLowerCase()}',
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 260,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: products.length,
                itemBuilder: (context, index) {
                  final p = products[index];
                  return SizedBox(
                    width: 160,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: ProductCard(
                        product: p,
                        flashSale: _flashSales[p.id],
                        onTap: () => context.push('${AppRoutes.productDetail}/${p.id}', extra: p),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}



