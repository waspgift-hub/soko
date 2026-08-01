import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
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
          scheme.brandPrimary,
          Colors.white,
          BorderSide.none
        ),
      DsButtonVariant.secondary => (
          Colors.transparent,
          scheme.brandPrimary,
          BorderSide(color: scheme.brandPrimary, width: 1.5)
        ),
      DsButtonVariant.tonal => (
          scheme.brandPrimary.withValues(alpha: 0.12),
          scheme.brandPrimary,
          BorderSide.none
        ),
      DsButtonVariant.ghost => (
          Colors.transparent,
          scheme.brandPrimary,
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
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: fg,
                  ),
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
