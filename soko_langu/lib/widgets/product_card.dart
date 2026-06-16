import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/product_model.dart';
import '../../models/flash_sale_model.dart';
import 'google_loading.dart';
import '../extensions/context_tr.dart';
import '../theme/app_colors.dart';

class ProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;
  final FlashSale? flashSale;

  const ProductCard({super.key, required this.product, required this.onTap, this.flashSale});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth;
        final scale = (cardWidth / 170).clamp(0.8, 1.4);
        final nameSize = (14 * scale).clamp(12.0, 18.0);
        final priceSize = (13 * scale).clamp(12.0, 17.0);
        final smallSize = (11 * scale).clamp(10.0, 14.0);
        final badgeSize = (10 * scale).clamp(9.0, 13.0);
        final padding = (8.0 * scale).clamp(6.0, 12.0);
        const radius = 15.0;

        Widget card = Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
                  child: product.images.isNotEmpty
                      ? Stack(
                          fit: StackFit.expand,
                          children: [
                            CachedNetworkImage(
                              imageUrl: product.images.first,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                color: Theme.of(context).colorScheme.surfaceContainerLow,
                                child: const Center(
                                  child: GoogleLoading(size: 24, strokeWidth: 2),
                                ),
                              ),
                              errorWidget: (context, url, error) => Container(
                                color: Theme.of(context).colorScheme.outlineVariant,
                                child: Icon(
                                  Icons.image,
                                  size: 40,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            _buildSellerBadge(context, badgeSize),
                            if (flashSale != null)
                              Positioned(
                                top: 8,
                                right: 8,
                                child: Container(
                                  padding: EdgeInsets.symmetric(horizontal: 6 * scale, vertical: 3 * scale),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.error,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '-${flashSale!.discountPercent.toStringAsFixed(0)}%',
                                    style: TextStyle(
                                      color: Theme.of(context).colorScheme.surface,
                                      fontSize: badgeSize,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        )
                      : Center(
                          child: Icon(
                            Icons.image,
                            size: 40,
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(padding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: nameSize,
                      ),
                    ),
                    SizedBox(height: 4 * scale),
                    if (flashSale != null) ...[
                      Text(
                        context.formatPrice(flashSale!.salePrice),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontWeight: FontWeight.bold,
                          fontSize: priceSize,
                        ),
                      ),
                      SizedBox(height: 2 * scale),
                      Text(
                        context.formatPrice(flashSale!.originalPrice),
                        style: TextStyle(
                          decoration: TextDecoration.lineThrough,
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                          fontSize: smallSize,
                        ),
                      ),
                    ] else
                      Text(
                        context.formatPrice(product.price),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: priceSize,
                        ),
                      ),
                    SizedBox(height: 4 * scale),
                    Row(
                      children: [
                        Icon(
                          Icons.location_on,
                          size: 12 * scale,
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                        SizedBox(width: 2 * scale),
                        Expanded(
                          child: Text(
                            product.location,
                            style: TextStyle(
                              fontSize: smallSize,
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (product.rating > 0) ...[
                      SizedBox(height: 2 * scale),
                      Row(
                        children: [
                          Icon(Icons.star, size: 12 * scale, color: Theme.of(context).colorScheme.tertiary),
                          SizedBox(width: 2 * scale),
                          Text(
                            "${product.rating.toStringAsFixed(1)} (${product.reviewCount})",
                            style: TextStyle(
                              fontSize: smallSize,
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );

        return GestureDetector(onTap: onTap, child: card);
      },
    );
  }

  Widget _buildSellerBadge(BuildContext context, double badgeSize) {
    return Stack(
      children: [
        if (product.isFeaturedValid)
          Positioned(
            top: 8,
            left: 8,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Theme.of(context).colorScheme.trendingOrange, Theme.of(context).colorScheme.trendingOrange.withValues(alpha: 0.7)],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.verified, size: badgeSize, color: Theme.of(context).colorScheme.surface),
                  SizedBox(width: 3),
                  Text(
                    context.tr('featured'),
                    style: TextStyle(color: Theme.of(context).colorScheme.surface,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
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



