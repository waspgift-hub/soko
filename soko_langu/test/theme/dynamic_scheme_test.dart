import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soko_vibe/theme/app_themes.dart';
import 'package:soko_vibe/theme/dynamic_scheme.dart';
import 'package:soko_vibe/theme/soko_palette.dart';
import 'package:soko_vibe/theme/theme_manager.dart';

/// Stand-in for an OS-provided dynamic scheme (Android 12+ wallpaper pulls
/// a purple-leaning palette here so the brand-green ramp is distinguishable).
ColorScheme fakeDynamic(Brightness brightness) =>
    ColorScheme.fromSeed(seedColor: Colors.deepPurple, brightness: brightness);

void main() {
  group('brandPrimaryRamp', () {
    test('keeps dynamic surfaces, rebuilds the primary ramp', () {
      final dynamic = fakeDynamic(Brightness.light);
      final ramp = brandPrimaryRamp(dynamic, isDark: false);

      expect(ramp.brightness, Brightness.light);
      expect(ramp.surface, dynamic.surface);
      expect(ramp.surfaceContainerHighest, dynamic.surfaceContainerHighest);
      expect(ramp.onSurface, dynamic.onSurface);
      expect(ramp.primary, isNot(dynamic.primary));
      expect(ramp.primaryContainer, isNot(dynamic.primaryContainer));
    });

    test('dark ramp preserves dark brightness and dynamic surfaces', () {
      final dynamic = fakeDynamic(Brightness.dark);
      final ramp = brandPrimaryRamp(dynamic, isDark: true);

      expect(ramp.brightness, Brightness.dark);
      expect(ramp.surface, dynamic.surface);
      expect(ramp.primary, isNot(dynamic.primary));
    });
  });

  group('buildDynamicLightTheme / buildDynamicDarkTheme', () {
    test('light theme carries harmonized commerce with brand text', () {
      final theme = buildDynamicLightTheme(fakeDynamic(Brightness.light));
      final brand = theme.extension<SokoColors>()!;

      expect(theme.brightness, Brightness.light);
      expect(brand.commerce, isNot(SokoPalette.lightPrimary));
      expect(brand.onCommerce, SokoPalette.onLightPrimary);
      // Surface-legible greens stay fixed for guaranteed contrast.
      expect(brand.brandOnSurface, SokoPalette.lightPrimary);
    });

    test('dark theme keeps dynamic surfaces and fixed dark greens', () {
      final dynamic = fakeDynamic(Brightness.dark);
      final theme = buildDynamicDarkTheme(dynamic);
      final brand = theme.extension<SokoColors>()!;

      expect(theme.colorScheme.surface, dynamic.surface);
      expect(brand.brandOnSurface, SokoPalette.darkPrimary);
      expect(brand.onCommerce, SokoPalette.onDarkPrimary);
    });
  });

  group('ThemeManager dynamic resolution', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('defaults to the fixed brand themes', () {
      final manager = ThemeManager();

      expect(manager.useDynamicColor, isFalse);
      expect(manager.lightTheme.colorScheme.primary, SokoPalette.lightPrimary);
      expect(manager.darkTheme.colorScheme.primary, SokoPalette.darkPrimary);
    });

    test('uses the OS scheme once explicitly enabled', () async {
      final manager = ThemeManager();
      final dynamic = fakeDynamic(Brightness.light);
      manager.setDynamicSchemes(dynamic, null);
      await manager.setUseDynamicColor(true);

      expect(manager.lightTheme.colorScheme.surface, dynamic.surface);
      expect(manager.lightTheme.colorScheme.primary, isNot(SokoPalette.lightPrimary));
    });
  });
}
