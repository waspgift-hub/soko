import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../extensions/context_tr.dart';
import '../../models/cart_item.dart';
import '../../services/product_service.dart';
import '../../theme/app_dimens.dart';
import '../ds/ds.dart';

/// Single cart line item with image, name, variant, quantity and price.
///
/// Delete via long-press or explicit delete action — the row is swipe-safe
/// thanks to [AnimatedSwitcher] on the trailing widget.
class CartItemTile extends StatelessWidget {
  final CartItem item;
  final ValueChanged<int> onQuantityChanged;
  final VoidCallback? onDelete;
  final bool enabled;

  const CartItemTile({
    super.key,
    required this.item,
    required this.onQuantityChanged,
    this.onDelete,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final maxQty = item.stock > 0 ? item.stock : 999999;

    return LayoutBuilder(
      builder: (context, constraints) {
        final tight = constraints.maxWidth < 300;

        return Container(
          padding: const EdgeInsets.all(AppSpacing.s3),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: SizedBox(
                  width: tight ? 56 : 72,
                  height: tight ? 56 : 72,
                  child: item.productImage.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: getThumbnailUrl(item.productImage),
                          fit: BoxFit.cover,
                          memCacheWidth: 144,
                          memCacheHeight: 144,
                          placeholder: (_, _) => Container(color: cs.surfaceContainerHighest, child: const DsSkeleton()),
                          errorWidget: (_, _, _) => Container(
                            color: cs.surfaceContainerHighest,
                            child: Icon(Icons.image_outlined, size: 24, color: cs.onSurfaceVariant),
                          ),
                        )
                      : Container(
                          color: cs.surfaceContainerHighest,
                          child: Icon(Icons.image_outlined, size: 24, color: cs.onSurfaceVariant),
                        ),
                ),
              ),
              SizedBox(width: tight ? AppSpacing.s2 : AppSpacing.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.productName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppFontSize.md,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                        height: 1.2,
                      ),
                    ),
                    if (item.variantId != null && item.variantId!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        item.variantId!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: AppFontSize.sm, color: cs.onSurfaceVariant),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.s2),
                    if (tight)
                      _compactRow(context, cs)
                    else
                      Row(
                        children: [
                        DsQuantitySelector(
                          value: item.quantity,
                          onChanged: enabled ? onQuantityChanged : (_) {},
                          min: 1,
max: maxQty,
                        ),
                          const Spacer(),
                          Text(
                            context.formatPrice(item.lineTotal),
                            style: TextStyle(
                              fontSize: AppFontSize.lg,
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              if (onDelete != null)
                IconButton(
                  onPressed: enabled ? onDelete : null,
                  icon: Icon(Icons.delete_outline_rounded, size: 20, color: cs.error),
                  tooltip: 'Remove',
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _compactRow(BuildContext context, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              context.formatPrice(item.unitPrice),
              style: TextStyle(fontSize: AppFontSize.sm, color: cs.onSurfaceVariant),
            ),
            const SizedBox(width: 4),
            Text(
              '\u00D7${item.quantity}',
              style: TextStyle(fontSize: AppFontSize.sm, color: cs.onSurfaceVariant),
            ),
            const Spacer(),
            Text(
              context.formatPrice(item.lineTotal),
              style: TextStyle(fontSize: AppFontSize.lg, fontWeight: FontWeight.w700, color: cs.onSurface),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s2),
        DsQuantitySelector(
          value: item.quantity,
          onChanged: enabled ? onQuantityChanged : (_) {},
          min: 1,
          max: item.stock,
        ),
      ],
    );
  }
}