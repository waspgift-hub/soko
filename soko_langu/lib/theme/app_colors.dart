import 'package:flutter/material.dart';

// Semantic monochrome ramp. These tokens give screens a single vocabulary for
// "background vs surface vs emphasis" in both themes. Values follow the brand
// system: black canvas + white canvas + one green accent (#00C853) for
// commerce/emphasis. Grays (#6B6B6B / #A7A7A7) carry only informational
// hierarchy. Green text/icons on a light surface use Deep Green #009624 so
// contrast stays ≥ 3.9:1; #00C853 is reserved for fills with black text.
extension AppColorScheme on ColorScheme {
  /// Canvas behind everything (scaffold).
  Color get bgCanvas =>
      brightness == Brightness.dark ? const Color(0xFF0B0B0B) : const Color(0xFFFFFFFF);

  /// Subtle tonal surface (grouped cards, sheet headers, section fills).
  Color get surfaceSubtle =>
      brightness == Brightness.dark ? const Color(0xFF121212) : const Color(0xFFF7F7F7);

  /// Raised surface (cards, dialogs).
  Color get surfaceRaised =>
      brightness == Brightness.dark ? const Color(0xFF181818) : const Color(0xFFFFFFFF);

  /// Primary content color (headings, emphasized labels).
  Color get contentPrimary =>
      brightness == Brightness.dark ? const Color(0xFFFFFFFF) : const Color(0xFF000000);

  /// Secondary content color (body copy below headings).
  Color get contentSecondary =>
      brightness == Brightness.dark ? const Color(0xFFA7A7A7) : const Color(0xFF6B6B6B);

  /// Muted content (metadata, placeholders, captions).
  Color get contentMuted =>
      brightness == Brightness.dark ? const Color(0xFF8E8E93) : const Color(0xFF737373);

  /// Hairline divider/border color.
  Color get hairline =>
      brightness == Brightness.dark ? const Color(0xFF292929) : const Color(0xFFE5E5E5);

  Color get brandPrimary => const Color(0xFF00C853);

  Color get brandAccent => brightness == Brightness.dark
      ? const Color(0xFF00C853)
      : const Color(0xFF009624);

  Color get brandSuccess => brightness == Brightness.dark
      ? const Color(0xFF00C853)
      : const Color(0xFF009624);

  Color get brandWarning => const Color(0xFFF59E0B);

  Color get brandInfo => brightness == Brightness.dark
      ? const Color(0xFFA7A7A7)
      : const Color(0xFF3B3B3B);

  Color get brandBorder => brightness == Brightness.dark
      ? const Color(0xFF292929)
      : const Color(0xFFE5E5E5);

  Color get brandTextPrimary => brightness == Brightness.dark
      ? const Color(0xFFFFFFFF)
      : const Color(0xFF000000);

  Color get brandTextSecondary => brightness == Brightness.dark
      ? const Color(0xFFA7A7A7)
      : const Color(0xFF6B6B6B);

  Color get surfaceDark => brightness == Brightness.dark
      ? const Color(0xFF0B0B0B)
      : const Color(0xFFFAFAFA);

  Color get surfaceLight => brightness == Brightness.dark
      ? const Color(0xFF121212)
      : const Color(0xFFFFFFFF);

  Color get cardBase => brightness == Brightness.dark
      ? const Color(0xFF121212)
      : const Color(0xFFFFFFFF);

  Color get cardElevated => brightness == Brightness.dark
      ? const Color(0xFF1E1E1E)
      : const Color(0xFFFFFFFF);

  Color get glassBg => brightness == Brightness.dark
      ? const Color(0x1AFFFFFF)
      : const Color(0xCCFFFFFF);

  Color get glassBorder => brightness == Brightness.dark
      ? const Color(0x33FFFFFF)
      : const Color(0x16000000);

  // WhatsApp CTA buttons keep the official brand green so users instantly
  // recognize the "chat on WhatsApp" affordance; the rest uses the Soko Vibe
  // green accent on a white/black canvas.
  Color get whatsappGreen => const Color(0xFF25D366);

  Color get trendingOrange => brightness == Brightness.dark
      ? const Color(0xFFFFFFFF)
      : const Color(0xFF000000);

  Color get successGreen => brightness == Brightness.dark
      ? const Color(0xFF00C853)
      : const Color(0xFF009624);

  Color get boostGold => brightness == Brightness.dark
      ? const Color(0xFFB45309)
      : const Color(0xFF7A5A00);

  Color get boostSilver => brightness == Brightness.dark
      ? const Color(0xFFC0C0C0)
      : const Color(0xFF7A7A7A);

  Color get boostBronze => brightness == Brightness.dark
      ? const Color(0xFF8E8E8E)
      : const Color(0xFF9E9E9E);

  Color get premiumAmber => brightness == Brightness.dark
      ? const Color(0xFFF59E0B)
      : const Color(0xFFB45309);

  Color get premiumTeal => brightness == Brightness.dark
      ? const Color(0xFFA7A7A7)
      : const Color(0xFF3B3B3B);
}
