import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../theme/app_dimens.dart';
import '../ds/ds.dart';

/// Category card with optional image or icon.
///
/// Shows a square tile with image/background and centered label underneath.
/// Used in the home grid and category screens.
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
              child: imageUrl != null && imageUrl!.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: imageUrl!,
                      fit: BoxFit.cover,
                      memCacheWidth: 128,
                      memCacheHeight: 128,
                      placeholder: (_, _) => Icon(icon, size: 28, color: cs.onSurfaceVariant),
                      errorWidget: (_, _, _) => Icon(icon, size: 28, color: cs.onSurfaceVariant),
                    )
                  : Icon(icon, size: 28, color: cs.onSurfaceVariant),
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
