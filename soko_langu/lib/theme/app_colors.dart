import 'package:flutter/material.dart';

extension AppColorScheme on ColorScheme {
  Color get brandPrimary => brightness == Brightness.dark
      ? const Color(0xFFFFFFFF)
      : const Color(0xFF000000);

  Color get brandAccent => brightness == Brightness.dark
      ? const Color(0xFFB0B0B0)
      : const Color(0xFF333333);

  Color get brandSuccess => brightness == Brightness.dark
      ? const Color(0xFFD4D4D8)
      : const Color(0xFF111111);

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
  // recognize the "chat on WhatsApp" affordance; everything else is grayscale.
  Color get whatsappGreen => const Color(0xFF25D366);

  Color get trendingOrange => brightness == Brightness.dark
      ? const Color(0xFFE4E4E7)
      : const Color(0xFF171717);

  Color get successGreen => brightness == Brightness.dark
      ? const Color(0xFFD4D4D8)
      : const Color(0xFF111111);

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
