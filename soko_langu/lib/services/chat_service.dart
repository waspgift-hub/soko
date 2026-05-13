import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/message_model.dart';

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
        'unreadCount': FieldValue.increment(1),
      }, SetOptions(merge: true));
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
  // 📨 GET MESSAGES
  // =========================
  Stream<List<Message>> getMessages(String otherUserId) {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return Stream.value([]);

    final conversationId = _getConversationId(currentUser.uid, otherUserId);

    return _db
        .collection("conversations")
        .doc(conversationId)
        .collection("messages")
        .orderBy("timestamp", descending: true)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map((doc) => Message.fromFirestore(doc)).toList(),
        );
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
        .snapshots()
        .map((snapshot) {
          final list = snapshot.docs
              .map((doc) => Conversation.fromFirestore(doc))
              .toList();
          list.sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));
          return list;
        });
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
  // =========================
  // ⌨️ TYPING INDICATOR
  // =========================
  Future<void> startTyping(String otherUserId) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final convId = _getConversationId(user.uid, otherUserId);
    await _db.collection("conversations").doc(convId).set({
      'typing_${user.uid}': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> stopTyping(String otherUserId) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final convId = _getConversationId(user.uid, otherUserId);
    await _db.collection("conversations").doc(convId).update({
      'typing_${user.uid}': null,
    });
  }

  Stream<bool> typingStream(String otherUserId) {
    final user = _auth.currentUser;
    if (user == null) return Stream.value(false);
    final convId = _getConversationId(user.uid, otherUserId);
    return _db.collection("conversations").doc(convId).snapshots().map((snap) {
      if (!snap.exists) return false;
      final data = snap.data();
      if (data == null) return false;
      return data['typing_$otherUserId'] != null;
    });
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
