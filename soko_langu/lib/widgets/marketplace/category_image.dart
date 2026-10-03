import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../services/category_artwork/category_artwork_service.dart';

/// Category artwork with a three-tier fallback that never breaks.
///
/// Resolution order, always terminating in something renderable:
///
/// 1. [imageUrl], when it is a real remote URL — the only tier that touches
///    the network.
/// 2. [localPath], else the installed artwork pack looked up by stable
///    taxonomy id through [CategoryArtworkService].
/// 3. [fallback] — a Material icon.
///
/// There is deliberately no bundled-asset tier. Category photographs ship in
/// the downloadable artwork pack and are addressed by taxonomy id, not by a
/// path compiled into the binary. An earlier version accepted a bundle path
/// here and ranked it *above* the pack; when those photos were removed from
/// the bundle, `Image.asset` threw, the error handler fell through to the
/// icon, and the entire downloaded pack stayed invisible on every screen —
/// the one outcome the pack exists to prevent. Keeping a single artwork
/// source removes that whole class of divergence.
///
/// The pack is looked up by id, never by display name, so the mapping survives
/// localization. Screens pass the taxonomy id and this widget does the rest;
/// no screen implements its own asset lookup.
class CategoryImage extends StatelessWidget {
  /// Remote artwork URL. Only an `http(s)`/`//` value counts; anything else is
  /// ignored so a stale path cannot shadow the installed artwork pack.
  final String? imageUrl;

  /// Explicit local file path, e.g. from the seller's own artwork upload.
  /// Takes precedence over [categoryId].
  final String? localPath;

  /// Stable taxonomy id (`electronics`). Resolved against the installed pack.
  final String? categoryId;

  /// Stable subcategory id (`phones`). Requires [categoryId] because a
  /// subcategory slug alone is not unique across categories.
  final String? subcategoryId;

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
    required this.fallback,
    this.fit = BoxFit.cover,
    this.iconSize = 28,
    this.iconColor,
    this.memCacheSize,
    this.borderRadius = BorderRadius.zero,
  });

  /// [imageUrl] only when it is genuinely remote.
  ///
  /// This is the single gate that keeps a non-URL out of every branch below.
  /// A bundled path used to be accepted here, which is how a photo deleted
  /// from the app bundle ended up permanently shadowing the artwork pack.
  String? get _remoteUrl {
    final v = imageUrl?.trim();
    if (v == null || v.isEmpty) return null;
    return (v.startsWith('http') || v.startsWith('//')) ? v : null;
  }

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
    // Tier 1: a real remote URL is the strongest signal we have.
    final remote = _remoteUrl;
    if (remote != null) return _remoteArt(context, remote);

    // Tier 2/3: an explicit file, then the installed pack. Both are local, so
    // they are cheap and cannot fail on a flaky connection.
    final packPath = _packPath();
    if (packPath != null) return _fileArt(context, packPath);

    return _iconFallback(context);
  }

  Widget _remoteArt(BuildContext context, String url) {
    return CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      memCacheWidth: memCacheSize,
      memCacheHeight: memCacheSize,
      placeholder: (context, _) => _iconFallback(context),
      errorWidget: (context, _, _) => _iconFallback(context),
    );
  }

  /// Pack file. An unreadable file (deleted by the OS, truncated by a crash)
  /// degrades to the icon rather than throwing inside the build.
  Widget _fileArt(BuildContext context, String path) {
    return Image.file(
      File(path),
      fit: fit,
      cacheWidth: memCacheSize,
      cacheHeight: memCacheSize,
      gaplessPlayback: true,
      errorBuilder: (context, _, _) => _iconFallback(context),
    );
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