import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class RateLimitService {
  static final RateLimitService _instance = RateLimitService._internal();
  factory RateLimitService() => _instance;
  RateLimitService._internal();

  static const int maxMessagesPerMinute = 30;
  static const int maxProductsPerHour = 10;
  static const int maxCallsPerHour = 20;
  static const int maxFollowsPerMinute = 10;

  Future<bool> canSendMessage() async {
    return _checkLimit('messages', maxMessagesPerMinute, 60);
  }

  Future<bool> canPostProduct() async {
    return _checkLimit('products', maxProductsPerHour, 3600);
  }

  Future<bool> canMakeCall() async {
    return _checkLimit('calls', maxCallsPerHour, 3600);
  }

  Future<bool> canFollow() async {
    return _checkLimit('follows', maxFollowsPerMinute, 60);
  }

  Future<bool> _checkLimit(String action, int maxCount, int windowSeconds) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'rate_$action';
    final now = DateTime.now().millisecondsSinceEpoch;
    final windowMs = windowSeconds * 1000;

    final data = prefs.getString(key);
    if (data == null) {
      await prefs.setString(key, jsonEncode([now]));
      return true;
    }

    try {
      final List<dynamic> timestamps = jsonDecode(data);
      final validTimestamps = timestamps
          .where((t) => now - (t as int) < windowMs)
          .toList();

      if (validTimestamps.length >= maxCount) return false;

      validTimestamps.add(now);
      await prefs.setString(key, jsonEncode(validTimestamps));
      return true;
    } catch (_) {
      await prefs.setString(key, jsonEncode([now]));
      return true;
    }
  }

  Future<void> clearLimits() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith('rate_'));
    for (final key in keys) {
      await prefs.remove(key);
    }
  }
}
