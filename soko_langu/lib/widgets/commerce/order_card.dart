import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../extensions/context_tr.dart';
import '../../services/product_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../ds/ds.dart';

/// Order/purchase card for listing screens.
///
/// Shows image, title, seller, status badge, total, date and item count.
/// Compact by default; expands into a vertical layout on very wide screens.
class OrderCard extends StatelessWidget {
  final String productName;
  final String productImage;
  final String sellerName;
  final String status;
  final double total;
  final DateTime? date;
  final int itemCount;
  final VoidCallback? onTap;
  final VoidCallback? onReorder;
  final VoidCallback? onReview;
  final bool showReviewButton;

  const OrderCard({
    super.key,
    required this.productName,
    required this.productImage,
    required this.sellerName,
    required this.status,
    required this.total,
    this.date,
    this.itemCount = 1,
    this.onTap,
    this.onReorder,
    this.onReview,
    this.showReviewButton = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final statusColor = _statusColor(status, cs);

    Widget card = Container(
      padding: const EdgeInsets.all(AppSpacing.s3),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: SizedBox(
              width: 64,
              height: 64,
              child: productImage.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: getThumbnailUrl(productImage),
                      fit: BoxFit.cover,
                      memCacheWidth: 128,
                      memCacheHeight: 128,
                      placeholder: (_, _) => Container(color: cs.surfaceContainerHighest, child: const DsSkeleton()),
                      errorWidget: (_, _, _) => Container(
                        color: cs.surfaceContainerHighest,
                        child: Icon(Icons.receipt_outlined, size: 24, color: cs.onSurfaceVariant),
                      ),
                    )
                  : Container(
                      color: cs.surfaceContainerHighest,
                      child: Icon(Icons.receipt_outlined, size: 24, color: cs.onSurfaceVariant),
                    ),
            ),
          ),
          const SizedBox(width: AppSpacing.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  productName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppFontSize.md,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sellerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: AppFontSize.sm, color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: AppSpacing.s1),
                Row(
                  children: [
                    _statusBadge(context, cs, status, statusColor),
                    const Spacer(),
                    Text(
                      context.formatPrice(total),
                      style: TextStyle(
                        fontSize: AppFontSize.md,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _dateString(context),
                  style: TextStyle(fontSize: AppFontSize.xs, color: cs.onSurfaceVariant),
                ),
                if (itemCount > 1) ...[
                  const SizedBox(height: 2),
                  Text(
                    '$itemCount items',
                    style: TextStyle(fontSize: AppFontSize.xs, color: cs.onSurfaceVariant),
                  ),
                ],
                if (showReviewButton || onReorder != null) ...[
                  const SizedBox(height: AppSpacing.s2),
                  Row(
                    children: [
                      if (onReorder != null)
                        DsButton(
                          onPressed: onReorder,
                          variant: DsButtonVariant.tonal,
                          size: DsButtonSize.sm,
                          fullWidth: false,
                          label: 'Reorder',
                          icon: Icons.replay_rounded,
                        ),
                      if (onReview != null && showReviewButton) ...[
                        const SizedBox(width: AppSpacing.s2),
                        DsButton(
                          onPressed: onReview,
                          variant: DsButtonVariant.secondary,
                          size: DsButtonSize.sm,
                          fullWidth: false,
                          label: 'Review',
                          icon: Icons.star_outline_rounded,
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    if (onTap != null) {
      card = AnimatedPress(onTap: onTap!, child: card);
    }

    return Semantics(
      button: onTap != null,
      label: '$productName, $status, ${context.formatPrice(total)}',
      child: card,
    );
  }

  String _dateString(BuildContext context) {
    if (date == null) return '';
    return '${date!.day}/${date!.month}/${date!.year}';
  }

  Widget _statusBadge(BuildContext context, ColorScheme cs, String status, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Color _statusColor(String status, ColorScheme cs) {
    final lower = status.toLowerCase();
    if (lower.contains('delivered') || lower.contains('completed')) return cs.successGreen;
    if (lower.contains('cancelled') || lower.contains('failed') || lower.contains('refunded')) return cs.error;
    if (lower.contains('pending') || lower.contains('processing')) return cs.primary;
    if (lower.contains('shipped') || lower.contains('transit')) return Colors.teal;
    return cs.onSurfaceVariant;
  }
}