import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/soko_cache_manager.dart';
import 'ds/ds.dart';

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
  final String? placeholderUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final String? heroTag;
  final BorderRadius? borderRadius;
  final Widget? errorWidget;

  const ProductCachedImage({
    super.key,
    this.url,
    this.placeholderUrl,
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
          memCacheWidth: _decodeDimension(context, width),
          memCacheHeight: _decodeDimension(context, height),
          fit: fit,
          fadeInDuration: const Duration(milliseconds: 300),
          fadeOutDuration: const Duration(milliseconds: 100),
          placeholder: (_, _) => _buildImagePlaceholder(cs),
          errorWidget: (_, _, _) => errorWidget ?? _buildFallback(cs),
        ),
      ),
    );
  }

  /// Physical decode target for [CachedNetworkImage].
  ///
  /// Calling `toInt()` on an infinite or NaN dimension throws
  /// `Unsupported operation: Infinity or NaN toInt`, which is one of the red
  /// screens reported from the product feed. Widgets legitimately receive
  /// `double.infinity` from unbounded parents, so anything non-finite or
  /// non-positive is dropped and the decoder keeps its native size.
  int? _decodeDimension(BuildContext context, double? logical) {
    if (logical == null || !logical.isFinite || logical <= 0) return null;
    final dpr = (MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1.0).clamp(1.0, 2.0);
    final px = (logical * dpr).round();
    return px > 0 ? px : null;
  }

  /// Blurred low-res preview while the full image loads (Facebook-style),
  /// falling back to shimmer when no compressed variant exists.
  Widget _buildImagePlaceholder(ColorScheme cs) {
    final low = placeholderUrl;
    if (low == null || low.isEmpty) return _buildPlaceholder(cs);
    return Container(
      color: cs.surfaceContainerLow,
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Image.network(
          low,
          fit: fit,
          width: width,
          height: height,
          errorBuilder: (_, _, _) => _buildPlaceholder(cs),
        ),
      ),
    );
  }

  Widget _buildPlaceholder(ColorScheme cs) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
          ),
        ),
        Center(
          child: DsLoadingDots(color: cs.primary),
        ),
      ],
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
