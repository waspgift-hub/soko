import 'package:flutter/material.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_typography.dart';

/// Design-system pill badge (spec §4.5) — JetBrains label on a colored fill.
class DsBadge extends StatelessWidget {
  final String label;
  final Color color;
  final Color? textColor;
  final IconData? icon;

  const DsBadge({
    super.key,
    required this.label,
    required this.color,
    this.textColor,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final fg = textColor ?? Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s2,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
          ],
          Text(label, style: AppTypography.statusChip(fg)),
        ],
      ),
    );
  }
}
