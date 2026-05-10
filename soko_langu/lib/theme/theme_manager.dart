import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_themes.dart';

class ThemeManager extends ChangeNotifier {
  static const String _tierKey = 'app_theme_tier';

  String _currentTier = 'free';

  String get currentTier => _currentTier;

  ThemeData get currentTheme => tierThemes[_currentTier] ?? tierThemes['free']!;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _currentTier = prefs.getString(_tierKey) ?? 'free';
    notifyListeners();
  }

  Future<void> setTier(String tier) async {
    if (!tierThemes.containsKey(tier)) return;
    _currentTier = tier;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tierKey, tier);
    notifyListeners();
  }

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
