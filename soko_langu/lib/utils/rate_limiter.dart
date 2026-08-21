import 'package:shared_preferences/shared_preferences.dart';

class RateLimiter {
  RateLimiter._();

  static const String _prefix = 'rate_limit_';

  static Future<bool> canProceed({
    required String action,
    Duration cooldown = const Duration(seconds: 30),
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_prefix$action';
    final lastTime = prefs.getInt(key);
    if (lastTime == null) return true;
    final now = DateTime.now().millisecondsSinceEpoch;
    return (now - lastTime) >= cooldown.inMilliseconds;
  }

  static Future<void> record(String action) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_prefix$action';
    await prefs.setInt(key, DateTime.now().millisecondsSinceEpoch);
  }

  static Future<int> getAttemptCount(String action) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('$_prefix${action}_count') ?? 0;
  }

  static Future<void> incrementAttempt(String action, {
    int maxAttempts = 5,
    Duration window = const Duration(minutes: 15),
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final countKey = '$_prefix${action}_count';
    final windowKey = '$_prefix${action}_window';
    final now = DateTime.now().millisecondsSinceEpoch;
    final windowStart = prefs.getInt(windowKey);

    if (windowStart == null || (now - windowStart) > window.inMilliseconds) {
      await prefs.setInt(windowKey, now);
      await prefs.setInt(countKey, 1);
      return;
    }

    final current = prefs.getInt(countKey) ?? 0;
    await prefs.setInt(countKey, current + 1);
  }

  static Future<bool> isWithinLimit(String action, {int maxAttempts = 5}) async {
    final count = await getAttemptCount(action);
    return count < maxAttempts;
  }

  static Future<void> reset(String action) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix${action}_count');
    await prefs.remove('$_prefix${action}_window');
  }
}
