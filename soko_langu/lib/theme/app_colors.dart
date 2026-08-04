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

  Color get glassSurface => brightness == Brightness.dark
      ? const Color(0x0DFFFFFF)
      : const Color(0x08FFFFFF);

  Color get glassHighlight => brightness == Brightness.dark
      ? const Color(0x15FFFFFF)
      : const Color(0x1A000000);

  Color get glassReflection => brightness == Brightness.dark
      ? const Color(0x08FFFFFF)
      : const Color(0x0DFFFFFF);

  Color get glassBorder => brightness == Brightness.dark
      ? const Color(0x2AFFFFFF)
      : const Color(0x08000000);

  Color get whatsappGreen => const Color(0xFF25D366);
  Color get trendingOrange => const Color(0xFFFF6F00);
  Color get flashSaleDarkGreen => const Color(0xFF1B4332);
  Color get flashSaleMidGreen => const Color(0xFF2D6A4F);
  Color get flashSaleAccentGreen => const Color(0xFF52B788);
  Color get flashSaleLightGreen => const Color(0xFF95D5B2);
  Color get flashSaleBg => const Color(0xFFF0F9F1);
  Color get successGreen => const Color(0xFF065535);
  Color get boostBronze => const Color(0xFFCD7F32);
  Color get boostSilver => const Color(0xFF9E9E9E);
  Color get boostGold => const Color(0xFFFFD700);
  Color get premiumAmber => const Color(0xFFFFB74D);
  Color get premiumTeal => const Color(0xFF26A69A);
  Color get premiumRose => const Color(0xFFEC407A);
  Color get premiumIndigo => const Color(0xFF5C6BC0);
}
