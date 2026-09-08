import 'package:flutter/material.dart';
import '../../theme/app_dimens.dart';
import '../ds/ds.dart';

/// Settings/profile menu row with icon, label, optional value and chevron.
class ProfileMenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;
  final VoidCallback? onTap;
  final Color? iconColor;

  const ProfileMenuTile({
    super.key,
    required this.icon,
    required this.label,
    this.value,
    this.onTap,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AnimatedPress(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4, vertical: AppSpacing.s3),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: iconColor ?? cs.onSurfaceVariant),
            const SizedBox(width: AppSpacing.s3),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: AppFontSize.md, color: cs.onSurface),
              ),
            ),
            if (value != null) ...[
              Text(
                value!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: AppFontSize.sm, color: cs.onSurfaceVariant),
              ),
              const SizedBox(width: AppSpacing.s2),
            ],
            Icon(Icons.chevron_right_rounded, size: 20, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}