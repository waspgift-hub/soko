import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/comment_model.dart';
import '../utils/network_error.dart';
import 'api_config.dart';
import 'auth_token.dart';

/// A page of top-level comments plus the cursor for the next one.
class CommentPage {
  final List<ProductComment> items;
  final String? nextCursor;
  final bool hasMore;
  final int total;
  final String sort;

  /// False when the seller has switched comments off for this listing. The
  /// server enforces it on write; the client uses it to hide the composer.
  final bool commentsEnabled;

  const CommentPage({
    required this.items,
    this.nextCursor,
    this.hasMore = false,
    this.total = 0,
    this.sort = 'newest',
    this.commentsEnabled = true,
  });

  static const empty = CommentPage(items: [], total: 0);

  CommentPage copyWith({
    List<ProductComment>? items,
    String? nextCursor,
    bool? hasMore,
    int? total,
    bool? commentsEnabled,
  }) {
    return CommentPage(
      items: items ?? this.items,
      nextCursor: nextCursor ?? this.nextCursor,
      hasMore: hasMore ?? this.hasMore,
      total: total ?? this.total,
      sort: sort,
      commentsEnabled: commentsEnabled ?? this.commentsEnabled,
    );
  }
}

/// Product comment client.
///
/// The server (`/api/v1/products/:id/comments`) is the source of truth. The
/// Firestore `products/{id}/comments` sub-collection is a degraded fallback used
/// only when the API is unreachable, so an older app build and a flaky network
/// both keep working without becoming a second write path in normal operation.
class CommentService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const Duration _pollInterval = Duration(seconds: 3);
  static const Duration _maxPollInterval = Duration(seconds: 15);

  static final Map<String, List<void Function()>> _activePolls = {};

  CollectionReference _commentsRef(String productId) =>
      _db.collection('products').doc(productId).collection('comments');

  Future<String?> _token() => AuthToken.current();

  Map<String, String> _headers(String? token) => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  // -------------------------------------------------------------------------
  // Reads
  // -------------------------------------------------------------------------

  /// One page of top-level comments. Never throws: an API failure falls back to
  /// the Firestore mirror, and a total failure returns [CommentPage.empty].
  Future<CommentPage> fetchComments(
    String productId, {
    String sort = 'newest',
    String? cursor,
    int limit = 20,
  }) async {
    final token = await _token();
    try {
      final query = <String, String>{
        'sort': sort,
        'limit': '$limit',
        'cursor': ?cursor,
      };
      final uri = Uri.parse(ApiConfig.v1('/products/$productId/comments'))
          .replace(queryParameters: query);
      final res = await http
          .get(uri, headers: _headers(token))
          .timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final data = body is Map<String, dynamic> ? body['data'] : null;
        if (data is Map<String, dynamic>) {
          final items = (data['items'] as List?)
                  ?.whereType<Map<String, dynamic>>()
                  .map(ProductComment.fromJson)
                  .toList() ??
              const <ProductComment>[];
          return CommentPage(
            items: items,
            nextCursor: data['nextCursor'] as String?,
            hasMore: data['hasMore'] == true,
            total: (data['total'] as num?)?.toInt() ?? items.length,
            sort: (data['sort'] ?? sort).toString(),
            commentsEnabled: data['commentsEnabled'] != false,
          );
        }
      }
    } catch (e) {
      debugPrint('[CommentService] fetchComments fallback: $e');
    }

    final items = await _fetchFirestoreFallback(productId);
    return CommentPage(items: items, total: items.length);
  }

  Future<List<ProductComment>> _fetchFirestoreFallback(String productId) async {
    try {
      final snap = await _commentsRef(productId)
          .orderBy('createdAt', descending: true)
          .limit(50)
          .get();
      return snap.docs
          .map((d) => ProductComment.fromFirestore(d.id, d.data() as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Replies for one root comment, oldest first.
  Future<List<ProductComment>> fetchReplies(
    String productId,
    String commentId, {
    String? cursor,
    int limit = 30,
  }) async {
    final token = await _token();
    try {
      final query = <String, String>{
        'limit': '$limit',
        'cursor': ?cursor,
      };
      final uri = Uri.parse(ApiConfig.v1('/comments/$commentId/replies'))
          .replace(queryParameters: query);
      final res = await http
          .get(uri, headers: _headers(token))
          .timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final items = body is Map<String, dynamic> ? body['data'] : null;
        if (items is List) {
          return items
              .whereType<Map<String, dynamic>>()
              .map(ProductComment.fromJson)
              .toList();
        }
      }
    } catch (e) {
      debugPrint('[CommentService] fetchReplies fallback: $e');
    }

    try {
      final snap = await _db
          .collection('products')
          .doc(productId)
          .collection('comments')
          .doc(commentId)
          .collection('replies')
          .orderBy('createdAt')
          .limit(limit)
          .get();
      return snap.docs
          .map((d) => ProductComment.fromFirestore(d.id, {
                ...d.data(),
                'parentId': commentId,
              }))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Live top-level stream used by the product-detail preview. Polling is
  /// backed off while nothing changes so an idle product page is cheap, and
  /// [refresh] makes a freshly posted comment appear immediately.
  Stream<CommentPage> commentsStream(String productId, {String sort = 'newest'}) {
    return _pollStream<CommentPage>(
      () => fetchComments(productId, sort: sort),
      pollKey: productId,
      fingerprint: (page) => page.items
          .map((c) =>
              '${c.id}:${c.likeCount}:${c.replyCount}:${c.pinned}:${c.deleted}:${c.text.hashCode}:${c.likedByMe}')
          .join('|'),
    );
  }

  Stream<List<ProductComment>> getComments(String productId) =>
      commentsStream(productId).map((page) => page.items);

  Stream<T> _pollStream<T>(
    Future<T> Function() fetch, {
    String Function(T value)? fingerprint,
    String? pollKey,
  }) {
    late StreamController<T> controller;
    Timer? timer;
    var delay = _pollInterval;
    String? lastFingerprint;

    void schedule() {
      timer?.cancel();
      timer = Timer(delay, () async {
        if (!controller.hasListener) return;
        final data = await fetch();
        if (!controller.hasListener) return;
        final key = fingerprint?.call(data);
        if (key == null || key != lastFingerprint) {
          controller.add(data);
          lastFingerprint = key;
          delay = _pollInterval;
        } else {
          final doubled = delay.inSeconds * 2;
          delay = Duration(
            seconds: doubled.clamp(_pollInterval.inSeconds, _maxPollInterval.inSeconds),
          );
        }
        schedule();
      });
    }

    void triggerImmediate() {
      timer?.cancel();
      schedule();
    }

    controller = StreamController<T>.broadcast(
      onListen: () async {
        if (pollKey != null) {
          _activePolls.putIfAbsent(pollKey, () => []).add(triggerImmediate);
        }
        final initial = await fetch();
        if (controller.hasListener) {
          controller.add(initial);
          lastFingerprint = fingerprint?.call(initial);
        }
        delay = _pollInterval;
        schedule();
      },
      onCancel: () {
        timer?.cancel();
        timer = null;
        if (pollKey != null) {
          final list = _activePolls[pollKey];
          if (list != null) {
            list.remove(triggerImmediate);
            if (list.isEmpty) _activePolls.remove(pollKey);
          }
        }
      },
    );
    return controller.stream;
  }

  /// Fires every active poll for [productId] so a new comment shows at once.
  void refresh(String productId) {
    final list = _activePolls[productId];
    if (list == null) return;
    for (final trigger in list) {
      try {
        trigger();
      } catch (_) {}
    }
  }

  // -------------------------------------------------------------------------
  // Writes
  // -------------------------------------------------------------------------

  Future<ProductComment> addComment({required String productId, required String text}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw NetworkError(message: 'Not logged in', userMessage: 'auth_login_required');
    }
    final token = await _token();
    if (token != null) {
      try {
        final res = await http
            .post(
              Uri.parse(ApiConfig.v1('/products/$productId/comments')),
              headers: _headers(token),
              body: jsonEncode({'text': text}),
            )
            .timeout(const Duration(seconds: 15));
        if (res.statusCode == 201) {
          final body = jsonDecode(res.body);
          final data = body is Map<String, dynamic> ? body['data'] : null;
          if (data is Map<String, dynamic>) {
            refresh(productId);
            return ProductComment.fromJson(data);
          }
        }
        if (res.statusCode == 422) {
          throw NetworkError(message: 'Profanity detected', userMessage: 'profanity_detected');
        }
        if (res.statusCode == 429) {
          throw NetworkError(message: 'Duplicate comment', userMessage: 'comment_duplicate');
        }
      } catch (e) {
        if (e is NetworkError) rethrow;
        debugPrint('[CommentService] addComment API failed: $e');
      }
    }

    final ref = await _commentsRef(productId).add({
      'userId': user.uid,
      'userName': user.displayName ?? user.email ?? 'Unknown',
      'userImage': user.photoURL,
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
      'replyCount': 0,
      'likeCount': 0,
    });
    refresh(productId);
    return ProductComment(
      id: ref.id,
      userId: user.uid,
      userName: user.displayName ?? user.email ?? 'Unknown',
      userImage: user.photoURL,
      text: text,
      createdAt: DateTime.now(),
    );
  }

  Future<ProductComment> addReply({
    required String productId,
    required String commentId,
    required String text,
    String? replyToId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw NetworkError(message: 'Not logged in', userMessage: 'auth_login_required');
    }
    final token = await _token();
    if (token != null) {
      try {
        final res = await http
            .post(
              Uri.parse(ApiConfig.v1('/comments/$commentId/replies')),
              headers: _headers(token),
              body: jsonEncode({
                'text': text,
                'replyToId': ?replyToId,
              }),
            )
            .timeout(const Duration(seconds: 15));
        if (res.statusCode == 201) {
          final body = jsonDecode(res.body);
          final data = body is Map<String, dynamic> ? body['data'] : null;
          if (data is Map<String, dynamic>) {
            refresh(productId);
            return ProductComment.fromJson(data);
          }
        }
        if (res.statusCode == 422) {
          throw NetworkError(message: 'Profanity detected', userMessage: 'profanity_detected');
        }
        if (res.statusCode == 429) {
          throw NetworkError(message: 'Duplicate comment', userMessage: 'comment_duplicate');
        }
      } catch (e) {
        if (e is NetworkError) rethrow;
        debugPrint('[CommentService] addReply API failed: $e');
      }
    }

    final ref = await _repliesRef(productId, commentId).add({
      'userId': user.uid,
      'userName': user.displayName ?? user.email ?? 'Unknown',
      'userImage': user.photoURL,
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
    });
    try {
      await _commentsRef(productId).doc(commentId).update({'replyCount': FieldValue.increment(1)});
    } catch (_) {}
    refresh(productId);
    return ProductComment(
      id: ref.id,
      userId: user.uid,
      userName: user.displayName ?? user.email ?? 'Unknown',
      userImage: user.photoURL,
      text: text,
      createdAt: DateTime.now(),
      parentId: commentId,
    );
  }

  CollectionReference _repliesRef(String productId, String commentId) =>
      _commentsRef(productId).doc(commentId).collection('replies');

  Future<ProductComment?> editComment({
    required String productId,
    required String commentId,
    required String text,
  }) async {
    final token = await _token();
    if (token == null) {
      throw NetworkError(message: 'Not logged in', userMessage: 'auth_login_required');
    }
    final res = await http
        .patch(
          Uri.parse(ApiConfig.v1('/comments/$commentId')),
          headers: _headers(token),
          body: jsonEncode({'text': text}),
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode == 200) {
      final body = jsonDecode(res.body);
      final data = body is Map<String, dynamic> ? body['data'] : null;
      refresh(productId);
      return data is Map<String, dynamic> ? ProductComment.fromJson(data) : null;
    }
    if (res.statusCode == 403) {
      throw NetworkError(
        message: 'Cannot edit another user\'s comment',
        userMessage: 'comment_edit_own_only',
      );
    }
    throw NetworkError(message: 'Failed to edit comment', userMessage: 'something_wrong');
  }

  /// Locks/unlocks one comment's like. Returns the authoritative
  /// `(liked, likeCount)` pair so the caller can reconcile an optimistic tap.
  Future<({bool liked, int likeCount})> toggleLike(String commentId) async {
    final token = await _token();
    if (token == null) {
      throw NetworkError(message: 'Not logged in', userMessage: 'auth_login_required');
    }
    final res = await http
        .post(
          Uri.parse(ApiConfig.v1('/comments/$commentId/like')),
          headers: _headers(token),
        )
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) {
      throw NetworkError(message: 'Failed to update like', userMessage: 'something_wrong');
    }
    final body = jsonDecode(res.body);
    final data = body is Map<String, dynamic> ? body['data'] : null;
    final map = data is Map<String, dynamic> ? data : const <String, dynamic>{};
    return (
      liked: map['liked'] == true,
      likeCount: (map['likeCount'] as num?)?.toInt() ?? 0,
    );
  }

  /// Switches comments on/off for a listing. Seller-only on the server.
  Future<void> setCommentsEnabled({
    required String productId,
    required bool enabled,
  }) async {
    final token = await _token();
    if (token == null) {
      throw NetworkError(message: 'Not logged in', userMessage: 'auth_login_required');
    }
    final res = await http
        .patch(
          Uri.parse(ApiConfig.v1('/products/$productId/comments/settings')),
          headers: _headers(token),
          body: jsonEncode({'enabled': enabled}),
        )
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) {
      throw NetworkError(
        message: 'Failed to update comment settings',
        userMessage: 'something_wrong',
      );
    }
  }

  Future<void> setPinned({required String commentId, required bool pinned}) async {
    final token = await _token();
    if (token == null) {
      throw NetworkError(message: 'Not logged in', userMessage: 'auth_login_required');
    }
    final uri = Uri.parse(ApiConfig.v1('/comments/$commentId/pin'));
    final res = pinned
        ? await http.post(uri, headers: _headers(token)).timeout(const Duration(seconds: 12))
        : await http.delete(uri, headers: _headers(token)).timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) {
      throw NetworkError(message: 'Failed to pin comment', userMessage: 'something_wrong');
    }
  }

  Future<void> reportComment({required String commentId, String reason = 'other'}) async {
    final token = await _token();
    if (token == null) {
      throw NetworkError(message: 'Not logged in', userMessage: 'auth_login_required');
    }
    final res = await http
        .post(
          Uri.parse(ApiConfig.v1('/comments/$commentId/report')),
          headers: _headers(token),
          body: jsonEncode({'reason': reason}),
        )
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 201 && res.statusCode != 200) {
      throw NetworkError(message: 'Failed to report comment', userMessage: 'something_wrong');
    }
  }

  Future<void> deleteComment({required String productId, required String commentId}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw NetworkError(message: 'Not logged in', userMessage: 'auth_login_required');
    }
    final token = await _token();
    if (token != null) {
      final res = await http
          .delete(
            Uri.parse(ApiConfig.v1('/comments/$commentId')),
            headers: _headers(token),
          )
          .timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        refresh(productId);
        return;
      }
      if (res.statusCode == 403) {
        throw NetworkError(
          message: 'Cannot delete another user\'s comment',
          userMessage: 'comment_edit_own_only',
        );
      }
      throw NetworkError(message: 'Failed to delete comment', userMessage: 'something_wrong');
    }

    final commentSnap = await _commentsRef(productId).doc(commentId).get();
    final commentData = commentSnap.data() as Map<String, dynamic>?;
    if (commentData == null || commentData['userId'] != user.uid) {
      throw NetworkError(
        message: 'Cannot delete another user\'s comment',
        userMessage: 'comment_edit_own_only',
      );
    }
    final replies = await _repliesRef(productId, commentId).get();
    final batch = _db.batch();
    for (final reply in replies.docs) {
      batch.delete(reply.reference);
    }
    batch.delete(_commentsRef(productId).doc(commentId));
    await batch.commit();
    refresh(productId);
  }

  Future<void> deleteReply({
    required String productId,
    required String commentId,
    required String replyId,
  }) async {
    final token = await _token();
    if (token == null) {
      throw NetworkError(message: 'Not logged in', userMessage: 'auth_login_required');
    }
    final res = await http
        .delete(
          Uri.parse(ApiConfig.v1('/comments/$commentId/replies/$replyId')),
          headers: _headers(token),
        )
        .timeout(const Duration(seconds: 12));
    if (res.statusCode == 200) {
      refresh(productId);
      return;
    }
    if (res.statusCode == 403) {
      throw NetworkError(
        message: 'Cannot delete another user\'s reply',
        userMessage: 'comment_edit_own_only',
      );
    }
    throw NetworkError(message: 'Failed to delete reply', userMessage: 'something_wrong');
  }

  /// Resolves an `@handle` to a profile so a tapped mention can navigate.
  Future<Map<String, dynamic>?> findUserByUsername(String username) async {
    final handle = username.trim().toLowerCase();
    if (handle.isEmpty) return null;
    try {
      final snap = await _db
          .collection('userPublic')
          .where('usernameLower', isEqualTo: handle)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return null;
      final doc = snap.docs.first;
      final data = doc.data();
      return <String, dynamic>{
        'userId': doc.id,
        'username': data['username'] ?? handle,
        'displayName': data['displayName'] ?? data['username'] ?? '',
      };
    } catch (e) {
      debugPrint('[CommentService] findUserByUsername failed: $e');
      return null;
    }
  }

  /// Username suggestions for the composer's `@mention` picker.
  Future<List<Map<String, dynamic>>> searchMentionUsers(String query) async {
    final q = query.trim().toLowerCase();
    if (q.length < 2) return const [];
    try {
      final snap = await _db
          .collection('userPublic')
          .where('usernameLower', isGreaterThanOrEqualTo: q)
          .where('usernameLower', isLessThan: '$q\uf8ff')
          .limit(6)
          .get();
      return snap.docs.map((d) {
        final data = d.data();
        return <String, dynamic>{
          'userId': d.id,
          'username': data['username'] ?? '',
          'displayName': data['displayName'] ?? data['username'] ?? '',
          'avatarUrl': data['avatarUrl'] ?? '',
        };
      }).where((u) => (u['username'] as String).isNotEmpty).toList();
    } catch (e) {
      debugPrint('[CommentService] mention search failed: $e');
      return const [];
    }
  }
}
