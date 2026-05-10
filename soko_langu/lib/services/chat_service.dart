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

      // Add message
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
            'productId': productId,
            'productName': productName,
          });

      // Update conversation
      await _db.collection("conversations").doc(conversationId).set({
        'participants': [sender.uid, receiverId],
        'lastMessage': content,
        'lastMessageTime': FieldValue.serverTimestamp(),
        'otherUserName': sender.displayName ?? sender.email ?? '',
        'otherUserImage': sender.photoURL,
        'unreadCount': FieldValue.increment(1),
      }, SetOptions(merge: true));
    } catch (e) {
      throw Exception("Failed to send message: $e");
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
        .orderBy("lastMessageTime", descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => Conversation.fromFirestore(doc))
              .toList(),
        );
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

      // Reset unread count
      await _db.collection("conversations").doc(conversationId).update({
        'unreadCount': 0,
      });
    } catch (e) {
      throw Exception("Failed to mark as read: $e");
    }
  }
}
