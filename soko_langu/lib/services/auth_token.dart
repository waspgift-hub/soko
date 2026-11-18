import 'package:firebase_auth/firebase_auth.dart';

/// Central Firebase ID-token access.
///
/// Firebase already caches and refreshes tokens internally. Forcing a refresh
/// on every call (`getIdToken(true)`) and calling `user.reload()` first added
/// one to two network round-trips to every screen action. This helper collapses
/// bursts into a single fetch and only forces when a caller needs fresh claims.
class AuthToken {
  AuthToken._();

  static const Duration _ttl = Duration(seconds: 30);
  static String? _value;
  static DateTime? _fetchedAt;
  static String? _uid;

  /// Returns the current ID token, or null when signed out.
  ///
  /// Pass [forceRefresh] only when a caller must observe a claim change that
  /// just happened on this device (for example immediately after KYC).
  static Future<String?> current({bool forceRefresh = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      clear();
      return null;
    }
    final now = DateTime.now();
    final usable = _value != null &&
        _uid == user.uid &&
        _fetchedAt != null &&
        now.difference(_fetchedAt!) < _ttl;
    if (usable && !forceRefresh) return _value;
    try {
      final token = await user.getIdToken(forceRefresh);
      _value = token;
      _fetchedAt = now;
      _uid = user.uid;
      return token;
    } catch (_) {
      // Keep serving the last good token rather than failing the whole action.
      return _value;
    }
  }

  /// Drops the cached token. Call on sign-out or when claims are known stale.
  static void clear() {
    _value = null;
    _fetchedAt = null;
    _uid = null;
  }
}
