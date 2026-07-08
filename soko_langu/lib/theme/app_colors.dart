import 'package:flutter/material.dart';

extension AppColorScheme on ColorScheme {
  Color get surfaceDark => brightness == Brightness.dark
      ? const Color(0xFF0A0E1A)
      : const Color(0xFFF8F9FE);

  Color get surfaceLight => brightness == Brightness.dark
      ? const Color(0xFF121729)
      : const Color(0xFFFFFFFF);

  Color get cardBase => brightness == Brightness.dark
      ? const Color(0xFF1A2040)
      : const Color(0xFFFFFFFF);

  Color get cardElevated => brightness == Brightness.dark
      ? const Color(0xFF222952)
      : const Color(0xFFFFFFFF);

  Color get glassBg => brightness == Brightness.dark
      ? const Color(0x1AFFFFFF)
      : const Color(0xCCFFFFFF);

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
