import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import 'animated_press.dart';

/// Design-system surface card (spec §4.3) with optional press feedback.
class DsCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final Color? color;
  final double radius;
  final EdgeInsetsGeometry padding;
  final BoxBorder? border;

  const DsCard({
    super.key,
    required this.child,
    this.onTap,
    this.color,
    this.radius = AppRadius.lg,
    this.padding = const EdgeInsets.all(AppSpacing.s4),
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final elevated = onTap != null;

    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? scheme.cardBase,
        borderRadius: BorderRadius.circular(radius),
        border: border ??
            Border.all(color: scheme.brandBorder, width: 0.5),
        boxShadow: elevated
            ? [
                BoxShadow(
                  color: scheme.brandTextPrimary.withValues(alpha: 0.10),
                  blurRadius: 12,
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
