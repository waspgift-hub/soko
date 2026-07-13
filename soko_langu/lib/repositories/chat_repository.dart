import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../services/api_config.dart';

class ChatRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get currentUid => _auth.currentUser?.uid;

  CollectionReference get _chats => _firestore.collection('chats');

  Future<String> createChat(String otherUid, {String? initialMessage}) async {
    final uid = currentUid;
    if (uid == null) throw Exception('Not authenticated');
    final doc = await _chats.add({
      'participants': [uid, otherUid],
      'lastMessage': initialMessage ?? '',
      'lastTimestamp': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  Stream<QuerySnapshot> getChats() {
    final uid = currentUid;
    if (uid == null) return const Stream.empty();
    return _chats.where('participants', arrayContains: uid).orderBy('lastTimestamp', descending: true).snapshots();
  }

  Future<void> sendMessage(String chatId, String text) async {
    final uid = currentUid;
    if (uid == null) return;

    // Look up chat doc to find the receiver
    final chatDoc = await _chats.doc(chatId).get();
    if (!chatDoc.exists) return;
    final data = chatDoc.data() as Map<String, dynamic>?;
    final participants = List<String>.from(data?['participants'] ?? []);
    final receiverId = participants.where((p) => p != uid).firstOrNull;
    if (receiverId == null) return;

    final idToken = await _auth.currentUser?.getIdToken();
    if (idToken == null) return;

    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/chat/send'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'senderId': uid,
          'receiverId': receiverId,
          'roomId': chatId,
          'text': text,
        }),
      );
      if (kDebugMode && response.statusCode != 200) {
        debugPrint('ChatRepository: send failed: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('ChatRepository: send error: $e');
    }
  }

  Stream<QuerySnapshot> getMessages(String chatId) {
    return _chats.doc(chatId).collection('messages').orderBy('timestamp', descending: false).snapshots();
  }

  Future<String> getOrCreateSellerRoom(String sellerId) async {
    final uid = currentUid;
    if (uid == null) throw Exception('Not authenticated');
    final existing = await _chats
        .where('participants', arrayContains: uid)
        .where('participants', arrayContains: sellerId)
        .limit(1)
        .get();
    if (existing.docs.isNotEmpty) return existing.docs.first.id;
    return createChat(sellerId);
  }
}
