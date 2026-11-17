import 'package:flutter/material.dart';
import 'soko_palette.dart';

/// Semantic surface and brand tokens layered on top of [ColorScheme].
///
/// This is the single vocabulary screens use for "background vs card vs
/// emphasis" in both themes. Every value comes from [SokoPalette] so the
/// emerald + white + black + soft-grey identity cannot drift between screens.
/// Green text/icons on a light surface use [SokoPalette.lightPrimary] (6.6:1);
/// the brighter dark-mode green is reserved for the black canvas.
extension AppColorScheme on ColorScheme {
  /// Canvas behind everything (scaffold).
  Color get bgCanvas =>
      brightness == Brightness.dark ? SokoPalette.darkBackground : SokoPalette.lightBackground;

  /// Subtle tonal surface (grouped cards, sheet headers, section fills).
  Color get surfaceSubtle => brightness == Brightness.dark
      ? SokoPalette.darkSurfaceSecondary
      : SokoPalette.lightSecondaryBackground;

  /// Raised surface (cards, dialogs).
  Color get surfaceRaised =>
      brightness == Brightness.dark ? SokoPalette.darkSurface : SokoPalette.lightCard;

  /// Primary content color (headings, emphasized labels).
  Color get contentPrimary =>
      brightness == Brightness.dark ? SokoPalette.darkTextPrimary : SokoPalette.lightTextPrimary;

  /// Secondary content color (body copy below headings).
  Color get contentSecondary => brightness == Brightness.dark
      ? SokoPalette.darkTextSecondary
      : SokoPalette.lightTextSecondary;

  /// Muted content (metadata, placeholders, captions).
  Color get contentMuted =>
      brightness == Brightness.dark ? SokoPalette.darkTextDisabled : SokoPalette.lightTextDisabled;

  /// Hairline divider/border color.
  Color get hairline =>
      brightness == Brightness.dark ? SokoPalette.darkBorder : SokoPalette.lightBorder;

  Color get brandPrimary =>
      brightness == Brightness.dark ? SokoPalette.darkPrimary : SokoPalette.lightPrimary;

  Color get brandAccent =>
      brightness == Brightness.dark ? SokoPalette.darkPrimary : SokoPalette.lightPrimary;

  Color get brandSuccess =>
      brightness == Brightness.dark ? SokoPalette.darkSuccess : SokoPalette.lightSuccess;

  Color get brandWarning =>
      brightness == Brightness.dark ? SokoPalette.darkWarning : SokoPalette.lightWarning;

  Color get brandInfo =>
      brightness == Brightness.dark ? SokoPalette.darkInfo : SokoPalette.lightInfo;

  Color get brandBorder =>
      brightness == Brightness.dark ? SokoPalette.darkBorder : SokoPalette.lightBorder;

  Color get brandTextPrimary =>
      brightness == Brightness.dark ? SokoPalette.darkTextPrimary : SokoPalette.lightTextPrimary;

  Color get brandTextSecondary => brightness == Brightness.dark
      ? SokoPalette.darkTextSecondary
      : SokoPalette.lightTextSecondary;

  Color get surfaceDark =>
      brightness == Brightness.dark ? SokoPalette.darkBackground : SokoPalette.lightBackground;

  Color get surfaceLight =>
      brightness == Brightness.dark ? SokoPalette.darkSurface : SokoPalette.lightCard;

  Color get cardBase =>
      brightness == Brightness.dark ? SokoPalette.darkSurface : SokoPalette.lightCard;

  Color get cardElevated =>
      brightness == Brightness.dark ? SokoPalette.darkSurfaceSecondary : SokoPalette.lightCard;

  Color get glassBg =>
      brightness == Brightness.dark ? const Color(0x1AFFFFFF) : const Color(0xCCFFFFFF);

  Color get glassBorder =>
      brightness == Brightness.dark ? const Color(0x33FFFFFF) : const Color(0x16000000);

  // WhatsApp CTA buttons keep the official brand green so users instantly
  // recognize the "chat on WhatsApp" affordance; the rest uses the Soko Vibe
  // green accent on a white/black canvas.
  Color get whatsappGreen => const Color(0xFF25D366);

  Color get trendingOrange =>
      brightness == Brightness.dark ? SokoPalette.darkTextPrimary : SokoPalette.lightTextPrimary;

  Color get successGreen =>
      brightness == Brightness.dark ? SokoPalette.darkSuccess : SokoPalette.lightSuccess;

  Color get premiumAmber =>
      brightness == Brightness.dark ? SokoPalette.darkWarning : SokoPalette.lightWarning;

  Color get premiumTeal => brightness == Brightness.dark
      ? SokoPalette.darkTextSecondary
      : SokoPalette.lightTextSecondary;
}
