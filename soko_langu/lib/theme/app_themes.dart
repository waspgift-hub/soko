import 'package:flutter/material.dart';
import 'app_typography.dart';

// Brand rule (§brand system): BLACK + WHITE canvas with a single GREEN accent
// #00C853 for emphasis (commerce CTAs, links, selection). Green-on-white text
// #00C853 only reaches ~2.2:1, so surface text/icons use Deep Green #009624
// (3.9:1) via SokoColors.brandOnSurface; #00C853 is reserved for fills paired
// with black text (9.4:1). Grays carry only informational hierarchy. `seed`
// stays for API compatibility with theme persistence but never influences the
// rendered palette.
ThemeData buildLightTheme(Color seed) {
  final scheme = const ColorScheme.light(
    primary: Color(0xFF00C853),
    onPrimary: Color(0xFF000000),
    primaryContainer: Color(0xFFE8F5E9),
    onPrimaryContainer: Color(0xFF00210B),
    inversePrimary: Color(0xFF00C853),
    secondary: Color(0xFF1A1A1A),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFE8E8E8),
    onSecondaryContainer: Color(0xFF1A1A1A),
    tertiary: Color(0xFF6B6B6B),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFF0F0F0),
    onTertiaryContainer: Color(0xFF1A1A1A),
    error: Color(0xFFD32F2F),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFFDAD6),
    onErrorContainer: Color(0xFF410002),
    surface: Color(0xFFFFFFFF),
    onSurface: Color(0xFF000000),
    surfaceDim: Color(0xFFE5E5E5),
    surfaceBright: Color(0xFFFFFFFF),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF7F7F7),
    surfaceContainer: Color(0xFFF2F2F2),
    surfaceContainerHigh: Color(0xFFECECEC),
    surfaceContainerHighest: Color(0xFFE5E5E5),
    onSurfaceVariant: Color(0xFF6B6B6B),
    outline: Color(0xFF747474),
    outlineVariant: Color(0xFFE5E5E5),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFF0B0B0B),
    onInverseSurface: Color(0xFFF7F7F7),
  );

  return _buildTheme(scheme);
}

ThemeData buildDarkTheme(Color seed) {
  final scheme = const ColorScheme.dark(
    primary: Color(0xFF00C853),
    onPrimary: Color(0xFF000000),
    primaryContainer: Color(0xFF10381C),
    onPrimaryContainer: Color(0xFFB7F7C9),
    inversePrimary: Color(0xFF009624),
    secondary: Color(0xFFE8E8E8),
    onSecondary: Color(0xFF000000),
    secondaryContainer: Color(0xFF2A2A2A),
    onSecondaryContainer: Color(0xFFEBEBEB),
    tertiary: Color(0xFFBEBEBE),
    onTertiary: Color(0xFF000000),
    tertiaryContainer: Color(0xFF333333),
    onTertiaryContainer: Color(0xFFF0F0F0),
    error: Color(0xFFD32F2F),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFF8C1D18),
    onErrorContainer: Color(0xFFFFDAD6),
    surface: Color(0xFF0B0B0B),
    onSurface: Color(0xFFFFFFFF),
    surfaceDim: Color(0xFF0B0B0B),
    surfaceBright: Color(0xFF1E1E1E),
    surfaceContainerLowest: Color(0xFF070707),
    surfaceContainerLow: Color(0xFF121212),
    surfaceContainer: Color(0xFF161616),
    surfaceContainerHigh: Color(0xFF1C1C1C),
    surfaceContainerHighest: Color(0xFF232323),
    onSurfaceVariant: Color(0xFFA7A7A7),
    outline: Color(0xFF8E8E93),
    outlineVariant: Color(0xFF292929),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFFF7F7F7),
    onInverseSurface: Color(0xFF0B0B0B),
  );

  return _buildTheme(scheme);
}

/// Builds the full branded theme from any [ColorScheme].
///
/// Used by the static brand themes and by the M3 Expressive dynamic-color
/// path (see dynamic_scheme.dart), which passes a harmonized [brand].
ThemeData buildThemeFromScheme(ColorScheme scheme, {SokoColors? brand}) =>
    _buildTheme(scheme, brandOverride: brand);

ThemeData _buildTheme(ColorScheme scheme, {SokoColors? brandOverride}) {
  final isDark = scheme.brightness == Brightness.dark;

  // Surfaces prefer solid, opaque fills for legibility; glass
  // translucency is retained only for the floating nav bar and
  // bottom sheets where layering is intentional.
  final cardSurface = isDark ? scheme.surfaceContainerLow : scheme.surface;
  final sheetSurface = isDark ? scheme.surfaceContainerLow : scheme.surface;

  final brand = brandOverride ??
      SokoColors(
        commerce: const Color(0xFF00C853),
        onCommerce: const Color(0xFF000000),
        successText: isDark ? const Color(0xFF00C853) : const Color(0xFF009624),
        warning: const Color(0xFFF59E0B),
        brandOnSurface: isDark ? const Color(0xFF00C853) : const Color(0xFF009624),
        deepGreen: const Color(0xFF009624),
      );

  final base = ThemeData(
    useMaterial3: true,
    brightness: scheme.brightness,
    colorScheme: scheme,
    extensions: [brand],
  );

  return base.copyWith(
    colorScheme: scheme,
    extensions: [brand],
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
        // PRIMARY BUTTON — black (light) / white (dark) for authority.
        backgroundColor: isDark ? Colors.white : Colors.black,
        foregroundColor: isDark ? Colors.black : Colors.white,
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
        // Same authority treatment as Elevated for consistency.
        backgroundColor: isDark ? Colors.white : Colors.black,
        foregroundColor: isDark ? Colors.black : Colors.white,
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
        // SECONDARY BUTTON — outlined neutral, not green.
        foregroundColor: scheme.onSurface,
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
      fillColor: isDark ? scheme.surfaceContainerLow : const Color(0xFFF7F7F7),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.outlineVariant),
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
      backgroundColor: isDark ? scheme.surfaceContainerLow : const Color(0xFFF7F7F7),
      selectedColor: scheme.primary.withValues(alpha: 0.15),
      labelStyle: TextStyle(color: scheme.onSurface),
      secondaryLabelStyle: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
      side: BorderSide(color: scheme.outlineVariant),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    ),

    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 0.5,
      space: 1,
    ),

    snackBarTheme: SnackBarThemeData(
      backgroundColor: isDark ? scheme.surfaceContainerHigh : scheme.surface,
      contentTextStyle: TextStyle(color: scheme.onSurface),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      actionTextColor: scheme.primary,
      width: 440,
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: cardSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      elevation: 8,
    ),

    cardTheme: CardThemeData(
      color: cardSurface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
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
        backgroundColor: WidgetStatePropertyAll(cardSurface),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: scheme.outlineVariant),
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
      backgroundColor: sheetSurface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      elevation: 8,
    ),

    popupMenuTheme: PopupMenuThemeData(
      color: cardSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      elevation: 4,
    ),

    drawerTheme: DrawerThemeData(
      backgroundColor: sheetSurface,
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
      backgroundColor: cardSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),

    datePickerTheme: DatePickerThemeData(
      backgroundColor: cardSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      headerBackgroundColor: scheme.primary,
      headerForegroundColor: scheme.onPrimary,
    ),

    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: isDark ? scheme.inverseSurface : const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: TextStyle(
        color: isDark ? scheme.onInverseSurface : Colors.white,
        fontSize: 12,
      ),
    ),
  );
}

/// Brand tokens beyond the Material [ColorScheme].
///
/// [commerce] is the single #00C853 fill for marketplace CTAs (buy/sell/pay)
/// and always pairs with black [onCommerce] text (9.4:1). [successText] and
/// [brandOnSurface] are the surface-legible green tones — light mode Deep
/// Green #009624 (3.9:1) because #00C853 text on white only reaches ~2.2:1.
@immutable
class SokoColors extends ThemeExtension<SokoColors> {
  /// #00C853 commerce fill (buy/sell/pay, selected states).
  final Color commerce;

  /// Text/icons placed on [commerce] fills (black).
  final Color onCommerce;

  /// Green for success text/icons sitting on a plain surface.
  final Color successText;

  /// #F59E0B warning/pending accents.
  final Color warning;

  /// Green legible as text/icons on a plain surface (light: #009624, dark: #00C853).
  final Color brandOnSurface;

  /// Deep green #009624 for tints, charts and separators.
  final Color deepGreen;

  const SokoColors({
    required this.commerce,
    required this.onCommerce,
    required this.successText,
    required this.warning,
    required this.brandOnSurface,
    required this.deepGreen,
  });

  /// Resolves the active [SokoColors]. Falls back to plain green values so a
  /// widget never crashes on an unextended theme.
  static SokoColors of(BuildContext context) =>
      Theme.of(context).extension<SokoColors>() ??
      const SokoColors(
        commerce: Color(0xFF00C853),
        onCommerce: Color(0xFF000000),
        successText: Color(0xFF009624),
        warning: Color(0xFFF59E0B),
        brandOnSurface: Color(0xFF009624),
        deepGreen: Color(0xFF009624),
      );

  @override
  SokoColors copyWith({
    Color? commerce,
    Color? onCommerce,
    Color? successText,
    Color? warning,
    Color? brandOnSurface,
    Color? deepGreen,
  }) {
    return SokoColors(
      commerce: commerce ?? this.commerce,
      onCommerce: onCommerce ?? this.onCommerce,
      successText: successText ?? this.successText,
      warning: warning ?? this.warning,
      brandOnSurface: brandOnSurface ?? this.brandOnSurface,
      deepGreen: deepGreen ?? this.deepGreen,
    );
  }

  @override
  SokoColors lerp(ThemeExtension<SokoColors>? other, double t) {
    if (other is! SokoColors) return this;
    return SokoColors(
      commerce: Color.lerp(commerce, other.commerce, t)!,
      onCommerce: Color.lerp(onCommerce, other.onCommerce, t)!,
      successText: Color.lerp(successText, other.successText, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      brandOnSurface: Color.lerp(brandOnSurface, other.brandOnSurface, t)!,
      deepGreen: Color.lerp(deepGreen, other.deepGreen, t)!,
    );
  }
}
