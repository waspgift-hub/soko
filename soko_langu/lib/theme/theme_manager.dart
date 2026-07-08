import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_themes.dart';

class ThemeManager extends ChangeNotifier {
  static const String _darkKey = 'app_dark_mode';
  static const String _seedKey = 'theme_seed_color';
  static const int _defaultSeed = 0xFF0F172A;

  bool _isDark = true;
  Color _seedColor = const Color(_defaultSeed);

  bool get isDark => _isDark;
  Color get seedColor => _seedColor;

  ThemeData get currentTheme =>
      _isDark ? buildDarkTheme(_seedColor) : buildLightTheme(_seedColor);

  ThemeData get lightTheme => buildLightTheme(_seedColor);
  ThemeData get darkTheme => buildDarkTheme(_seedColor);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _isDark = prefs.getBool(_darkKey) ?? false;
    final seed = prefs.getInt(_seedKey);
    if (seed != null) _seedColor = Color(seed);
    notifyListeners();
  }

  Future<void> setDark(bool value) async {
    _isDark = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_darkKey, value);
    notifyListeners();
  }

  Future<void> toggleDark() async => setDark(!_isDark);

  Future<void> setSeedColor(Color color) async {
    _seedColor = color;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_seedKey, color.value);
    notifyListeners();
  }
}
