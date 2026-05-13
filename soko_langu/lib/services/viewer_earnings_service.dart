import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ViewerEarningsService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  static const String adUnitId = 'ca-app-pub-3940256099942544/5224354917';

  Future<void> creditAdView({required int coins}) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await _db.collection('users').doc(uid).update({
      'softCoins': FieldValue.increment(coins),
    });
    await _db.collection('viewer_ad_views').add({
      'userId': uid,
      'coinsEarned': coins,
      'timestamp': FieldValue.serverTimestamp(),
      'payoutMonth': '${DateTime.now().month}_${DateTime.now().year}',
    });
  }

  Future<int> getDailyAdCount() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return 0;
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final snap = await _db
        .collection('viewer_ad_views')
        .where('userId', isEqualTo: uid)
        .where('timestamp', isGreaterThanOrEqualTo: start)
        .count()
        .get();
    return snap.count ?? 0;
  }

  Stream<QuerySnapshot> streamSoftPayoutHistory() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const Stream.empty();
    return _db
        .collection('viewer_soft_payouts')
        .where('userId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }
}
