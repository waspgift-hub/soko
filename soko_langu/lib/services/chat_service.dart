import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/message_model.dart';
import 'notification_service.dart';

class ChatService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String _getConversationId(String userId1, String userId2) {
    return userId1.compareTo(userId2) < 0
        ? '${userId1}_$userId2'
        : '${userId2}_$userId1';
  }

  // =========================
  // 🔍 CHECK IF CONVERSATION EXISTS
  // =========================
  Future<bool> hasConversation(String otherUserId) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return false;
    final conversationId = _getConversationId(currentUser.uid, otherUserId);
    final doc = await _db.collection("conversations").doc(conversationId).get();
    return doc.exists;
  }

  // =========================
  // 💬 SEND MESSAGE
  // =========================
  Future<void> sendMessage({
    required String receiverId,
    required String content,
    String? productId,
    String? productName,
  }) async {
    try {
      final sender = _auth.currentUser;
      if (sender == null) throw Exception("User not logged in");

      final conversationId = _getConversationId(sender.uid, receiverId);

      await _db
          .collection("conversations")
          .doc(conversationId)
          .collection("messages")
          .add({
            'senderId': sender.uid,
            'receiverId': receiverId,
            'content': content,
            'timestamp': FieldValue.serverTimestamp(),
            'isRead': false,
            'isEdited': false,
            'productId': productId,
            'productName': productName,
          });

      await _db.collection("conversations").doc(conversationId).set({
        'participants': [sender.uid, receiverId],
        'lastMessage': content,
        'lastMessageTime': FieldValue.serverTimestamp(),
        'otherUserName': sender.displayName ?? sender.email ?? '',
        'otherUserImage': sender.photoURL,
        'unreadCount': FieldValue.increment(1),
      }, SetOptions(merge: true));

      NotificationService().sendNotification(
        userId: receiverId,
        title: sender.displayName ?? sender.email ?? 'New message',
        body: content,
        data: {
          'type': 'chat',
          'senderId': sender.uid,
          'conversationId': conversationId,
          'senderName': sender.displayName ?? sender.email ?? '',
        },
      );
    } catch (e) {
      throw Exception("Failed to send message: $e");
    }
  }

  // =========================
  // ✏️ EDIT MESSAGE
  // =========================
  Future<void> editMessage({
    required String otherUserId,
    required String messageId,
    required String newContent,
  }) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) throw Exception("User not logged in");

      final conversationId = _getConversationId(currentUser.uid, otherUserId);

      await _db
          .collection("conversations")
          .doc(conversationId)
          .collection("messages")
          .doc(messageId)
          .update({'content': newContent, 'isEdited': true});

      await _db.collection("conversations").doc(conversationId).update({
        'lastMessage': newContent,
      });
    } catch (e) {
      throw Exception("Failed to edit message: $e");
    }
  }

  // =========================
  // 🗑️ DELETE MESSAGE (soft delete)
  // =========================
  Future<void> deleteMessage({
    required String otherUserId,
    required String messageId,
  }) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) throw Exception("User not logged in");

      final conversationId = _getConversationId(currentUser.uid, otherUserId);

      await _db
          .collection("conversations")
          .doc(conversationId)
          .collection("messages")
          .doc(messageId)
          .update({'content': 'deleted', 'isEdited': false});
    } catch (e) {
      throw Exception("Failed to delete message: $e");
    }
  }

  // =========================
  // 📨 GET MESSAGES (paged)
  // =========================
  Stream<List<Message>> getMessages(
    String otherUserId, {
    int limit = 50,
  }) {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return Stream.value([]);

    final conversationId = _getConversationId(currentUser.uid, otherUserId);

    return _db
        .collection("conversations")
        .doc(conversationId)
        .collection("messages")
        .orderBy("timestamp", descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map((doc) => Message.fromFirestore(doc)).toList(),
        );
  }

  // =========================
  // 📨 LOAD OLDER MESSAGES (pagination)
  // =========================
  Future<List<Message>> loadOlderMessages(
    String otherUserId, {
    required DocumentSnapshot? lastDoc,
    int limit = 30,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return [];

    final conversationId = _getConversationId(currentUser.uid, otherUserId);
    var query = _db
        .collection("conversations")
        .doc(conversationId)
        .collection("messages")
        .orderBy("timestamp", descending: true)
        .limit(limit);

    if (lastDoc != null) {
      query = query.startAfterDocument(lastDoc);
    }

    final snap = await query.get();
    return snap.docs.map((doc) => Message.fromFirestore(doc)).toList();
  }

  // =========================
  // 📋 GET CONVERSATIONS
  // =========================
  Stream<List<Conversation>> getConversations() {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return Stream.value([]);

    return _db
        .collection("conversations")
        .where("participants", arrayContains: currentUser.uid)
        .orderBy("lastMessageTime", descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => Conversation.fromFirestore(doc))
              .toList(),
        );
  }

  // =========================
  // 🗑️ DELETE CONVERSATION
  // =========================
  Future<void> deleteConversation(String otherUserId) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) throw Exception("Not logged in");
    final conversationId = _getConversationId(currentUser.uid, otherUserId);

    final messages = await _db
        .collection("conversations")
        .doc(conversationId)
        .collection("messages")
        .get();

    final batch = _db.batch();
    for (var msg in messages.docs) {
      batch.delete(msg.reference);
    }
    batch.delete(_db.collection("conversations").doc(conversationId));
    await batch.commit();
  }

  // =========================
  // ✅ MARK MESSAGES AS READ
  // =========================
  Future<void> markAsRead(String otherUserId) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return;

      final conversationId = _getConversationId(currentUser.uid, otherUserId);

      final messages = await _db
          .collection("conversations")
          .doc(conversationId)
          .collection("messages")
          .where("receiverId", isEqualTo: currentUser.uid)
          .where("isRead", isEqualTo: false)
          .get();

      final batch = _db.batch();
      for (var doc in messages.docs) {
        batch.update(doc.reference, {'isRead': true});
      }
      await batch.commit();

      await _db.collection("conversations").doc(conversationId).update({
        'unreadCount': 0,
      });
    } catch (e) {
      throw Exception("Failed to mark as read: $e");
    }
  }
}
