import 'package:flutter/material.dart';
import '../../theme/app_dimens.dart';
import '../ds/ds.dart';

/// User profile header with avatar, name, location and optional edit action.
///
/// Used on the profile screen and public profile pages.
class ProfileHeader extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final String? location;
  final bool isVerified;
  final VoidCallback? onEdit;
  final VoidCallback? onAvatarTap;

  const ProfileHeader({
    super.key,
    required this.name,
    this.imageUrl,
    this.location,
    this.isVerified = false,
    this.onEdit,
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

    return Row(
      children: [
        GestureDetector(
          onTap: onAvatarTap,
          child: DsAvatar(
            imageUrl: imageUrl,
            initials: _initials(name),
            size: DsAvatarSize.md,
          ),
        ),
        const SizedBox(width: AppSpacing.s3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
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
                const SizedBox(height: 2),
                Text(
                  location!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: AppFontSize.sm, color: cs.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
        if (onEdit != null)
          DsButton(
            onPressed: onEdit,
            variant: DsButtonVariant.secondary,
            size: DsButtonSize.sm,
            fullWidth: false,
            icon: Icons.edit_outlined,
            label: 'Edit',
          ),
      ],
    );
  }
}