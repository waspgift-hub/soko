import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'rate_limit_service.dart';

class FollowService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<bool> followUser(String userId) async {
    final currentUid = _auth.currentUser?.uid;
    if (currentUid == null || currentUid == userId) return false;
    if (!await RateLimitService().canFollow()) return false;

    final batch = _db.batch();
    final followingRef = _db.collection('users').doc(currentUid).collection('following').doc(userId);
    final followerRef = _db.collection('users').doc(userId).collection('followers').doc(currentUid);

    batch.set(followingRef, {'followedAt': FieldValue.serverTimestamp()});
    batch.set(followerRef, {'followedAt': FieldValue.serverTimestamp()});

    await batch.commit();
    return true;
  }

  Future<bool> unfollowUser(String userId) async {
    final currentUid = _auth.currentUser?.uid;
    if (currentUid == null || currentUid == userId) return false;

    final batch = _db.batch();
    final followingRef = _db.collection('users').doc(currentUid).collection('following').doc(userId);
    final followerRef = _db.collection('users').doc(userId).collection('followers').doc(currentUid);

    batch.delete(followingRef);
    batch.delete(followerRef);

    await batch.commit();
    return true;
  }

  Future<bool> isFollowing(String userId) async {
    final currentUid = _auth.currentUser?.uid;
    if (currentUid == null) return false;

    final doc = await _db.collection('users').doc(currentUid).collection('following').doc(userId).get();
    return doc.exists;
  }

  Stream<int> getFollowerCount(String userId) {
    return _db.collection('users').doc(userId).collection('followers').snapshots().map((snap) => snap.docs.length);
  }

  Stream<int> getFollowingCount(String userId) {
    return _db.collection('users').doc(userId).collection('following').snapshots().map((snap) => snap.docs.length);
  }

  Stream<List<Map<String, dynamic>>> getFollowers(String userId) {
    return _db
        .collection('users')
        .doc(userId)
        .collection('followers')
        .orderBy('followedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList());
  }

  Stream<List<Map<String, dynamic>>> getFollowing(String userId) {
    return _db
        .collection('users')
        .doc(userId)
        .collection('following')
        .orderBy('followedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList());
  }

  Stream<bool> isFollowingStream(String userId) {
    final currentUid = _auth.currentUser?.uid;
    if (currentUid == null) return Stream.value(false);
    return _db
        .collection('users')
        .doc(currentUid)
        .collection('following')
        .doc(userId)
        .snapshots()
        .map((snap) => snap.exists);
  }

  Stream<int> followersCount(String userId) {
    return getFollowerCount(userId);
  }

  Stream<int> followingCount(String userId) {
    return getFollowingCount(userId);
  }

  Future<void> follow(String userId) async {
    await followUser(userId);
  }

  Future<void> unfollow(String userId) async {
    await unfollowUser(userId);
  }

  Stream<List<Map<String, dynamic>>> getFollowingProducts() {
    final currentUid = _auth.currentUser?.uid;
    if (currentUid == null) return Stream.value([]);

    return _db
        .collection('users')
        .doc(currentUid)
        .collection('following')
        .snapshots()
        .asyncMap((followingSnap) async {
      final sellerIds = followingSnap.docs.map((d) => d.id).toList();
      if (sellerIds.isEmpty) return [];

      final products = <Map<String, dynamic>>[];
      for (final sellerId in sellerIds.take(10)) {
        final snap = await _db
            .collection('products')
            .where('sellerId', isEqualTo: sellerId)
            .where('isActive', isEqualTo: true)
            .orderBy('createdAt', descending: true)
            .limit(5)
            .get();
        for (final doc in snap.docs) {
          products.add({'id': doc.id, ...doc.data()});
        }
      }
      products.sort((a, b) {
        final aTime = (a['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
        final bTime = (b['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
        return bTime.compareTo(aTime);
      });
      return products;
    });
  }
}
