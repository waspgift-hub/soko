import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../models/comment_model.dart';
import '../utils/network_error.dart';
import 'api_config.dart';
import 'notification_service.dart';

class CommentService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final NotificationService _notif = NotificationService();

  static const Duration _pollInterval = Duration(seconds: 8);

  CollectionReference _commentsRef(String productId) =>
      _db.collection('products').doc(productId).collection('comments');

  CollectionReference _repliesRef(String productId, String commentId) =>
      _commentsRef(productId).doc(commentId).collection('replies');

  Future<String?> _token() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    try {
      await user.reload();
      return await user.getIdToken(true);
    } catch (_) {
      return null;
    }
  }

  Future<void> addComment({
    required String productId,
    required String text,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw NetworkError(
        message: 'Not logged in',
        userMessage: 'auth_login_required',
      );
    final token = await _token();
    if (token != null) {
      try {
        final res = await http.post(
          Uri.parse(ApiConfig.v1('/products/$productId/comments')),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({'text': text}),
        );
        if (res.statusCode == 201) {
          await _mirrorToFirestore(productId, user, text);
          _notifySeller(productId, user);
          return;
        }
      } catch (_) {}
    }
    await user.reload();
    await user.getIdToken(true);
    await _commentsRef(productId).add({
      'userId': user.uid,
      'userName': user.displayName ?? user.email ?? 'Unknown',
      'userImage': user.photoURL,
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
      'replyCount': 0,
    });

    _notifySeller(productId, user);
  }

  // Postgres row is the source; write the Firestore sub-collection copy so the
  // existing snapshot stream keeps showing live comments during the transition.
  Future<void> _mirrorToFirestore(String productId, User user, String text) async {
    try {
      await _commentsRef(productId).add({
        'userId': user.uid,
        'userName': user.displayName ?? user.email ?? 'Unknown',
        'userImage': user.photoURL,
        'text': text,
        'createdAt': FieldValue.serverTimestamp(),
        'replyCount': 0,
      });
    } catch (_) {}
  }

  Future<void> addReply({
    required String productId,
    required String commentId,
    required String text,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw NetworkError(
        message: 'Not logged in',
        userMessage: 'auth_login_required',
      );
    final token = await _token();
    if (token != null) {
      try {
        final res = await http.post(
          Uri.parse(ApiConfig.v1('/comments/$commentId/replies')),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({'text': text}),
        );
        if (res.statusCode == 201) {
          await _mirrorReplyToFirestore(productId, commentId, user, text);
          _notifyCommentAuthor(productId, commentId, user, text);
          return;
        }
      } catch (_) {}
    }
    await user.reload();
    await user.getIdToken(true);
    await _repliesRef(productId, commentId).add({
      'userId': user.uid,
      'userName': user.displayName ?? user.email ?? 'Unknown',
      'userImage': user.photoURL,
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await _commentsRef(
      productId,
    ).doc(commentId).update({'replyCount': FieldValue.increment(1)});

    _notifyCommentAuthor(productId, commentId, user, text);
  }

  Future<void> _mirrorReplyToFirestore(
    String productId,
    String commentId,
    User user,
    String text,
  ) async {
    try {
      await _repliesRef(productId, commentId).add({
        'userId': user.uid,
        'userName': user.displayName ?? user.email ?? 'Unknown',
        'userImage': user.photoURL,
        'text': text,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await _commentsRef(
        productId,
      ).doc(commentId).update({'replyCount': FieldValue.increment(1)});
    } catch (_) {}
  }

  Future<void> _notifySeller(String productId, User user) async {
    try {
      final productDoc = await _db.collection('products').doc(productId).get();
      if (!productDoc.exists) return;
      final sellerId = productDoc.data()?['sellerId'] as String?;
      if (sellerId == null || sellerId == user.uid) return;
      final name = user.displayName ?? user.email ?? 'Someone';
      _notif.sendNotification(
        userId: sellerId,
        title: 'New Comment on your listing!',
        body: '$name commented on your product',
        data: {
          'type': 'comment',
          'productId': productId,
        },
      );
    } catch (e) {
      debugPrint('CommentService _notifySeller: $e');
    }
  }

  Future<void> _notifyCommentAuthor(
    String productId,
    String commentId,
    User user,
    String replyText,
  ) async {
    try {
      final commentSnap =
          await _commentsRef(productId).doc(commentId).get();
      if (!commentSnap.exists) return;
      final commentData = commentSnap.data() as Map<String, dynamic>?;
      final authorId = commentData?['userId'] as String?;
      if (authorId == null || authorId == user.uid) return;
      final name = user.displayName ?? user.email ?? 'Someone';
      final truncated =
          replyText.length > 80 ? '${replyText.substring(0, 80)}…' : replyText;
      _notif.sendNotification(
        userId: authorId,
        title: 'New reply to your comment!',
        body: '$name replied: "$truncated"',
        data: {
          'type': 'comment_reply',
          'productId': productId,
          'commentId': commentId,
        },
      );
    } catch (e) {
      debugPrint('CommentService _notifyCommentAuthor: $e');
    }
  }

  Future<void> deleteComment({
    required String productId,
    required String commentId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw NetworkError(
        message: 'Not logged in',
        userMessage: 'auth_login_required',
      );
    final token = await _token();
    if (token != null) {
      try {
        final res = await http.delete(
          Uri.parse(ApiConfig.v1('/comments/$commentId')),
          headers: {'Authorization': 'Bearer $token'},
        );
        if (res.statusCode == 200) {
          // Postgres row soft-deleted; remove the mirrored Firestore copy so
          // the snapshot stream stops showing it during the transition.
          try {
            await _commentsRef(productId).doc(commentId).delete();
          } catch (_) {}
          return;
        }
        if (res.statusCode == 403) {
          throw NetworkError(
            message: 'Cannot delete another user\'s comment',
            userMessage: 'comment_edit_own_only',
          );
        }
      } catch (e) {
        if (e is NetworkError) rethrow;
      }
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
    for (var reply in replies.docs) {
      batch.delete(reply.reference);
    }
    batch.delete(_commentsRef(productId).doc(commentId));
    await batch.commit();
  }

  Future<void> deleteReply({
    required String productId,
    required String commentId,
    required String replyId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw NetworkError(
        message: 'Not logged in',
        userMessage: 'auth_login_required',
      );
    final token = await _token();
    if (token != null) {
      try {
        final res = await http.delete(
          Uri.parse(ApiConfig.v1('/comments/$commentId/replies/$replyId')),
          headers: {'Authorization': 'Bearer $token'},
        );
        if (res.statusCode == 200) {
          // Postgres row soft-deleted; remove the mirrored Firestore copy.
          try {
    final replySnap = await _repliesRef(productId, commentId).doc(replyId).get();
    final replyData = replySnap.data() as Map<String, dynamic>?;
    if (replySnap.exists && replyData?['userId'] == user.uid) {
              await _repliesRef(productId, commentId).doc(replyId).delete();
              await _commentsRef(
                productId,
              ).doc(commentId).update({'replyCount': FieldValue.increment(-1)});
            }
          } catch (_) {}
          return;
        }
        if (res.statusCode == 403) {
          throw NetworkError(
            message: 'Cannot delete another user\'s reply',
            userMessage: 'comment_edit_own_only',
          );
        }
      } catch (e) {
        if (e is NetworkError) rethrow;
      }
    }
    final replySnap = await _repliesRef(
      productId,
      commentId,
    ).doc(replyId).get();
    final replyData = replySnap.data() as Map<String, dynamic>?;
    if (replyData == null || replyData['userId'] != user.uid) {
      throw NetworkError(
        message: 'Cannot delete another user\'s reply',
        userMessage: 'comment_edit_own_only',
      );
    }
    await _repliesRef(productId, commentId).doc(replyId).delete();
    await _commentsRef(
      productId,
    ).doc(commentId).update({'replyCount': FieldValue.increment(-1)});
  }

  Stream<List<ProductComment>> getComments(String productId) {
    if (ApiConfig.kUseCommentsApi) {
      return _pollStream<List<ProductComment>>(
        () => _fetchCommentsApi(productId),
      );
    }
    return _commentsRef(productId)
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map(
                (doc) => ProductComment.fromFirestore(
                  doc.id,
                  doc.data() as Map<String, dynamic>,
                ),
              )
              .toList(),
        );
  }

  Stream<List<CommentReply>> getReplies(String productId, String commentId) {
    if (ApiConfig.kUseCommentsApi) {
      return _pollStream<List<CommentReply>>(
        () => _fetchRepliesApi(commentId),
      );
    }
    return _repliesRef(productId, commentId)
        .orderBy('createdAt')
        .limit(50)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map(
                (doc) => CommentReply.fromFirestore(
                  doc.id,
                  commentId,
                  doc.data() as Map<String, dynamic>,
                ),
              )
              .toList(),
        );
  }

  // The Firestore reads live stream; the Postgres reads poll every few seconds
  // until the widget cancels. The Stream contract the widget sees is unchanged:
  // `T` here is the full list type (`List<ProductComment>` etc), so the widget
  // still receives whole snapshots just like the Firestore `snapshots()`.
  Stream<T> _pollStream<T>(Future<T?> Function() fetch) {
    late StreamController<T> controller;
    Timer? timer;
    controller = StreamController<T>.broadcast(
      onListen: () async {
        timer = Timer.periodic(_pollInterval, (_) async {
          final data = await fetch();
          if (data != null && controller.hasListener) controller.add(data);
        });
        final initial = await fetch();
        if (initial != null && controller.hasListener) controller.add(initial);
      },
      onCancel: () {
        timer?.cancel();
        timer = null;
      },
    );
    return controller.stream;
  }

  Future<List<ProductComment>?> _fetchCommentsApi(String productId) async {
    try {
      final token = await _token();
      final res = await http.get(
        Uri.parse(ApiConfig.v1('/products/$productId/comments?limit=100')),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body);
      final data = body['data'];
      if (data is! Map) return null;
      final items = data['items'];
      if (items is! List) return null;
      return items.map((raw) {
        final d = raw as Map<String, dynamic>;
        return ProductComment(
          id: d['id'] as String,
          userId: d['userId'] as String? ?? '',
          userName: d['userName'] as String? ?? 'Unknown',
          userImage: d['userImage'] as String?,
          text: d['text'] as String? ?? '',
          createdAt: DateTime.tryParse(d['createdAt'] as String? ?? '') ??
              DateTime.now(),
          replyCount: (d['replyCount'] as num?)?.toInt() ?? 0,
        );
      }).toList();
    } catch (_) {
      return null;
    }
  }

  Future<List<CommentReply>?> _fetchRepliesApi(String commentId) async {
    try {
      final token = await _token();
      final res = await http.get(
        Uri.parse(ApiConfig.v1('/comments/$commentId/replies')),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body);
      final items = body['data'];
      if (items is! List) return null;
      return items.map((raw) {
        final d = raw as Map<String, dynamic>;
        return CommentReply(
          id: d['id'] as String,
          commentId: commentId,
          userId: d['userId'] as String? ?? '',
          userName: d['userName'] as String? ?? 'Unknown',
          userImage: d['userImage'] as String?,
          text: d['text'] as String? ?? '',
          createdAt: DateTime.tryParse(d['createdAt'] as String? ?? '') ??
              DateTime.now(),
        );
      }).toList();
    } catch (_) {
      return null;
    }
  }
}
