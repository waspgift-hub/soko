import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/soko_cache_manager.dart';

/// Standardized image widget with consistent caching, memory optimization,
/// and error handling. No shimmer or loading animation — images appear instantly
/// from cache or show a simple fallback.
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
          fadeInDuration: Duration.zero,
          fadeOutDuration: Duration.zero,
          placeholder: (_, _) => _buildFallback(cs),
          errorWidget: (_, _, _) => errorWidget ?? _buildFallback(cs),
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
