import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/product_model.dart';
import '../../models/flash_sale_model.dart';
import '../../services/product_service.dart';
import '../../services/soko_cache_manager.dart';
import '../extensions/context_tr.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import 'soko_vibe_watermark.dart';
import 'ds/ds.dart';

class ProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;
  final FlashSale? flashSale;

  const ProductCard({super.key, required this.product, required this.onTap, this.flashSale});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
            color: cs.surface,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: cs.brightness == Brightness.dark ? 0.25 : 0.05),
                blurRadius: 14,
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
                            Hero(
                              tag: 'product-img-${product.id}',
                              child: CachedNetworkImage(
                                imageUrl: getThumbnailUrl(product.images.first),
                                cacheManager: SokoCacheManager(),
                                memCacheWidth: 360,
                                memCacheHeight: 360,
                                fit: BoxFit.cover,
                                fadeInDuration: Duration.zero,
                                fadeOutDuration: Duration.zero,
                                placeholder: (context, url) => Container(
                                  color: cs.surfaceContainerLow,
                                ),
                                errorWidget: (context, url, error) => Container(
                                  color: cs.surfaceContainerLow,
                                  child: Icon(Icons.image_outlined, size: 40, color: cs.onSurfaceVariant),
                                ),
                              ),
                            ),
                            _buildSellerBadge(context, badgeSize, cs),
                            Positioned(
                              bottom: 6,
                              left: 6,
                              child: IgnorePointer(
                                child: SokoVibeWatermark(),
                              ),
                            ),
                            if (flashSale != null)
                              Positioned(
                                top: 8, right: 8,
                                child: Container(
                                  padding: EdgeInsets.symmetric(horizontal: 6 * scale, vertical: 3 * scale),
                                  decoration: BoxDecoration(
                                    color: cs.error,
                                    borderRadius: BorderRadius.circular(10),
                                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 6)],
                                  ),
                                  child: Text('-${flashSale!.discountPercent.toStringAsFixed(0)}%',
                                    style: TextStyle(color: cs.surface, fontSize: badgeSize, fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ),
                          ],
                        )
                      : Center(child: Icon(Icons.image_outlined, size: 40, color: cs.onSurface.withValues(alpha: 0.6))),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(padding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: nameSize, color: cs.onSurface),
                          ),
                        ),
                        if (product.sellerKycApproved) ...[
                          SizedBox(width: 2 * scale),
                          Icon(Icons.verified, size: 14 * scale, color: cs.successGreen),
                        ],
                      ],
                    ),
                    SizedBox(height: 4 * scale),
                    if (flashSale != null) ...[
                      Text(context.formatPrice(flashSale!.salePrice),
                        style: AppTypography.amount(cs.error).copyWith(fontSize: priceSize, fontWeight: FontWeight.w700),
                      ),
                      SizedBox(height: 2 * scale),
                      Text(context.formatPrice(flashSale!.originalPrice),
                        style: TextStyle(decoration: TextDecoration.lineThrough, color: cs.onSurface.withValues(alpha: 0.5), fontSize: smallSize),
                      ),
                    ] else
                      Text(context.formatPrice(product.price),
                        style: AppTypography.amount(cs.primary).copyWith(fontSize: priceSize, fontWeight: FontWeight.w700),
                      ),
                    SizedBox(height: 4 * scale),
                    Row(
                      children: [
                        Icon(Icons.location_on_outlined, size: 12 * scale, color: cs.onSurface.withValues(alpha: 0.45)),
                        SizedBox(width: 2 * scale),
                        Expanded(
                          child: Text(product.location,
                            style: TextStyle(fontSize: smallSize, color: cs.onSurface.withValues(alpha: 0.5)),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (product.condition == 'new')
                          Text('  ·  ${context.tr('new')}',
                            style: TextStyle(fontSize: smallSize, color: cs.successGreen, fontWeight: FontWeight.w600),
                          ),
                      ],
                    ),
                    if (product.rating > 0) ...[
                      SizedBox(height: 2 * scale),
                      Row(
                        children: [
                          Icon(Icons.star_rounded, size: 13 * scale, color: cs.trendingOrange),
                          SizedBox(width: 2 * scale),
                          Text("${product.rating.toStringAsFixed(1)} (${product.reviewCount})",
                            style: TextStyle(fontSize: smallSize, color: cs.onSurface.withValues(alpha: 0.5)),
                          ),
                          const Spacer(),
                          if (product.soldCount > 0)
                            Text('${product.soldCount} ${context.tr('sold')}',
                              style: TextStyle(fontSize: smallSize * 0.9, color: cs.onSurface.withValues(alpha: 0.4)),
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

        final displayPrice = flashSale?.salePrice ?? product.price;
        final semanticsLabel = [
          product.name,
          context.formatPrice(displayPrice),
          if (product.location.isNotEmpty) product.location,
          if (product.rating > 0)
            '${product.rating.toStringAsFixed(1)} ${context.tr('rating')}',
        ].join(', ');

        return Semantics(
          button: true,
          label: semanticsLabel,
          onTap: onTap,
          child: AnimatedPress(
            onTap: onTap,
            pressedScale: 0.98,
            child: card,
          ),
        );
      },
    );
  }

  Widget _buildSellerBadge(BuildContext context, double badgeSize, ColorScheme cs) {
    return Stack(
      children: [
        if (product.isFeaturedValid)
          Positioned(
            top: 8, left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [cs.trendingOrange, cs.trendingOrange.withValues(alpha: 0.7)]),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.verified, size: badgeSize, color: cs.surface),
                  const SizedBox(width: 3),
                  Text(context.tr('featured'),
                    style: TextStyle(color: cs.surface, fontSize: 9, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
