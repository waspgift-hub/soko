import 'package:flutter/material.dart';

/// Official Soko Vibe brand palette — the single source of raw color values.
///
/// Widgets must read colors from [Theme.of] (`ColorScheme`, [SokoColors]) or
/// the semantic surface tokens in `neumorphic.dart`. These constants exist so
/// theme builders and standalone tokens agree; hardcoding them in screens
/// defeats the dark-mode and contrast guarantees.
class SokoPalette {
  SokoPalette._();

  // ── Light mode ───────────────────────────────────────────────────────────
  static const Color lightPrimary = Color(0xFF0B6B3A);
  static const Color lightPrimaryDark = Color(0xFF084D2B);
  static const Color lightPrimaryLight = Color(0xFFE9F5ED);
  static const Color lightBackground = Color(0xFFF7F8F7);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightSecondaryBackground = Color(0xFFE9F5ED);
  static const Color lightTextPrimary = Color(0xFF17211B);
  static const Color lightTextSecondary = Color(0xFF5F6B63);
  static const Color lightTextDisabled = Color(0xFF9AA59D);
  static const Color lightBorder = Color(0xFFE2E8E3);
  static const Color lightDivider = Color(0xFFEDF0ED);

  // ── Dark mode ────────────────────────────────────────────────────────────
  static const Color darkPrimary = Color(0xFF32B86C);
  static const Color darkPrimaryDark = Color(0xFF228B50);
  static const Color darkPrimaryLight = Color(0xFF193C29);
  static const Color darkBackground = Color(0xFF000000);
  static const Color darkSurface = Color(0xFF101713);
  static const Color darkSurfaceSecondary = Color(0xFF18221B);
  static const Color darkTextPrimary = Color(0xFFFFFFFF);
  static const Color darkTextSecondary = Color(0xFFB3C4B8);
  static const Color darkTextDisabled = Color(0xFF78847B);
  static const Color darkBorder = Color(0xFF29352D);
  static const Color darkDivider = Color(0xFF202A23);

  // ── Shared accents ───────────────────────────────────────────────────────
  static const Color amber = Color(0xFFF4B740);

  /// Text legible on [lightPrimary]: 6.6:1, meets WCAG AA.
  static const Color onLightPrimary = Color(0xFFFFFFFF);

  /// [darkPrimary] is too bright for white text (2.6:1). Near-black keeps the
  /// same green fill at 8.2:1 instead of dropping to an unreadable button.
  static const Color onDarkPrimary = Color(0xFF04160B);

  // Semantic states are independent of the brand ramp so a status badge never
  // reads as a "buy" action.
  static const Color lightSuccess = Color(0xFF0B6B3A);
  static const Color darkSuccess = Color(0xFF32B86C);

  /// Amber is a fill/label accent; as text on white it fails AA, so the
  /// legible tone is a deep amber-brown (5.0:1).
  static const Color lightWarning = Color(0xFFB45309);
  static const Color darkWarning = Color(0xFFF4B740);

  static const Color lightError = Color(0xFFB42318);
  static const Color darkError = Color(0xFFFF6B6B);

  static const Color lightInfo = Color(0xFF1A5FB4);
  static const Color darkInfo = Color(0xFF6FB3FF);

  /// Hex for a logo/watermark chevron or splash brand block. Text on this
  /// surface must always be [onDarkPrimary] in dark, [onLightPrimary] in light.
  static Color brandSurface(Brightness brightness) =>
      brightness == Brightness.dark ? darkPrimary : lightPrimary;
}
