import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import 'animated_press.dart';

/// Design-system selectable pill chip (spec §4.2 SegmentedTabs).
///
/// Selected state fills with brand primary; label and icon inherit contrast.
class DsChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool filled;

  const DsChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.icon,
    this.filled = true,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = filled
        ? (selected ? scheme.brandPrimary : scheme.cardBase)
        : Colors.transparent;
    final fg = filled
        ? (selected ? Colors.white : scheme.brandTextSecondary)
        : scheme.brandPrimary;
    final border = selected && !filled
        ? Border.all(color: scheme.brandPrimary, width: 1.5)
        : Border.all(color: scheme.brandBorder, width: 0.5);

    final chip = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s4,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius2.xl),
        border: border,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: AppSpacing.s1),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: fg,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return chip;
    return AnimatedPress(onTap: onTap, child: chip);
  }
}
