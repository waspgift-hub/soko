import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/product_service.dart';
import '../models/product_model.dart';
import '../extensions/context_tr.dart';
import '../app/routes.dart';

class TrendingCarousel extends StatefulWidget {
  const TrendingCarousel({super.key});

  @override
  State<TrendingCarousel> createState() => _TrendingCarouselState();
}

class _TrendingCarouselState extends State<TrendingCarousel> {
  final PageController _pageCtrl = PageController(viewportFraction: 0.4);
  int _currentPage = 0;

  @override
  void dispose() {
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
                  const Icon(Icons.trending_up, color: Color(0xFFFF6F00), size: 20),
                  const SizedBox(width: 6),
                  Text(
                    'Trending',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1B4332),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${products.length} ${context.tr('products').toLowerCase()}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
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
                        return _buildCard(p);
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
                                ? const Color(0xFFFF6F00)
                                : Colors.grey[300],
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

  Widget _buildCard(Product p) {
    return GestureDetector(
      onTap: () => context.push(
        '${AppRoutes.productDetail}/${p.id}',
        extra: p,
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFF6F00).withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
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
                color: Colors.grey[100],
                child: p.images.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: p.images.first,
                        fit: BoxFit.cover,
                        width: double.infinity,
                      )
                    : const Center(child: Icon(Icons.image, color: Colors.grey, size: 32)),
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
                  Text(
                    context.formatPrice(p.price),
                    style: const TextStyle(
                      color: Color(0xFFFF6F00),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  const Icon(Icons.star, color: Color(0xFFFF6F00), size: 12),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
