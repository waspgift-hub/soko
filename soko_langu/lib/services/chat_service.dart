import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/chat_room.dart';
import '../models/chat_message.dart';
import '../models/message_model.dart';
import 'api_config.dart';

class ChatService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String _roomIdFor(String uid1, String uid2) {
    final ids = [uid1, uid2]..sort();
    return ids.join('_');
  }

  String? otherParticipant(ChatRoom room, String currentUid) {
    return room.participants.where((p) => p != currentUid).firstOrNull;
  }

  Future<String> getUserName(String uid) async {
    try {
      final doc = await _db.collection('users').doc(uid).get();
      if (!doc.exists) return uid.substring(0, 8);
      final data = doc.data()!;
      return (data['displayName'] as String?)?.trim() ??
          (data['name'] as String?)?.trim() ??
          uid.substring(0, 8);
    } catch (_) {
      return uid.substring(0, 8);
    }
  }

  Future<String> getOrCreateRoom({
    required String otherUserId,
    String? productId,
    String? productTitle,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not logged in');
    final roomId = _roomIdFor(user.uid, otherUserId);

    final existing = await _db.collection('chat_rooms').doc(roomId).get();
    if (existing.exists) return roomId;

    await _db.collection('chat_rooms').doc(roomId).set({
      'participants': [user.uid, otherUserId],
      'last_message': '',
      'last_timestamp': FieldValue.serverTimestamp(),
      'unread_count_buyer': 0,
      'unread_count_seller': 0,
      if (productId != null) 'product_id': productId,
      if (productTitle != null) 'product_title': productTitle,
    });

    if (kDebugMode) debugPrint('ChatService: created room $roomId');
    return roomId;
  }

  Stream<List<ChatRoom>> getRooms() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream.value([]);
    return _db
        .collection('chat_rooms')
        .where('participants', arrayContains: user.uid)
        .orderBy('last_timestamp', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => ChatRoom.fromMap(doc.id, doc.data()))
            .toList());
  }

  Stream<List<Message>> getMessages(String roomId) {
    return _db
        .collection('chat_rooms')
        .doc(roomId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => Message.fromMap(doc.id, doc.data()))
            .toList());
  }

  Future<void> sendMessage({
    required String receiverId,
    required String content,
    String? productId,
    String? productName,
    String? replyTo,
    String? replyToContent,
    String? replyToSender,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final roomId = _roomIdFor(user.uid, receiverId);

    final data = <String, dynamic>{
      'sender_id': user.uid,
      'text': content,
      'timestamp': FieldValue.serverTimestamp(),
      'is_read': false,
    };
    await _db.collection('chat_rooms').doc(roomId).collection('messages').add(data);

    final update = <String, dynamic>{
      'last_message': content,
      'last_timestamp': FieldValue.serverTimestamp(),
    };
    await _db.collection('chat_rooms').doc(roomId).update(update);

    _sendPushNotification(
      otherId: receiverId,
      senderName: user.displayName ?? user.email ?? 'Mtumiaji',
      message: content,
      roomId: roomId,
    );
  }

  Future<void> markAsRead(String roomId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final roomDoc = await _db.collection('chat_rooms').doc(roomId).get();
    final room = roomDoc.data();
    if (room == null) return;

    final userDoc = await _db.collection('users').doc(user.uid).get();
    final userData = userDoc.data();
    final isBuyer = userData?['isBuyer'] == true;
    final field = isBuyer ? 'unread_count_buyer' : 'unread_count_seller';

    await _db.collection('chat_rooms').doc(roomId).update({field: 0});
  }

  Future<void> addReaction({
    required String otherUserId,
    required String messageId,
    required String emoji,
  }) async {
    // stub
  }

  Future<void> blockUser(String userId) async {
    // stub
  }

  Future<void> deleteConversation(String userId) async {
    // stub
  }

  Future<void> _sendPushNotification({
    required String otherId,
    required String senderName,
    required String message,
    required String roomId,
  }) async {
    try {
      await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/send-notification'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userId': otherId,
          'title': senderName,
          'body': message,
          'data': {
            'type': 'chat',
            'senderId': FirebaseAuth.instance.currentUser?.uid ?? '',
            'senderName': senderName,
            'roomId': roomId,
          },
        }),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('ChatService: push notification failed: $e');
    }
  }
}
