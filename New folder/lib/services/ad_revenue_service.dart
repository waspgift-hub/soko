import 'package:cloud_firestore/cloud_firestore.dart';

class AdRevenueService {
  Future<void> recordAdView({
    required String sellerId,
    required String sellerTier,
    required String productId,
  }) async {
    try {
      await FirebaseFirestore.instance.collection('ad_views').add({
        'sellerId': sellerId,
        'sellerTier': sellerTier,
        'productId': productId,
        'viewedAt': FieldValue.serverTimestamp(),
        'type': 'product_view',
      });
    } catch (e) {
      // Silently fail - revenue tracking shouldn't break the app
    }
  }
}