import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'app_themes.dart';
import 'soko_palette.dart';

// Brand green fill; kept in sync with SokoColors in app_themes.dart.
const _brandGreen = SokoPalette.lightPrimary;

/// M3 Expressive dynamic color: an OS-provided scheme (Android 12+ wallpaper,
/// desktop accents) merged with the Soko Vibe brand.
///
/// WHY wholesale scheme + rebuilt primary ramp (instead of a full fromSeed
/// rebuild): the brand rule fixes a black/white canvas with green commerce
/// CTAs. The dynamic scheme drives every M3 tonal role so the app feels
/// personal, while only the *primary ramp* is regenerated in the brand-green
/// hue with the 2025 vibrant spec (DynamicSchemeVariant.vibrant) — tonal
/// harmony is preserved and brand recognition survives. Commerce fills keep
/// fixed black text, so contrast never depends on the wallpaper.
ThemeData buildDynamicLightTheme(ColorScheme dynamic) {
  final isDark = false;
  return buildThemeFromScheme(
    _brandRamp(dynamic, isDark: isDark),
    brand: _dynamicBrand(dynamic, isDark: isDark),
  );
}

/// M3 Expressive dynamic color for dark mode. See [buildDynamicLightTheme].
ThemeData buildDynamicDarkTheme(ColorScheme dynamic) {
  final isDark = true;
  return buildThemeFromScheme(
    _brandRamp(dynamic, isDark: isDark),
    brand: _dynamicBrand(dynamic, isDark: isDark),
  );
}

/// Dynamic scheme whose primary ramp is regenerated in the brand-green hue.
///
/// The seed is the brand green harmonized toward the wallpaper primary, so
/// the ramp leans into the user's palette instead of clashing with it. The
/// vibrant 2025 variant keeps the ramp saturated and expressive.
@visibleForTesting
ColorScheme brandPrimaryRamp(ColorScheme dynamic, {required bool isDark}) {
  final seed = _brandGreen.harmonizeWith(dynamic.primary);
  final ramp = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: isDark ? Brightness.dark : Brightness.light,
    dynamicSchemeVariant: DynamicSchemeVariant.vibrant,
  );
  return dynamic.copyWith(
    primary: ramp.primary,
    onPrimary: ramp.onPrimary,
    primaryContainer: ramp.primaryContainer,
    onPrimaryContainer: ramp.onPrimaryContainer,
  );
}

ColorScheme _brandRamp(ColorScheme dynamic, {required bool isDark}) =>
    brandPrimaryRamp(dynamic, isDark: isDark);

/// Brand extension for the dynamic theme.
///
/// Only the commerce fill is harmonized toward the wallpaper hue (it always
/// pairs with fixed on-brand text, so contrast is unaffected). Surface-legible
/// greens stay fixed: harmonizing them could erode the guaranteed 6.6:1
/// ratio on white.
SokoColors _dynamicBrand(ColorScheme dynamic, {required bool isDark}) {
  return SokoColors(
    commerce: _brandGreen.harmonizeWith(dynamic.primary),
    onCommerce: isDark ? SokoPalette.onDarkPrimary : SokoPalette.onLightPrimary,
    successText: isDark ? SokoPalette.darkSuccess : SokoPalette.lightSuccess,
    warning: isDark ? SokoPalette.darkWarning : SokoPalette.lightWarning,
    brandOnSurface: isDark ? SokoPalette.darkPrimary : SokoPalette.lightPrimary,
    deepGreen: isDark ? SokoPalette.darkPrimaryDark : SokoPalette.lightPrimaryDark,
  );
}
