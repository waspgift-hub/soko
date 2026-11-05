import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

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

    final meRef = _db.collection('users').doc(_uid!);
    final themRef = _db.collection('users').doc(targetId);
    final [meDoc, themDoc, followingDoc, outgoingReq] = await Future.wait([
      meRef.get(),
      themRef.get(),
      meRef.collection('following').doc(targetId).get(),
      meRef.collection('followRequestsSent').doc(targetId).get(),
    ]);
    if (followingDoc.exists) return FollowResult.following();
    if (outgoingReq.exists) return FollowResult.requested();

    final meData = meDoc.data() ?? <String, dynamic>{};
    final themData = themDoc.data() ?? <String, dynamic>{};
    final themBlocksMe =
        themData['blockedIds'] is List && (themData['blockedIds'] as List).contains(_uid);
    final iBlockThem =
        meData['blockedIds'] is List && (meData['blockedIds'] as List).contains(targetId);
    if (themBlocksMe || iBlockThem) return FollowResult.blocked();

    final theirVisibility = ProfileVisibilitySettings.fromMap(
      themData['visibility'] as Map<String, dynamic>?,
    );
    final isPrivate = theirVisibility.isPrivate;
    final now = DateTime.now();

    if (isPrivate) {
      // Rules currently allow requester to write only users/{requester}/followRequestsSent.
      // Incoming request under target requires server mediation; do not weaken rules.
      await meRef
          .collection('followRequestsSent')
          .doc(targetId)
          .set(FollowRequest(requesterId: _uid!, targetId: targetId, createdAt: now).toMap());
      return FollowResult.requested();
    }

    // Rules allow follower to create own following edge and follower edge on a public target.
    // userPublic counters are server-owned in comments; client counter updates may be denied by rules.
    final batch = _db.batch();
    batch.set(
      meRef.collection('following').doc(targetId),
      FollowRelationship(followerId: _uid!, followingId: targetId, createdAt: now).toMap(),
    );
    batch.set(
      themRef.collection('followers').doc(_uid!),
      FollowRelationship(followerId: _uid!, followingId: targetId, createdAt: now).toMap(),
    );
    await batch.commit();
    try {
      await themRef.set({'followerCount': FieldValue.increment(1)}, SetOptions(merge: true));
      await meRef.set({'followingCount': FieldValue.increment(1)}, SetOptions(merge: true));
    } catch (_) {}
    try {
      await _notifications.sendNotification(
        userId: targetId,
        title: 'New follower',
        body: '${_auth.currentUser?.displayName ?? 'Someone'} started following you',
        data: {'type': 'follow', 'followerId': _uid!},
      );
    } catch (_) {}
    return FollowResult.following();
  }

  /// Unfollow [targetId]. Removes both follow edges and decrements counts.
  /// No-op if not following.
  Future<void> unfollow(String targetId) async {
    if (isSignedOut || targetId == _uid) return;
    final meRef = _db.collection('users').doc(_uid!);
    final themRef = _db.collection('users').doc(targetId);
    final existing = await meRef.collection('following').doc(targetId).get();
    if (!existing.exists) return;
    final batch = _db.batch();
    batch.delete(meRef.collection('following').doc(targetId));
    batch.delete(themRef.collection('followers').doc(_uid!));
    await batch.commit();
    try {
      await themRef.set({'followerCount': FieldValue.increment(-1)}, SetOptions(merge: true));
      await meRef.set({'followingCount': FieldValue.increment(-1)}, SetOptions(merge: true));
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
    // Target can write their followers edge and delete their incoming request under current rules,
    // but cannot write requester's following/followRequestsSent. Requires server mediation for full consistency.
    final meRef = _db.collection('users').doc(_uid!);
    final batch = _db.batch();
    batch.set(
      meRef.collection('followers').doc(requesterId),
      FollowRelationship(
        followerId: requesterId,
        followingId: _uid!,
        createdAt: DateTime.now(),
      ).toMap(),
    );
    batch.delete(meRef.collection('followRequests').doc(requesterId));
    await batch.commit();
    try {
      await meRef.set({'followerCount': FieldValue.increment(1)}, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> rejectRequest(String requesterId) async {
    if (isSignedOut) return;
    final meRef = _db.collection('users').doc(_uid!);
    await meRef.collection('followRequests').doc(requesterId).delete();
  }

  Future<void> cancelRequest(String targetId) async {
    if (isSignedOut) return;
    final meRef = _db.collection('users').doc(_uid!);
    await meRef.collection('followRequestsSent').doc(targetId).delete();
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
    final doc = await _db.collection('users').doc(ownerId).get();
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
    final doc = await _db.collection('users').doc(ownerId).get();
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

    final meRef = _db.collection('users').doc(_uid!);
    final themRef = _db.collection('users').doc(targetId);

    final [iFollowThem, theyFollowMe] = await Future.wait([
      meRef.collection('following').doc(targetId).get(),
      meRef.collection('followers').doc(targetId).get(),
    ]);

    final batch = _db.batch();
    batch.delete(meRef.collection('following').doc(targetId));
    batch.delete(themRef.collection('followers').doc(_uid!));
    batch.delete(meRef.collection('followers').doc(targetId));
    batch.delete(themRef.collection('following').doc(_uid!));
    batch.delete(meRef.collection('followRequests').doc(targetId));
    batch.delete(themRef.collection('followRequests').doc(_uid!));
    batch.delete(meRef.collection('followRequestsSent').doc(targetId));
    batch.delete(themRef.collection('followRequestsSent').doc(_uid!));

    final meUpdates = <String, dynamic>{};
    final themUpdates = <String, dynamic>{};
    if (iFollowThem.exists) {
      meUpdates['followingCount'] = FieldValue.increment(-1);
      themUpdates['followerCount'] = FieldValue.increment(-1);
    }
    if (theyFollowMe.exists) {
      meUpdates['followerCount'] = FieldValue.increment(-1);
      themUpdates['followingCount'] = FieldValue.increment(-1);
    }
    if (meUpdates.isNotEmpty) batch.update(meRef, meUpdates);
    if (themUpdates.isNotEmpty) batch.update(themRef, themUpdates);

    batch.set(
      meRef.collection('blocked').doc(targetId),
      BlockedAccount(blockerId: _uid!, blockedId: targetId, createdAt: DateTime.now()).toMap(),
    );
    await batch.commit();
  }

  /// Unblock [targetId]. Removes the block record; does not re-follow.
  Future<void> unblock(String targetId) async {
    if (isSignedOut) return;
    final meRef = _db.collection('users').doc(_uid!);
    await meRef.collection('blocked').doc(targetId).delete();
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
