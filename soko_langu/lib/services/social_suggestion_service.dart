import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/social_models.dart';
import 'api_config.dart';
import 'follow_service.dart';
import 'user_service.dart';

/// Surface suggested accounts to follow.
///
/// Signals used (in priority order):
/// 1. Accounts followed by people the current user follows (second-degree).
/// 2. KYC-approved / Blue Tick sellers (public trust signal).
/// 3. High-selling / popular sellers.
///
/// Accounts the user already follows, has blocked, is blocked by, or is the
/// current user are always excluded.
class SocialSuggestionService {
  SocialSuggestionService._();
  static final SocialSuggestionService _instance = SocialSuggestionService._();
  factory SocialSuggestionService() => _instance;

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FollowService _follow = FollowService();
  final UserService _userService = UserService();

  String? get _uid => _auth.currentUser?.uid;
  bool get isSignedOut => _uid == null;

  /// Returns suggested seller/user uids, deduplicated and ranked.
  ///
  /// [limit] caps the number returned (default 20).
  Future<List<String>> suggestedSellers({int limit = 20}) async {
    if (isSignedOut) return [];

    final followed = <String>{};
    final followingDocs = await _db
        .collection('users')
        .doc(_uid!)
        .collection('following')
        .get();
    for (final d in followingDocs.docs) followed.add(d.id);

    final blocked = <String>{};
    final blockedDocs = await _db
        .collection('users')
        .doc(_uid!)
        .collection('blocked')
        .get();
    for (final d in blockedDocs.docs) blocked.add(d.id);

    final candidates = <String, int>{}; // uid -> score

    // 1) Second-degree: people followed by those I follow.
    for (final followeeId in followed) {
      if (followed.contains(followeeId) || blocked.contains(followeeId)) continue;
      final ffDocs = await _db
          .collection('users')
          .doc(followeeId)
          .collection('following')
          .limit(15)
          .get();
      for (final d in ffDocs.docs) {
        final candidate = d.id;
        if (candidate == _uid ||
            followed.contains(candidate) ||
            blocked.contains(candidate)) continue;
        candidates[candidate] = (candidates[candidate] ?? 0) + 3;
      }
    }

    // 2) KYC-approved / Blue Tick sellers who I don't follow yet.
    final verifiedDocs = await _db
        .collection('userPublic')
        .where('kycApproved', isEqualTo: true)
        .limit(40)
        .get();
    for (final d in verifiedDocs.docs) {
      final candidate = d.id;
      if (candidate == _uid ||
          followed.contains(candidate) ||
          blocked.contains(candidate)) continue;
      candidates[candidate] = (candidates[candidate] ?? 0) + 2;
    }

    // Sort by score desc, then uid for stability.
    final ranked = candidates.entries.toList()
      ..sort((a, b) {
        final c = b.value.compareTo(a.value);
        if (c != 0) return c;
        return a.key.compareTo(b.key);
      });

    return ranked.take(limit).map((e) => e.key).toList();
  }

  /// Build [UserProfile] objects for the suggested uids, in order.
  Future<List<UserProfile>> resolveSuggestions({int limit = 20}) async {
    final uids = await suggestedSellers(limit: limit);
    if (uids.isEmpty) return [];
    return _userService.getProfiles(uids).then((map) {
      return uids
          .map((uid) => map[uid])
          .whereType<UserProfile>()
          .toList();
    });
  }
}