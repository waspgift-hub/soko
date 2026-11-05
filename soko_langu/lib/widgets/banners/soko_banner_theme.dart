import 'package:flutter/material.dart';

import '../../theme/design_tokens.dart';

/// Shared visual primitives for Soko Vibe in-app banners (NOT AdMob).
class SokoBannerTheme {
  SokoBannerTheme._();

  static const double radius = 24;
  static const double minHeight = 168;
  static const double maxContentWidth = 920;

  static BorderRadius get borderRadius => BorderRadius.circular(radius);

  static EdgeInsets outerMargin(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final h = w >= 900 ? 20.0 : (w >= 600 ? 18.0 : 16.0);
    return EdgeInsets.fromLTRB(h, 4, h, 12);
  }

  static BoxDecoration surfaceDecoration(
    BuildContext context, {
    Gradient? gradient,
    Color? color,
    List<BoxShadow>? shadows,
  }) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;
    return BoxDecoration(
      color: color ?? cs.surfaceContainerLow,
      gradient: gradient,
      borderRadius: borderRadius,
      border: Border.all(
        color: cs.outlineVariant.withValues(alpha: isDark ? 0.22 : 0.45),
        width: 0.8,
      ),
      boxShadow:
          shadows ??
          [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.05),
              blurRadius: isDark ? 12 : 16,
              offset: const Offset(0, 4),
            ),
          ],
    );
  }

  static Widget badge(
    BuildContext context,
    String label, {
    IconData? icon,
    Color? background,
    Color? foreground,
  }) {
    final cs = Theme.of(context).colorScheme;
    final bg = background ?? cs.primary.withValues(alpha: 0.12);
    final fg = foreground ?? cs.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 13, color: fg), const SizedBox(width: 5)],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Ds.badge(
                fg,
              ).copyWith(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.2),
            ),
          ),
        ],
      ),
    );
  }

  static Widget ctaPill(BuildContext context, String label, {bool primary = true}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: primary ? cs.primary : cs.surface,
        borderRadius: BorderRadius.circular(999),
        border: primary ? null : Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Ds.bannerCta(
                primary ? cs.onPrimary : cs.onSurface,
              ).copyWith(fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.arrow_forward_rounded, size: 14, color: primary ? cs.onPrimary : cs.onSurface),
        ],
      ),
    );
  }
}

/// Constrains banner width on large screens while keeping mobile full-bleed.
class SokoBannerFrame extends StatelessWidget {
  const SokoBannerFrame({super.key, required this.child, this.margin});
  final Widget child;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin ?? SokoBannerTheme.outerMargin(context),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: SokoBannerTheme.maxContentWidth),
          child: child,
        ),
      ),
    );
  }
}
