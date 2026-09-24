import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Category artwork with icon fallback.
///
/// Shows [imageUrl] (remote URL or bundled asset path) and renders
/// [fallback] when artwork is missing or fails to load, so tiles never
/// break on categories without uploaded photos.
class CategoryImage extends StatelessWidget {
  final String? imageUrl;
  final IconData fallback;
  final BoxFit fit;
  final double iconSize;
  final Color? iconColor;
  final int? memCacheSize;
  final BorderRadius borderRadius;

  const CategoryImage({
    super.key,
    required this.imageUrl,
    required this.fallback,
    this.fit = BoxFit.cover,
    this.iconSize = 28,
    this.iconColor,
    this.memCacheSize,
    this.borderRadius = BorderRadius.zero,
  });

  bool get _hasArtwork => imageUrl != null && imageUrl!.isNotEmpty;
  bool get _isRemote => _hasArtwork && imageUrl!.startsWith('http');

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (!_hasArtwork) return _fallbackIcon(cs);
    final Widget art = _isRemote ? _remoteArt() : _assetArt();
    if (borderRadius == BorderRadius.zero) return art;
    return ClipRRect(borderRadius: borderRadius, child: art);
  }

  Widget _remoteArt() {
    return CachedNetworkImage(
      imageUrl: imageUrl!,
      fit: fit,
      memCacheWidth: memCacheSize,
      memCacheHeight: memCacheSize,
      placeholder: (context, _) =>
          _fallbackIcon(Theme.of(context).colorScheme),
      errorWidget: (context, _, _) =>
          _fallbackIcon(Theme.of(context).colorScheme),
    );
  }

  Widget _assetArt() {
    return Image.asset(
      imageUrl!,
      fit: fit,
      errorBuilder: (context, _, _) =>
          _fallbackIcon(Theme.of(context).colorScheme),
    );
  }

  Widget _fallbackIcon(ColorScheme cs) {
    return Icon(
      fallback,
      size: iconSize,
      color: iconColor ?? cs.onSurfaceVariant,
    );
  }
}
