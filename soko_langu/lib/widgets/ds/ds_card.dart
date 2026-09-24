import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../theme/neumorphic.dart';
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
    // Raised surfaces sit flush with the panel base color so the dual
    // neumorphic shadows (white top-left, gray bottom-right) stay visible.
    final base = color ?? Neu.base(scheme.brightness);
    final depth = switch (elevation) {
      DsCardElevation.flat => 0.0,
      DsCardElevation.low => 3.0,
      DsCardElevation.medium => 6.0,
    };
    final elevated = onTap != null || depth > 0;

    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(radius),
        // Raised cards drop the hairline — a border would fight the extruded
        // shadow; only flat list surfaces keep an edge.
        border: depth > 0
            ? null
            : border ??
                Border.all(color: scheme.brandBorder, width: 0.5),
        boxShadow: elevated ? Neu.raised(depth, scheme.brightness) : null,
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
