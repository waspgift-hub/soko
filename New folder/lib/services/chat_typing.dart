import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ChatTyping {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String _convId(String uid, String otherUid) {
    return uid.compareTo(otherUid) < 0 ? '${uid}_$otherUid' : '${otherUid}_$uid';
  }

  Future<void> startTyping(String otherUserId) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final convId = _convId(user.uid, otherUserId);
    await _db.collection("conversations").doc(convId).set({
      'typing_${user.uid}': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> stopTyping(String otherUserId) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final convId = _convId(user.uid, otherUserId);
    await _db.collection("conversations").doc(convId).update({
      'typing_${user.uid}': null,
    });
  }

  Future<void> sendTypingStatus(String otherUserId, bool isTyping) async {
    if (isTyping) {
      await startTyping(otherUserId);
    } else {
      await stopTyping(otherUserId);
    }
  }

  Stream<bool> observeTyping(String otherUserId) async* {
    final user = _auth.currentUser;
    if (user == null) {
      yield false;
      return;
    }
    final convId = _convId(user.uid, otherUserId);
    await for (final snap in _db.collection("conversations").doc(convId).snapshots()) {
      if (!snap.exists) {
        yield false;
      } else {
        final data = snap.data();
        yield data != null && data['typing_$otherUserId'] != null;
      }
    }
  }
}
