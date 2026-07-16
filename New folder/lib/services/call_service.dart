import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';
import 'package:flutter_callkit_incoming/entities/notification_params.dart';
import 'notification_service.dart';
import '../utils/network_error.dart';

class CallService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get _uid => _auth.currentUser?.uid ?? '';
  bool get _loggedIn => _auth.currentUser != null;

  String _channelName(String uid1, String uid2) {
    final ids = [uid1, uid2]..sort();
    return 'call_${ids.join("_")}';
  }

  Future<Map<String, dynamic>?> getActiveCall() async {
    if (!_loggedIn) return null;
    final snap = await _db
        .collection('calls')
        .where('participants', arrayContains: _uid)
        .where('status', whereIn: ['ringing', 'connected'])
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    final doc = snap.docs.first;
    final data = doc.data();
    final createdAt = data['createdAt'] as Timestamp?;
    if (createdAt != null) {
      final age = DateTime.now().difference(createdAt.toDate());
      if (data['status'] == 'ringing' && age.inMinutes > 2) {
        await _db.collection('calls').doc(doc.id).update({'status': 'expired'});
        return null;
      }
      if (data['status'] == 'connected' && age.inHours > 4) {
        await _db.collection('calls').doc(doc.id).update({'status': 'ended'});
        return null;
      }
    }
    return {'id': doc.id, ...data};
  }

  Stream<Map<String, dynamic>?> getCallStream(String callId) {
    return _db
        .collection('calls')
        .doc(callId)
        .snapshots()
        .map((snap) {
      if (!snap.exists) return null;
      return {'id': snap.id, ...snap.data()!};
    });
  }

  Future<String> initiateCall({
    required String calleeId,
    required String type,
    String? callerName,
    String? callerImage,
  }) async {
    if (!_loggedIn)
      throw NetworkError(
        message: 'Not logged in',
        userMessage: 'Please log in to continue.',
      );

    await cleanupStaleCalls();

    final existing = await getActiveCall();
    if (existing != null) {
      throw NetworkError(
        message: 'Already in a call',
        userMessage: 'Uko kwenye simu tayari. Maliza simu ya sasa kwanza.',
      );
    }

    final callRef = _db.collection('calls').doc();
    final channelName = _channelName(_uid, calleeId);
    final name = callerName ?? _auth.currentUser?.displayName ?? '';
    final image = callerImage ?? _auth.currentUser?.photoURL ?? '';

    await callRef.set({
      'callerId': _uid,
      'calleeId': calleeId,
      'receiverId': calleeId,
      'participants': [_uid, calleeId],
      'channelName': channelName,
      'channelId': channelName,
      'type': type,
      'status': 'ringing',
      'timestamp': FieldValue.serverTimestamp(),
      'callerName': name,
      'callerImage': image,
      'createdAt': FieldValue.serverTimestamp(),
    });

    await NotificationService().sendNotification(
      userId: calleeId,
      title: 'Incoming ${type == "video" ? "Video" : "Voice"} Call',
      body: '$name is calling you',
      data: {
        'type': 'call',
        'callId': callRef.id,
        'callerId': _uid,
        'channelName': channelName,
        'callType': type,
        'callerName': name,
        'callerImage': image,
        'handle': type == 'video' ? 'Video Call' : 'Voice Call',
      },
    );

    return callRef.id;
  }

  Future<void> acceptCall(String callId) async {
    await _db.collection('calls').doc(callId).update({'status': 'connected'});
    await FlutterCallkitIncoming.endCall(callId);
  }

  Future<void> endCall(String callId) async {
    await _db.collection('calls').doc(callId).update({
      'status': 'ended',
      'endedAt': FieldValue.serverTimestamp(),
    });
    await FlutterCallkitIncoming.endCall(callId);
  }

  Future<void> declineCall(String callId) async {
    await _db.collection('calls').doc(callId).update({'status': 'declined'});
    await FlutterCallkitIncoming.endCall(callId);
  }

  Future<void> cancelCall(String callId) async {
    await _db.collection('calls').doc(callId).update({'status': 'cancelled'});
    await FlutterCallkitIncoming.endCall(callId);
  }

  Future<void> missCall(String callId) async {
    await _db.collection('calls').doc(callId).update({'status': 'missed'});
    await FlutterCallkitIncoming.endCall(callId);
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
        .where('participants', arrayContains: _uid)
        .where('status', whereIn: ['ringing', 'connected'])
        .snapshots()
        .asyncMap((snap) async {
      if (snap.docs.isEmpty) return null;
      final doc = snap.docs.first;
      final data = doc.data();
      final createdAt = data['createdAt'] as Timestamp?;
      if (createdAt != null) {
        final age = DateTime.now().difference(createdAt.toDate());
        if (data['status'] == 'ringing' && age.inMinutes > 2) {
          await _db.collection('calls').doc(doc.id).update({'status': 'expired'});
          return null;
        }
        if (data['status'] == 'connected' && age.inHours > 4) {
          await _db.collection('calls').doc(doc.id).update({'status': 'ended'});
          return null;
        }
      }
      return {'id': doc.id, ...data};
    });
  }

  Future<void> showCallKitUI({
    required String callId,
    required String callerName,
    required String callerImage,
    required String channelName,
    required String callType,
    bool isOutgoing = false,
  }) async {
    final activeCalls = await FlutterCallkitIncoming.activeCalls();
    if (activeCalls is List && activeCalls.isNotEmpty) return;

    final params = CallKitParams(
      id: callId,
      nameCaller: callerName,
      appName: 'Soko Vibe',
      avatar: callerImage.isNotEmpty ? callerImage : null,
      handle: callType == 'video' ? 'Video Call' : 'Voice Call',
      type: callType == 'video' ? 1 : 0,
      textAccept: 'Accept',
      textDecline: 'Decline',
      duration: 30000,
      missedCallNotification: const NotificationParams(
        showNotification: true,
        isShowCallback: true,
        callbackText: 'Call back',
      ),
      extra: <String, dynamic>{
        'callId': callId,
        'callerId': isOutgoing ? _uid : '',
        'channelName': channelName,
        'callType': callType,
        'callerName': callerName,
        'callerImage': callerImage,
      },
      android: AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#0D1B12',
        backgroundUrl: null,
        actionColor: '#2D6A4F',
        textColor: '#FFFFFF',
        incomingCallNotificationChannelName: 'Incoming Calls',
        missedCallNotificationChannelName: 'Missed Calls',
        isShowCallID: false,
        isShowFullLockedScreen: true,
      ),
      ios: IOSParams(
        iconName: 'CallKitLogo',
        handleType: 'generic',
        supportsVideo: true,
        maximumCallGroups: 1,
        maximumCallsPerCallGroup: 1,
        audioSessionMode: 'default',
        audioSessionActive: true,
        audioSessionPreferredSampleRate: 44100.0,
        audioSessionPreferredIOBufferDuration: 0.005,
        supportsDTMF: false,
        supportsHolding: false,
        supportsGrouping: false,
        supportsUngrouping: false,
        ringtonePath: 'system_ringtone_default',
      ),
    );

    await FlutterCallkitIncoming.showCallkitIncoming(params);
  }

  Future<void> endAllCallKitCalls() async {
    await FlutterCallkitIncoming.endAllCalls();
  }

  Future<void> cleanupOldCalls() async {
    if (!_loggedIn) return;
    final cutoff = DateTime.now().subtract(const Duration(minutes: 5));
    final old = await _db
        .collection('calls')
        .where('participants', arrayContains: _uid)
        .where('status', whereIn: ['ringing', 'connected'])
        .where('createdAt', isLessThan: Timestamp.fromDate(cutoff))
        .get();
    final batch = _db.batch();
    for (var doc in old.docs) {
      batch.update(doc.reference, {'status': 'ended'});
    }
    await batch.commit();
    await FlutterCallkitIncoming.endAllCalls();
  }

  Future<void> cleanupStaleCalls() async {
    if (!_loggedIn) return;
    final now = DateTime.now();
    final snap = await _db
        .collection('calls')
        .where('participants', arrayContains: _uid)
        .where('status', whereIn: ['ringing', 'connected'])
        .get();
    if (snap.docs.isEmpty) return;

    final batch = _db.batch();
    for (var doc in snap.docs) {
      final data = doc.data();
      final createdAt = data['createdAt'] as Timestamp?;
      if (createdAt == null) {
        batch.update(doc.reference, {'status': 'ended'});
        continue;
      }
      final age = now.difference(createdAt.toDate());
      if (data['status'] == 'ringing' && age.inMinutes > 1) {
        batch.update(doc.reference, {'status': 'expired'});
      } else if (data['status'] == 'connected' && age.inHours > 4) {
        batch.update(doc.reference, {'status': 'ended'});
      }
    }
    await batch.commit();
  }

  Future<void> clearAllActiveCalls() async {
    if (!_loggedIn) return;
    final snap = await _db
        .collection('calls')
        .where('participants', arrayContains: _uid)
        .where('status', whereIn: ['ringing', 'connected'])
        .get();
    final batch = _db.batch();
    for (var doc in snap.docs) {
      batch.update(doc.reference, {'status': 'ended'});
    }
    await batch.commit();
    await FlutterCallkitIncoming.endAllCalls();
  }
}
