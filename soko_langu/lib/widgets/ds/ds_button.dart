import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../soko_vibe_loading.dart';
import 'animated_press.dart';

enum DsButtonVariant { primary, secondary, tonal, ghost, danger }

enum DsButtonSize { sm, md, lg }

/// Design-system button (spec §4.1).
///
/// Primary CTAs are full-width and 52dp tall by default; loading swaps the
/// label for an 18dp spinner while preserving width. Haptic feedback fires
/// on every tap to give physical confirmation without visual overhead.
class DsButton extends StatelessWidget {
  final DsButtonVariant variant;
  final DsButtonSize size;
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;
  final bool fullWidth;
  final double? height;
  final EdgeInsetsGeometry padding;

  const DsButton({
    super.key,
    required this.label,
    this.variant = DsButtonVariant.primary,
    this.size = DsButtonSize.md,
    this.onPressed,
    this.loading = false,
    this.icon,
    this.fullWidth = true,
    this.height,
    this.padding = const EdgeInsets.symmetric(horizontal: 24),
  });

  bool get _enabled => onPressed != null && !loading;

  double get _resolvedHeight => height ?? switch (size) {
    DsButtonSize.sm => 40,
    DsButtonSize.md => 52,
    DsButtonSize.lg => 56,
  };

  double get _fontSize => switch (size) {
    DsButtonSize.sm => 13,
    DsButtonSize.md => 14,
    DsButtonSize.lg => 16,
  };

  double get _iconSize => switch (size) {
    DsButtonSize.sm => 16,
    DsButtonSize.md => 20,
    DsButtonSize.lg => 22,
  };

  double get _radius => switch (size) {
    DsButtonSize.sm => 12,
    DsButtonSize.md => 16,
    DsButtonSize.lg => 18,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final disabled = !_enabled;

    final (Color fill, Color fg, BorderSide side) = switch (variant) {
      DsButtonVariant.primary => (
          scheme.primary,
          scheme.onPrimary,
          BorderSide.none,
        ),
      DsButtonVariant.secondary => (
          Colors.transparent,
          scheme.primary,
          BorderSide(color: scheme.primary, width: 1.5),
        ),
      DsButtonVariant.tonal => (
          scheme.primary.withValues(alpha: 0.12),
          scheme.primary,
          BorderSide.none,
        ),
      DsButtonVariant.ghost => (
          Colors.transparent,
          scheme.primary,
          BorderSide.none,
        ),
      DsButtonVariant.danger => (scheme.error, scheme.onError, BorderSide.none),
    };

    final labelStyle = TextStyle(
      fontSize: _fontSize,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.1,
      color: disabled ? fg.withValues(alpha: 0.38) : fg,
    );

    final child = SizedBox(
      height: _resolvedHeight,
      width: fullWidth ? double.infinity : null,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: disabled ? fill.withValues(alpha: 0.38) : fill,
          borderRadius: BorderRadius.circular(_radius),
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
                  size: _iconSize,
                  dotSize: _iconSize * 0.25,
                  color: fg,
                )
              else ...[
                if (icon != null) ...[
                  Icon(icon, size: _iconSize, color: labelStyle.color),
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
      onTap: () {
        HapticFeedback.selectionClick();
        onPressed?.call();
      },
      child: child,
    );
  }
}
