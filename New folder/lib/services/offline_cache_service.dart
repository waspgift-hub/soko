import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class OfflineCacheService {
  static final OfflineCacheService _instance = OfflineCacheService._internal();
  factory OfflineCacheService() => _instance;
  OfflineCacheService._internal();

  static const String _productsKey = 'cached_products';
  static const String _chatsKey = 'cached_chats';
  static const String _userKey = 'cached_user';
  static const String _lastSyncKey = 'last_sync';

  Future<void> cacheProducts(List<Map<String, dynamic>> products) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_productsKey, jsonEncode(products));
    await prefs.setString(_lastSyncKey, DateTime.now().toIso8601String());
  }

  Future<List<Map<String, dynamic>>> getCachedProducts() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_productsKey);
    if (data == null) return [];
    try {
      final list = jsonDecode(data) as List;
      return list.map((e) => e as Map<String, dynamic>).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> cacheChats(List<Map<String, dynamic>> chats) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_chatsKey, jsonEncode(chats));
  }

  Future<List<Map<String, dynamic>>> getCachedChats() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_chatsKey);
    if (data == null) return [];
    try {
      final list = jsonDecode(data) as List;
      return list.map((e) => e as Map<String, dynamic>).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> cacheUser(Map<String, dynamic> user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, jsonEncode(user));
  }

  Future<Map<String, dynamic>?> getCachedUser() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_userKey);
    if (data == null) return null;
    try {
      return jsonDecode(data) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<DateTime?> getLastSync() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_lastSyncKey);
    if (data == null) return null;
    try {
      return DateTime.parse(data);
    } catch (_) {
      return null;
    }
  }

  Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_productsKey);
    await prefs.remove(_chatsKey);
    await prefs.remove(_userKey);
    await prefs.remove(_lastSyncKey);
  }
}
