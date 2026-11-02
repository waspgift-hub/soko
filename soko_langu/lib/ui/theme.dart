import 'package:flutter/material.dart';

import 'tokens.dart';

ThemeData buildUiTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: UiColors.accent,
    primary: UiColors.accent,
    onPrimary: UiColors.onAccent,
    surface: UiColors.surface,
    onSurface: UiColors.ink,
    error: UiColors.danger,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: UiColors.surface,
    appBarTheme: const AppBarTheme(
      backgroundColor: UiColors.surface,
      foregroundColor: UiColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    cardTheme: const CardThemeData(
      color: UiColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: UiColors.line),
        borderRadius: BorderRadius.all(Radius.circular(UiRadius.control)),
      ),
    ),
    dividerTheme: const DividerThemeData(color: UiColors.line, space: 1),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: UiColors.accent,
        foregroundColor: UiColors.onAccent,
        elevation: 0,
        minimumSize: const Size.fromHeight(48),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(UiRadius.control)),
        ),
      ),
    ),
    textTheme: const TextTheme(
      titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: UiColors.ink),
      titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: UiColors.ink),
      bodyMedium: TextStyle(fontSize: 14, color: UiColors.ink),
      bodySmall: TextStyle(fontSize: 12, color: UiColors.muted),
    ),
  );
}
