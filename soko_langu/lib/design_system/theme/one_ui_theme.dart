import 'package:flutter/material.dart';
import '../tokens/one_ui_tokens.dart';

ThemeData buildOneUiLightTheme() {
  final colorScheme = ColorScheme.light(
    primary: OneUiColors.accent,
    onPrimary: OneUiColors.textOnAccent,
    primaryContainer: OneUiColors.accentContainer,
    onPrimaryContainer: OneUiColors.accent,
    secondary: OneUiColors.textPrimary,
    onSecondary: OneUiColors.surface,
    surface: OneUiColors.surface,
    onSurface: OneUiColors.textPrimary,
    surfaceContainerHighest: OneUiColors.surfaceContainer,
    surfaceContainerHigh: OneUiColors.surfaceVariant,
    surfaceContainer: OneUiColors.surfaceVariant,
    surfaceContainerLow: OneUiColors.surfaceContainer,
    surfaceContainerLowest: OneUiColors.surface,
    error: OneUiColors.error,
    onError: OneUiColors.textOnAccent,
    outline: OneUiColors.outline,
    outlineVariant: OneUiColors.border,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: OneUiColors.background,
    
    // AppBar - Samsung style clean
    appBarTheme: AppBarTheme(
      backgroundColor: OneUiColors.background,
      foregroundColor: OneUiColors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        color: OneUiColors.textPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
      iconTheme: IconThemeData(color: OneUiColors.textPrimary),
    ),
    
    // Cards - rounded, clean
    cardTheme: CardThemeData(
      color: OneUiColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(OneUiRadius.lg),
        side: BorderSide(color: OneUiColors.border, width: 0.5),
      ),
    ),
    
    // Buttons
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: OneUiColors.accent,
        foregroundColor: OneUiColors.textOnAccent,
        elevation: 0,
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OneUiRadius.full),
        ),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
      ),
    ),
    
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: OneUiColors.surface,
        foregroundColor: OneUiColors.textPrimary,
        elevation: 0,
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OneUiRadius.full),
          side: BorderSide(color: OneUiColors.border),
        ),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          letterSpacing: -0.2,
        ),
      ),
    ),
    
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: OneUiColors.accent,
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          letterSpacing: -0.2,
        ),
      ),
    ),
    
    // Input fields
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: OneUiColors.surfaceVariant,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(OneUiRadius.md),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(OneUiRadius.md),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(OneUiRadius.md),
        borderSide: BorderSide(color: OneUiColors.accent, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: OneUiSpacing.lg, vertical: OneUiSpacing.md),
      hintStyle: TextStyle(color: OneUiColors.textTertiary, fontSize: 15),
    ),
    
    // List tiles
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: OneUiSpacing.xl, vertical: OneUiSpacing.xs),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(OneUiRadius.md),
      ),
    ),
    
    // Bottom Navigation
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: OneUiColors.surface,
      selectedItemColor: OneUiColors.accent,
      unselectedItemColor: OneUiColors.textTertiary,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
      selectedLabelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      unselectedLabelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
    ),
    
    // Divider
    dividerTheme: DividerThemeData(
      color: OneUiColors.divider,
      thickness: 1,
      space: 1,
    ),
    
    // Page transitions - smooth like One UI
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
      },
    ),
    
    // Typography
    textTheme: TextTheme(
      displayLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: OneUiColors.textPrimary, letterSpacing: -0.5),
      displayMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: OneUiColors.textPrimary, letterSpacing: -0.5),
      displaySmall: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: OneUiColors.textPrimary, letterSpacing: -0.3),
      headlineLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: OneUiColors.textPrimary, letterSpacing: -0.3),
      headlineMedium: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: OneUiColors.textPrimary, letterSpacing: -0.2),
      headlineSmall: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: OneUiColors.textPrimary, letterSpacing: -0.2),
      titleLarge: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: OneUiColors.textPrimary, letterSpacing: -0.2),
      titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: OneUiColors.textPrimary, letterSpacing: -0.1),
      titleSmall: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: OneUiColors.textPrimary, letterSpacing: -0.1),
      bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, color: OneUiColors.textPrimary, height: 1.5),
      bodyMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w400, color: OneUiColors.textPrimary, height: 1.5),
      bodySmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: OneUiColors.textSecondary, height: 1.5),
      labelLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: OneUiColors.textPrimary, letterSpacing: -0.1),
      labelMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: OneUiColors.textPrimary, letterSpacing: -0.1),
      labelSmall: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: OneUiColors.textSecondary, letterSpacing: -0.1),
    ),
  );
}

ThemeData buildOneUiDarkTheme() {
  final colorScheme = ColorScheme.dark(
    primary: OneUiColors.accent,
    onPrimary: OneUiColors.textOnAccent,
    primaryContainer: Color(0xFF1A3D2A),
    onPrimaryContainer: OneUiColors.accent,
    surface: OneUiColors.darkSurface,
    onSurface: OneUiColors.darkTextPrimary,
    surfaceContainerHighest: OneUiColors.darkSurfaceContainer,
    error: OneUiColors.error,
    onError: OneUiColors.textOnAccent,
    outline: OneUiColors.darkBorder,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: OneUiColors.darkBackground,
    appBarTheme: AppBarTheme(
      backgroundColor: OneUiColors.darkBackground,
      foregroundColor: OneUiColors.darkTextPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        color: OneUiColors.darkTextPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
    ),
    cardTheme: CardThemeData(
      color: OneUiColors.darkSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(OneUiRadius.lg),
        side: BorderSide(color: OneUiColors.darkBorder, width: 0.5),
      ),
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: OneUiColors.darkSurface,
      selectedItemColor: OneUiColors.accent,
      unselectedItemColor: OneUiColors.darkTextSecondary,
      type: BottomNavigationBarType.fixed,
    ),
  );
}
