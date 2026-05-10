import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PresenceService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  StreamSubscription? _onDisconnectSub;
  Timer? _heartbeatTimer;

  void initialize() {
    final user = _auth.currentUser;
    if (user == null) return;

    _setOnline(user.uid);

    _onDisconnectSub = _auth.authStateChanges().listen((u) {
      if (u == null) {
        _cleanup();
      }
    });
  }

  Future<void> _setOnline(String uid) async {
    final ref = _db.collection('users').doc(uid);

    await ref.set({
      'isOnline': true,
      'lastSeen': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    ref.update({'isOnline': true});

    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      ref.update({'isOnline': true, 'lastSeen': FieldValue.serverTimestamp()});
    });
  }

  Future<void> setOffline() async {
    final user = _auth.currentUser;
    if (user == null) return;
    await _db.collection('users').doc(user.uid).update({
      'isOnline': false,
      'lastSeen': FieldValue.serverTimestamp(),
    });
  }

  Stream<bool> isOnline(String uid) {
    return _db.collection('users').doc(uid).snapshots().map((doc) {
      if (!doc.exists) return false;
      final data = doc.data()!;
      return data['isOnline'] == true;
    });
  }

  Stream<DateTime?> lastSeen(String uid) {
    return _db.collection('users').doc(uid).snapshots().map((doc) {
      if (!doc.exists) return null;
      final data = doc.data()!;
      final ts = data['lastSeen'];
      if (ts is Timestamp) return ts.toDate();
      return null;
    });
  }

  void _cleanup() {
    _heartbeatTimer?.cancel();
    _onDisconnectSub?.cancel();
  }

  void dispose() {
    setOffline();
    _cleanup();
  }
}
