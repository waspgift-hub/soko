import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../theme/surface_policy.dart';
import 'animated_press.dart';

enum DsChipSize { sm, md }

/// Design-system filter chip.
///
/// FLAT by default: an unselected chip is a `chip` role and rests on the canvas
/// with a hairline edge. Only the *selected* chip takes the soft-UI treatment
/// (`activeFilter`), where the brand-green fill is the "pressed in" active
/// state. That is deliberate — a recessed well on every chip would put soft-UI
/// on the majority of chips and swamp the flat/soft ratio on filter-heavy
/// screens such as search and category products.
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
    final fg = filled
        ? (selected ? scheme.onPrimary : scheme.brandTextSecondary)
        : scheme.primary;

    final decoration = filled
        ? (selected
            // Soft-UI: the one accent on the chip.
            ? SurfacePolicy.decorate(
                SurfaceRole.activeFilter,
                scheme.brightness,
                radius: AppRadius2.xl,
                fill: scheme.primary,
              )
            : SurfacePolicy.decorate(
                SurfaceRole.chip,
                scheme.brightness,
                radius: AppRadius2.xl,
                fill: scheme.surfaceContainer,
              ))
        : BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius2.xl),
            border: Border.all(
              color: selected ? scheme.primary : scheme.brandBorder,
              width: selected ? 1.5 : 0.5,
            ),
          );

    final verticalPad = chipSize == DsChipSize.sm ? 6.0 : 10.0;
    final fontSize = chipSize == DsChipSize.sm ? 12.0 : 14.0;
    final iconSize = chipSize == DsChipSize.sm ? 14.0 : 16.0;
    final gap = chipSize == DsChipSize.sm ? 3.0 : 4.0;

    final chip = Container(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.s4,
        vertical: verticalPad,
      ),
      decoration: decoration,
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
