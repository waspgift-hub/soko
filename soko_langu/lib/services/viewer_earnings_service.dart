import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ViewerEarningsService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  static const String adUnitId = 'ca-app-pub-3940256099942544/5224354917';

  Future<void> creditAdView({
    required int viewerCoins,
    required int adminCoins,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    await _db.collection('users').doc(uid).update({
      'softCoins': FieldValue.increment(viewerCoins),
    });

    await _db.collection('admin_ad_revenue').add({
      'coinsEarned': adminCoins,
      'viewerId': uid,
      'timestamp': FieldValue.serverTimestamp(),
      'payoutMonth': '${DateTime.now().month}_${DateTime.now().year}',
    });

    await _db.collection('viewer_ad_views').add({
      'userId': uid,
      'viewerCoins': viewerCoins,
      'adminCoins': adminCoins,
      'timestamp': FieldValue.serverTimestamp(),
      'payoutMonth': '${DateTime.now().month}_${DateTime.now().year}',
    });
  }

  Future<int> getTotalAdCount() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return 0;
    final snap = await _db
        .collection('viewer_ad_views')
        .where('userId', isEqualTo: uid)
        .count()
        .get();
    return snap.count ?? 0;
  }
}
