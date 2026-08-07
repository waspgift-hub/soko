import 'package:flutter/material.dart';
import '../soko_vibe_loading.dart';
import 'animated_press.dart';

enum DsButtonVariant { primary, secondary, tonal, ghost, danger }

/// Design-system button (spec §4.1).
///
/// Primary CTAs are full-width and 52dp tall by default; loading swaps the
/// label for an 18dp spinner while preserving width.
class DsButton extends StatelessWidget {
  final DsButtonVariant variant;
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;
  final bool fullWidth;
  final double height;
  final EdgeInsetsGeometry padding;

  const DsButton({
    super.key,
    required this.label,
    this.variant = DsButtonVariant.primary,
    this.onPressed,
    this.loading = false,
    this.icon,
    this.fullWidth = true,
    this.height = 52,
    this.padding = const EdgeInsets.symmetric(horizontal: 24),
  });

  bool get _enabled => onPressed != null && !loading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final disabled = !_enabled;

    final (Color fill, Color fg, BorderSide side) = switch (variant) {
      DsButtonVariant.primary => (
          scheme.primary,
          scheme.onPrimary,
          BorderSide.none
        ),
      DsButtonVariant.secondary => (
          Colors.transparent,
          scheme.primary,
          BorderSide(color: scheme.primary, width: 1.5)
        ),
      DsButtonVariant.tonal => (
          scheme.primary.withValues(alpha: 0.12),
          scheme.primary,
          BorderSide.none
        ),
      DsButtonVariant.ghost => (
          Colors.transparent,
          scheme.primary,
          BorderSide.none
        ),
      DsButtonVariant.danger => (scheme.error, scheme.onError, BorderSide.none),
    };

    final labelStyle = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.1,
      color: disabled ? fg.withValues(alpha: 0.38) : fg,
    );

    final child = SizedBox(
      height: height,
      width: fullWidth ? double.infinity : null,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: disabled ? fill.withValues(alpha: 0.38) : fill,
          borderRadius: BorderRadius.circular(16),
          border: side == BorderSide.none
              ? null
              : Border.fromBorderSide(side),
        ),
        child: Padding(
          padding: padding,
          child: Row(
            mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (loading)
                SokoVibeThreeDotLoader(
                  size: 18,
                  dotSize: 4.5,
                  color: fg,
                )
              else ...[
                if (icon != null) ...[
                  Icon(icon, size: 20, color: labelStyle.color),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    label,
                    style: labelStyle,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    return AnimatedPress(
      enabled: _enabled,
      onTap: onPressed,
      child: child,
    );
  }
}
