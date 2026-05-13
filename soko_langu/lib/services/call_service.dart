import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'notification_service.dart';

class CallService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get _uid => _auth.currentUser?.uid ?? '';
  bool get _loggedIn => _auth.currentUser != null;

  String _channelName(String uid1, String uid2) {
    final ids = [uid1, uid2]..sort();
    return 'call_${ids.join("_")}';
  }

  Future<String> initiateCall({
    required String calleeId,
    required String type,
    String? callerName,
    String? callerImage,
  }) async {
    if (!_loggedIn) throw Exception('Not logged in');
    final callRef = _db.collection('calls').doc();
    final channelName = _channelName(_uid, calleeId);
    await callRef.set({
      'callerId': _uid,
      'calleeId': calleeId,
      'channelName': channelName,
      'type': type,
      'status': 'ringing',
      'callerName': callerName ?? _auth.currentUser?.displayName ?? '',
      'callerImage': callerImage ?? _auth.currentUser?.photoURL ?? '',
      'createdAt': FieldValue.serverTimestamp(),
    });
    await NotificationService().sendNotification(
      userId: calleeId,
      title: 'Incoming ${type == "video" ? "Video" : "Voice"} Call',
      body:
          '${callerName ?? _auth.currentUser?.displayName ?? "Someone"} is calling you',
      data: {
        'type': 'call',
        'callId': callRef.id,
        'callerId': _uid,
        'channelName': channelName,
        'callType': type,
        'callerName': callerName ?? _auth.currentUser?.displayName ?? '',
        'callerImage': callerImage ?? _auth.currentUser?.photoURL ?? '',
      },
    );
    return callRef.id;
  }

  Future<void> acceptCall(String callId) async {
    await _db.collection('calls').doc(callId).update({'status': 'connected'});
  }

  Future<void> endCall(String callId) async {
    await _db.collection('calls').doc(callId).update({
      'status': 'ended',
      'endedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> declineCall(String callId) async {
    await _db.collection('calls').doc(callId).update({'status': 'declined'});
  }

  Future<void> cancelCall(String callId) async {
    await _db.collection('calls').doc(callId).update({'status': 'cancelled'});
  }

  Future<void> missCall(String callId) async {
    await _db.collection('calls').doc(callId).update({'status': 'missed'});
  }

  Stream<Map<String, dynamic>?> incomingCallStream() {
    if (!_loggedIn) return Stream.value(null);
    return _db
        .collection('calls')
        .where('calleeId', isEqualTo: _uid)
        .where('status', isEqualTo: 'ringing')
        .snapshots()
        .map((snap) {
          if (snap.docs.isEmpty) return null;
          final doc = snap.docs.first;
          return {'id': doc.id, ...doc.data()};
        });
  }

  Stream<Map<String, dynamic>?> myActiveCallStream() {
    if (!_loggedIn) return Stream.value(null);
    return _db
        .collection('calls')
        .where('status', whereIn: ['ringing', 'connected'])
        .snapshots()
        .map((snap) {
          for (var doc in snap.docs) {
            final data = doc.data();
            if (data['callerId'] == _uid || data['calleeId'] == _uid) {
              return {'id': doc.id, ...data};
            }
          }
          return null;
        });
  }

  Future<void> cleanupOldCalls() async {
    final cutoff = DateTime.now().subtract(const Duration(minutes: 5));
    final old = await _db
        .collection('calls')
        .where('status', whereIn: ['ringing', 'connected'])
        .get();
    final batch = _db.batch();
    for (var doc in old.docs) {
      final ts = doc.data()['createdAt'] as Timestamp?;
      if (ts != null && ts.toDate().isBefore(cutoff)) {
        batch.update(doc.reference, {'status': 'ended'});
      }
    }
    await batch.commit();
  }
}
