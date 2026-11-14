import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Unified design tokens for the Soko Vibe website.
/// All pages and components should consume these values rather than literals.
class SokoTokens {
  SokoTokens._();

  // Spacing (4px grid)
  static const double s2 = 2;
  static const double s4 = 4;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s32 = 32;
  static const double s40 = 40;
  static const double s48 = 48;
  static const double s56 = 56;
  static const double s64 = 64;
  static const double s72 = 72;
  static const double s96 = 96;

  // Radii
  static const double radiusSm = 10;
  static const double radiusMd = 14;
  static const double radiusLg = 20;
  static const double radiusXl = 28;
  static const double radiusPill = 999;

  // Durations
  static const Duration durationFast = Duration(milliseconds: 150);
  static const Duration durationBase = Duration(milliseconds: 240);
  static const Duration durationSlow = Duration(milliseconds: 420);

  // Layout
  static const double maxContentWidth = 1200;
  static const double maxReadingWidth = 760;
  static const double navHeight = 72;

  // Breakpoints (aligned with app_breakpoints.dart)
  static const double bpMobile = 600;
  static const double bpTablet = 900;
  static const double bpDesktop = 1200;
  static const double bpWide = 1440;

  static Color focusRing(BuildContext context) =>
      SokoBrand.deepGreen.withValues(alpha: 0.35);
}
