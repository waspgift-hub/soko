import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../theme/app_colors.dart';
import '../../services/product_service.dart';
import '../soko_vibe_watermark.dart';
import '../ds/ds.dart';

/// Compact square product tile for horizontal rails and small grids.
///
/// Intrinsic-width layout (typically 140–160dp) so it sits naturally inside
/// [ListView] with `scrollDirection: Axis.horizontal`.  Image aspect is 1:1;
/// name, price, rating and optional seller line follow below.
class CompactProductCard extends StatelessWidget {
  final String title;
  final num price;
  final num? oldPrice;
  final String imageUrl;
  final double rating;
  final int reviewCount;
  final String? sellerName;
  final bool kycVerified;
  final VoidCallback onTap;
  final int discountPercent;

  const CompactProductCard({
    super.key,
    required this.title,
    required this.price,
    this.oldPrice,
    required this.imageUrl,
    this.rating = 0,
    this.reviewCount = 0,
    this.sellerName,
    this.kycVerified = false,
    required this.onTap,
    this.discountPercent = 0,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth.isFinite ? constraints.maxWidth : 150.0;

        Widget card = Container(
          width: cardWidth,
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: cs.brightness == Brightness.dark ? 0.25 : 0.05),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    imageUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: getThumbnailUrl(imageUrl),
                            fit: BoxFit.cover,
                            memCacheWidth: 280,
                            memCacheHeight: 280,
                            placeholder: (_, _) => Container(color: cs.surfaceContainerLow, child: const DsSkeleton()),
                            errorWidget: (_, _, _) => Container(
                              color: cs.surfaceContainerLow,
                              child: Icon(Icons.image_outlined, size: 32, color: cs.onSurfaceVariant),
                            ),
                          )
                        : Container(
                            color: cs.surfaceContainerLow,
                            child: Icon(Icons.image_outlined, size: 32, color: cs.onSurfaceVariant),
                          ),
                    Positioned(
                      bottom: 4,
                      left: 4,
                      child: IgnorePointer(child: SokoVibeWatermark()),
                    ),
                    if (discountPercent > 0)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: cs.error,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '-$discountPercent%',
                            style: TextStyle(
                              color: cs.surface,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurface),
                    ),
                    const SizedBox(height: 4),
                    DsPrice(
                      price: price,
                      oldPrice: oldPrice,
                      size: 12,
                      weight: FontWeight.w700,
                      color: cs.primary,
                    ),
                    const SizedBox(height: 2),
                    if (rating > 0)
                      Row(
                        children: [
                          Icon(Icons.star_rounded, size: 12, color: cs.primary),
                          const SizedBox(width: 2),
                          Text(
                            rating.toStringAsFixed(1),
                            style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                          ),
                          if (reviewCount > 0) ...[
                            const SizedBox(width: 2),
                            Text('($reviewCount)', style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant)),
                          ],
                          const Spacer(),
                          if (sellerName != null && sellerName!.isNotEmpty)
                            Flexible(
                              child: Text(
                                sellerName!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant),
                              ),
                            ),
                          if (kycVerified) ...[
                            const SizedBox(width: 2),
                            Icon(Icons.verified, size: 11, color: cs.successGreen),
                          ],
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        );

        return Semantics(
          button: true,
          label: '$title, $price',
          child: AnimatedPress(onTap: onTap, child: card),
        );
      },
    );
  }
}