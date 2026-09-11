import 'package:flutter/material.dart';

// Semantic monochrome ramp. These tokens give screens a single vocabulary for
// "background vs surface vs emphasis" in both themes. Values follow the brand
// rule: near-black (not pure #000) for emphasis on light, near-white for
// emphasis on dark, and gray mid-tones purely for informational hierarchy.
extension AppColorScheme on ColorScheme {
  /// Canvas behind everything (scaffold).
  Color get bgCanvas =>
      brightness == Brightness.dark ? const Color(0xFF0A0A0A) : const Color(0xFFFFFFFF);

  /// Subtle tonal surface (grouped cards, sheet headers, section fills).
  Color get surfaceSubtle =>
      brightness == Brightness.dark ? const Color(0xFF111111) : const Color(0xFFFAFAFA);

  /// Raised surface (cards, dialogs).
  Color get surfaceRaised =>
      brightness == Brightness.dark ? const Color(0xFF171717) : const Color(0xFFFFFFFF);

  /// Primary content color (headings, emphasized labels).
  Color get contentPrimary =>
      brightness == Brightness.dark ? const Color(0xFFFAFAFA) : const Color(0xFF0A0A0A);

  /// Secondary content color (body copy below headings).
  Color get contentSecondary =>
      brightness == Brightness.dark ? const Color(0xFFA3A3A3) : const Color(0xFF525252);

  /// Muted content (metadata, placeholders, captions).
  Color get contentMuted =>
      brightness == Brightness.dark ? const Color(0xFF8E8E93) : const Color(0xFF737373);

  /// Hairline divider/border color.
  Color get hairline =>
      brightness == Brightness.dark ? const Color(0xFF262626) : const Color(0xFFE5E5E5);

  Color get brandPrimary => brightness == Brightness.dark
      ? const Color(0xFFA8E6CF)
      : const Color(0xFF9CD9B0);

  Color get brandAccent => brightness == Brightness.dark
      ? const Color(0xFFB8E8CF)
      : const Color(0xFF74C89B);

  Color get brandSuccess => brightness == Brightness.dark
      ? const Color(0xFFA8E6CF)
      : const Color(0xFF9CD9B0);

  Color get brandWarning => brightness == Brightness.dark
      ? const Color(0xFFE4E4E7)
      : const Color(0xFF333333);

  Color get brandInfo => brightness == Brightness.dark
      ? const Color(0xFFA1A1AA)
      : const Color(0xFF18181B);

  Color get brandBorder => brightness == Brightness.dark
      ? const Color(0xFF2E2E32)
      : const Color(0xFFE4E4E7);

  Color get brandTextPrimary => brightness == Brightness.dark
      ? const Color(0xFFF4F4F5)
      : const Color(0xFF09090B);

  Color get brandTextSecondary => brightness == Brightness.dark
      ? const Color(0xFFA1A1AA)
      : const Color(0xFF52525B);

  Color get surfaceDark => brightness == Brightness.dark
      ? const Color(0xFF000000)
      : const Color(0xFFFAFAFA);

  Color get surfaceLight => brightness == Brightness.dark
      ? const Color(0xFF121212)
      : const Color(0xFFFFFFFF);

  Color get cardBase => brightness == Brightness.dark
      ? const Color(0xFF171717)
      : const Color(0xFFFFFFFF);

  Color get cardElevated => brightness == Brightness.dark
      ? const Color(0xFF1E1E1E)
      : const Color(0xFFFFFFFF);

  Color get glassBg => brightness == Brightness.dark
      ? const Color(0x1AFFFFFF)
      : const Color(0xCCFFFFFF);

  Color get glassBorder => brightness == Brightness.dark
      ? const Color(0x2AFFFFFF)
      : const Color(0x08000000);

  // WhatsApp CTA buttons keep the official brand green so users instantly
  // recognize the "chat on WhatsApp" affordance; the rest uses the Soko Vibe
  // green accent on a white/black canvas.
  Color get whatsappGreen => const Color(0xFF25D366);

  Color get trendingOrange => brightness == Brightness.dark
      ? const Color(0xFFE4E4E7)
      : const Color(0xFF171717);

  Color get successGreen => brightness == Brightness.dark
      ? const Color(0xFFA8E6CF)
      : const Color(0xFF9CD9B0);

  Color get boostGold => brightness == Brightness.dark
      ? const Color(0xFFF5F5F5)
      : const Color(0xFF0A0A0A);

  Color get boostSilver => brightness == Brightness.dark
      ? const Color(0xFFC0C0C0)
      : const Color(0xFF7A7A7A);

  Color get boostBronze => brightness == Brightness.dark
      ? const Color(0xFF8E8E8E)
      : const Color(0xFF9E9E9E);

  Color get premiumAmber => brightness == Brightness.dark
      ? const Color(0xFFE4E4E7)
      : const Color(0xFF333333);

  Color get premiumTeal => brightness == Brightness.dark
      ? const Color(0xFFA1A1AA)
      : const Color(0xFF18181B);
}
