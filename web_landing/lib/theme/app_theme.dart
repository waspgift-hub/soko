import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Material 3 foundation for the Soko Vibe marketing site.
///
/// Black/white canvas with green reserved for actions; editorial type scale
/// (Inter) with JetBrains Mono for prices.
class SokoWebTheme {
  SokoWebTheme._();

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: SokoBrand.green,
      brightness: Brightness.light,
      surface: SokoBrand.white,
    );

    // Bundled Inter variable font (see pubspec); weights map to its wght axis.
    const inter = TextTheme(
      displayLarge: TextStyle(
        fontFamily: 'Inter',
        fontWeight: FontWeight.w800,
        letterSpacing: -2.5,
        color: SokoBrand.ink,
      ),
      displayMedium: TextStyle(
        fontFamily: 'Inter',
        fontWeight: FontWeight.w800,
        letterSpacing: -1.8,
        color: SokoBrand.ink,
      ),
      headlineLarge: TextStyle(
        fontFamily: 'Inter',
        fontWeight: FontWeight.w800,
        letterSpacing: -1.2,
        color: SokoBrand.ink,
      ),
      headlineSmall: TextStyle(
        fontFamily: 'Inter',
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
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
        height: 1.55,
        color: SokoBrand.ink,
      ),
      bodyMedium: TextStyle(
        fontFamily: 'Inter',
        height: 1.55,
        color: SokoBrand.muted,
      ),
      labelLarge: TextStyle(
        fontFamily: 'Inter',
        fontWeight: FontWeight.w600,
      ),
    );
    const mono = TextTheme(
      titleLarge: TextStyle(fontFamily: 'JetBrainsMono'),
      titleMedium: TextStyle(fontFamily: 'JetBrainsMono'),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme.copyWith(
        primary: SokoBrand.deepGreen,
        onPrimary: Colors.white,
        surface: SokoBrand.white,
        onSurface: SokoBrand.ink,
      ),
      scaffoldBackgroundColor: SokoBrand.white,
      fontFamily: 'Inter',
      textTheme: inter,
      extensions: const [
        SokoPrices(mono: mono),
      ],
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
        fillColor: const Color(0xFFF4F5F4),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        hintStyle: const TextStyle(color: SokoBrand.muted),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: SokoBrand.black,
          foregroundColor: SokoBrand.white,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
          textStyle:
              const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: SokoBrand.ink,
          side: const BorderSide(color: SokoBrand.ink, width: 1.2),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
          textStyle:
              const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFFF4F5F4),
        labelStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          color: SokoBrand.ink,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: const BorderSide(color: SokoBrand.line),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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

/// Monospace price styles (JetBrains Mono).
@immutable
class SokoPrices extends ThemeExtension<SokoPrices> {
  final TextTheme mono;
  const SokoPrices({required this.mono});

  TextStyle get amount => mono.titleLarge!.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
        color: SokoBrand.ink,
      );
  TextStyle get amountSmall => mono.titleMedium!.copyWith(
        fontWeight: FontWeight.w700,
        color: SokoBrand.ink,
      );

  @override
  SokoPrices copyWith({TextTheme? mono}) => SokoPrices(mono: mono ?? this.mono);

  @override
  SokoPrices lerp(ThemeExtension<SokoPrices>? other, double t) => this;
}
