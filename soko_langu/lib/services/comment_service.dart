import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/comment_model.dart';
import '../utils/network_error.dart';

class CommentService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference _commentsRef(String productId) =>
      _db.collection('products').doc(productId).collection('comments');

  CollectionReference _repliesRef(String productId, String commentId) =>
      _commentsRef(productId).doc(commentId).collection('replies');

  Future<void> addComment({
    required String productId,
    required String text,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw NetworkError(
        message: 'Not logged in',
        userMessage: 'Please log in to continue.',
      );
    await _commentsRef(productId).add({
      'userId': user.uid,
      'userName': user.displayName ?? user.email ?? 'Unknown',
      'userImage': user.photoURL,
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
      'replyCount': 0,
    });
  }

  Future<void> addReply({
    required String productId,
    required String commentId,
    required String text,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw NetworkError(
        message: 'Not logged in',
        userMessage: 'Please log in to continue.',
      );
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
  }

  Future<void> deleteComment({
    required String productId,
    required String commentId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw NetworkError(
        message: 'Not logged in',
        userMessage: 'Please log in to continue.',
      );
    final commentSnap = await _commentsRef(productId).doc(commentId).get();
    final commentData = commentSnap.data() as Map<String, dynamic>?;
    if (commentData == null || commentData['userId'] != user.uid) {
      throw NetworkError(
        message: 'Cannot delete another user\'s comment',
        userMessage: 'You can only delete your own comments.',
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
        userMessage: 'Please log in to continue.',
      );
    final replySnap = await _repliesRef(
      productId,
      commentId,
    ).doc(replyId).get();
    final replyData = replySnap.data() as Map<String, dynamic>?;
    if (replyData == null || replyData['userId'] != user.uid) {
      throw NetworkError(
        message: 'Cannot delete another user\'s reply',
        userMessage: 'You can only delete your own replies.',
      );
    }
    await _repliesRef(productId, commentId).doc(replyId).delete();
    await _commentsRef(
      productId,
    ).doc(commentId).update({'replyCount': FieldValue.increment(-1)});
  }

  Stream<List<ProductComment>> getComments(String productId) {
    return _commentsRef(productId)
        .orderBy('createdAt', descending: true)
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
    return _repliesRef(productId, commentId)
        .orderBy('createdAt')
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
}
