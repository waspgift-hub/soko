import 'package:flutter/material.dart';
import 'app_colors.dart';

class SokoWebTheme {
  SokoWebTheme._();

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: SokoBrand.deepGreen,
      brightness: Brightness.light,
      surface: SokoBrand.white,
    );

    const inter = TextTheme(
      displayLarge: TextStyle(
        fontFamily: 'Inter',
        fontWeight: FontWeight.w800,
        letterSpacing: -2.0,
        color: SokoBrand.ink,
      ),
      displayMedium: TextStyle(
        fontFamily: 'Inter',
        fontWeight: FontWeight.w800,
        letterSpacing: -1.4,
        color: SokoBrand.ink,
      ),
      headlineLarge: TextStyle(
        fontFamily: 'Inter',
        fontWeight: FontWeight.w800,
        letterSpacing: -1.0,
        color: SokoBrand.ink,
      ),
      headlineSmall: TextStyle(
        fontFamily: 'Inter',
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: SokoBrand.ink,
      ),
      titleLarge: TextStyle(
        fontFamily: 'Inter',
        fontWeight: FontWeight.w700,
        color: SokoBrand.ink,
      ),
      titleMedium: TextStyle(
        fontFamily: 'Inter',
        fontWeight: FontWeight.w600,
        color: SokoBrand.ink,
      ),
      bodyLarge: TextStyle(
        fontFamily: 'Inter',
        fontWeight: FontWeight.w400,
        height: 1.6,
        color: SokoBrand.ink,
      ),
      bodyMedium: TextStyle(
        fontFamily: 'Inter',
        height: 1.6,
        color: SokoBrand.muted,
      ),
      labelLarge: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme.copyWith(
        primary: SokoBrand.deepGreen,
        secondary: SokoBrand.teal,
        onPrimary: Colors.white,
        surface: SokoBrand.white,
        onSurface: SokoBrand.ink,
        error: SokoBrand.error,
      ),
      scaffoldBackgroundColor: SokoBrand.paper,
      fontFamily: 'Inter',
      textTheme: inter,
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: SokoBrand.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: SokoBrand.line),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: SokoBrand.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: SokoBrand.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: SokoBrand.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: SokoBrand.deepGreen, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: SokoBrand.error),
        ),
        hintStyle: const TextStyle(color: SokoBrand.muted),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: SokoBrand.deepGreen,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: SokoBrand.ink,
          side: const BorderSide(color: SokoBrand.line, width: 1.2),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(color: SokoBrand.line, thickness: 1),
      appBarTheme: const AppBarTheme(
        backgroundColor: SokoBrand.white,
        foregroundColor: SokoBrand.ink,
        elevation: 0,
      ),
    );
  }
}
