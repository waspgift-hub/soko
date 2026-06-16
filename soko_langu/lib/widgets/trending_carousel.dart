import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/product_service.dart';
import '../services/flash_sale_service.dart';
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
  final PageController _pageCtrl = PageController(viewportFraction: 0.4);
  int _currentPage = 0;
  final FlashSaleService _flashSaleService = FlashSaleService();
  Map<String, FlashSale> _flashSales = {};
  StreamSubscription? _flashSub;

  @override
  void initState() {
    super.initState();
    _flashSub = _flashSaleService.getActiveFlashSalesMap().listen((map) {
      if (mounted) setState(() => _flashSales = map);
    });
  }

  @override
  void dispose() {
    _flashSub?.cancel();
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Product>>(
      stream: ProductService().getFeaturedProducts(),
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.isEmpty) {
          return const SizedBox.shrink();
        }
        final products = snap.data!;
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
                    'Trending',
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
              height: 170,
              child: Column(
                children: [
                  Expanded(
                    child: PageView.builder(
                      controller: _pageCtrl,
                      itemCount: products.length,
                      onPageChanged: (i) => setState(() => _currentPage = i),
                      itemBuilder: (context, index) {
                        final p = products[index];
                        return _buildCard(p, _flashSales[p.id]);
                      },
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (products.length > 1)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        products.length > 7 ? 7 : products.length,
                        (i) => AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          width: _currentPage == i ? 8 : 6,
                          height: _currentPage == i ? 8 : 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _currentPage == i
                                ? Theme.of(context).colorScheme.trendingOrange
                                : Theme.of(context).colorScheme.outline,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCard(Product p, FlashSale? fs) {
    return GestureDetector(
      onTap: () => context.push(
        '${AppRoutes.productDetail}/${p.id}',
        extra: p,
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).colorScheme.trendingOrange.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
              child: Container(
                height: 100,
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                child: Stack(children: [
                  p.images.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: p.images.first,
                          fit: BoxFit.cover,
                          width: double.infinity,
                        )
                      : Center(child: Icon(Icons.image, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6), size: 32)),
                  if (fs != null)
                    Positioned(
                      top: 4, left: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(color: Colors.red.shade600, borderRadius: BorderRadius.circular(4)),
                        child: Text('-${fs.discountPercent}%', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                    ),
                ]),
              ),
            ),
            // Name
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 2),
              child: Text(
                p.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                ),
              ),
            ),
            // Price + featured star
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
              child: Row(
                children: [
                  if (fs != null) ...[
                    Text(context.formatPrice(fs.salePrice), style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(width: 4),
                    Text(context.formatPrice(p.price), style: TextStyle(decoration: TextDecoration.lineThrough, color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 10)),
                  ] else
                    Text(context.formatPrice(p.price), style: TextStyle(color: Theme.of(context).colorScheme.trendingOrange, fontWeight: FontWeight.bold, fontSize: 12)),
                  const Spacer(),
                  Icon(Icons.star, color: Theme.of(context).colorScheme.trendingOrange, size: 12),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}



