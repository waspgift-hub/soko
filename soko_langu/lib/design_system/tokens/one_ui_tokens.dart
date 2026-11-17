import 'package:flutter/material.dart';
import '../../theme/soko_palette.dart';

/// Samsung One UI-inspired design tokens aligned with Soko Vibe branding.
/// Prefer [Theme.of(context).colorScheme] in widgets; these tokens are for
/// shared constants and standalone theme builders. Every value re-exports
/// [SokoPalette], so this file can never drift onto a second green.
class OneUiColors {
  OneUiColors._();

  static const Color background = SokoPalette.lightBackground;
  static const Color surface = SokoPalette.lightCard;
  static const Color surfaceContainer = SokoPalette.lightSecondaryBackground;
  static const Color surfaceVariant = SokoPalette.lightDivider;

  static const Color textPrimary = SokoPalette.lightTextPrimary;
  static const Color textSecondary = SokoPalette.lightTextSecondary;
  static const Color textTertiary = SokoPalette.lightTextDisabled;
  static const Color textOnAccent = SokoPalette.onLightPrimary;

  static const Color accent = SokoPalette.lightPrimary;
  static const Color accentPressed = SokoPalette.lightPrimaryDark;
  static const Color accentContainer = SokoPalette.lightPrimaryLight;
  static const Color commerce = SokoPalette.lightPrimary;
  static const Color onCommerce = SokoPalette.onLightPrimary;

  static const Color border = SokoPalette.lightBorder;
  static const Color divider = SokoPalette.lightDivider;
  // Control outlines must reach 3:1, so they use the secondary text tone
  // rather than the decorative border, which is only a hairline separator.
  static const Color outline = SokoPalette.lightTextSecondary;

  static const Color success = SokoPalette.lightSuccess;
  static const Color warning = SokoPalette.lightWarning;
  static const Color error = SokoPalette.lightError;
  static const Color info = SokoPalette.lightInfo;
  static const Color disabled = SokoPalette.lightTextDisabled;

  static const Color darkBackground = SokoPalette.darkBackground;
  static const Color darkSurface = SokoPalette.darkSurface;
  static const Color darkSurfaceContainer = SokoPalette.darkSurfaceSecondary;
  static const Color darkSurfaceVariant = SokoPalette.darkBorder;
  static const Color darkTextPrimary = SokoPalette.darkTextPrimary;
  static const Color darkTextSecondary = SokoPalette.darkTextSecondary;
  static const Color darkTextTertiary = SokoPalette.darkTextDisabled;
  static const Color darkBorder = SokoPalette.darkBorder;
  static const Color darkDivider = SokoPalette.darkDivider;
  static const Color darkAccent = SokoPalette.darkPrimary;
  static const Color darkAccentContainer = SokoPalette.darkPrimaryLight;
  static const Color darkOnAccent = SokoPalette.onDarkPrimary;
  static const Color darkOnAccentContainer = Color(0xFFA7EBC2);
  static const Color darkSuccess = SokoPalette.darkSuccess;
  static const Color darkWarning = SokoPalette.darkWarning;
  static const Color darkError = SokoPalette.darkError;
  static const Color darkOnError = Color(0xFF2A0808);
  static const Color darkInfo = SokoPalette.darkInfo;
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
