import 'package:flutter/material.dart';

class AppTypography {
  AppTypography._();

  static const String _inter = 'Inter';
  static const String _spaceGrotesk = 'Space Grotesk';
  static const String _jetBrainsMono = 'JetBrains Mono';

  // Semantic font size scale (base values, respect text scaling)
  static const double _displayLargeSize = 34;
  static const double _displayMediumSize = 28;
  static const double _headlineLargeSize = 24;
  static const double _headlineMediumSize = 20;
  static const double _titleLargeSize = 18;
  static const double _titleMediumSize = 16;
  static const double _titleSmallSize = 14;
  static const double _bodyLargeSize = 16;
  static const double _bodyMediumSize = 14;
  static const double _bodySmallSize = 12;
  static const double _labelLargeSize = 13;
  static const double _labelMediumSize = 11;
  static const double _labelSmallSize = 10;

  static TextTheme apply(TextTheme base, ColorScheme scheme) {
    return base.copyWith(
      displayLarge: TextStyle(
        fontFamily: _spaceGrotesk,
        fontSize: _displayLargeSize,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.2,
        height: 1.1,
        color: scheme.onSurface,
      ),
      displayMedium: TextStyle(
        fontFamily: _spaceGrotesk,
        fontSize: _displayMediumSize,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
        height: 1.15,
        color: scheme.onSurface,
      ),
      headlineLarge: TextStyle(
        fontFamily: _spaceGrotesk,
        fontSize: _headlineLargeSize,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.6,
        color: scheme.onSurface,
      ),
      headlineMedium: TextStyle(
        fontFamily: _spaceGrotesk,
        fontSize: _headlineMediumSize,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.4,
        color: scheme.onSurface,
      ),
      titleLarge: TextStyle(
        fontFamily: _spaceGrotesk,
        fontSize: _titleLargeSize,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
        color: scheme.onSurface,
      ),
      titleMedium: TextStyle(
        fontFamily: _inter,
        fontSize: _titleMediumSize,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: scheme.onSurface,
      ),
      titleSmall: TextStyle(
        fontFamily: _inter,
        fontSize: _titleSmallSize,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      bodyLarge: TextStyle(
        fontFamily: _inter,
        fontSize: _bodyLargeSize,
        fontWeight: FontWeight.w400,
        height: 1.4,
        color: scheme.onSurface,
      ),
      bodyMedium: TextStyle(
        fontFamily: _inter,
        fontSize: _bodyMediumSize,
        fontWeight: FontWeight.w400,
        height: 1.35,
        color: scheme.onSurface,
      ),
      bodySmall: TextStyle(
        fontFamily: _inter,
        fontSize: _bodySmallSize,
        fontWeight: FontWeight.w400,
        height: 1.3,
        color: scheme.onSurface,
      ),
      labelLarge: TextStyle(
        fontFamily: _jetBrainsMono,
        fontSize: _labelLargeSize,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.3,
        color: scheme.onSurface,
      ),
      labelMedium: TextStyle(
        fontFamily: _jetBrainsMono,
        fontSize: _labelMediumSize,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.2,
        color: scheme.onSurface,
      ),
      labelSmall: TextStyle(
        fontFamily: _jetBrainsMono,
        fontSize: _labelSmallSize,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.1,
        color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
      ),
    );
  }

  // Semantic typography tokens — use these instead of raw TextStyle constructors
  // Display headings
  static TextStyle displayLarge(Color color) => TextStyle(
        fontFamily: _spaceGrotesk,
        fontSize: _displayLargeSize,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.2,
        height: 1.1,
        color: color,
      );

  static TextStyle displayMedium(Color color) => TextStyle(
        fontFamily: _spaceGrotesk,
        fontSize: _displayMediumSize,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
        height: 1.15,
        color: color,
      );

  // Screen/section headings
  static TextStyle screenTitle(Color color) => TextStyle(
        fontFamily: _spaceGrotesk,
        fontSize: 26,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.6,
        color: color,
      );

  static TextStyle sectionTitle(Color color) => TextStyle(
        fontFamily: _spaceGrotesk,
        fontSize: _headlineLargeSize,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.4,
        color: color,
      );

  // Card/product titles
  static TextStyle cardTitle(Color color) => TextStyle(
        fontFamily: _spaceGrotesk,
        fontSize: _titleLargeSize,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
        color: color,
      );

  static TextStyle productTitle(Color color) => TextStyle(
        fontFamily: _inter,
        fontSize: _titleMediumSize,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: color,
      );

  // Prices (mono for alignment)
  static TextStyle price(Color color) => TextStyle(
        fontFamily: _jetBrainsMono,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
        color: color,
      );

  static TextStyle priceLarge(Color color) => TextStyle(
        fontFamily: _jetBrainsMono,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
        color: color,
      );

  // Body text
  static TextStyle bodyLarge(Color color) => TextStyle(
        fontFamily: _inter,
        fontSize: _bodyLargeSize,
        fontWeight: FontWeight.w400,
        height: 1.4,
        color: color,
      );

  static TextStyle bodyMedium(Color color) => TextStyle(
        fontFamily: _inter,
        fontSize: _bodyMediumSize,
        fontWeight: FontWeight.w400,
        height: 1.35,
        color: color,
      );

  static TextStyle bodySmall(Color color) => TextStyle(
        fontFamily: _inter,
        fontSize: _bodySmallSize,
        fontWeight: FontWeight.w400,
        height: 1.3,
        color: color,
      );

  // Secondary/metadata text
  static TextStyle metadata(Color color) => TextStyle(
        fontFamily: _inter,
        fontSize: _bodySmallSize,
        fontWeight: FontWeight.w400,
        height: 1.3,
        color: color,
      );

  static TextStyle caption(Color color) => TextStyle(
        fontFamily: _inter,
        fontSize: _labelSmallSize,
        fontWeight: FontWeight.w400,
        height: 1.2,
        color: color,
      );

  // Labels & buttons
  static TextStyle labelLarge(Color color) => TextStyle(
        fontFamily: _jetBrainsMono,
        fontSize: _labelLargeSize,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.3,
        color: color,
      );

  static TextStyle labelMedium(Color color) => TextStyle(
        fontFamily: _jetBrainsMono,
        fontSize: _labelMediumSize,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.2,
        color: color,
      );

  static TextStyle labelSmall(Color color) => TextStyle(
        fontFamily: _jetBrainsMono,
        fontSize: _labelSmallSize,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.1,
        color: color,
      );

  static TextStyle buttonText(Color color) => TextStyle(
        fontFamily: _inter,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
        color: color,
      );

  static TextStyle buttonTextSmall(Color color) => TextStyle(
        fontFamily: _inter,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
        color: color,
      );

  // Form labels & hints
  static TextStyle formLabel(Color color) => TextStyle(
        fontFamily: _inter,
        fontSize: _titleSmallSize,
        fontWeight: FontWeight.w500,
        color: color,
      );

  static TextStyle inputHint(Color color) => TextStyle(
        fontFamily: _inter,
        fontSize: _bodyMediumSize,
        fontWeight: FontWeight.w400,
        color: color,
      );

  // Status indicators
  static TextStyle statusChip(Color color) => TextStyle(
        fontFamily: _jetBrainsMono,
        fontSize: _labelSmallSize,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
        color: color,
      );

  static TextStyle badge(Color color) => TextStyle(
        fontFamily: _jetBrainsMono,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
        color: color,
      );

  // Amounts (monospace for alignment)
  static TextStyle amount(Color color) => TextStyle(
        fontFamily: _jetBrainsMono,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
        color: color,
      );

  static TextStyle amountLarge(Color color) => TextStyle(
        fontFamily: _jetBrainsMono,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3,
        color: color,
      );

  // Error & validation messages
  static TextStyle error(Color color) => TextStyle(
        fontFamily: _inter,
        fontSize: _bodySmallSize,
        fontWeight: FontWeight.w500,
        height: 1.3,
        color: color,
      );

  // Promotional banners
  static TextStyle bannerTitle(Color color) => TextStyle(
        fontFamily: _spaceGrotesk,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        color: color,
      );

  static TextStyle bannerSubtitle(Color color) => TextStyle(
        fontFamily: _inter,
        fontSize: 13,
        fontWeight: FontWeight.w400,
        height: 1.4,
        color: color,
      );

  static TextStyle bannerCta(Color color) => TextStyle(
        fontFamily: _inter,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
        color: color,
      );

  // Brand-specific
  static TextStyle brandTitle(Color color) => TextStyle(
        fontFamily: _spaceGrotesk,
        fontSize: 30,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
        color: color,
      );

  static TextStyle appBarTitle(Color color) => TextStyle(
        fontFamily: _inter,
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
        color: color,
      );

  static TextStyle monoLabel(Color color) => TextStyle(
        fontFamily: _jetBrainsMono,
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.2,
        color: color,
      );

  static TextStyle timeIndicator(Color color) => TextStyle(
        fontFamily: _jetBrainsMono,
        fontSize: 11,
        fontWeight: FontWeight.w400,
        color: color,
      );
}
