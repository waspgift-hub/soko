import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../services/category_artwork/category_artwork_service.dart';

/// Category artwork with a three-tier fallback that never breaks.
///
/// Resolution order, always terminating in something renderable:
///
/// 1. [imageUrl] — remote URL from the API, or a bundled asset path.
/// 2. [localPath] — a file from the installed artwork pack, looked up by
///    stable taxonomy id through [CategoryArtworkService].
/// 3. [fallback] — a Material icon.
///
/// The local pack is looked up by id, never by display name, so the mapping
/// survives localization. Screens pass the taxonomy id and this widget does
/// the rest; no screen implements its own asset lookup.
class CategoryImage extends StatelessWidget {
  /// Remote URL or bundled asset path. Takes precedence over [localPath].
  final String? imageUrl;

  /// Explicit local file path, e.g. from the seller's own artwork upload.
  /// Takes precedence over [categoryId].
  final String? localPath;

  /// Stable taxonomy id (`electronics`). Resolved against the installed pack.
  final String? categoryId;

  /// Stable subcategory id (`phones`). Requires [categoryId] because a
  /// subcategory slug alone is not unique across categories.
  final String? subcategoryId;

  /// Bundled lightweight placeholder, used when no pack file exists yet.
  final String? placeholderAsset;

  final IconData fallback;
  final BoxFit fit;
  final double iconSize;
  final Color? iconColor;
  final int? memCacheSize;
  final BorderRadius borderRadius;

  const CategoryImage({
    super.key,
    this.imageUrl,
    this.localPath,
    this.categoryId,
    this.subcategoryId,
    this.placeholderAsset,
    required this.fallback,
    this.fit = BoxFit.cover,
    this.iconSize = 28,
    this.iconColor,
    this.memCacheSize,
    this.borderRadius = BorderRadius.zero,
  });

  bool get _hasRemote => imageUrl != null && imageUrl!.isNotEmpty;

  bool get _isRemoteUrl =>
      _hasRemote &&
      (imageUrl!.startsWith('http') || imageUrl!.startsWith('//'));

  /// Resolved pack file for this tile, or null when the pack has no artwork
  /// for the id (or is not installed at all).
  String? _packPath() {
    if (localPath != null && localPath!.isNotEmpty) return localPath;
    final service = CategoryArtworkService.instance;
    if (categoryId == null || categoryId!.isEmpty) return null;
    if (subcategoryId != null && subcategoryId!.isNotEmpty) {
      return service.resolveSubcategory(categoryId!, subcategoryId!);
    }
    return service.resolveCategory(categoryId!);
  }

  @override
  Widget build(BuildContext context) {
    final art = _buildArt(context);
    if (borderRadius == BorderRadius.zero) return art;
    return ClipRRect(borderRadius: borderRadius, child: art);
  }

  Widget _buildArt(BuildContext context) {
    if (_hasRemote && _isRemoteUrl) return _remoteArt(context);
    if (_hasRemote && !_isRemoteUrl) return _bundledAsset(context);

    final packPath = _packPath();
    if (packPath != null) return _fileArt(context, packPath);

    if (placeholderAsset != null) return _bundledAsset(context);

    return _iconFallback(context);
  }

  Widget _remoteArt(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: imageUrl!,
      fit: fit,
      memCacheWidth: memCacheSize,
      memCacheHeight: memCacheSize,
      placeholder: (context, _) => _iconFallback(context),
      errorWidget: (context, _, _) => _fallbackAfterFailure(context),
    );
  }

  /// Pack file. An unreadable file (deleted by the OS, truncated by a crash)
  /// degrades to the placeholder rather than throwing inside the build.
  Widget _fileArt(BuildContext context, String path) {
    return Image.file(
      File(path),
      fit: fit,
      cacheWidth: memCacheSize,
      cacheHeight: memCacheSize,
      gaplessPlayback: true,
      errorBuilder: (context, _, _) => _fallbackAfterFailure(context),
    );
  }

  Widget _bundledAsset(BuildContext context) {
    return Image.asset(
      imageUrl!,
      fit: fit,
      errorBuilder: (context, _, _) => _fallbackAfterFailure(context),
    );
  }

  /// The tile has artwork on record but it could not be painted. Falling
  /// through to the icon here is what keeps a corrupt or half-deleted pack
  /// from ever showing a broken-image box.
  Widget _fallbackAfterFailure(BuildContext context) {
    if (placeholderAsset != null && !_hasRemote) return _bundledAsset(context);
    return _iconFallback(context);
  }

  Widget _iconFallback(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ColoredBox(
      color: cs.surfaceContainerHighest,
      child: Center(
        child: Icon(fallback, size: iconSize, color: iconColor ?? cs.primary),
      ),
    );
  }
}