import 'package:flutter/material.dart';
import '../../theme/app_dimens.dart';
import '../ds/ds.dart';
import 'category_image.dart';

/// Category card with image-first artwork and icon fallback.
///
/// Shows a square photo tile with centered label underneath. Used in the
/// home grid and category screens.
class CategoryCard extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final IconData icon;
  final VoidCallback onTap;

  const CategoryCard({
    super.key,
    required this.name,
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
