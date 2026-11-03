import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import 'animated_press.dart';

enum DsCardElevation { flat, low, medium }

/// Design-system surface card (spec §4.3) with optional press feedback.
///
/// Three elevation levels cover every layout need:
/// - `flat` — list items, inline groups (shadowless, border only)
/// - `low` — tappable cards that need depth hint
/// - `medium` — featured content, hero cards
class DsCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final Color? color;
  final double radius;
  final EdgeInsetsGeometry padding;
  final BoxBorder? border;
  final DsCardElevation elevation;

  const DsCard({
    super.key,
    required this.child,
    this.onTap,
    this.color,
    this.radius = AppRadius.lg,
    this.padding = const EdgeInsets.all(AppSpacing.s4),
    this.border,
    this.elevation = DsCardElevation.flat,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final elevated = onTap != null || elevation != DsCardElevation.flat;

    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? scheme.cardBase,
        borderRadius: BorderRadius.circular(radius),
        border: border ??
            Border.all(color: scheme.brandBorder, width: 0.5),
        boxShadow: elevated
            ? [
                BoxShadow(
                  color: scheme.brandTextPrimary.withValues(
                    alpha: switch (elevation) {
                      DsCardElevation.flat => 0,
                      DsCardElevation.low => isDark ? 0.08 : 0.06,
                      DsCardElevation.medium => isDark ? 0.15 : 0.10,
                    },
                  ),
                  blurRadius: switch (elevation) {
                    DsCardElevation.flat => 0,
                    DsCardElevation.low => 8,
                    DsCardElevation.medium => 20,
                  },
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Padding(padding: padding, child: child),
    );

    if (onTap == null) return card;
    return AnimatedPress(
      onTap: onTap,
      pressedScale: 0.98,
      child: card,
    );
  }
}
