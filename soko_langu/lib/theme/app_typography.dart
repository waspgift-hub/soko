import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTypography {
  AppTypography._();

  static TextTheme apply(TextTheme base, ColorScheme scheme) {
    final inter = GoogleFonts.interTextTheme(base);
    return inter.copyWith(
      displayLarge: GoogleFonts.spaceGrotesk(
        fontSize: 34,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.2,
        height: 1.1,
        color: scheme.onSurface,
      ),
      displayMedium: GoogleFonts.spaceGrotesk(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
        height: 1.15,
        color: scheme.onSurface,
      ),
      headlineLarge: GoogleFonts.spaceGrotesk(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.6,
        color: scheme.onSurface,
      ),
      headlineMedium: GoogleFonts.spaceGrotesk(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.4,
        color: scheme.onSurface,
      ),
      titleLarge: GoogleFonts.spaceGrotesk(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
        color: scheme.onSurface,
      ),
      titleMedium: GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: scheme.onSurface,
      ),
      titleSmall: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      bodyLarge: GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 1.4,
        color: scheme.onSurface,
      ),
      bodyMedium: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.35,
        color: scheme.onSurfaceVariant,
      ),
      labelLarge: GoogleFonts.jetBrainsMono(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.3,
        color: scheme.onSurfaceVariant,
      ),
      labelMedium: GoogleFonts.jetBrainsMono(
        fontSize: 11,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.2,
        color: scheme.onSurfaceVariant,
      ),
      labelSmall: GoogleFonts.jetBrainsMono(
        fontSize: 10,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.1,
        color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
      ),
    );
  }

  static TextStyle brandTitle(Color color) => GoogleFonts.spaceGrotesk(
        fontSize: 30,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
        color: color,
      );

  static TextStyle screenTitle(Color color) => GoogleFonts.spaceGrotesk(
        fontSize: 26,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.6,
        color: color,
      );

  static TextStyle appBarTitle(Color color) => GoogleFonts.inter(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
        color: color,
      );

  static TextStyle monoLabel(Color color) => GoogleFonts.jetBrainsMono(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.2,
        color: color,
      );

  static TextStyle timeIndicator(Color color) => GoogleFonts.jetBrainsMono(
        fontSize: 11,
        fontWeight: FontWeight.w400,
        color: color,
      );

  static TextStyle statusChip(Color color) => GoogleFonts.jetBrainsMono(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
        color: color,
      );
}
