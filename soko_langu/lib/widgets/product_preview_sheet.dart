import 'dart:io';

import 'package:flutter/material.dart';

import '../../extensions/context_tr.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import '../../theme/design_tokens.dart';
import 'ads/blue_tick_badge.dart';
import 'ds/ds.dart';

/// Preview of a listing exactly as a buyer will see it, shown immediately
/// before publishing.
///
/// Why this matters for speed: newly picked images are still local files at this
/// point, so the preview renders from disk with no network wait and no upload.
/// The seller can confirm the listing and then publish without the preview
/// itself costing anything.
class ProductPreviewSheet {
  const ProductPreviewSheet({
    required this.name,
    required this.price,
    required this.category,
    required this.subcategory,
    required this.stock,
    required this.condition,
    required this.description,
    required this.brand,
    required this.location,
    required this.district,
    required this.isWholesale,
    required this.variants,
    required this.sellerId,
    required this.newImagePaths,
    required this.existingImageUrls,
    required this.hasVideo,
    this.publishLabel,
    this.isEditing = false,
  });

  final String name;
  final double price;
  final String category;
  final String subcategory;
  final int stock;
  final String condition;
  final String description;
  final String brand;
  final String location;
  final String district;
  final bool isWholesale;
  final List<Map<String, dynamic>> variants;

  /// Seller uid, so the Blue Tick appears here exactly as it will in the
  /// marketplace. A seller should never discover at publish time that their
  /// verified badge is missing.
  final String sellerId;

  /// Local paths of images not yet uploaded.
  final List<String> newImagePaths;

  /// Already-hosted URLs (edit flow).
  final List<String> existingImageUrls;

  final bool hasVideo;
  final String? publishLabel;
  final bool isEditing;

  /// Presents the preview. Returns true when the seller confirmed, so the caller
  /// can run the publish itself — keeping "show" and "do" separate means the
  /// preview can also be opened read-only from the app bar without any risk of
  /// accidentally publishing.
  static Future<bool> show(
    BuildContext context, {
    required ProductPreviewSheet preview,
  }) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PreviewShell(
        preview: preview,
        onPublish: () => Navigator.of(ctx).pop(true),
        onEdit: () => Navigator.of(ctx).pop(false),
      ),
    );
    return confirmed == true;
  }
}

class _PreviewShell extends StatelessWidget {
  const _PreviewShell({
    required this.preview,
    required this.onPublish,
    required this.onEdit,
  });

  final ProductPreviewSheet preview;
  final VoidCallback onPublish;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const _Grabber(),
            Padding(
              padding: const EdgeInsets.fromLTRB(Ds.sp4, 0, Ds.sp4, Ds.sp3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      context.tr('preview_listing', 'Onyesho la bidhaa'),
                      style: AppTypography.screenTitle(cs.onSurface),
                    ),
                  ),
                  TextButton(
                    onPressed: onEdit,
                    child: Text(context.tr('edit', 'Badilisha')),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: cs.hairline),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.all(Ds.sp4),
                children: [
                  _PreviewCard(preview: preview),
                  const SizedBox(height: Ds.sp4),
                  _PreviewChecklist(preview: preview),
                ],
              ),
            ),
            _PreviewActions(
              preview: preview,
              onEdit: onEdit,
              onPublish: onPublish,
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewActions extends StatelessWidget {
  const _PreviewActions({
    required this.preview,
    required this.onEdit,
    required this.onPublish,
  });

  final ProductPreviewSheet preview;
  final VoidCallback onEdit;
  final VoidCallback onPublish;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ready = preview.name.trim().isNotEmpty && preview.price > 0;

    return Container(
      padding: EdgeInsets.fromLTRB(
        Ds.sp4,
        Ds.sp3,
        Ds.sp4,
        Ds.sp3 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.hairline)),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: onEdit,
              child: Text(context.tr('edit', 'Badilisha')),
            ),
          ),
          const SizedBox(width: Ds.sp3),
          Expanded(
            flex: 2,
            child: DsButton(
              onPressed: ready ? onPublish : null,
              label: preview.publishLabel ??
                  context.tr(preview.isEditing ? 'update_product' : 'sell_product'),
              icon: Icons.check_rounded,
            ),
          ),
        ],
      ),
    );
  }
}

class _Grabber extends StatelessWidget {
  const _Grabber();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Ds.sp3),
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: cs.hairline,
          borderRadius: BorderRadius.circular(Ds.rFull),
        ),
      ),
    );
  }
}

/// The buyer-facing card. Deliberately reuses the same primitives the real
/// listing uses (DsCard, DsPrice, DsBadge) so the preview cannot drift from
/// production.
class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.preview});
  final ProductPreviewSheet preview;

  List<String> get _allImages =>
      [...preview.existingImageUrls, ...preview.newImagePaths];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final images = _allImages;

    return DsCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (images.isEmpty)
            _NoImagePlaceholder()
          else
            _ImageCarousel(paths: images, hasVideo: preview.hasVideo),
          Padding(
            padding: const EdgeInsets.all(Ds.sp4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        preview.name.trim().isEmpty
                            ? context.tr('untitled', 'Hakuna jina')
                            : preview.name.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.screenTitle(cs.onSurface)
                            .copyWith(fontSize: 17),
                      ),
                    ),
                    if (preview.sellerId.isNotEmpty)
                      BlueTickBadge(sellerId: preview.sellerId, size: 16),
                  ],
                ),
                const SizedBox(height: Ds.sp2),
                DsPrice(
                  price: preview.price,
                  currencyOverride: 'TZS',
                  large: true,
                  color: cs.primary,
                ),
                const SizedBox(height: Ds.sp3),
                Wrap(
                  spacing: Ds.sp2,
                  runSpacing: Ds.sp2,
                  children: [
                    if (preview.category.isNotEmpty)
                      DsBadge(
                        label: preview.subcategory.isEmpty
                            ? preview.category
                            : '${preview.category} · ${preview.subcategory}',
                        color: cs.primary,
                      ),
                    DsBadge(
                      label: preview.condition == 'new'
                          ? context.tr('condition_new', 'Mpya')
                          : context.tr('condition_used', 'Imetumika'),
                      color: preview.condition == 'new' ? cs.successGreen : cs.contentSecondary,
                    ),
                    DsBadge(
                      label: '${context.tr('stock', 'Stock')}: ${preview.stock}',
                      color: preview.stock > 0 ? cs.successGreen : cs.error,
                    ),
                    if (preview.brand.trim().isNotEmpty)
                      DsBadge(label: preview.brand.trim(), color: cs.contentSecondary),
                    if (preview.hasVideo)
                      DsBadge(label: context.tr('has_video', 'Video'), color: cs.tertiary),
                    if (preview.isWholesale)
                      DsBadge(
                        label: context.tr('wholesale', 'Rejareja'),
                        color: cs.tertiary,
                      ),
                  ],
                ),
                if (preview.description.trim().isNotEmpty) ...[
                  const SizedBox(height: Ds.sp3),
                  Text(
                    preview.description.trim(),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: cs.onSurface.withValues(alpha: 0.8),
                    ),
                  ),
                ],
                if (preview.variants.isNotEmpty) ...[
                  const SizedBox(height: Ds.sp3),
                  Text(
                    context.tr('variants', 'Variant'),
                    style: AppTypography.monoLabel(cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: Ds.sp1),
                  ...preview.variants.take(4).map((v) {
                    final adj = (v['priceAdjustment'] as num?)?.toString() ?? '0';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        '${v['name'] ?? ''}: ${v['value'] ?? ''}'
                        '${adj == '0' ? '' : '  (+$adj)'}',
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                    );
                  }),
                ],
                if (_locationLabel(preview).isNotEmpty) ...[
                  const SizedBox(height: Ds.sp3),
                  Row(
                    children: [
                      Icon(Icons.place_outlined, size: 14, color: cs.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          _locationLabel(preview),
                          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
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
  }

  static String _locationLabel(ProductPreviewSheet p) =>
      [p.district, p.location].where((s) => s.trim().isNotEmpty).join(', ');
}

/// Renders local files from disk when they exist, and falls back to the network
/// image for already-hosted URLs. This is what keeps the preview instant.
class _ImageCarousel extends StatefulWidget {
  const _ImageCarousel({required this.paths, required this.hasVideo});
  final List<String> paths;
  final bool hasVideo;

  @override
  State<_ImageCarousel> createState() => _ImageCarouselState();
}

class _ImageCarouselState extends State<_ImageCarousel> {
  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        AspectRatio(
          aspectRatio: 4 / 3,
          child: Stack(
            fit: StackFit.expand,
            children: [
              PageView.builder(
                controller: _controller,
                itemCount: widget.paths.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (_, i) => _PreviewImage(path: widget.paths[i]),
              ),
              if (widget.hasVideo)
                Positioned(
                  left: Ds.sp3,
                  top: Ds.sp3,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(Ds.rFull),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.play_circle_fill, size: 13, color: Colors.white),
                        SizedBox(width: 4),
                        Text(
                          'Video',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (widget.paths.length > 1)
                Positioned(
                  right: Ds.sp3,
                  top: Ds.sp3,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(Ds.rFull),
                    ),
                    child: Text(
                      '${_index + 1}/${widget.paths.length}',
                      style: const TextStyle(fontSize: 10, color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (widget.paths.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: Ds.sp2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(widget.paths.length, (i) {
                final active = i == _index;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: active ? 16 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: active ? cs.primary : cs.hairline,
                    borderRadius: BorderRadius.circular(Ds.rFull),
                  ),
                );
              }),
            ),
          ),
      ],
    );
  }
}

class _PreviewImage extends StatelessWidget {
  const _PreviewImage({required this.path});
  final String path;

  @override
  Widget build(BuildContext context) {
    final isRemote = path.startsWith('http://') || path.startsWith('https://');
    if (isRemote) {
      return Image.network(
        path,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const _NoImagePlaceholder(),
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : const _NoImagePlaceholder(),
      );
    }
    // Local file: decode from disk, no network.
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => const _NoImagePlaceholder(),
    );
  }
}

class _NoImagePlaceholder extends StatelessWidget {
  const _NoImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ColoredBox(
      color: cs.surfaceContainerLow,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_not_supported_outlined, size: 34, color: cs.onSurfaceVariant),
            const SizedBox(height: Ds.sp2),
            Text(
              context.tr('upload_image', 'Pakia picha'),
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pre-publish sanity list. Catching "no photo", "no price" or "out of stock"
/// here is far cheaper than a failed publish.
class _PreviewChecklist extends StatelessWidget {
  const _PreviewChecklist({required this.preview});
  final ProductPreviewSheet preview;

  @override
  Widget build(BuildContext context) {
    final items = <(bool, String, String)>[
      (
        preview.newImagePaths.isNotEmpty || preview.existingImageUrls.isNotEmpty,
        context.tr('at_least_one_photo', 'Kuna picha'),
        context.tr('at_least_one_photo_warn', 'Ongeza angalau picha moja'),
      ),
      (
        preview.price > 0,
        context.tr('price_set', 'Bei imewekwa'),
        context.tr('price_set_warn', 'Weka bei'),
      ),
      (
        preview.name.trim().length >= 3,
        context.tr('title_added', 'Jina limewekwa'),
        context.tr('title_added_warn', 'Weka jina la bidhaa'),
      ),
      (
        preview.stock > 0,
        context.tr('stock_available', 'Stock ipo'),
        context.tr('stock_available_warn', 'Stock ni 0 — hiiwezi kusaidia'),
      ),
      (
        preview.description.trim().length >= 10,
        context.tr('description_added', 'Maelezo yamapili'),
        context.tr('description_added_warn', 'Ongeza maelezo zaidi ya herufi 10'),
      ),
    ];

    final missing = items.where((i) => !i.$1).length;
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(Ds.sp3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(Ds.rMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                missing == 0 ? Icons.check_circle : Icons.info_outline,
                size: 16,
                color: missing == 0 ? cs.successGreen : cs.onSurfaceVariant,
              ),
              const SizedBox(width: Ds.sp2),
              Text(
                missing == 0
                    ? context.tr('ready_to_publish', 'Tayari kuchapisha')
                    : context.tr('before_publishing', 'Kabla ya kuchapisha'),
                style: AppTypography.monoLabel(cs.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: Ds.sp2),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    item.$1 ? Icons.check_rounded : Icons.remove_rounded,
                    size: 14,
                    color: item.$1 ? cs.successGreen : cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      item.$1 ? item.$2 : item.$3,
                      style: TextStyle(
                        fontSize: 12,
                        color: item.$1 ? cs.onSurfaceVariant : cs.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}


