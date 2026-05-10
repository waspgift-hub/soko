import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AdRevenueService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> recordAdView({
    required String sellerId,
    required String sellerTier,
    required String productId,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    if (sellerTier == 'free') return;

    await _db.collection('ad_views').add({
      'buyerId': uid,
      'sellerId': sellerId,
      'sellerTier': sellerTier,
      'productId': productId,
      'timestamp': FieldValue.serverTimestamp(),
      'processed': false,
    });
  }

  Future<int> getAdViewsCountToday(String sellerId) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final snap = await _db
        .collection('ad_views')
        .where('sellerId', isEqualTo: sellerId)
        .where('timestamp', isGreaterThanOrEqualTo: start)
        .count()
        .get();
    return snap.count ?? 0;
  }

  Future<int> getAdViewsCountThisMonth(String sellerId) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    final snap = await _db
        .collection('ad_views')
        .where('sellerId', isEqualTo: sellerId)
        .where('timestamp', isGreaterThanOrEqualTo: start)
        .count()
        .get();
    return snap.count ?? 0;
  }
}
