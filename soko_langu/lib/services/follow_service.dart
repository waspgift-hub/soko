import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';

import '../models/social_models.dart';
import 'notification_service.dart';

/// Centralized service for the social graph: follow / unfollow, follow
/// requests (private accounts), followers / following lists, and block /
/// unblock.
///
/// Every relationship is written to Firestore in a single batch so the graph
/// stays consistent: a follow exists iff both `users/{followerId}/following/{followingId}`
/// and `users/{followingId}/followers/{followerId}` are present.
///
/// The client never trusts another user's follow state — every write is gated by
/// Firestore rules and every read consults the server-owned documents.
class FollowService {
  FollowService._();
  static final FollowService _instance = FollowService._();
  factory FollowService() => _instance;

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final NotificationService _notifications = NotificationService();

  /// Current user's uid, or null when signed out.
  String? get _uid => _auth.currentUser?.uid;

  /// True when signed out — no social graph access is permitted.
  bool get isSignedOut => _uid == null;

  // ─── Follow / unfollow ───────────────────────────────────────────────────

  /// Follow [targetId].
  ///
  /// If the target account is public, the follow is active immediately. If the
  /// target is private, a follow request is created instead and the caller is
  /// told via [FollowResult.requested] that approval is pending.
  ///
  /// Returns [FollowResult.following] when the follow is active,
  /// [FollowResult.requested] when approval is pending, or [FollowResult.blocked]
  /// when either account has blocked the other.
  Future<FollowResult> follow(String targetId) async {
    if (isSignedOut) return FollowResult.error('not_signed_in');
    if (targetId == _uid) return FollowResult.error('cannot_follow_self');
    try {
      final token = await _auth.currentUser?.getIdToken();
      final res = await http.post(
        Uri.parse(ApiConfig.v1('/social/follow')),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({'targetId': targetId}),
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = jsonDecode(res.body)['data'] ?? {};
        final st = data['status'] as String? ?? '';
        if (st == 'following') return FollowResult.following();
        if (st == 'requested') return FollowResult.requested();
        if (st == 'blocked') return FollowResult.blocked();
      }
      return FollowResult.error('follow_failed');
    } catch (e) {
      return FollowResult.error(e.toString());
    }
  }

  /// Unfollow [targetId]. Removes both follow edges and decrements counts.
  /// No-op if not following.
  Future<void> unfollow(String targetId) async {
    if (isSignedOut || targetId == _uid) return;
    try {
      final token = await _auth.currentUser?.getIdToken();
      await http.post(
        Uri.parse(ApiConfig.v1('/social/unfollow')),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({'targetId': targetId}),
      );
    } catch (_) {}
  }

  /// Whether the current user has a pending follow request to [targetId].
  Future<bool> hasPendingFollowRequest(String targetId) async {
    if (isSignedOut) return false;
    final doc = await _db
        .collection('users')
        .doc(_uid!)
        .collection('followRequestsSent')
        .doc(targetId)
        .get();
    return doc.exists;
  }

  /// Whether [uid] follows the current user.
  Future<bool> isFollowedBy(String uid) async {
    if (isSignedOut) return false;
    final doc = await _db.collection('users').doc(uid).collection('following').doc(_uid!).get();
    return doc.exists;
  }

  /// Whether the current user follows [uid].
  Future<bool> isFollowing(String uid) async {
    if (isSignedOut) return false;
    final doc = await _db.collection('users').doc(_uid!).collection('following').doc(uid).get();
    return doc.exists;
  }

  // ─── Follow requests (private accounts) ─────────────────────────────────

  /// Pending follow requests sent TO the current user (they must approve).
  Stream<List<FollowRequest>> streamIncomingRequests() {
    if (isSignedOut) return const Stream.empty();
    return _db
        .collection('users')
        .doc(_uid!)
        .collection('followRequests')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => FollowRequest.fromDoc(d.id, _uid!, d.data())).toList());
  }

  /// Pending follow requests sent BY the current user.
  Stream<List<FollowRequest>> streamOutgoingRequests() {
    if (isSignedOut) return const Stream.empty();
    return _db
        .collection('users')
        .doc(_uid!)
        .collection('followRequestsSent')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => FollowRequest.fromDoc(_uid!, d.id, d.data())).toList());
  }

  /// Approve [requesterId]'s follow request, creating the follow relationship.
  ///
  /// Only callable by the request target (the current user).
  Future<void> acceptRequest(String requesterId) async {
    if (isSignedOut) return;
    try {
      final token = await _auth.currentUser?.getIdToken();
      await http.post(
        Uri.parse(ApiConfig.v1('/social/accept')),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({'requesterId': requesterId}),
      );
    } catch (_) {}
  }

  Future<void> rejectRequest(String requesterId) async {
    if (isSignedOut) return;
    try {
      final token = await _auth.currentUser?.getIdToken();
      await http.post(
        Uri.parse(ApiConfig.v1('/social/reject')),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({'requesterId': requesterId}),
      );
    } catch (_) {}
  }

  Future<void> cancelRequest(String targetId) async {
    if (isSignedOut) return;
    try {
      final token = await _auth.currentUser?.getIdToken();
      await http.post(
        Uri.parse(ApiConfig.v1('/social/cancel')),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({'targetId': targetId}),
      );
    } catch (_) {}
  }

  // ─── Followers / following lists ────────────────────────────────────────

  /// Stream of uids following [ownerId] (most recent first).
  Stream<List<String>> streamFollowers(String ownerId) {
    return _db
        .collection('users')
        .doc(ownerId)
        .collection('followers')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.id).toList());
  }

  /// Stream of uids [ownerId] is following (most recent first).
  Stream<List<String>> streamFollowing(String ownerId) {
    return _db
        .collection('users')
        .doc(ownerId)
        .collection('following')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.id).toList());
  }

  /// Count of followers for [ownerId] (denormalized, always consistent).
  Future<int> followerCount(String ownerId) async {
    final doc = await _db.collection('userPublic').doc(ownerId).get();
    return doc.data()?['followerCount'] as int? ?? 0;
  }

  /// Stream of follower count for [ownerId].
  Stream<int> followerCountStream(String ownerId) {
    return _db
        .collection('users')
        .doc(ownerId)
        .snapshots()
        .map((doc) => doc.data()?['followerCount'] as int? ?? 0);
  }

  /// Count of accounts [ownerId] is following (denormalized).
  Future<int> followingCount(String ownerId) async {
    final doc = await _db.collection('userPublic').doc(ownerId).get();
    return doc.data()?['followingCount'] as int? ?? 0;
  }

  /// Stream of following count for [ownerId].
  Stream<int> followingCountStream(String ownerId) {
    return _db
        .collection('users')
        .doc(ownerId)
        .snapshots()
        .map((doc) => doc.data()?['followingCount'] as int? ?? 0);
  }

  // ─── Block / unblock ────────────────────────────────────────────────────

  /// Block [targetId]. Removes any existing follow in both directions and
  /// creates a block record.
  Future<void> block(String targetId) async {
    if (isSignedOut || targetId == _uid) return;
    try {
      final token = await _auth.currentUser?.getIdToken();
      await http.post(
        Uri.parse(ApiConfig.v1('/social/block')),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({'targetId': targetId}),
      );
    } catch (_) {}
  }

  /// Unblock [targetId]. Removes the block record; does not re-follow.
  Future<void> unblock(String targetId) async {
    if (isSignedOut) return;
    try {
      final token = await _auth.currentUser?.getIdToken();
      await http.post(
        Uri.parse(ApiConfig.v1('/social/unblock')),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({'targetId': targetId}),
      );
    } catch (_) {}
  }

  /// Whether [uid] has blocked the current user.
  Future<bool> isBlockedBy(String uid) async {
    if (isSignedOut) return false;
    final doc = await _db.collection('users').doc(uid).collection('blocked').doc(_uid!).get();
    return doc.exists;
  }

  /// Whether the current user has blocked [uid].
  Future<bool> hasBlocked(String uid) async {
    if (isSignedOut) return false;
    final doc = await _db.collection('users').doc(_uid!).collection('blocked').doc(uid).get();
    return doc.exists;
  }

  /// Stream of uids blocked by the current user.
  Stream<List<String>> streamBlocked() {
    if (isSignedOut) return const Stream.empty();
    return _db
        .collection('users')
        .doc(_uid!)
        .collection('blocked')
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.id).toList());
  }
}

/// Outcome of a [FollowService.follow] call.
@immutable
class FollowResult {
  const FollowResult._(this._kind, this._message);

  factory FollowResult.following() => FollowResult._('following', null);
  factory FollowResult.requested() => FollowResult._('requested', null);
  factory FollowResult.blocked() => FollowResult._('blocked', null);
  factory FollowResult.error(String message) => FollowResult._('error', message);

  final String _kind;
  final String? _message;

  bool get isFollowing => _kind == 'following';
  bool get isRequested => _kind == 'requested';
  bool get isBlocked => _kind == 'blocked';
  bool get isError => _kind == 'error';
  String? get message => _message;

  @override
  String toString() => 'FollowResult($_kind${_message == null ? '' : ': $_message'})';
}
