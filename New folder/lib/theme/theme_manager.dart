import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_themes.dart';
import 'dark_theme.dart';

class ThemeManager extends ChangeNotifier {
  static const String _tierKey = 'app_theme_tier';
  static const String _darkKey = 'app_dark_mode';

  String _currentTier = 'free';
  bool _isDark = false;

  String get currentTier => _currentTier;
  bool get isDark => _isDark;

  ThemeData get currentTheme => _isDark
      ? buildDarkTheme()
      : (tierThemes[_currentTier] ?? tierThemes['free']!);

  ThemeData get lightTheme => tierThemes[_currentTier] ?? tierThemes['free']!;
  ThemeData get darkTheme => buildDarkTheme();

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _currentTier = prefs.getString(_tierKey) ?? 'free';
    _isDark = prefs.getBool(_darkKey) ?? false;
    notifyListeners();
  }

  Future<void> setTier(String tier) async {
    if (!tierThemes.containsKey(tier)) return;
    _currentTier = tier;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tierKey, tier);
    notifyListeners();
  }

  Future<void> setDark(bool value) async {
    _isDark = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_darkKey, value);
    notifyListeners();
  }

  Future<void> toggleDark() async => setDark(!_isDark);

  Color get seedColor {
    switch (_currentTier) {
      case 'silver':
        return Colors.blueGrey;
      case 'premium':
        return Colors.amber;
      default:
        return Colors.green;
    }
  }

  String get label {
    switch (_currentTier) {
      case 'silver':
        return 'Silver';
      case 'premium':
        return 'Premium';
      default:
        return 'Free';
    }
  }
}