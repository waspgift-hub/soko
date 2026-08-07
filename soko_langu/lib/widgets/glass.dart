import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Unified glassmorphism toolkit for Soko Vibe.
///
/// All surfaces share a single backing implementation ([_GlassSurface]) so
/// blur, tint, border, highlight and shadow stay consistent across screens.
/// The [Glass] namespace offers the raw primitive ([Glass.box]) while
/// [GlassCard], [GlassButton] and [GlassChip] are ready-made composites.
class Glass {
  static const double defaultRadius = 16;
  static const double defaultBlur = 12;

  /// Builds a frosted-glass box around [child].
  ///
  /// [tint] defaults to the theme glass tint so dark/light mode is handled
  /// automatically. [highlight] is drawn over the glass (used by [GlassCard]
  /// for its sheen); pass a custom widget to override it.
  static Widget box({
    required Widget child,
    double blur = defaultBlur,
    double radius = defaultRadius,
    double opacity = 0.55,
    EdgeInsetsGeometry? padding,
    EdgeInsetsGeometry? margin,
    Color? tint,
    Widget? highlight,
  }) {
    return _GlassSurface(
      blur: blur,
      radius: radius,
      opacity: opacity,
      padding: padding,
      margin: margin,
      tint: tint,
      highlight: highlight,
      child: child,
    );
  }
}

/// A frosted-glass card: [Glass.box] with default padding, a corner sheen and
/// a soft shadow. The light, content-focused container for list tiles, stats
/// and form sections.
class GlassCard extends StatelessWidget {
  final Widget child;
  final double radius;
  final double blur;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final Color? tint;
  final VoidCallback? onTap;

  const GlassCard({
    super.key,
    required this.child,
    this.radius = Glass.defaultRadius,
    this.blur = Glass.defaultBlur,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.tint,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = Glass.box(
      blur: blur,
      radius: radius,
      padding: padding,
      margin: margin,
      tint: tint,
      child: child,
    );
    if (onTap == null) return card;
    return _GlassPressable(radius: radius, onTap: onTap!, child: card);
  }
}

/// A glass action button. Uses [Material] + [InkWell] so ripples stay visible
/// over the frosted surface; [onPressed] being null renders a disabled state.
class GlassButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String? label;
  final IconData? icon;
  final Widget? child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final bool emphasized;

  const GlassButton({
    super.key,
    this.onPressed,
    this.label,
    this.icon,
    this.child,
    this.radius = 14,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    this.emphasized = false,
  }) : assert(child != null || label != null, 'child or label required');

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final content = child ??
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 20,
                color: emphasized ? cs.onPrimary : cs.onSurface,
              ),
              const SizedBox(width: 8),
            ],
            Text(
              label!,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: emphasized ? cs.onPrimary : cs.onSurface,
              ),
            ),
          ],
        );

    final glass = Glass.box(
      radius: radius,
      padding: padding,
      tint: emphasized ? cs.primary.withValues(alpha: 0.85) : null,
      opacity: emphasized ? 0.9 : 0.6,
      child: content,
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onPressed,
        child: Opacity(
          opacity: onPressed == null ? 0.45 : 1,
          child: glass,
        ),
      ),
    );
  }
}

/// A compact pill-shaped glass tag for filters, categories and status labels.
class GlassChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;

  const GlassChip({
    super.key,
    required this.label,
    this.icon,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(
            icon,
            size: 16,
            color: selected ? cs.onPrimary : cs.onSurface.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 6),
        ],
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? cs.onPrimary : cs.onSurface.withValues(alpha: 0.8),
          ),
        ),
      ],
    );

    final chip = Glass.box(
      radius: 999,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      tint: selected ? cs.primary.withValues(alpha: 0.7) : null,
      opacity: selected ? 0.9 : 0.5,
      child: content,
    );

    if (onTap == null) return chip;
    return _GlassPressable(radius: 999, onTap: onTap!, child: chip);
  }
}

/// Shared frosted-glass surface.
///
/// Uses a [ClipRRect] + [BackdropFilter] so the tint and blur follow rounded
/// corners, then overlays a translucent border and the default corner sheen.
class _GlassSurface extends StatelessWidget {
  final Widget child;
  final double blur;
  final double radius;
  final double opacity;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? tint;
  final Widget? highlight;

  const _GlassSurface({
    required this.child,
    required this.blur,
    required this.radius,
    required this.opacity,
    this.padding,
    this.margin,
    this.tint,
    this.highlight,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = tint ?? cs.glassBg;

    final surface = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: base.withValues(alpha: opacity),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: cs.glassBorder.withValues(alpha: isDark ? 0.6 : 0.7),
              width: 0.6,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.05),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Stack(
            children: [
              ?highlight,
              child,
            ],
          ),
        ),
      ),
    );

    if (margin == null) return surface;
    return Padding(padding: margin!, child: surface);
  }
}

/// Wraps a glass surface so taps keep the ripple clipped to its rounded shape.
class _GlassPressable extends StatelessWidget {
  final double radius;
  final VoidCallback onTap;
  final Widget child;

  const _GlassPressable({
    required this.radius,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onTap,
        child: child,
      ),
    );
  }
}
