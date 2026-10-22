import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  static const _themeKey = 'settings_theme_mode';
  static const _colorKey = 'settings_color_seed';
  static const _reminderKey = 'settings_daily_reminder';
  static const _hourKey = 'settings_reminder_hour';
  static const _minuteKey = 'settings_reminder_minute';
  static const _startupSoundKey = 'settings_startup_sound';

  ThemeMode themeMode = ThemeMode.system;
  int colorSeed = 0xFF2E7D32;
  bool dailyReminder = true;
  int reminderHour = 19;
  int reminderMinute = 0;
  bool startupSound = true;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final theme = prefs.getString(_themeKey) ?? 'system';
    themeMode = switch (theme) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    colorSeed = prefs.getInt(_colorKey) ?? 0xFF2E7D32;
    dailyReminder = prefs.getBool(_reminderKey) ?? true;
    reminderHour = prefs.getInt(_hourKey) ?? 19;
    reminderMinute = prefs.getInt(_minuteKey) ?? 0;
    startupSound = prefs.getBool(_startupSoundKey) ?? true;
  }

  Future<void> saveStartupSound(bool value) async {
    startupSound = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_startupSoundKey, value);
  }

  Future<void> saveTheme(ThemeMode value) async {
    themeMode = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, switch (value) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    });
  }

  Future<void> saveColor(int value) async {
    colorSeed = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_colorKey, value);
  }

  Future<void> saveReminder(bool value) async {
    dailyReminder = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_reminderKey, value);
  }

  Future<void> saveReminderTime(int hour, int minute) async {
    reminderHour = hour;
    reminderMinute = minute;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_hourKey, hour);
    await prefs.setInt(_minuteKey, minute);
  }
}
