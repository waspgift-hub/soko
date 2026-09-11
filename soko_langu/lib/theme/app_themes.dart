import 'package:flutter/material.dart';
import 'app_typography.dart';

// Brand rule: Soko Vibe green accent for emphasis (buttons, links, selection),
// white canvas in light mode and black canvas in dark mode. Grays carry only
// informational hierarchy. `seed` stays for API compatibility with theme
// persistence but never influences the rendered palette.
ThemeData buildLightTheme(Color seed) {
  final scheme = const ColorScheme.light(
    primary: Color(0xFF2D6A4F),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFD7EBDD),
    onPrimaryContainer: Color(0xFF0B2E21),
    inversePrimary: Color(0xFFB8B8B8),
    secondary: Color(0xFF3B3B3B),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFEBEBEB),
    onSecondaryContainer: Color(0xFF1C1C1C),
    tertiary: Color(0xFF5C5C5C),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFF0F0F0),
    onTertiaryContainer: Color(0xFF1C1C1C),
    error: Color(0xFFBA1A1A),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFFDAD6),
    onErrorContainer: Color(0xFF410002),
    surface: Color(0xFFFAFAFA),
    onSurface: Color(0xFF09090B),
    surfaceDim: Color(0xFFD9D9D9),
    surfaceBright: Color(0xFFFAFAFA),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF4F4F5),
    surfaceContainer: Color(0xFFECECEE),
    surfaceContainerHigh: Color(0xFFE4E4E7),
    surfaceContainerHighest: Color(0xFFD4D4D8),
    onSurfaceVariant: Color(0xFF52525B),
    outline: Color(0xFF747474),
    outlineVariant: Color(0xFFE4E4E7),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFF121212),
    onInverseSurface: Color(0xFFF5F5F5),
  );

  return _buildTheme(scheme);
}

ThemeData buildDarkTheme(Color seed) {
  final scheme = const ColorScheme.dark(
    primary: Color(0xFF52B788),
    onPrimary: Color(0xFF052E16),
    primaryContainer: Color(0xFF1B4332),
    onPrimaryContainer: Color(0xFFAFE3C7),
    inversePrimary: Color(0xFF303030),
    secondary: Color(0xFFD6D6D6),
    onSecondary: Color(0xFF000000),
    secondaryContainer: Color(0xFF2A2A2A),
    onSecondaryContainer: Color(0xFFEBEBEB),
    tertiary: Color(0xFFBEBEBE),
    onTertiary: Color(0xFF000000),
    tertiaryContainer: Color(0xFF333333),
    onTertiaryContainer: Color(0xFFF0F0F0),
    error: Color(0xFFF2B8B5),
    onError: Color(0xFF601410),
    errorContainer: Color(0xFF8C1D18),
    onErrorContainer: Color(0xFFFFDAD6),
    surface: Color(0xFF000000),
    onSurface: Color(0xFFF4F4F5),
    surfaceDim: Color(0xFF0D0D0D),
    surfaceBright: Color(0xFF1F1F1F),
    surfaceContainerLowest: Color(0xFF0A0A0A),
    surfaceContainerLow: Color(0xFF121212),
    surfaceContainer: Color(0xFF171717),
    surfaceContainerHigh: Color(0xFF1E1E1E),
    surfaceContainerHighest: Color(0xFF27272A),
    onSurfaceVariant: Color(0xFFA1A1AA),
    outline: Color(0xFF8E8E93),
    outlineVariant: Color(0xFF2E2E32),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFFF4F4F5),
    onInverseSurface: Color(0xFF0A0A0A),
  );

  return _buildTheme(scheme);
}

ThemeData _buildTheme(ColorScheme scheme) {
  final isDark = scheme.brightness == Brightness.dark;
  final glassBorder = isDark
      ? const Color(0x2AFFFFFF)
      : const Color(0x08000000);

  final glassCard = isDark
      ? const Color(0xFF171717).withValues(alpha: 0.65)
      : const Color(0xFFFFFFFF).withValues(alpha: 0.82);

  final glassSheet = isDark
      ? const Color(0xFF121212).withValues(alpha: 0.75)
      : const Color(0xFFFFFFFF).withValues(alpha: 0.88);

  final base = ThemeData(
    useMaterial3: true,
    brightness: scheme.brightness,
    colorScheme: scheme,
  );

  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    textTheme: AppTypography.apply(base.textTheme, scheme),
    // Android 12+ sparkle ripple + consistent material transitions for the
    // few non-GoRouter Navigator.push call sites.
    splashFactory: InkSparkle.splashFactory,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
      },
    ),

    iconTheme: IconThemeData(
      color: scheme.onSurface.withValues(alpha: 0.75),
    ),

    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: const TextStyle(
        fontFamily: 'Inter',
        fontSize: 17,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ).copyWith(color: scheme.onSurface),
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
    ),

    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: isDark
          ? const Color(0xFF121212).withValues(alpha: 0.75)
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
          ? const Color(0xFF121212).withValues(alpha: 0.75)
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
          borderRadius: BorderRadius.circular(12),
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
          borderRadius: BorderRadius.circular(12),
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
          borderRadius: BorderRadius.circular(12),
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
          ? const Color(0xFF171717).withValues(alpha: 0.55)
          : const Color(0xFFF4F4F5).withValues(alpha: 0.7),
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
          ? const Color(0xFF171717).withValues(alpha: 0.55)
          : const Color(0xFFF4F4F5).withValues(alpha: 0.7),
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
          ? const Color(0xFF2E2E32)
          : const Color(0xFFE4E4E7),
      thickness: 0.5,
      space: 1,
    ),

    snackBarTheme: SnackBarThemeData(
      backgroundColor: isDark
          ? const Color(0xFF1E1E1E).withValues(alpha: 0.75)
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
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.35)),
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
            ? const Color(0xFF1E1E1E).withValues(alpha: 0.85)
            : const Color(0xFF1A1A1A).withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: TextStyle(
        color: isDark ? Colors.white : scheme.onSurface,
        fontSize: 12,
      ),
    ),
  );
}
