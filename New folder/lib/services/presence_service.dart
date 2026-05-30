import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';

class PresenceService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  StreamSubscription? _authSub;
  Timer? _heartbeatTimer;
  WidgetsBindingObserver? _lifecycleObserver;
  bool _initialized = false;

  void initialize() {
    if (_initialized) return;
    _initialized = true;

    final user = _auth.currentUser;
    if (user != null) {
      _setOnline(user.uid);
    }

    _authSub = _auth.authStateChanges().listen((u) {
      if (u != null) {
        _setOnline(u.uid);
      } else {
        _cleanup();
      }
    });

    _lifecycleObserver = _LifecycleObserver(
      onResume: () {
        final user = _auth.currentUser;
        if (user != null) _setOnline(user.uid);
      },
      onPause: () {
        final user = _auth.currentUser;
        if (user != null) _setOffline(user.uid);
      },
    );
    WidgetsBinding.instance.addObserver(_lifecycleObserver!);
  }

  Future<void> _setOnline(String uid) async {
    final ref = _db.collection('users').doc(uid);

    await ref.set({
      'isOnline': true,
      'lastSeen': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    ref.update({'isOnline': true});

    _db.collection('users').doc(uid).update({
      '_onDisconnect': {
        'isOnline': false,
        'lastSeen': FieldValue.serverTimestamp(),
      },
    });

    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      ref.update({'isOnline': true, 'lastSeen': FieldValue.serverTimestamp()});
    });
  }

  Future<void> _setOffline(String uid) async {
    await _db.collection('users').doc(uid).update({
      'isOnline': false,
      'lastSeen': FieldValue.serverTimestamp(),
    });
  }

  Future<void> setOffline() async {
    final user = _auth.currentUser;
    if (user == null) return;
    await _setOffline(user.uid);
  }

  Stream<bool> isOnline(String uid) {
    return _db.collection('users').doc(uid).snapshots().map((doc) {
      if (!doc.exists) return false;
      final data = doc.data()!;
      final isOnline = data['isOnline'] == true;
      if (isOnline) {
        final lastSeen = data['lastSeen'];
        if (lastSeen is Timestamp) {
          final diff = DateTime.now().difference(lastSeen.toDate());
          if (diff.inMinutes > 3) return false;
        }
      }
      return isOnline;
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
    _initialized = false;
    _heartbeatTimer?.cancel();
    _authSub?.cancel();
    if (_lifecycleObserver != null) {
      WidgetsBinding.instance.removeObserver(_lifecycleObserver!);
      _lifecycleObserver = null;
    }
  }

  void dispose() {
    setOffline();
    _cleanup();
  }
}

class _LifecycleObserver with WidgetsBindingObserver {
  final VoidCallback onResume;
  final VoidCallback onPause;

  _LifecycleObserver({required this.onResume, required this.onPause});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        onResume();
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        onPause();
        break;
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }
}
