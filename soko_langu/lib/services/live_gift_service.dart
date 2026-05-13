import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/live_gift.dart';

class LiveGiftService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  static const double streamerShare = 0.7;

  // ── Premium coins (bought, 1 coin = TZS 5) ──
  Future<int> getPremiumCoins() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return 0;
    final doc = await _db.collection('users').doc(uid).get();
    return (doc.data()?['coins'] ?? 0) as int;
  }

  Stream<int> streamPremiumCoins() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value(0);
    return _db
        .collection('users')
        .doc(uid)
        .snapshots()
        .map((doc) => (doc.data()?['coins'] ?? 0) as int);
  }

  // ── Soft coins (earned from ads, 1 coin = TZS 1) ──
  Future<int> getSoftCoins() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return 0;
    final doc = await _db.collection('users').doc(uid).get();
    return (doc.data()?['softCoins'] ?? 0) as int;
  }

  Stream<int> streamSoftCoins() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value(0);
    return _db
        .collection('users')
        .doc(uid)
        .snapshots()
        .map((doc) => (doc.data()?['softCoins'] ?? 0) as int);
  }

  Future<int> getTotalCoins() async {
    final premium = await getPremiumCoins();
    final soft = await getSoftCoins();
    return premium + soft;
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
      final data = userDoc.data() ?? {};
      final premiumCoins = (data['coins'] ?? 0) as int;
      final softCoins = (data['softCoins'] ?? 0) as int;

      if (gift.isPremium) {
        if (premiumCoins < gift.coinCost) return false;
        tx.update(userRef, {'coins': premiumCoins - gift.coinCost});
      } else {
        final total = premiumCoins + softCoins;
        if (total < gift.coinCost) return false;

        int remaining = gift.coinCost;
        int softUsed = 0;
        int premiumUsed = 0;

        if (softCoins >= remaining) {
          softUsed = remaining;
        } else {
          softUsed = softCoins;
          premiumUsed = remaining - softCoins;
        }

        tx.update(userRef, {
          'softCoins': softCoins - softUsed,
          'coins': premiumCoins - premiumUsed,
        });
      }

      int coinCost = gift.coinCost;
      bool usingPremium = gift.isPremium;
      final tzsValue = gift.isPremium
          ? coinCost * LiveGift.tzsPerPremiumCoin
          : coinCost * LiveGift.tzsPerSoftCoin;
      final streamerEarning = (tzsValue * streamerShare).round();

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
        'coinCost': coinCost,
        'isPremium': usingPremium,
        'valueTzs': tzsValue,
        'streamerEarning': streamerEarning,
        'platformEarning': (tzsValue - streamerEarning),
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

  Future<void> addPremiumCoins(String uid, int amount) async {
    await _db.collection('users').doc(uid).update({
      'coins': FieldValue.increment(amount),
    });
  }

  Future<void> addSoftCoins(String uid, int amount) async {
    await _db.collection('users').doc(uid).update({
      'softCoins': FieldValue.increment(amount),
    });
  }
}
