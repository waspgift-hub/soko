import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_dimens.dart';
import 'app_motion.dart';
import 'app_typography.dart';

/// Unified design-token facade — the single import screens need to build
/// any UI with consistent primitives.  Delegates to the existing token
/// files (`app_colors`, `app_dimens`, `app_motion`, `app_typography`)
/// so the codebase migrates incrementally without a flag-day rewrite.
class Ds {
  Ds._();

  // ── Color semantics ──────────────────────────────────────────────────────
  static Color surface(BuildContext ctx) =>
      Theme.of(ctx).colorScheme.surface;
  static Color onSurface(BuildContext ctx) =>
      Theme.of(ctx).colorScheme.onSurface;
  static Color primary(BuildContext ctx) =>
      Theme.of(ctx).colorScheme.primary;
  static Color error(BuildContext ctx) =>
      Theme.of(ctx).colorScheme.error;
  static Color outline(BuildContext ctx) =>
      Theme.of(ctx).colorScheme.outlineVariant;

  /// Safe scaffold background — pure black (dark) / white (light).
  static Color scaffoldBg(BuildContext ctx) =>
      Theme.of(ctx).brightness == Brightness.dark
          ? Colors.black
          : Colors.white;

  // ── Spacing (4px grid) ───────────────────────────────────────────────────
  static const double sp1 = AppSpacing.s1;
  static const double sp2 = AppSpacing.s2;
  static const double sp3 = AppSpacing.s3;
  static const double sp4 = AppSpacing.s4;
  static const double sp5 = AppSpacing.s5;
  static const double sp6 = AppSpacing.s6;
  static const double sp7 = AppSpacing.s7;
  static const double sp8 = AppSpacing.s8;
  static const double sp9 = AppSpacing.s9;
  static const double sp10 = AppSpacing.s10;

  // ── Radius ───────────────────────────────────────────────────────────────
  static const double rSm = AppRadius.sm;
  static const double rMd = AppRadius.md;
  static const double rLg = AppRadius.lg;
  static const double rXl = AppRadius.xl;
  static const double rFull = AppRadius.full;

  // ── Motion ───────────────────────────────────────────────────────────────
  static Duration get durFast => Motion.ripple;
  static Duration get durMed => Motion.cardEnter;
  static Duration get durSlow => Motion.sheet;
  static Curve get curve => Motion.easeOutCubic;

  // ── Typography (context-free) ────────────────────────────────────────────
  static TextStyle displayLg(Color c) => AppTypography.brandTitle(c);
  static TextStyle headingMd(Color c) => AppTypography.screenTitle(c);
  static TextStyle bodyLg(Color c) => AppTypography.appBarTitle(c);
  static TextStyle bodyMd(Color c) => AppTypography.statusChip(c);
  static TextStyle labelMd(Color c) => AppTypography.monoLabel(c);
  static TextStyle amount(Color c) => AppTypography.amount(c);

  // ── Haptics ──────────────────────────────────────────────────────────────
  static void tap() => HapticFeedback.selectionClick();
  static void light() => HapticFeedback.lightImpact();
  static void medium() => HapticFeedback.mediumImpact();
  static void heavy() => HapticFeedback.heavyImpact();

  // ── Shadows ──────────────────────────────────────────────────────────────
  static List<BoxShadow> shadowSm(BuildContext ctx) {
    final isDark = Theme.of(ctx).brightness == Brightness.dark;
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
        blurRadius: 8,
        offset: const Offset(0, 2),
      ),
    ];
  }

  static List<BoxShadow> shadowMd(BuildContext ctx) {
    final isDark = Theme.of(ctx).brightness == Brightness.dark;
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.08),
        blurRadius: 16,
        offset: const Offset(0, 4),
      ),
    ];
  }

  // ── Gradients ────────────────────────────────────────────────────────────
  static LinearGradient brandGradient(Color c) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [c, c.withValues(alpha: 0.72)],
      );

  static LinearGradient shimmerBase(BuildContext ctx) {
    final isDark = Theme.of(ctx).brightness == Brightness.dark;
    return LinearGradient(
      colors: [
        isDark ? const Color(0xFF222952) : const Color(0xFFE4E7EF),
        isDark ? const Color(0xFF121729) : const Color(0xFFF6F7FB),
        isDark ? const Color(0xFF222952) : const Color(0xFFE4E7EF),
      ],
    );
  }

  // ── Content constraints ──────────────────────────────────────────────────
  static const double maxFormWidth = 440;
  static const double maxContentWidth = 600;
}

/// Extension on [BuildContext] for even shorter access inside build methods.
///
/// Usage: `context.ds.surface` instead of `Ds.surface(context)`.
extension DsContext on BuildContext {
  ColorScheme get cs => Theme.of(this).colorScheme;
  Brightness get brightness => Theme.of(this).brightness;
  bool get isDark => brightness == Brightness.dark;
}
