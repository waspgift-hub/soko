import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/live_gift.dart';

class LiveGiftService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  static const double streamerShare = 0.7;

  Future<int> getCoinBalance() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return 0;
    final doc = await _db.collection('users').doc(uid).get();
    return (doc.data()?['coins'] ?? 0) as int;
  }

  Stream<int> streamCoinBalance() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value(0);
    return _db
        .collection('users')
        .doc(uid)
        .snapshots()
        .map((doc) => (doc.data()?['coins'] ?? 0) as int);
  }

  Future<bool> sendGift({
    required String streamerId,
    required String streamId,
    required LiveGift gift,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return false;

    return _db.runTransaction((tx) async {
      final userRef = _db.collection('users').doc(user.uid);
      final userDoc = await tx.get(userRef);
      final coins = (userDoc.data()?['coins'] ?? 0) as int;

      if (coins < gift.coinCost) return false;

      tx.update(userRef, {'coins': coins - gift.coinCost});

      final streamerEarning = (gift.coinCost * 5 * streamerShare).round();
      final streamerRef = _db.collection('users').doc(streamerId);
      final streamerDoc = await tx.get(streamerRef);
      final currentEarnings =
          (streamerDoc.data()?['streamerEarnings'] ?? 0) as int;
      tx.update(streamerRef, {
        'streamerEarnings': currentEarnings + streamerEarning,
      });

      tx.set(_db.collection('live_gifts').doc(), {
        'from': user.uid,
        'fromName': user.displayName ?? user.email ?? 'Anonymous',
        'streamerId': streamerId,
        'streamId': streamId,
        'giftId': gift.id,
        'giftName': gift.name,
        'giftEmoji': gift.emoji,
        'coinCost': gift.coinCost,
        'valueTzs': gift.tzsValue,
        'streamerEarning': streamerEarning,
        'platformEarning': (gift.tzsValue - streamerEarning),
        'createdAt': FieldValue.serverTimestamp(),
      });

      return true;
    });
  }

  Stream<int> streamStreamerEarnings() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value(0);
    return _db
        .collection('users')
        .doc(uid)
        .snapshots()
        .map((doc) => (doc.data()?['streamerEarnings'] ?? 0) as int);
  }

  Stream<List<Map<String, dynamic>>> streamGiftsForStream(String streamId) {
    return _db
        .collection('live_gifts')
        .where('streamId', isEqualTo: streamId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.data()).toList());
  }

  Future<void> addCoins(String uid, int amount) async {
    await _db.collection('users').doc(uid).update({
      'coins': FieldValue.increment(amount),
    });
  }
}
