import 'package:flutter/material.dart';
import '../../theme/app_dimens.dart';
import '../ds/ds.dart';

/// Seller-specific profile header with storefront badge, rating and follow/chat
/// action buttons.
class SellerProfileHeader extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final String? location;
  final double rating;
  final int reviewCount;
  final bool isVerified;
  final bool isFollowing;
  final VoidCallback? onFollow;
  final VoidCallback? onChat;
  final VoidCallback? onAvatarTap;

  const SellerProfileHeader({
    super.key,
    required this.name,
    this.imageUrl,
    this.location,
    this.rating = 0,
    this.reviewCount = 0,
    this.isVerified = false,
    this.isFollowing = false,
    this.onFollow,
    this.onChat,
    this.onAvatarTap,
  });

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return '?';
    final first = parts[0][0].toUpperCase();
    final last = parts.length > 1 ? parts.last[0].toUpperCase() : '';
    return first + last;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      children: [
        GestureDetector(
          onTap: onAvatarTap,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              DsAvatar(
                imageUrl: imageUrl,
                initials: _initials(name),
                size: DsAvatarSize.lg,
              ),
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: cs.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: cs.surface, width: 2),
                  ),
                  child: const Icon(Icons.storefront, size: 14, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s3),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppFontSize.xl,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
            ),
            if (isVerified) ...[
              const SizedBox(width: 4),
              DsVerifiedCheck(),
            ],
          ],
        ),
        if (location != null && location!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.location_on_outlined, size: 14, color: cs.onSurfaceVariant),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  location!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: AppFontSize.sm, color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ],
        if (rating > 0) ...[
          const SizedBox(height: AppSpacing.s2),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.star_rounded, size: 18, color: cs.primary),
              const SizedBox(width: 4),
              Text(
                rating.toStringAsFixed(1),
                style: TextStyle(
                  fontSize: AppFontSize.md,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
              if (reviewCount > 0) ...[
                const SizedBox(width: 4),
                Text(
                  '($reviewCount)',
                  style: TextStyle(fontSize: AppFontSize.sm, color: cs.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.s4),
        Row(
          children: [
            if (onFollow != null)
              Expanded(
                child: DsButton(
                  onPressed: onFollow,
                  variant: isFollowing ? DsButtonVariant.secondary : DsButtonVariant.primary,
                  size: DsButtonSize.md,
                  fullWidth: true,
                  label: isFollowing ? 'Following' : 'Follow',
                  icon: isFollowing
                      ? Icons.person_remove_outlined
                      : Icons.person_add_outlined,
                ),
              ),
            if (onFollow != null && onChat != null)
              const SizedBox(width: AppSpacing.s3),
            if (onChat != null)
              Expanded(
                child: DsButton(
                  onPressed: onChat,
                  variant: DsButtonVariant.tonal,
                  size: DsButtonSize.md,
                  fullWidth: true,
                  label: 'Chat',
                  icon: Icons.chat_outlined,
                ),
              ),
          ],
        ),
      ],
    );
  }
}