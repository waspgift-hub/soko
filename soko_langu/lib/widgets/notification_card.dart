import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/notification_item.dart';
import '../theme/app_dimens.dart';
import 'ds/ds.dart';

/// Notification list card with icon, title, body, relative time and unread dot.
class NotificationCard extends StatelessWidget {
  final NotificationItem item;
  final VoidCallback onTap;

  const NotificationCard({
    super.key,
    required this.item,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final icon = _iconForType(item.type);

    return AnimatedPress(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.s3),
        decoration: BoxDecoration(
          color: item.isRead ? cs.surface : cs.primary.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: item.isRead
                ? cs.outlineVariant.withValues(alpha: 0.5)
                : cs.primary.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.productImage != null && item.productImage!.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: CachedNetworkImage(
                    imageUrl: item.productImage!,
                    fit: BoxFit.cover,
                    memCacheWidth: 96,
                    memCacheHeight: 96,
                    placeholder: (_, _) =>
                        Container(color: cs.surfaceContainerHighest, child: const DsSkeleton()),
                    errorWidget: (_, _, _) => _iconTile(context, cs, icon),
                  ),
                ),
              )
            else if (item.otherUserImage != null && item.otherUserImage!.isNotEmpty)
              CircleAvatar(
                radius: 24,
                backgroundColor: cs.surfaceContainerHighest,
                backgroundImage: CachedNetworkImageProvider(item.otherUserImage!),
              )
            else
              _iconTile(context, cs, icon),
            const SizedBox(width: AppSpacing.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppFontSize.md,
                            fontWeight: item.isRead ? FontWeight.w500 : FontWeight.w700,
                            color: cs.onSurface,
                            height: 1.2,
                          ),
                        ),
                      ),
                      if (!item.isRead)
                        Container(
                          margin: const EdgeInsets.only(left: AppSpacing.s2, top: 4),
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: cs.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  if (item.body.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: AppFontSize.sm, color: cs.onSurfaceVariant, height: 1.3),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.s2),
                  Text(
                    _relativeTime(item.timestamp),
                    style: TextStyle(fontSize: AppFontSize.xs, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconTile(BuildContext context, ColorScheme cs, IconData icon) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Icon(icon, size: 22, color: cs.onSurfaceVariant),
    );
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'order':
        return Icons.receipt_long_outlined;
      case 'message':
        return Icons.chat_outlined;
      case 'review':
        return Icons.rate_review_outlined;
      case 'payment':
        return Icons.payments_outlined;
      case 'promo':
        return Icons.local_offer_outlined;
      case 'follow':
        return Icons.person_add_alt_1_outlined;
      default:
        return Icons.notifications_outlined;
    }
  }

  String _relativeTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inDays >= 1) return '${diff.inDays}d';
    if (diff.inHours >= 1) return '${diff.inHours}h';
    if (diff.inMinutes >= 1) return '${diff.inMinutes}m';
    return 'now';
  }
}