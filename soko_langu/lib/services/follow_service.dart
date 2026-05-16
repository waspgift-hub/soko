import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FollowService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get _uid => _auth.currentUser?.uid ?? '';
  bool get _loggedIn => _auth.currentUser != null;

  Future<void> follow(String userId) async {
    if (!_loggedIn) throw Exception('Not logged in');
    if (userId == _uid) throw Exception('Cannot follow yourself');

    final batch = _db.batch();
    final followerRef = _db.collection('users').doc(_uid).collection('following').doc(userId);
    final followingRef = _db.collection('users').doc(userId).collection('followers').doc(_uid);

    batch.set(followerRef, {
      'userId': userId,
      'followedAt': FieldValue.serverTimestamp(),
    });
    batch.set(followingRef, {
      'userId': _uid,
      'followedAt': FieldValue.serverTimestamp(),
    });

    batch.update(_db.collection('users').doc(_uid), {
      'followingCount': FieldValue.increment(1),
    });
    batch.update(_db.collection('users').doc(userId), {
      'followersCount': FieldValue.increment(1),
    });

    await batch.commit();
  }

  Future<void> unfollow(String userId) async {
    if (!_loggedIn) throw Exception('Not logged in');

    final batch = _db.batch();
    final followerRef = _db.collection('users').doc(_uid).collection('following').doc(userId);
    final followingRef = _db.collection('users').doc(userId).collection('followers').doc(_uid);

    batch.delete(followerRef);
    batch.delete(followingRef);

    batch.update(_db.collection('users').doc(_uid), {
      'followingCount': FieldValue.increment(-1),
    });
    batch.update(_db.collection('users').doc(userId), {
      'followersCount': FieldValue.increment(-1),
    });

    await batch.commit();
  }

  Future<bool> isFollowing(String userId) async {
    if (!_loggedIn) return false;
    final doc = await _db.collection('users').doc(_uid).collection('following').doc(userId).get();
    return doc.exists;
  }

  Stream<bool> isFollowingStream(String userId) {
    if (!_loggedIn) return Stream.value(false);
    return _db.collection('users').doc(_uid).collection('following').doc(userId).snapshots().map((doc) => doc.exists);
  }

  Stream<int> followersCount(String userId) {
    return _db.collection('users').doc(userId).snapshots().map((doc) {
      if (!doc.exists) return 0;
      return (doc.data()?['followersCount'] ?? 0) as int;
    });
  }

  Stream<int> followingCount(String userId) {
    return _db.collection('users').doc(userId).snapshots().map((doc) {
      if (!doc.exists) return 0;
      return (doc.data()?['followingCount'] ?? 0) as int;
    });
  }

  Stream<List<Map<String, dynamic>>> getFollowers(String userId) {
    return _db.collection('users').doc(userId).collection('followers').orderBy('followedAt', descending: true).snapshots().map((snap) {
      return snap.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
    });
  }

  Stream<List<Map<String, dynamic>>> getFollowing(String userId) {
    return _db.collection('users').doc(userId).collection('following').orderBy('followedAt', descending: true).snapshots().map((snap) {
      return snap.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
    });
  }
}
