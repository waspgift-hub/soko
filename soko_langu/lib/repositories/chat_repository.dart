import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
    await _chats.doc(chatId).collection('messages').add({
      'senderId': uid,
      'text': text,
      'timestamp': FieldValue.serverTimestamp(),
    });
    await _chats.doc(chatId).update({
      'lastMessage': text,
      'lastTimestamp': FieldValue.serverTimestamp(),
    });
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
