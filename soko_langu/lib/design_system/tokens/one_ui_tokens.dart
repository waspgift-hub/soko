import 'package:flutter/material.dart';

/// Samsung One UI-inspired design tokens aligned with Soko Vibe branding.
/// Prefer [Theme.of(context).colorScheme] in widgets; these tokens are for
/// shared constants and standalone theme builders.
class OneUiColors {
  OneUiColors._();

  static const Color background = Color(0xFFF7F7F7);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceContainer = Color(0xFFF2F2F2);
  static const Color surfaceVariant = Color(0xFFECECEC);

  static const Color textPrimary = Color(0xFF000000);
  static const Color textSecondary = Color(0xFF505050);
  static const Color textTertiary = Color(0xFF6B6B6B);
  static const Color textOnAccent = Color(0xFFFFFFFF);

  static const Color accent = Color(0xFF1F8F4E);
  static const Color accentPressed = Color(0xFF197A42);
  static const Color accentContainer = Color(0xFFE8F5EE);
  static const Color commerce = Color(0xFF00C853);
  static const Color onCommerce = Color(0xFF000000);

  static const Color border = Color(0xFFE5E5E5);
  static const Color divider = Color(0xFFF0F0F0);
  static const Color outline = Color(0xFFD0D0D0);

  static const Color success = Color(0xFF1F8F4E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFFF3B30);
  static const Color info = Color(0xFF007AFF);
  static const Color disabled = Color(0xFFBDBDBD);

  static const Color darkBackground = Color(0xFF000000);
  static const Color darkSurface = Color(0xFF1C1C1E);
  static const Color darkSurfaceContainer = Color(0xFF2C2C2E);
  static const Color darkSurfaceVariant = Color(0xFF232323);
  static const Color darkTextPrimary = Color(0xFFFFFFFF);
  static const Color darkTextSecondary = Color(0xFFA7A7A7);
  static const Color darkTextTertiary = Color(0xFF8E8E93);
  static const Color darkBorder = Color(0xFF38383A);
  static const Color darkDivider = Color(0xFF292929);
}

class OneUiSpacing {
  OneUiSpacing._();
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 48;
  static const double page = 20;
}

class OneUiRadius {
  OneUiRadius._();
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 28;
  static const double full = 999;
}

class OneUiMotion {
  OneUiMotion._();
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 250);
  static const Duration slow = Duration(milliseconds: 350);
  static const Duration page = Duration(milliseconds: 320);
  static const Curve ease = Curves.easeOutCubic;
  static const Curve emphasized = Cubic(0.2, 0, 0, 1);
}
