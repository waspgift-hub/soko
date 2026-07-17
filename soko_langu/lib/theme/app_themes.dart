import 'package:flutter/material.dart';
import 'app_typography.dart';

ThemeData buildLightTheme(Color seed) {
  final scheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: Brightness.light,
  ).copyWith(
    surface: const Color(0xFFF8F9FE),
    surfaceContainerLow: const Color(0xFFF0F1F8),
    surfaceContainer: const Color(0xFFE8E9F0),
    surfaceContainerHigh: const Color(0xFFDEDFE8),
    surfaceContainerHighest: const Color(0xFFD0D1DC),
    onSurface: const Color(0xFF0A0E1A),
    onSurfaceVariant: const Color(0xFF494D5E),
    outlineVariant: const Color(0xFFE0E1EC),
  );

  return _buildTheme(scheme);
}

ThemeData buildDarkTheme(Color seed) {
  final scheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: Brightness.dark,
  ).copyWith(
    surface: const Color(0xFF0A0E1A),
    surfaceContainerLow: const Color(0xFF121729),
    surfaceContainer: const Color(0xFF1A2040),
    surfaceContainerHigh: const Color(0xFF222952),
    surfaceContainerHighest: const Color(0xFF2A3360),
    onSurface: const Color(0xFFF0F1F8),
    onSurfaceVariant: const Color(0xFFB0B5C8),
    outlineVariant: const Color(0xFF2A2E4A),
  );

  return _buildTheme(scheme);
}

ThemeData _buildTheme(ColorScheme scheme) {
  final isDark = scheme.brightness == Brightness.dark;
  final glassBorder = isDark
      ? const Color(0x2AFFFFFF)
      : const Color(0x08000000);

  final glassCard = isDark
      ? const Color(0xFF1A2040).withValues(alpha: 0.65)
      : const Color(0xFFFFFFFF).withValues(alpha: 0.82);

  final glassSheet = isDark
      ? const Color(0xFF121729).withValues(alpha: 0.75)
      : const Color(0xFFFFFFFF).withValues(alpha: 0.88);

  final base = ThemeData(
    useMaterial3: true,
    brightness: scheme.brightness,
    colorScheme: scheme,
  );

  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: Colors.transparent,
    textTheme: AppTypography.apply(base.textTheme, scheme),

    iconTheme: IconThemeData(
      color: scheme.onSurface.withValues(alpha: 0.75),
    ),

    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: GoogleFontsPlus.inter(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
        color: scheme.onSurface,
      ),
      scrolledUnderElevation: 0,
    ),

    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: isDark
          ? const Color(0xFF121729).withValues(alpha: 0.75)
          : const Color(0xFFFFFFFF).withValues(alpha: 0.82),
      indicatorColor: scheme.primary.withValues(alpha: 0.15),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: scheme.primary,
          );
        }
        return TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: scheme.onSurface.withValues(alpha: 0.45),
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return IconThemeData(color: scheme.primary, size: 24);
        }
        return IconThemeData(
          color: scheme.onSurface.withValues(alpha: 0.45),
          size: 24,
        );
      }),
      elevation: 0,
      shadowColor: Colors.transparent,
      height: 64,
    ),

    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: isDark
          ? const Color(0xFF121729).withValues(alpha: 0.75)
          : const Color(0xFFFFFFFF).withValues(alpha: 0.82),
      selectedItemColor: scheme.primary,
      unselectedItemColor: scheme.onSurface.withValues(alpha: 0.45),
      type: BottomNavigationBarType.fixed,
      elevation: 0,
      selectedLabelStyle: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelStyle: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: scheme.onSurface.withValues(alpha: 0.45),
      ),
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 15,
          letterSpacing: 0.2,
        ),
        elevation: 0,
        shadowColor: Colors.transparent,
      ),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.primary,
        side: BorderSide(color: scheme.outlineVariant),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: scheme.primary,
        textStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark
          ? const Color(0xFF1A2040).withValues(alpha: 0.55)
          : const Color(0xFFF0F1F8).withValues(alpha: 0.7),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.error, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.error, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 14,
      ),
      labelStyle: TextStyle(
        color: scheme.onSurfaceVariant,
        fontWeight: FontWeight.w500,
      ),
      hintStyle: TextStyle(
        color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
      ),
      prefixIconColor: scheme.onSurfaceVariant.withValues(alpha: 0.6),
      suffixIconColor: scheme.onSurfaceVariant.withValues(alpha: 0.6),
    ),

    chipTheme: ChipThemeData(
      backgroundColor: isDark
          ? const Color(0xFF1A2040).withValues(alpha: 0.55)
          : const Color(0xFFF0F1F8).withValues(alpha: 0.7),
      selectedColor: scheme.primary.withValues(alpha: 0.12),
      labelStyle: TextStyle(color: scheme.onSurface),
      secondaryLabelStyle: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    ),

    dividerTheme: DividerThemeData(
      color: isDark
          ? const Color(0xFF2A2E4A)
          : const Color(0xFFE0E1EC),
      thickness: 0.5,
      space: 1,
    ),

    snackBarTheme: SnackBarThemeData(
      backgroundColor: isDark
          ? const Color(0xFF222952).withValues(alpha: 0.75)
          : const Color(0xFFFFFFFF).withValues(alpha: 0.88),
      contentTextStyle: TextStyle(color: scheme.onSurface),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: glassBorder),
      ),
      actionTextColor: scheme.primary,
      width: 440,
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: glassCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      elevation: 8,
    ),

    cardTheme: CardThemeData(
      color: glassCard,
      elevation: 0,
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
    ),

    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    ),

    badgeTheme: BadgeThemeData(
      backgroundColor: scheme.primary,
      textColor: scheme.onPrimary,
      textStyle: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
      ),
    ),

    sliderTheme: SliderThemeData(
      activeTrackColor: scheme.primary,
      inactiveTrackColor: scheme.surfaceContainerHighest,
      thumbColor: scheme.primary,
      overlayColor: scheme.primary.withValues(alpha: 0.12),
      trackHeight: 4,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
    ),

    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return scheme.primary;
        return scheme.onSurface.withValues(alpha: 0.25);
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return scheme.primary.withValues(alpha: 0.3);
        }
        return scheme.onSurface.withValues(alpha: 0.08);
      }),
    ),

    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: scheme.surfaceContainerHighest,
    ),

    tabBarTheme: TabBarThemeData(
      labelColor: scheme.primary,
      unselectedLabelColor: scheme.onSurface.withValues(alpha: 0.45),
      indicatorColor: scheme.primary,
      labelStyle: const TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 14,
      ),
      unselectedLabelStyle: const TextStyle(
        fontWeight: FontWeight.w500,
        fontSize: 14,
      ),
    ),

    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(glassCard),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: glassBorder),
          ),
        ),
        elevation: WidgetStatePropertyAll(4),
      ),
    ),

    listTileTheme: ListTileThemeData(
      tileColor: Colors.transparent,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      titleTextStyle: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: scheme.onSurface,
      ),
      subtitleTextStyle: TextStyle(
        fontSize: 13,
        color: scheme.onSurfaceVariant,
      ),
      leadingAndTrailingTextStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: scheme.onSurfaceVariant,
      ),
    ),

    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: glassSheet,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      elevation: 8,
    ),

    popupMenuTheme: PopupMenuThemeData(
      color: glassCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: glassBorder),
      ),
      elevation: 4,
    ),

    drawerTheme: DrawerThemeData(
      backgroundColor: glassSheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
      ),
    ),

    expansionTileTheme: ExpansionTileThemeData(
      iconColor: scheme.onSurfaceVariant,
      collapsedIconColor: scheme.onSurfaceVariant,
      shape: Border(),
      collapsedShape: Border(),
    ),

    timePickerTheme: TimePickerThemeData(
      backgroundColor: glassCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
    ),

    datePickerTheme: DatePickerThemeData(
      backgroundColor: glassCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      headerBackgroundColor: scheme.primary,
      headerForegroundColor: scheme.onPrimary,
    ),

    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF222952).withValues(alpha: 0.85)
            : const Color(0xFF1A1A2E).withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: TextStyle(
        color: isDark ? Colors.white : Colors.white,
        fontSize: 12,
      ),
    ),
  );
}

class GoogleFontsPlus {
  static TextStyle inter({
    double? fontSize,
    FontWeight? fontWeight,
    double? letterSpacing,
    Color? color,
  }) {
    return TextStyle(
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      color: color,
    );
  }
}
