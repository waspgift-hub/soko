import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_themes.dart';

class ThemeManager extends ChangeNotifier {
  static const String _darkKey = 'app_dark_mode';
  static const String _themeModeKey = 'app_theme_mode';
  static const String _seedKey = 'theme_seed_color';
  static const int _defaultSeed = 0xFF1B5E20;

  ThemeMode _themeMode = ThemeMode.system;
  bool _isDark = false;
  Color _seedColor = const Color(_defaultSeed);

  bool get isDark => _isDark;
  Color get seedColor => _seedColor;
  ThemeMode get themeMode => _themeMode;

  ThemeData get currentTheme =>
      _isDark ? buildDarkTheme(_seedColor) : buildLightTheme(_seedColor);

  ThemeData get lightTheme => buildLightTheme(_seedColor);
  ThemeData get darkTheme => buildDarkTheme(_seedColor);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    final savedMode = prefs.getString(_themeModeKey);
    if (savedMode == 'dark') {
      _themeMode = ThemeMode.dark;
      _isDark = true;
    } else if (savedMode == 'light') {
      _themeMode = ThemeMode.light;
      _isDark = false;
    } else {
      _themeMode = ThemeMode.system;
      _isDark = _resolveSystemDark();
    }

    // Migrate legacy key
    if (savedMode == null && prefs.containsKey(_darkKey)) {
      final legacy = prefs.getBool(_darkKey) ?? false;
      _themeMode = legacy ? ThemeMode.dark : ThemeMode.light;
      _isDark = legacy;
      await prefs.setString(_themeModeKey, legacy ? 'dark' : 'light');
      await prefs.remove(_darkKey);
    }

    final seed = prefs.getInt(_seedKey);
    if (seed != null) _seedColor = Color(seed);
    notifyListeners();
  }

  Future<void> setDark(bool value) async {
    _isDark = value;
    _themeMode = value ? ThemeMode.dark : ThemeMode.light;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, value ? 'dark' : 'light');
    _updateStatusBar();
    notifyListeners();
  }

  Future<void> toggleDark() async => setDark(!_isDark);

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    if (mode == ThemeMode.system) {
      _isDark = _resolveSystemDark();
    } else {
      _isDark = mode == ThemeMode.dark;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, mode == ThemeMode.dark ? 'dark' : mode == ThemeMode.light ? 'light' : 'system');
    _updateStatusBar();
    notifyListeners();
  }

  void onSystemBrightnessChanged(Brightness brightness) {
    if (_themeMode == ThemeMode.system) {
      final newDark = brightness == Brightness.dark;
      if (_isDark != newDark) {
        _isDark = newDark;
        _updateStatusBar();
        notifyListeners();
      }
    }
  }

  bool _resolveSystemDark() {
    final brightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
    return brightness == Brightness.dark;
  }

  void _updateStatusBar() {
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: _isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: _isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: _isDark ? const Color(0xFF0D0D0D) : Colors.white,
        systemNavigationBarIconBrightness: _isDark ? Brightness.light : Brightness.dark,
      ),
    );
  }
}
