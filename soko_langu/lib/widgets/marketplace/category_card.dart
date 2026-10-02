import 'package:flutter/material.dart';
import '../../theme/app_dimens.dart';
import '../ds/ds.dart';
import 'category_image.dart';

/// Category card with image-first artwork and icon fallback.
///
/// Shows a square photo tile with centered label underneath. Used by the home
/// screen strip; the category explorer has its own larger tiles. Artwork is
/// resolved by [categoryId] against the installed artwork pack.
class CategoryCard extends StatelessWidget {
  final String name;

  /// Stable taxonomy id, used to look up downloaded artwork.
  final String? categoryId;

  final String? imageUrl;
  final IconData icon;
  final VoidCallback onTap;

  const CategoryCard({
    super.key,
    required this.name,
    this.categoryId,
    this.imageUrl,
    this.icon = Icons.category_rounded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Semantics(
      button: true,
      label: name,
      child: AnimatedPress(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
              ),
              clipBehavior: Clip.antiAlias,
              child: CategoryImage(
                imageUrl: imageUrl,
                categoryId: categoryId,
                fallback: icon,
                memCacheSize: 128,
              ),
            ),
            const SizedBox(height: AppSpacing.s2),
            Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppFontSize.sm,
                fontWeight: FontWeight.w500,
                color: cs.onSurface,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
