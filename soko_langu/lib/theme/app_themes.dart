import 'package:flutter/material.dart';
import 'app_typography.dart';

ThemeData _base(Brightness brightness, Color seed) {
  final base = ThemeData(useMaterial3: true, brightness: brightness);
  final scheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: brightness,
  );
  return base.copyWith(
    colorScheme: scheme,
    textTheme: AppTypography.apply(base.textTheme, scheme),
  );
}

ThemeData buildLightTheme(Color seed) {
  final scheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: Brightness.light,
  );
  return _base(Brightness.light, seed).copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFFF0F9F1),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: scheme.primary,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: AppTypography.appBarTitle(scheme.primary),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.primary,
        side: BorderSide(color: scheme.primary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 2,
      shadowColor: scheme.primary.withValues(alpha: 0.15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: const Color(0xFFF0F9F1),
      selectedItemColor: scheme.primary,
      unselectedItemColor: Colors.grey[400],
      type: BottomNavigationBarType.fixed,
      elevation: 0,
      selectedLabelStyle: const TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 12,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      filled: true,
      fillColor: Colors.grey[50],
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.grey[100],
      selectedColor: scheme.primary,
      labelStyle: TextStyle(color: scheme.onSurface),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    ),
    dividerTheme: DividerThemeData(color: Colors.grey[200], thickness: 1),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    badgeTheme: BadgeThemeData(
      backgroundColor: scheme.primary,
      textColor: scheme.onPrimary,
    ),
  );
}
