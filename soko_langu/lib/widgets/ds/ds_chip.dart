import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import 'animated_press.dart';

enum DsChipSize { sm, md }

class DsChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool filled;
  final DsChipSize chipSize;

  const DsChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.icon,
    this.filled = true,
    this.chipSize = DsChipSize.md,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = filled
        ? (selected ? scheme.primary : scheme.cardBase)
        : Colors.transparent;
    final fg = filled
        ? (selected ? scheme.onPrimary : scheme.brandTextSecondary)
        : scheme.primary;
    final border = selected && !filled
        ? Border.all(color: scheme.primary, width: 1.5)
        : Border.all(color: scheme.brandBorder, width: 0.5);

    final verticalPad = chipSize == DsChipSize.sm ? 6.0 : 10.0;
    final fontSize = chipSize == DsChipSize.sm ? 12.0 : 14.0;
    final iconSize = chipSize == DsChipSize.sm ? 14.0 : 16.0;
    final gap = chipSize == DsChipSize.sm ? 3.0 : 4.0;

    final chip = Container(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.s4,
        vertical: verticalPad,
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
            Icon(icon, size: iconSize, color: fg),
            SizedBox(width: gap),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: fg,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return Semantics(label: label, child: chip);
    return Semantics(
      button: true,
      selected: selected,
      label: '$label${selected ? ' (selected)' : ''}',
      child: AnimatedPress(onTap: onTap, child: chip),
    );
  }
}
