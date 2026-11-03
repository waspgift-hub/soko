import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Key/value secret storage.
///
/// Native builds use the platform keystore. Web has no secure enclave and
/// flutter_secure_storage has no web implementation—fall back to browser
/// storage so app lock and other stored keys keep working in the web build.
class SecureStorageService {
  static const _storage = FlutterSecureStorage();
  static const _webPrefix = 'secure_';

  static Future<void> write(String key, String value) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_webPrefix$key', value);
      return;
    }
    await _storage.write(key: key, value: value);
  }

  static Future<String?> read(String key) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('$_webPrefix$key');
    }
    return await _storage.read(key: key);
  }

  static Future<void> delete(String key) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_webPrefix$key');
      return;
    }
    await _storage.delete(key: key);
  }

  static Future<void> deleteAll() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys()) {
        if (key.startsWith(_webPrefix)) {
          await prefs.remove(key);
        }
      }
      return;
    }
    await _storage.deleteAll();
  }
}
