import 'package:flutter/material.dart';
import 'app_typography.dart';
import 'neumorphic.dart';
import 'soko_palette.dart';

// Brand rule: EMERALD GREEN + WHITE + BLACK + SOFT GREY, with amber reserved
// for promotions. The canvas is #F7F8F7 / #000000 and cards are #FFFFFF /
// #101713. Every value comes from SokoPalette so screens cannot drift onto
// "another green". `seed` stays for API compatibility with theme persistence
// but never influences the rendered palette.
ThemeData buildLightTheme(Color seed) {
  final scheme = const ColorScheme.light(
    primary: SokoPalette.lightPrimary,
    onPrimary: SokoPalette.onLightPrimary,
    primaryContainer: SokoPalette.lightPrimaryLight,
    onPrimaryContainer: SokoPalette.lightPrimaryDark,
    inversePrimary: SokoPalette.darkPrimary,
    secondary: SokoPalette.lightPrimaryDark,
    onSecondary: SokoPalette.onLightPrimary,
    secondaryContainer: SokoPalette.lightPrimaryLight,
    onSecondaryContainer: SokoPalette.lightPrimaryDark,
    tertiary: SokoPalette.lightTextSecondary,
    onTertiary: SokoPalette.onLightPrimary,
    tertiaryContainer: SokoPalette.lightDivider,
    onTertiaryContainer: SokoPalette.lightTextPrimary,
    error: SokoPalette.lightError,
    onError: SokoPalette.onLightPrimary,
    errorContainer: Color(0xFFFBE9E7),
    onErrorContainer: Color(0xFF7A1710),
    surface: SokoPalette.lightCard,
    onSurface: SokoPalette.lightTextPrimary,
    surfaceDim: Color(0xFFEDF0ED),
    surfaceBright: SokoPalette.lightCard,
    surfaceContainerLowest: SokoPalette.lightCard,
    surfaceContainerLow: Color(0xFFFBFCFB),
    surfaceContainer: SokoPalette.lightSecondaryBackground,
    surfaceContainerHigh: SokoPalette.lightDivider,
    surfaceContainerHighest: SokoPalette.lightBorder,
    onSurfaceVariant: SokoPalette.lightTextSecondary,
    // Control outlines must reach 3:1 against the card, so they use the
    // secondary text tone — the decorative hairline stays in outlineVariant.
    outline: SokoPalette.lightTextSecondary,
    outlineVariant: SokoPalette.lightBorder,
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: SokoPalette.lightTextPrimary,
    onInverseSurface: SokoPalette.lightBackground,
  );

  return _buildTheme(scheme);
}

ThemeData buildDarkTheme(Color seed) {
  final scheme = const ColorScheme.dark(
    primary: SokoPalette.darkPrimary,
    onPrimary: SokoPalette.onDarkPrimary,
    primaryContainer: SokoPalette.darkPrimaryLight,
    onPrimaryContainer: Color(0xFFA7EBC2),
    inversePrimary: SokoPalette.lightPrimary,
    secondary: SokoPalette.darkPrimaryDark,
    onSecondary: SokoPalette.onDarkPrimary,
    secondaryContainer: Color(0xFF16301F),
    onSecondaryContainer: Color(0xFFC9F5D9),
    tertiary: SokoPalette.darkTextSecondary,
    onTertiary: SokoPalette.onDarkPrimary,
    tertiaryContainer: SokoPalette.darkSurfaceSecondary,
    onTertiaryContainer: SokoPalette.darkTextPrimary,
    error: SokoPalette.darkError,
    onError: Color(0xFF2A0808),
    errorContainer: Color(0xFF4A1310),
    onErrorContainer: Color(0xFFFFDAD6),
    surface: SokoPalette.darkSurface,
    onSurface: SokoPalette.darkTextPrimary,
    surfaceDim: SokoPalette.darkBackground,
    surfaceBright: SokoPalette.darkSurfaceSecondary,
    surfaceContainerLowest: SokoPalette.darkBackground,
    surfaceContainerLow: Color(0xFF0B100D),
    surfaceContainer: SokoPalette.darkSurfaceSecondary,
    surfaceContainerHigh: SokoPalette.darkSurfaceSecondary,
    surfaceContainerHighest: SokoPalette.darkBorder,
    onSurfaceVariant: SokoPalette.darkTextSecondary,
    outline: SokoPalette.darkTextDisabled,
    outlineVariant: SokoPalette.darkDivider,
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: SokoPalette.darkTextPrimary,
    onInverseSurface: SokoPalette.lightTextPrimary,
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

  // Flat-first canvas (see surface_policy.dart): the canvas and every content
  // surface are FLAT — pure white / near-black with a hairline edge. The
  // soft-UI element base (Neu.base) is deliberately *not* used here, because a
  // soft-UI canvas would leave the flat 90% looking grey-on-grey and give the
  // soft 10% (CTAs, FAB, nav bar, input wells) nothing to contrast against.
  // The flat tokens are the single source of truth so decorated surfaces and
  // the theme canvas cannot drift apart.
  final flatCanvas = Neu.canvas(scheme.brightness);
  final flatFill = Neu.flatFill(scheme.brightness);
  final neuGroove = Neu.grooveColor(scheme.brightness);

  // Recessed fill for the soft-UI input wells. The raised element base is
  // resolved by the widgets themselves (Neu.base) so a control can tint it.
  final neuInset = Neu.insetBase(scheme.brightness);
  final brand =
      brandOverride ??
      SokoColors(
        commerce: isDark ? SokoPalette.darkPrimary : SokoPalette.lightPrimary,
        onCommerce: isDark ? SokoPalette.onDarkPrimary : SokoPalette.onLightPrimary,
        successText: isDark ? SokoPalette.darkSuccess : SokoPalette.lightSuccess,
        warning: isDark ? SokoPalette.darkWarning : SokoPalette.lightWarning,
        brandOnSurface: isDark ? SokoPalette.darkPrimary : SokoPalette.lightPrimary,
        deepGreen: isDark ? SokoPalette.darkPrimaryDark : SokoPalette.lightPrimaryDark,
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
    // FLAT canvas. Soft-UI is additive here, not foundational.
    scaffoldBackgroundColor: flatCanvas,
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
      // Brand rule: every icon that doesn't opt into a semantic color
      // (error/warning) inherits the surface-legible brand green — #0B6B3A in
      // light mode, #32B86C in dark — instead of a neutral gray.
      color: brand.brandOnSurface,
    ),

    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: scheme.onSurface,
      // Header icons (back, actions) render in brand green while the title
      // text stays onSurface for readability.
      iconTheme: IconThemeData(color: brand.brandOnSurface),
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
      backgroundColor: flatFill,
      indicatorColor: scheme.primary.withValues(alpha: 0.12),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: scheme.primary);
        }
        // Unselected tabs are secondary content, not a faded brand green — a
        // green-on-green row made "selected" hard to pick out of the bar.
        return TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant);
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return IconThemeData(color: scheme.primary, size: 24);
        }
        return IconThemeData(color: scheme.onSurfaceVariant, size: 24);
      }),
      elevation: 0,
      shadowColor: Colors.transparent,
      height: 64,
    ),

    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: flatFill,
      selectedItemColor: scheme.primary,
      unselectedItemColor: scheme.onSurfaceVariant,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
      selectedLabelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
      unselectedLabelStyle: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: scheme.onSurfaceVariant,
      ),
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        // PRIMARY CTA — the green commerce accent. This is one of the soft-UI
        // roles, so it carries a hue-tinted glow rather than a neutral drop
        // shadow; that glow is what separates it from the flat 90%. The full
        // dual-shadow treatment lives on DsButton, which is the design-system
        // CTA — this theme only covers legacy ElevatedButton call sites.
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, letterSpacing: 0.2),
        elevation: 2,
        shadowColor: Color.lerp(
          scheme.primary,
          Colors.black,
          0.25,
        )!.withValues(alpha: isDark ? 0.45 : 0.2),
      ),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        // Same accent authority as Elevated.
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        elevation: 0,
        shadowColor: Colors.transparent,
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        // SECONDARY BUTTON — transparent with a primary-green edge and label,
        // exactly one visual step below the filled CTA.
        foregroundColor: scheme.primary,
        backgroundColor: Colors.transparent,
        side: BorderSide(color: scheme.primary, width: 1.2),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: scheme.primary,
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      // RECESSED input wells — one of the soft-UI roles, so the fill sits a
      // step darker than the flat canvas with a hairline groove. Focus swaps
      // the groove to the green commerce accent.
      filled: true,
      fillColor: neuInset,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: neuGroove, width: 0.8),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: neuGroove, width: 0.8),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: neuGroove, width: 0.8),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.error, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.error, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      labelStyle: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w500),
      hintStyle: TextStyle(color: scheme.onSurfaceVariant),
      prefixIconColor: scheme.primary,
      suffixIconColor: scheme.primary,
    ),

    chipTheme: ChipThemeData(
      // FLAT chips. A selected filter uses the light-green container (not the
      // primary fill) so the chip label keeps AA contrast in both themes.
      backgroundColor: scheme.surfaceContainerHigh,
      selectedColor: scheme.primaryContainer,
      labelStyle: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w500),
      secondaryLabelStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
      side: BorderSide(color: scheme.outlineVariant),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    ),

    dividerTheme: DividerThemeData(color: neuGroove, thickness: 0.5, space: 1),

    snackBarTheme: SnackBarThemeData(
      backgroundColor: flatFill,
      contentTextStyle: TextStyle(color: scheme.onSurface),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: neuGroove),
      ),
      actionTextColor: scheme.primary,
      width: 440,
      elevation: 0,
    ),

    dialogTheme: DialogThemeData(
      // FLAT overlay — raised by an overlay-strength flat shadow, not the
      // soft-UI light/shade pair.
      backgroundColor: flatFill,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: neuGroove),
      ),
      elevation: 0,
      shadowColor: Colors.transparent,
    ),

    cardTheme: CardThemeData(
      // FLAT content card — this is the workhorse surface of the flat 90%, and
      // the single biggest change from the previous soft-UI-everywhere theme.
      color: flatFill,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: neuGroove, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
    ),

    floatingActionButtonTheme: FloatingActionButtonThemeData(
      // SOFT — floatingAction is one of the soft-UI roles. This Flutter version
      // has no shadowColor on FloatingActionButtonThemeData, so a theme-level
      // FAB cannot carry the hue-tinted glow; a genuinely soft FAB must be built
      // with Neu.raisedHue, as the sell FAB in bottom_nav_bar.dart does.
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),

    badgeTheme: BadgeThemeData(
      backgroundColor: scheme.primary,
      textColor: scheme.onPrimary,
      textStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
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
        // A 25% tint made the off thumb nearly invisible; secondary text
        // keeps the control boundary at 3:1.
        return scheme.onSurfaceVariant;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return scheme.primary.withValues(alpha: 0.3);
        }
        return scheme.surfaceContainerHighest;
      }),
    ),

    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: scheme.surfaceContainerHighest,
    ),

    tabBarTheme: TabBarThemeData(
      labelColor: scheme.primary,
      // Unselected tabs are secondary content; a 45% onSurface tint fell
      // below AA on the light canvas.
      unselectedLabelColor: scheme.onSurfaceVariant,
      indicatorColor: scheme.primary,
      labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
    ),

    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(flatFill),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: neuGroove),
          ),
        ),
        elevation: WidgetStatePropertyAll(0),
        shadowColor: WidgetStatePropertyAll(Colors.transparent),
      ),
    ),

    listTileTheme: ListTileThemeData(
      tileColor: Colors.transparent,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      titleTextStyle: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: scheme.onSurface),
      subtitleTextStyle: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
      leadingAndTrailingTextStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: scheme.onSurfaceVariant,
      ),
    ),

    bottomSheetTheme: BottomSheetThemeData(
      // FLAT overlay.
      backgroundColor: flatFill,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      elevation: 0,
      shadowColor: Colors.transparent,
    ),

    popupMenuTheme: PopupMenuThemeData(
      color: flatFill,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: neuGroove),
      ),
      elevation: 0,
      shadowColor: Colors.transparent,
    ),

    drawerTheme: DrawerThemeData(
      backgroundColor: flatFill,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
    ),

    expansionTileTheme: ExpansionTileThemeData(
      iconColor: scheme.primary.withValues(alpha: 0.7),
      collapsedIconColor: scheme.primary.withValues(alpha: 0.7),
      shape: Border(),
      collapsedShape: Border(),
    ),

    timePickerTheme: TimePickerThemeData(
      backgroundColor: flatFill,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: neuGroove),
      ),
    ),

    datePickerTheme: DatePickerThemeData(
      backgroundColor: flatFill,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: neuGroove),
      ),
      headerBackgroundColor: scheme.primary,
      headerForegroundColor: scheme.onPrimary,
    ),

    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: isDark ? scheme.inverseSurface : const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: TextStyle(color: isDark ? scheme.onInverseSurface : Colors.white, fontSize: 12),
    ),
  );
}

/// Brand tokens beyond the Material [ColorScheme].
///
/// [commerce] is the primary button/CTA fill — #0B6B3A in light (6.6:1 with
/// white) and #32B86C in dark (8.2:1 with near-black). [successText] and
/// [brandOnSurface] are the surface-legible green tones, so green text/icons
/// never fall below AA on the canvas.
@immutable
class SokoColors extends ThemeExtension<SokoColors> {
  /// Primary green CTA fill (buy/sell/pay, selected states).
  final Color commerce;

  /// Text/icons placed on [commerce] fills.
  final Color onCommerce;

  /// Green for success text/icons sitting on a plain surface.
  final Color successText;

  /// Amber warning accent, darkened for text in light mode.
  final Color warning;

  /// Green legible as text/icons on a plain surface (light: #0B6B3A, dark: #32B86C).
  final Color brandOnSurface;

  /// Dark green #084D2B / #228B50 for tints, charts and separators.
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
        commerce: SokoPalette.lightPrimary,
        onCommerce: SokoPalette.onLightPrimary,
        successText: SokoPalette.lightSuccess,
        warning: SokoPalette.lightWarning,
        brandOnSurface: SokoPalette.lightPrimary,
        deepGreen: SokoPalette.lightPrimaryDark,
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
