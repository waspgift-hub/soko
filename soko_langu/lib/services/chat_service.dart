import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/chat_room.dart';
import '../models/message_model.dart';
import 'api_config.dart';
import 'local_cache_service.dart';

class ChatService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

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

    // Emit cached rooms immediately, then switch to live stream
    final cachedStream = _getCachedRooms(user.uid).asStream();

    // Return a stream that first emits cached, then merges with live
    return cachedStream
        .asyncExpand((cached) => _getLiveRooms(user.uid).map((live) {
              final liveIds = live.map((r) => r.id).toSet();
              final extraCached = cached.where((r) => !liveIds.contains(r.id));
              return [...live, ...extraCached];
            }))
        .handleError((_) => []);
  }

  /// Get cached rooms from Hive for instant UI
  Future<List<ChatRoom>> _getCachedRooms(String userId) async {
    try {
      await LocalCacheService.init();
      final cached = LocalCacheService.getCachedRoomsForUser(userId);
      // Sort by lastTimestamp descending (newest first), handle nulls
      cached.sort((a, b) => (b.lastTimestamp?.millisecondsSinceEpoch ?? 0)
          .compareTo(a.lastTimestamp?.millisecondsSinceEpoch ?? 0));
      return cached;
    } catch (_) {
      return [];
    }
  }

  /// Live rooms stream from Firestore
  Stream<List<ChatRoom>> _getLiveRooms(String userId) {
    return _db
        .collection('chat_rooms')
        .where('participants', arrayContains: userId)
        .orderBy('last_timestamp', descending: true)
        .snapshots()
        .map((snap) {
      final rooms = snap.docs
          .map((doc) => ChatRoom.fromMap(doc.id, doc.data()))
          .toList();
      unawaited(LocalCacheService.cacheRooms(rooms));
      return rooms;
    });
  }

  Stream<List<Message>> getMessages(String roomId, {int limit = 100}) {
    return _db
        .collection('chat_rooms')
        .doc(roomId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) {
      final msgs = snap.docs
          .map((doc) => Message.fromMap(doc.id, doc.data()))
          .toList();
      unawaited(LocalCacheService.cacheMessages(roomId, msgs));
      return msgs;
    });
  }

  Future<List<Message>> loadOlderMessages(String roomId,
      {required Timestamp before, int limit = 50}) async {
    final snap = await _db
        .collection('chat_rooms')
        .doc(roomId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .where('timestamp', isLessThan: before)
        .limit(limit)
        .get();
    final msgs = snap.docs
        .map((doc) => Message.fromMap(doc.id, doc.data()))
        .toList();
    unawaited(LocalCacheService.cacheMessages(roomId, msgs));
    return msgs;
  }

  Future<List<Message>> getCachedMessages(String roomId) async {
    return LocalCacheService.getCachedMessages(roomId);
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

    final idToken = await user.getIdToken();
    final body = <String, dynamic>{
      'senderId': user.uid,
      'receiverId': receiverId,
      'roomId': roomId,
      'text': content,
      if (productId != null) 'productId': productId,
      if (productName != null) 'productName': productName,
      if (replyTo != null) 'replyTo': replyTo,
      if (replyToContent != null) 'replyToContent': replyToContent,
      if (replyToSender != null) 'replyToSender': replyToSender,
    };

    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/chat/send'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final messageId = data['messageId'] as String? ?? '';

        unawaited(LocalCacheService.cacheSingleMessage(roomId, Message(
          id: messageId,
          senderId: user.uid,
          receiverId: receiverId,
          content: content,
          timestamp: DateTime.now(),
          isRead: false,
          isDelivered: true,
          productId: productId,
          productName: productName,
          replyTo: replyTo,
          replyToContent: replyToContent,
          replyToSender: replyToSender,
        )));
      } else {
        if (kDebugMode) debugPrint('ChatService: send failed: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('ChatService: send error: $e');
    }
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
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await _db.collection('users').doc(uid).update({
      'blockedUsers': FieldValue.arrayUnion([userId])
    });
  }

  Future<void> deleteConversation(String userId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final roomsSnap = await _db
        .collection('conversations')
        .where('participants', arrayContains: uid)
        .get();
    for (final room in roomsSnap.docs) {
      final participants = List<String>.from(room['participants'] ?? []);
      if (participants.contains(userId)) {
        await room.reference.delete();
      }
    }
  }
}
