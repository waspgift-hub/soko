import 'package:shared_preferences/shared_preferences.dart';

class OnboardingService {
  static const _seenKey = 'onboarding_seen';
  static const _firstTimeKey = 'isFirstTimeUser';

  Future<bool> isCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_seenKey) ??
        !(prefs.getBool(_firstTimeKey) ?? true);
  }

  Future<void> markCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_seenKey, true);
    await prefs.setBool(_firstTimeKey, false);
  }
}
