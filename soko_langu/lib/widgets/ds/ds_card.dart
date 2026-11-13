import 'package:flutter/material.dart';
import '../../theme/app_dimens.dart';
import '../../theme/neumorphic.dart';
import '../../theme/surface_policy.dart';
import 'animated_press.dart';

enum DsCardElevation { flat, low, medium }

/// Design-system content card (spec §4.3) with optional press feedback.
///
/// [DsCardElevation.flat] is the default and the only one that should reach
/// general content: `card` is a flat role under [SurfacePolicy], so a card
/// rests on the canvas behind a hairline edge. `low` and `medium` opt into the
/// soft-UI raised treatment and are reserved for the few hero surfaces per
/// screen — spending them on every list item would erase the flat/soft ratio.
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
    final depth = switch (elevation) {
      DsCardElevation.flat => 0.0,
      DsCardElevation.low => 3.0,
      DsCardElevation.medium => 6.0,
    };

    final card = DecoratedBox(
      decoration: depth > 0
          // Opted into soft-UI: extruded off the canvas with a dual shadow and
          // no hairline, which would fight the highlight edge.
          ? BoxDecoration(
              color: color ?? scheme.surface,
              borderRadius: BorderRadius.circular(radius),
              boxShadow: Neu.raised(depth, scheme.brightness),
            )
          : SurfacePolicy.decorate(
              SurfaceRole.card,
              scheme.brightness,
              radius: radius,
              fill: color,
              border: border,
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
