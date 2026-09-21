import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../models/chat_room.dart';
import '../models/message_model.dart';
import '../models/sync_operation.dart';
import 'api_config.dart';
import 'local_cache_service.dart';
import 'sync_queue_service.dart';

/// Firestore owner of DM chat (`chat_rooms`, `chat_rooms/<id>/messages`).
/// Repository boundary (§14): chat collections are written ONLY here; no
/// commerce module may add chat writes. The server legacy shim
/// (`feature-compat.js`) mirrors these collections for moderation fallback,
/// and `admin_dashboard_screen` reads `chat_rooms` directly (read-only admin
/// exception). Phase E moves this to an owned chat service — until then every
/// chat write must go through this class so the domain stays isolated.
class ChatService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String roomIdFor(String uid1, String uid2) {
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
    final roomId = roomIdFor(user.uid, otherUserId);

    final existing = await _db.collection('chat_rooms').doc(roomId).get();
    if (existing.exists) return roomId;

    await _db.collection('chat_rooms').doc(roomId).set({
      'participants': [user.uid, otherUserId],
      'last_message': '',
      'last_timestamp': FieldValue.serverTimestamp(),
      'unread_counts': {
        user.uid: 0,
        otherUserId: 0,
      },
      // legacy role fields kept for backward-compat reads
      'unread_count_buyer': 0,
      'unread_count_seller': 0,
      'product_id': ?productId,
      'product_title': ?productTitle,
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
        .limit(50)
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
    final live = _db
        .collection('chat_rooms')
        .doc(roomId)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .limit(limit)
        .snapshots()
        .map((snap) {
      final msgs = snap.docs
          .map((doc) => Message.fromMap(doc.id, doc.data()))
          .toList();
      unawaited(LocalCacheService.cacheMessages(roomId, msgs));
      return msgs;
    });

    return LocalCacheService.getCachedMessages(roomId).asStream()
        .asyncExpand((cached) => live.map((liveMsgs) {
          if (liveMsgs.isNotEmpty) return liveMsgs;
          return cached;
        }));
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

  /// Returns the Firestore message ID if send succeeds, null otherwise.
  ///
  /// [clientMessageId] is the offline-first idempotency key: the server
  /// returns the original message instead of duplicating when a retry
  /// carries the same key. Generated when absent so every send is safe
  /// to retry, including engine-driven outbox drains.
  Future<String?> sendMessage({
    required String receiverId,
    required String content,
    String? productId,
    String? productName,
    String? replyTo,
    String? replyToContent,
    String? replyToSender,
    String? clientMessageId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    final roomId = roomIdFor(user.uid, receiverId);

    final idToken = await user.getIdToken();
    final body = <String, dynamic>{
      'senderId': user.uid,
      'receiverId': receiverId,
      'roomId': roomId,
      'text': content,
      'productId': ?productId,
      'productName': ?productName,
      'replyTo': ?replyTo,
      'replyToContent': ?replyToContent,
      'replyToSender': ?replyToSender,
      'clientMessageId': clientMessageId ?? const Uuid().v4(),
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
        return messageId;
      } else {
        if (kDebugMode) debugPrint('ChatService: send failed: ${response.statusCode} ${response.body}');
        return null;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('ChatService: send error: $e');
      return null;
    }
  }

  /// Persist a message locally and queue it for delivery. Returns the
  /// client message id used as the Hive key, the UI temp id, and the
  /// outbox idempotency key — one id for all three, so restarts and
  /// retries can never duplicate the message.
  Future<String> queueMessage({
    required SyncQueueService outbox,
    required String receiverId,
    required String content,
    String? productId,
    String? productName,
    String? replyTo,
    String? replyToContent,
    String? replyToSender,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not logged in');
    final roomId = roomIdFor(user.uid, receiverId);
    final clientMessageId = const Uuid().v4();
    await LocalCacheService.cacheSingleMessage(
      roomId,
      Message(
        id: clientMessageId,
        senderId: user.uid,
        receiverId: receiverId,
        content: content,
        timestamp: DateTime.now(),
        isRead: false,
        isDelivered: false,
        productId: productId,
        productName: productName,
        replyTo: replyTo,
        replyToContent: replyToContent,
        replyToSender: replyToSender,
      ),
    );
    await outbox.enqueue(
      operationType: SyncOperationType.chatSend,
      entityType: 'message',
      entityId: clientMessageId,
      payload: {
        'receiverId': receiverId,
        'roomId': roomId,
        'senderId': user.uid,
        'content': content,
        'productId': ?productId,
        'productName': ?productName,
        'replyTo': ?replyTo,
        'replyToContent': ?replyToContent,
        'replyToSender': ?replyToSender,
      },
      priority: SyncPriority.high,
      idempotencyKey: clientMessageId,
    );
    return clientMessageId;
  }

  /// Mark all unread incoming messages as read in Firestore.
  Future<void> markMessagesAsRead(String roomId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final snap = await _db
        .collection('chat_rooms')
        .doc(roomId)
        .collection('messages')
        .where('is_read', isEqualTo: false)
        .get();

    if (snap.docs.isEmpty) return;

    final batch = _db.batch();
    for (final doc in snap.docs) {
      final data = doc.data();
      // Only mark messages sent by the other person
      final senderId = data['sender_id'] ?? data['senderId'] ?? '';
      if (senderId != user.uid) {
        batch.update(doc.reference, {'is_read': true, 'isRead': true});
      }
    }
    await batch.commit();
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
    final legacyField = isBuyer ? 'unread_count_buyer' : 'unread_count_seller';

    // Clear this user's unread (per-user map first, legacy field second).
    await _db.collection('chat_rooms').doc(roomId).update({
      'unread_counts.${user.uid}': 0,
      legacyField: 0,
    });
  }

  Future<void> addReaction({
    required String otherUserId,
    required String messageId,
    required String emoji,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final roomId = roomIdFor(uid, otherUserId);
    final msgRef = _db
        .collection('chat_rooms')
        .doc(roomId)
        .collection('messages')
        .doc(messageId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(msgRef);
      if (!snap.exists) return;
      final data = snap.data() as Map<String, dynamic>;
      final reactions = Map<String, List<dynamic>>.from(
          data['reactions'] as Map? ?? {});
      final reactors = List<String>.from(reactions[emoji] ?? []);
      if (reactors.contains(uid)) {
        reactors.remove(uid);
      } else {
        reactors.add(uid);
      }
      if (reactors.isEmpty) {
        reactions.remove(emoji);
      } else {
        reactions[emoji] = reactors;
      }
      tx.update(msgRef, {'reactions': reactions});
    });
  }

  Future<void> blockUser(String userId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await _db.collection('users').doc(uid).update({
      'blockedUsers': FieldValue.arrayUnion([userId])
    });
  }

  Future<void> unblockUser(String userId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await _db.collection('users').doc(uid).update({
      'blockedUsers': FieldValue.arrayRemove([userId])
    });
  }

  Future<void> toggleMute(String roomId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final doc = await _db.collection('chat_rooms').doc(roomId).get();
    if (!doc.exists) return;
    final data = doc.data()!;
    final muted = List<String>.from(data['muted_by'] ?? []);
    if (muted.contains(uid)) {
      await doc.reference.update({'muted_by': FieldValue.arrayRemove([uid])});
    } else {
      await doc.reference.update({'muted_by': FieldValue.arrayUnion([uid])});
    }
  }

  Future<void> togglePin(String roomId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final doc = await _db.collection('chat_rooms').doc(roomId).get();
    if (!doc.exists) return;
    final data = doc.data()!;
    final pinned = List<String>.from(data['pinned_by'] ?? []);
    if (pinned.contains(uid)) {
      await doc.reference.update({'pinned_by': FieldValue.arrayRemove([uid])});
    } else {
      await doc.reference.update({'pinned_by': FieldValue.arrayUnion([uid])});
    }
  }

  Future<void> toggleArchive(String roomId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final doc = await _db.collection('chat_rooms').doc(roomId).get();
    if (!doc.exists) return;
    final data = doc.data()!;
    final archived = List<String>.from(data['archived_by'] ?? []);
    if (archived.contains(uid)) {
      await doc.reference.update({'archived_by': FieldValue.arrayRemove([uid])});
    } else {
      await doc.reference.update({'archived_by': FieldValue.arrayUnion([uid])});
    }
  }

  Future<void> toggleFavourite(String roomId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final doc = await _db.collection('chat_rooms').doc(roomId).get();
    if (!doc.exists) return;
    final data = doc.data()!;
    final fav = List<String>.from(data['favourited_by'] ?? []);
    if (fav.contains(uid)) {
      await doc.reference.update({'favourited_by': FieldValue.arrayRemove([uid])});
    } else {
      await doc.reference.update({'favourited_by': FieldValue.arrayUnion([uid])});
    }
  }

  Future<void> deleteConversation(String userId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final roomId = roomIdFor(uid, userId);
    await deleteAllMessages(roomId);
    await deleteForMe(roomId);
  }

  Future<void> deleteAllMessages(String roomId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final msgs = await _db
        .collection('chat_rooms')
        .doc(roomId)
        .collection('messages')
        .get();
    if (msgs.docs.isEmpty) return;
    final batch = _db.batch();
    for (final doc in msgs.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  Future<void> deleteForMe(String roomId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final doc = _db.collection('chat_rooms').doc(roomId);
    await doc.update({
      'deleted_by': FieldValue.arrayUnion([uid]),
    });
  }

  Future<void> addShortcut(String roomId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await _db.collection('users').doc(uid).update({
      'chat_shortcuts': FieldValue.arrayUnion([roomId]),
    });
  }

  Future<ChatRoom?> getRoomDoc(String roomId) async {
    final doc = await _db.collection('chat_rooms').doc(roomId).get();
    if (!doc.exists) return null;
    return ChatRoom.fromMap(doc.id, doc.data()!);
  }

  Future<bool> isBlocked(String userId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return false;
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) return false;
    final blocked = List<String>.from(doc.data()!['blockedUsers'] ?? []);
    return blocked.contains(userId);
  }
}

/// SyncEngine handler for [SyncOperationType.chatSend]. Resends with the
/// stored idempotency key (server dedupes, never duplicates), flips the
/// local cached copy to delivered, and throws on failure so the engine
/// retries or dead-letters instead of silently dropping the message.
Future<void> syncQueuedChatMessage(SyncOperation op) async {
  final p = op.payload;
  final messageId = await ChatService().sendMessage(
    receiverId: p['receiverId'] as String,
    content: p['content'] as String,
    productId: p['productId'] as String?,
    productName: p['productName'] as String?,
    replyTo: p['replyTo'] as String?,
    replyToContent: p['replyToContent'] as String?,
    replyToSender: p['replyToSender'] as String?,
    clientMessageId: op.idempotencyKey,
  );
  if (messageId == null || messageId.isEmpty) {
    throw Exception('Chat resend returned no message id');
  }
  await LocalCacheService.cacheSingleMessage(
    p['roomId'] as String,
    Message(
      id: op.idempotencyKey,
      senderId: p['senderId'] as String,
      receiverId: p['receiverId'] as String,
      content: p['content'] as String,
      timestamp: op.createdAt,
      isRead: false,
      isDelivered: true,
      productId: p['productId'] as String?,
      productName: p['productName'] as String?,
      replyTo: p['replyTo'] as String?,
      replyToContent: p['replyToContent'] as String?,
      replyToSender: p['replyToSender'] as String?,
    ),
  );
}
