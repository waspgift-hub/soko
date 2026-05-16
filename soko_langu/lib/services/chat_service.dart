import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/message_model.dart';
import 'notification_service.dart';

class ChatService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get _uid => _auth.currentUser?.uid ?? '';
  bool get _loggedIn => _auth.currentUser != null;

  String _getConversationId(String userId1, String userId2) {
    return userId1.compareTo(userId2) < 0
        ? '${userId1}_$userId2'
        : '${userId2}_$userId1';
  }

  Future<bool> isBlocked(String otherUserId) async {
    if (!_loggedIn) return false;
    final doc = await _db.collection('blocked').doc(_getConversationId(_uid, otherUserId)).get();
    return doc.exists;
  }

  Future<void> blockUser(String otherUserId) async {
    if (!_loggedIn) return;
    await _db.collection('blocked').doc(_getConversationId(_uid, otherUserId)).set({
      'userId': _uid,
      'blockedUserId': otherUserId,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<void> unblockUser(String otherUserId) async {
    if (!_loggedIn) return;
    await _db.collection('blocked').doc(_getConversationId(_uid, otherUserId)).delete();
  }

  Stream<List<String>> getBlockedUsers() {
    if (!_loggedIn) return Stream.value([]);
    return _db
        .collection('blocked')
        .where('userId', isEqualTo: _uid)
        .snapshots()
        .map((snap) => snap.docs.map((doc) => doc.data()['blockedUserId'] as String).toList());
  }

  Future<void> pinConversation(String otherUserId) async {
    if (!_loggedIn) return;
    final convId = _getConversationId(_uid, otherUserId);
    await _db.collection('conversations').doc(convId).set({'isPinned': true}, SetOptions(merge: true));
  }

  Future<void> unpinConversation(String otherUserId) async {
    if (!_loggedIn) return;
    final convId = _getConversationId(_uid, otherUserId);
    await _db.collection('conversations').doc(convId).set({'isPinned': false}, SetOptions(merge: true));
  }

  Future<void> muteConversation(String otherUserId) async {
    if (!_loggedIn) return;
    final convId = _getConversationId(_uid, otherUserId);
    await _db.collection('conversations').doc(convId).set({'isMuted': true}, SetOptions(merge: true));
  }

  Future<void> unmuteConversation(String otherUserId) async {
    if (!_loggedIn) return;
    final convId = _getConversationId(_uid, otherUserId);
    await _db.collection('conversations').doc(convId).set({'isMuted': false}, SetOptions(merge: true));
  }

  Future<bool> hasConversation(String otherUserId) async {
    if (!_loggedIn) return false;
    final conversationId = _getConversationId(_uid, otherUserId);
    final doc = await _db.collection("conversations").doc(conversationId).get();
    return doc.exists;
  }

  Future<void> sendMessage({
    required String receiverId,
    required String content,
    String? productId,
    String? productName,
    String? replyTo,
    String? replyToContent,
    String? replyToSender,
    String messageType = 'text',
  }) async {
    if (!_loggedIn) throw Exception("User not logged in");

    final conversationId = _getConversationId(_uid, receiverId);

    await _db
        .collection("conversations")
        .doc(conversationId)
        .collection("messages")
        .add({
          'senderId': _uid,
          'receiverId': receiverId,
          'content': content,
          'timestamp': FieldValue.serverTimestamp(),
          'isRead': false,
          'isDelivered': true,
          'isEdited': false,
          'productId': productId,
          'productName': productName,
          'replyTo': replyTo,
          'replyToContent': replyToContent,
          'replyToSender': replyToSender,
          'messageType': messageType,
          'isDeletedForEveryone': false,
          'reactions': {},
        });

    final displayContent = messageType == 'image' ? '📷 Picha' : messageType == 'voice' ? '🎤 Sauti' : content;
    await _db.collection("conversations").doc(conversationId).set({
      'participants': [_uid, receiverId],
      'lastMessage': displayContent,
      'lastMessageTime': FieldValue.serverTimestamp(),
      'otherUserName': _auth.currentUser!.displayName ?? _auth.currentUser!.email ?? '',
      'otherUserImage': _auth.currentUser!.photoURL,
      'unreadCount': FieldValue.increment(1),
    }, SetOptions(merge: true));

    NotificationService().sendNotification(
      userId: receiverId,
      title: _auth.currentUser!.displayName ?? _auth.currentUser!.email ?? 'New message',
      body: displayContent,
      data: {
        'type': 'chat',
        'senderId': _uid,
        'conversationId': conversationId,
        'senderName': _auth.currentUser!.displayName ?? _auth.currentUser!.email ?? '',
      },
    );
  }

  Future<void> editMessage({
    required String otherUserId,
    required String messageId,
    required String newContent,
  }) async {
    if (!_loggedIn) throw Exception("User not logged in");
    final conversationId = _getConversationId(_uid, otherUserId);
    await _db
        .collection("conversations")
        .doc(conversationId)
        .collection("messages")
        .doc(messageId)
        .update({'content': newContent, 'isEdited': true});
  }

  Future<void> deleteMessageForMe({
    required String otherUserId,
    required String messageId,
  }) async {
    if (!_loggedIn) throw Exception("User not logged in");
    final conversationId = _getConversationId(_uid, otherUserId);
    await _db
        .collection("conversations")
        .doc(conversationId)
        .collection("messages")
        .doc(messageId)
        .update({'content': 'deleted', 'isEdited': false});
  }

  Future<void> deleteMessageForEveryone({
    required String otherUserId,
    required String messageId,
  }) async {
    if (!_loggedIn) throw Exception("User not logged in");
    final conversationId = _getConversationId(_uid, otherUserId);
    final msgDoc = _db
        .collection("conversations")
        .doc(conversationId)
        .collection("messages")
        .doc(messageId);
    final snap = await msgDoc.get();
    if (!snap.exists) return;
    final msgTime = (snap.data()?['timestamp'] as Timestamp?)?.toDate();
    if (msgTime == null) return;
    final diff = DateTime.now().difference(msgTime);
    if (diff.inMinutes > 15) throw Exception('Muda umeisha. Unaweza futa ndani ya dakika 15 tu.');
    await msgDoc.update({
      'content': 'Umejumbe imefutwa',
      'isDeletedForEveryone': true,
      'isEdited': false,
    });
  }

  Future<void> forwardMessage({
    required String messageId,
    required String fromUserId,
    required String toUserId,
  }) async {
    if (!_loggedIn) throw Exception("User not logged in");
    final fromConvId = _getConversationId(_uid, fromUserId);
    final msgDoc = await _db
        .collection("conversations")
        .doc(fromConvId)
        .collection("messages")
        .doc(messageId)
        .get();
    if (!msgDoc.exists) return;
    final data = msgDoc.data()!;
    final toConvId = _getConversationId(_uid, toUserId);
    await _db
        .collection("conversations")
        .doc(toConvId)
        .collection("messages")
        .add({
          'senderId': _uid,
          'receiverId': toUserId,
          'content': data['content'] ?? '',
          'timestamp': FieldValue.serverTimestamp(),
          'isRead': false,
          'isDelivered': true,
          'isEdited': false,
          'messageType': data['messageType'] ?? 'text',
          'isDeletedForEveryone': false,
          'reactions': {},
          'replyToContent': '↪️ Imetumwa tena',
          'replyToSender': data['senderId'],
        });
    final displayContent = (data['messageType'] ?? 'text') == 'image' ? '📷 Picha' : (data['content'] ?? '');
    await _db.collection("conversations").doc(toConvId).set({
      'participants': [_uid, toUserId],
      'lastMessage': displayContent,
      'lastMessageTime': FieldValue.serverTimestamp(),
      'otherUserName': _auth.currentUser!.displayName ?? _auth.currentUser!.email ?? '',
      'otherUserImage': _auth.currentUser!.photoURL,
      'unreadCount': FieldValue.increment(1),
    }, SetOptions(merge: true));
  }

  Future<void> addReaction({
    required String otherUserId,
    required String messageId,
    required String emoji,
  }) async {
    if (!_loggedIn) return;
    final conversationId = _getConversationId(_uid, otherUserId);
    final msgRef = _db
        .collection("conversations")
        .doc(conversationId)
        .collection("messages")
        .doc(messageId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(msgRef);
      if (!snap.exists) return;
      final data = snap.data() ?? {};
      final reactions = Map<String, dynamic>.from(data['reactions'] ?? {});
      final users = List<String>.from(reactions[emoji] ?? []);
      if (users.contains(_uid)) {
        users.remove(_uid);
        if (users.isEmpty) reactions.remove(emoji);
        else reactions[emoji] = users;
      } else {
        users.add(_uid);
        reactions[emoji] = users;
      }
      tx.update(msgRef, {'reactions': reactions});
    });
  }

  Stream<List<Message>> getMessages(String otherUserId, {int limit = 50}) {
    if (!_loggedIn) return Stream.value([]);
    final conversationId = _getConversationId(_uid, otherUserId);
    return _db
        .collection("conversations")
        .doc(conversationId)
        .collection("messages")
        .orderBy("timestamp", descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => Message.fromFirestore(doc)).toList());
  }

  Future<List<Message>> loadOlderMessages(
    String otherUserId, {
    required DocumentSnapshot? lastDoc,
    int limit = 30,
  }) async {
    if (!_loggedIn) return [];
    final conversationId = _getConversationId(_uid, otherUserId);
    var query = _db
        .collection("conversations")
        .doc(conversationId)
        .collection("messages")
        .orderBy("timestamp", descending: true)
        .limit(limit);
    if (lastDoc != null) query = query.startAfterDocument(lastDoc);
    final snap = await query.get();
    return snap.docs.map((doc) => Message.fromFirestore(doc)).toList();
  }

  Future<List<Message>> searchMessages(String otherUserId, String query) async {
    if (!_loggedIn) return [];
    final conversationId = _getConversationId(_uid, otherUserId);
    final snap = await _db
        .collection("conversations")
        .doc(conversationId)
        .collection("messages")
        .orderBy("timestamp", descending: true)
        .limit(200)
        .get();
    return snap.docs
        .map((doc) => Message.fromFirestore(doc))
        .where((msg) => msg.content.toLowerCase().contains(query.toLowerCase()))
        .toList();
  }

  Stream<List<Conversation>> getConversations() {
    if (!_loggedIn) return Stream.value([]);
    return _db
        .collection("conversations")
        .where("participants", arrayContains: _uid)
        .orderBy("lastMessageTime", descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => Conversation.fromFirestore(doc)).toList());
  }

  Future<void> deleteConversation(String otherUserId) async {
    if (!_loggedIn) throw Exception("Not logged in");
    final conversationId = _getConversationId(_uid, otherUserId);
    final messages = await _db
        .collection("conversations")
        .doc(conversationId)
        .collection("messages")
        .get();
    final batch = _db.batch();
    for (var msg in messages.docs) batch.delete(msg.reference);
    batch.delete(_db.collection("conversations").doc(conversationId));
    await batch.commit();
  }

  Future<void> markAsRead(String otherUserId) async {
    if (!_loggedIn) return;
    final conversationId = _getConversationId(_uid, otherUserId);
    final messages = await _db
        .collection("conversations")
        .doc(conversationId)
        .collection("messages")
        .where("receiverId", isEqualTo: _uid)
        .where("isRead", isEqualTo: false)
        .get();
    final batch = _db.batch();
    for (var doc in messages.docs) {
      batch.update(doc.reference, {'isRead': true});
    }
    await batch.commit();
    await _db.collection("conversations").doc(conversationId).update({'unreadCount': 0});
  }

  Future<void> markAsDelivered(String messageId, String otherUserId) async {
    if (!_loggedIn) return;
    final conversationId = _getConversationId(_uid, otherUserId);
    await _db
        .collection("conversations")
        .doc(conversationId)
        .collection("messages")
        .doc(messageId)
        .update({'isDelivered': true});
  }
}
