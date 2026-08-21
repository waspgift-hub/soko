import 'package:flutter/material.dart';

class AppTypography {
  AppTypography._();

  static const String _inter = 'Inter';
  static const String _spaceGrotesk = 'Space Grotesk';
  static const String _jetBrainsMono = 'JetBrains Mono';

  static TextTheme apply(TextTheme base, ColorScheme scheme) {
    return base.copyWith(
      displayLarge: TextStyle(
        fontFamily: _spaceGrotesk,
        fontSize: 34,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.2,
        height: 1.1,
        color: scheme.onSurface,
      ),
      displayMedium: TextStyle(
        fontFamily: _spaceGrotesk,
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
        height: 1.15,
        color: scheme.onSurface,
      ),
      headlineLarge: TextStyle(
        fontFamily: _spaceGrotesk,
        fontSize: 24,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.6,
        color: scheme.onSurface,
      ),
      headlineMedium: TextStyle(
        fontFamily: _spaceGrotesk,
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.4,
        color: scheme.onSurface,
      ),
      titleLarge: TextStyle(
        fontFamily: _spaceGrotesk,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
        color: scheme.onSurface,
      ),
      titleMedium: TextStyle(
        fontFamily: _inter,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: scheme.onSurface,
      ),
      titleSmall: TextStyle(
        fontFamily: _inter,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      bodyLarge: TextStyle(
        fontFamily: _inter,
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 1.4,
        color: scheme.onSurface,
      ),
      bodyMedium: TextStyle(
        fontFamily: _inter,
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.35,
        color: scheme.onSurface,
      ),
      bodySmall: TextStyle(
        fontFamily: _inter,
        fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 1.3,
        color: scheme.onSurface,
      ),
      labelLarge: TextStyle(
        fontFamily: _jetBrainsMono,
        fontSize: 13,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.3,
        color: scheme.onSurface,
      ),
      labelMedium: TextStyle(
        fontFamily: _jetBrainsMono,
        fontSize: 11,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.2,
        color: scheme.onSurface,
      ),
      labelSmall: TextStyle(
        fontFamily: _jetBrainsMono,
        fontSize: 10,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.1,
        color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
      ),
    );
  }

  static TextStyle brandTitle(Color color) => const TextStyle(
        fontFamily: _spaceGrotesk,
        fontSize: 30,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
      ).copyWith(color: color);

  static TextStyle screenTitle(Color color) => const TextStyle(
        fontFamily: _spaceGrotesk,
        fontSize: 26,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.6,
      ).copyWith(color: color);

  static TextStyle appBarTitle(Color color) => const TextStyle(
        fontFamily: _inter,
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
      ).copyWith(color: color);

  static TextStyle monoLabel(Color color) => const TextStyle(
        fontFamily: _jetBrainsMono,
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.2,
      ).copyWith(color: color);

  static TextStyle timeIndicator(Color color) => const TextStyle(
        fontFamily: _jetBrainsMono,
        fontSize: 11,
        fontWeight: FontWeight.w400,
      ).copyWith(color: color);

  static TextStyle statusChip(Color color) => const TextStyle(
        fontFamily: _jetBrainsMono,
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ).copyWith(color: color);

  static TextStyle amount(Color color) => const TextStyle(
        fontFamily: _jetBrainsMono,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
      ).copyWith(color: color);
}
