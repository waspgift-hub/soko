import 'package:cloud_firestore/cloud_firestore.dart';

/// Username / handle validation + availability helpers.
///
/// Requirements:
/// - unique (case-insensitive)
/// - normalized: lowercased, trimmed
/// - 3..20 chars, a-z0-9 _ . only, cannot start/end with _ or .
/// - no consecutive __ or .. or ._
/// - reserved system names blocked
class UsernameService {
  UsernameService._();
  static final instance = UsernameService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const int minLength = 3;
  static const int maxLength = 20;

  static const Set<String> reserved = {
    'admin',
    'sokovibe',
    'soko',
    'vibe',
    'sokolangu',
    'support',
    'help',
    'api',
    'www',
    'root',
    'system',
    'official',
    'verified',
    'null',
    'undefined',
    'anonymous',
    'user',
    'seller',
    'buyer',
    'moderator',
    'test',
    'demo',
    'soko_vibe',
    'sokovibe_store',
    // protect numeric confusion
    'sokovibe_tz',
    'sokovibe.co.tz',
  };

  static const Set<String> blockedSubstrings = {
    'admin',
    'root',
    'support',
  };

  /// Normalizes raw input to canonical form (lowercase, trimmed, stripped @).
  static String normalize(String raw) {
    var s = raw.trim().toLowerCase();
    if (s.startsWith('@')) s = s.substring(1);
    return s;
  }

  /// Returns null when valid, else human-readable error key.
  static String? validate(String raw) {
    final v = normalize(raw);
    if (v.isEmpty) return 'username_required';
    if (v.length < minLength) return 'username_too_short';
    if (v.length > maxLength) return 'username_too_long';
    // allowed chars
    if (!RegExp(r'^[a-z0-9_.]+$').hasMatch(v)) return 'username_invalid_chars';
    if (v.startsWith('_') || v.startsWith('.') || v.endsWith('_') || v.endsWith('.')) {
      return 'username_invalid_edge';
    }
    if (v.contains('__') || v.contains('..') || v.contains('._') || v.contains('_.')) {
      return 'username_invalid_sequence';
    }
    if (reserved.contains(v)) return 'username_reserved';
    for (final bad in blockedSubstrings) {
      if (v == bad) return 'username_reserved';
    }
    // Tanzanian phone-like handles disallowed for privacy
    if (RegExp(r'^0[67]\d{8}$').hasMatch(v)) return 'username_phone_not_allowed';
    if (RegExp(r'^255[67]\d{8}$').hasMatch(v)) return 'username_phone_not_allowed';
    return null;
  }

  /// Case-insensitive uniqueness check via Firestore `usernameLower` field.
  /// [excludeUid] skips current user's own doc.
  Future<bool> isAvailable(String raw, {String? excludeUid}) async {
    final norm = normalize(raw);
    final err = validate(raw);
    if (err != null) return false;
    try {
      final snap = await _db
          .collection('users')
          .where('usernameLower', isEqualTo: norm)
          .limit(5)
          .get();
      if (snap.docs.isEmpty) return true;
      for (final d in snap.docs) {
        if (d.id != excludeUid) return false;
      }
      return true;
    } catch (_) {
      // fallback to legacy username field
      try {
        final snap2 = await _db
            .collection('users')
            .where('username', isEqualTo: norm)
            .limit(5)
            .get();
        if (snap2.docs.isEmpty) return true;
        for (final d in snap2.docs) {
          if (d.id != excludeUid) return false;
        }
        return true;
      } catch (_) {
        return false;
      }
    }
  }

  /// Claims a username for the current user — writes both `username` and
  /// `usernameLower` for case-insensitive queries. Throws on taken/invalid.
  Future<void> claim(String uid, String raw) async {
    final norm = normalize(raw);
    final err = validate(raw);
    if (err != null) throw Exception(err);
    final avail = await isAvailable(raw, excludeUid: uid);
    if (!avail) throw Exception('username_taken');
    await _db.collection('users').doc(uid).set({
      'username': norm,
      'usernameLower': norm,
      'usernameUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Resolves a username or raw uid to a uid. Returns null if not found.
  Future<String?> resolveToUid(String raw) async {
    final norm = normalize(raw);
    if (norm.isEmpty) return null;
    // first try as usernameLower
    try {
      final snap = await _db
          .collection('users')
          .where('usernameLower', isEqualTo: norm)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) return snap.docs.first.id;
    } catch (_) {}
    try {
      final snap2 = await _db
          .collection('users')
          .where('username', isEqualTo: norm)
          .limit(1)
          .get();
      if (snap2.docs.isNotEmpty) return snap2.docs.first.id;
    } catch (_) {}
    // fallback: maybe raw is already uid
    final doc = await _db.collection('users').doc(raw).get();
    if (doc.exists) return raw;
    return null;
  }
}
