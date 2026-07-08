import 'package:shared_preferences/shared_preferences.dart';

class SmsLanguagePreference {
  static const String _key = 'sms_language';

  Future<void> set(String langCode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, langCode);
  }

  Future<String> get() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key) ?? 'sw';
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
