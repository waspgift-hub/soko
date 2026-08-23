import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/soko_cache_manager.dart';

/// Standardized image widget with consistent caching, shimmer placeholder,
/// fade-in transition, memory optimization, and error handling.
///
/// Usage:
///   ProductCachedImage(url: product.images.first, width: 120, height: 120)
///
/// Features:
/// - SokoCacheManager (3-day disk cache, 400 objects max)
/// - Memory cache sized to display dimensions (saves RAM)
/// - Shimmer skeleton placeholder while loading
/// - 300ms fade-in transition from placeholder to loaded
/// - Consistent error icon for broken images
/// - Optional hero animation for product detail transitions
class ProductCachedImage extends StatelessWidget {
  final String? url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final String? heroTag;
  final BorderRadius? borderRadius;
  final Widget? errorWidget;

  const ProductCachedImage({
    super.key,
    this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.heroTag,
    this.borderRadius,
    this.errorWidget,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final placeholder = _buildPlaceholder(cs);

    if (url == null || url!.isEmpty) {
      return _wrapWithHero(_buildFallback(cs));
    }

    return _wrapWithHero(
      ClipRRect(
        borderRadius: borderRadius ?? BorderRadius.zero,
        child: CachedNetworkImage(
          imageUrl: url!,
          cacheManager: SokoCacheManager(),
          memCacheWidth: width?.toInt(),
          memCacheHeight: height?.toInt(),
          fit: fit,
          fadeInDuration: const Duration(milliseconds: 300),
          fadeOutDuration: const Duration(milliseconds: 100),
          placeholder: (_, _) => placeholder,
          errorWidget: (_, _, _) => errorWidget ?? _buildFallback(cs),
        ),
      ),
    );
  }

  Widget _buildPlaceholder(ColorScheme cs) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment(-1.0, -0.3),
          end: Alignment(1.0, 0.3),
          colors: [
            cs.surfaceContainerLow,
            cs.surfaceContainerHigh.withValues(alpha: 0.5),
            cs.surfaceContainerLow,
          ],
        ),
      ),
    );
  }

  Widget _buildFallback(ColorScheme cs) {
    return Container(
      width: width,
      height: height,
      color: cs.surfaceContainerLow,
      child: Icon(
        Icons.image_outlined,
        size: width != null && width! < 60 ? 20 : 40,
        color: cs.onSurfaceVariant.withValues(alpha: 0.5),
      ),
    );
  }

  Widget _wrapWithHero(Widget child) {
    if (heroTag == null) return child;
    return Hero(tag: heroTag!, child: child);
  }
}
