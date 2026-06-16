import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:carousel_slider/carousel_slider.dart';
import '../services/product_service.dart';
import '../services/flash_sale_service.dart';
import '../models/product_model.dart';
import '../models/flash_sale_model.dart';
import '../app/routes.dart';
import '../extensions/context_tr.dart';

class DynamicBanner extends StatelessWidget {
  const DynamicBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Product>>(
      stream: ProductService().getBoostedProducts(),
      builder: (context, productSnapshot) {
        final boosted = productSnapshot.data ?? [];
        if (boosted.isNotEmpty) {
          return _BoostedCarousel(products: boosted);
        }
        return StreamBuilder<List<FlashSale>>(
          stream: FlashSaleService().getActiveFlashSales(),
          builder: (context, flashSnapshot) {
            final sales = flashSnapshot.data ?? [];
            if (sales.isNotEmpty) {
              return const SizedBox.shrink();
            }
            return const EarnMoneyBanner();
          },
        );
      },
    );
  }
}

class _BoostedCarousel extends StatelessWidget {
  final List<Product> products;

  const _BoostedCarousel({required this.products});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        CarouselSlider.builder(
          itemCount: products.length,
          itemBuilder: (context, index, _) {
            return _BoostedCard(product: products[index]);
          },
          options: CarouselOptions(
            height: 200,
            autoPlay: true,
            autoPlayInterval: const Duration(seconds: 4),
            enlargeCenterPage: true,
            viewportFraction: 0.85,
            autoPlayCurve: Curves.easeInOut,
          ),
        ),
        Positioned(
          top: 8,
          left: 24,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.amber.shade700,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.trending_up, color: Colors.white, size: 16),
                SizedBox(width: 4),
                Text(
                  'FEATURED',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _BoostedCard extends StatelessWidget {
  final Product product;

  const _BoostedCard({required this.product});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('${AppRoutes.productDetail}/${product.id}',
          extra: product),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Theme.of(context).cardColor,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                bottomLeft: Radius.circular(16),
              ),
              child: SizedBox(
                width: 140,
                height: 176,
                child: product.images.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: product.images.first,
                        fit: BoxFit.cover,
                        placeholder: (_, _) => _imagePlaceholder(),
                        errorWidget: (_, _, _) => _imagePlaceholder(),
                      )
                    : _imagePlaceholder(),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade100,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'BOOSTED',
                        style: TextStyle(
                          color: Colors.amber,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      product.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${context.currencySymbol()} ${product.price.toStringAsFixed(0)}',
                      style: TextStyle(
                        color: Theme.of(context).primaryColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _infoChip(Icons.star,
                            product.rating.toStringAsFixed(1), Colors.amber),
                        const SizedBox(width: 8),
                        _infoChip(Icons.shopping_bag,
                            '${product.soldCount} ${_soldText(context)}', Colors.grey),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 2),
        Text(text, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }

  Widget _imagePlaceholder() {
    return Container(
      color: Colors.grey.shade200,
      child: const Icon(Icons.image, color: Colors.grey, size: 40),
    );
  }

  String _soldText(BuildContext context) {
    return 'sold';
  }
}

class EarnMoneyBanner extends StatelessWidget {
  const EarnMoneyBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push(AppRoutes.addProduct),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        height: 160,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1B5E20), Color(0xFF388E3C), Color(0xFF4CAF50)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1B5E20).withValues(alpha: 0.4),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              right: -20,
              bottom: -20,
              child: Icon(
                Icons.monetization_on,
                size: 140,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.monetization_on,
                                color: Colors.yellow, size: 28),
                            SizedBox(width: 8),
                            Text(
                              'PATA PESA',
                              style: TextStyle(
                                color: Colors.yellow,
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Uza bidhaa yako leo hii\nna upate pesa papo hapo!',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 13,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.yellow,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Anza Kuuza',
                                style: TextStyle(
                                  color: Color(0xFF1B5E20),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              SizedBox(width: 6),
                              Icon(
                                Icons.arrow_forward,
                                color: Color(0xFF1B5E20),
                                size: 16,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _iconCircle(Icons.people, 'Wateja'),
                      const SizedBox(height: 12),
                      _iconCircle(Icons.trending_up, 'Mapato'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconCircle(IconData icon, String label) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: const BoxDecoration(
            color: Colors.white24,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 10),
        ),
      ],
    );
  }
}
