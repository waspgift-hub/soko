import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/flash_sale_model.dart';
import '../../models/product_model.dart';
import '../../services/product_service.dart';
import '../../services/soko_cache_manager.dart';
import '../../extensions/context_tr.dart';
import '../../theme/app_colors.dart';
import '../../theme/surface_policy.dart';
import 'ads/blue_tick_badge.dart';
import 'ds/ds.dart';
import 'soko_vibe_watermark.dart';

/// Marketplace product tile.
///
/// Rendering budget: a grid shows 20–60 of these at once, so every choice here is
/// about keeping the frame cheap.
///
/// * Images sit behind a [RepaintBoundary] — they are the expensive paint, and
///   without it a scroll repaints every visible tile.
/// * The image placeholder is **static**, not the animated `DsSkeleton`. That
///   skeleton runs a repeating `AnimationController`; with dozens of tiles
///   scrolling, dozens of shimmer loops repainted every single frame and fought
///   the scroll for the GPU.
/// * No [Hero] here. Heroes are scanned by the route's `HeroController` on every
///   frame; a grid full of them is pure overhead. The detail page keeps its own
///   hero and still cross-fades fine.
/// * Promotional badges skip the wrapping `Stack` entirely when there are none.
class ProductCard extends StatelessWidget {
  const ProductCard({
    super.key,
    required this.product,
    required this.onTap,
    this.flashSale,
    this.isBoosted = false,
  });

  final Product product;
  final VoidCallback onTap;
  final FlashSale? flashSale;
  final bool isBoosted;

  /// Hoisted so 60 cards do not each allocate a cache-manager reference.
  static final cacheManager = SokoCacheManager();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = (constraints.maxWidth / 170).clamp(0.8, 1.4);
        final nameSize = (14 * scale).clamp(12.0, 17.0);
        final priceSize = (13 * scale).clamp(12.0, 16.0);
        final smallSize = (10.5 * scale).clamp(9.5, 12.5);
        final padding = (8.0 * scale).clamp(6.0, 11.0);
        const radius = 15.0;

        final card = Container(
          decoration: SurfacePolicy.decorate(
            SurfaceRole.card,
            cs.brightness,
            radius: radius,
            fill: cs.surface,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(radius)),
                  child: _buildImage(context, cs, radius, scale, smallSize),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(padding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildTitleRow(cs, nameSize, scale),
                    SizedBox(height: 3 * scale),
                    _buildPrice(cs, priceSize),
                    SizedBox(height: 4 * scale),
                    _buildMetaRow(context, cs, smallSize, scale),
                    SizedBox(height: 3 * scale),
                    _buildFooterRow(context, cs, smallSize),
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
          context.tr(product.condition == 'new' ? 'new' : 'used'),
          if (product.district.isNotEmpty) product.district,
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
            child: RepaintBoundary(child: card),
          ),
        );
      },
    );
  }

  // ─── Image ────────────────────────────────────────────────────────────────

  Widget _buildImage(
    BuildContext context,
    ColorScheme cs,
    double radius,
    double scale,
    double smallSize,
  ) {
    if (product.images.isEmpty) {
      return Center(
        child: Icon(Icons.image_outlined, size: 36, color: cs.onSurface.withValues(alpha: 0.6)),
      );
    }

    final badges = _buildSellerBadges(context, cs, scale);

    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: CachedNetworkImage(
            imageUrl: getThumbnailUrl(product.images.first),
            cacheManager: cacheManager,
            // Decode at roughly the on-screen size. Decoding a full-resolution
            // photo into every tile was a large memory and rasterisation cost.
            memCacheWidth: (_decodeWidth(scale) * 2).round(),
            fit: BoxFit.cover,
            fadeInDuration: const Duration(milliseconds: 180),
            fadeOutDuration: const Duration(milliseconds: 80),
            // Static placeholder: no AnimationController, no per-frame repaint.
            placeholder: (context, url) =>
                ColoredBox(color: cs.surfaceContainerLow),
            errorWidget: (context, url, error) => ColoredBox(
              color: cs.surfaceContainerLow,
              child: Icon(Icons.image_outlined, size: 36, color: cs.onSurfaceVariant),
            ),
          ),
        ),
        // `?badges` keeps the Stack child list free of a null slot while still
        // omitting the badge layer entirely when there is nothing to show.
        ?badges,
        // Video: a clip is the single most useful signal on a marketplace
        // tile, and it was previously invisible here.
        if (product.videoUrl != null && product.videoUrl!.isNotEmpty)
          Positioned(
            top: 6,
            right: 6,
            child: _ImageChip(
              icon: Icons.play_circle_fill,
              label: null,
              color: cs.surface,
              iconColor: cs.primary,
              size: 16 * scale,
            ),
          ),
        if (product.images.length > 1)
          Positioned(
            top: 6,
            right: product.videoUrl != null && product.videoUrl!.isNotEmpty ? 26 * scale : 6,
            child: _ImageChip(
              icon: Icons.photo_library_outlined,
              label: '${product.images.length}',
              color: cs.surface,
              iconColor: cs.onSurface,
              size: 11 * scale,
            ),
          ),
        Positioned(
          bottom: 6,
          left: 6,
          child: const IgnorePointer(child: SokoVibeWatermark()),
        ),
        if (flashSale != null)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 5 * scale, vertical: 2 * scale),
              decoration: BoxDecoration(
                color: cs.error,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '-${flashSale!.discountPercent.toStringAsFixed(0)}%',
                style: TextStyle(
                  color: cs.surface,
                  fontSize: (10 * scale).clamp(9.0, 12.0),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Rough on-screen width for the decode budget. Deliberately simple: a linear
  /// read off the same scale the layout already computed.
  double _decodeWidth(double scale) => 180 * scale;

  // ─── Body ─────────────────────────────────────────────────────────────────

  Widget _buildTitleRow(ColorScheme cs, double nameSize, double scale) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            product.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: nameSize,
              height: 1.15,
              color: cs.onSurface,
            ),
          ),
        ),
        // Blue Tick from trusted state, replacing the inline Icons.verified that
        // used to trust a client-writable product field.
        if (product.sellerId.isNotEmpty) BlueTickBadge(
          sellerId: product.sellerId,
          size: 13 * scale,
        ),
      ],
    );
  }

  Widget _buildPrice(ColorScheme cs, double priceSize) {
    return flashSale != null
        ? DsPrice(
            price: flashSale!.salePrice,
            oldPrice: flashSale!.originalPrice,
            color: cs.error,
            size: priceSize,
            weight: FontWeight.w700,
          )
        : DsPrice(
            price: product.price,
            color: cs.primary,
            size: priceSize,
            weight: FontWeight.w700,
          );
  }

  /// Condition + district. Previously only "new" appeared, and only as a
  /// two-character fragment — a used phone looked identical to a new one.
  Widget _buildMetaRow(
    BuildContext context,
    ColorScheme cs,
    double smallSize,
    double scale,
  ) {
    final isNew = product.condition == 'new';
    final place = product.district.isNotEmpty
        ? product.district
        : (product.location.isNotEmpty && product.location != 'Tanzania'
            ? product.location
            : '');

    return Row(
      children: [
        Flexible(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isNew ? Icons.auto_awesome : Icons.handyman_outlined,
                size: smallSize,
                color: isNew ? cs.successGreen : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 2),
              Flexible(
                child: Text(
                  context.tr(isNew ? 'new' : 'used'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: smallSize,
                    fontWeight: FontWeight.w600,
                    color: isNew ? cs.successGreen : cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (place.isNotEmpty) ...[
          SizedBox(width: 6 * scale),
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.place_outlined, size: smallSize, color: cs.onSurfaceVariant),
                const SizedBox(width: 2),
                Flexible(
                  child: Text(
                    place,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: smallSize,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// Rating, sold count and stock.
  ///
  /// Stock was absent entirely, so an out-of-stock item looked identical to a
  /// live one. Showing "Out of stock" up front is what stops a buyer from
  /// tapping a dead listing.
  Widget _buildFooterRow(BuildContext context, ColorScheme cs, double smallSize) {
    final muted = cs.onSurface.withValues(alpha: 0.55);
    final stockOut = product.stock <= 0;
    final stockLow = !stockOut && product.stock <= 3;

    return Row(
      children: [
        if (product.rating > 0) ...[
          Icon(Icons.star_rounded, size: 13 * (smallSize / 10.5), color: cs.trendingOrange),
          const SizedBox(width: 2),
          Text(
            '${product.rating.toStringAsFixed(1)} (${product.reviewCount})',
            style: TextStyle(fontSize: smallSize, color: muted),
          ),
        ] else if (product.soldCount > 0) ...[
          Icon(Icons.local_fire_department_outlined, size: 13 * (smallSize / 10.5), color: muted),
          const SizedBox(width: 2),
          Text(
            '${product.soldCount} ${context.tr('sold')}',
            style: TextStyle(fontSize: smallSize, color: muted),
          ),
        ],
        const Spacer(),
        if (stockOut)
          Text(
            context.tr('out_of_stock'),
            style: TextStyle(
              fontSize: smallSize,
              fontWeight: FontWeight.w700,
              color: cs.error,
            ),
          )
        else if (stockLow)
          Text(
            context.tr('only_left', '{n} left').replaceAll('{n}', '${product.stock}'),
            style: TextStyle(fontSize: smallSize, color: cs.brandWarning),
          ),
      ],
    );
  }

  // ─── Badges ───────────────────────────────────────────────────────────────

  /// Returns null instead of an empty `Stack` when there is nothing to show —
  /// one fewer layer on the majority of tiles.
  Widget? _buildSellerBadges(BuildContext context, ColorScheme cs, double scale) {
    final featured = product.isFeaturedValid;
    final boosted = isBoosted || product.isBoostedValid;
    if (!featured && !boosted) return null;

    return Stack(
      children: [
        if (featured)
          Positioned(
            top: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [cs.trendingOrange, cs.trendingOrange.withValues(alpha: 0.7)],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.verified, size: 9 * scale, color: cs.surface),
                  const SizedBox(width: 3),
                  Text(
                    context.tr('featured'),
                    style: TextStyle(color: cs.surface, fontSize: 9, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
        if (boosted)
          Positioned(
            top: featured ? 32 : 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
              ),
              child: Text(
                context.tr('boost_product'),
                style: TextStyle(color: cs.primary, fontSize: 9, fontWeight: FontWeight.bold),
              ),
            ),
          ),
      ],
    );
  }
}

/// Small pill used for the on-image media badges.
class _ImageChip extends StatelessWidget {
  const _ImageChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.iconColor,
    required this.size,
  });

  final IconData icon;
  final String? label;
  final Color color;
  final Color iconColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: label == null ? 3 : 5, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: size, color: iconColor),
          if (label != null) ...[
            const SizedBox(width: 2),
            Text(
              label!,
              style: TextStyle(
                fontSize: size * 0.85,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ],
      ),
    );
  }
}