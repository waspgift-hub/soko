import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../models/review_model.dart';
import 'notification_service.dart';
import 'api_config.dart';

class SellerRating {
  final double averageRating;
  final int totalReviews;
  final int fiveStar;
  final int fourStar;
  final int threeStar;
  final int twoStar;
  final int oneStar;

  SellerRating({
    this.averageRating = 0.0,
    this.totalReviews = 0,
    this.fiveStar = 0,
    this.fourStar = 0,
    this.threeStar = 0,
    this.twoStar = 0,
    this.oneStar = 0,
  });

  double get ratingPercent =>
      totalReviews > 0 ? (averageRating / 5.0) : 0.0;
}

class RatingService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<SellerRating> getSellerRating(String sellerId) async {
    try {
      final snap = await _db
          .collection('reviews')
          .where('sellerId', isEqualTo: sellerId)
          .get();

      if (snap.docs.isEmpty) return SellerRating();

      int total = 0;
      int f5 = 0, f4 = 0, f3 = 0, f2 = 0, f1 = 0;

      for (var doc in snap.docs) {
        final r = (doc.data()['rating'] as num?)?.toDouble() ?? 0;
        total += r.toInt();
        final rounded = r.round();
        if (rounded >= 5) f5++;
        else if (rounded >= 4) f4++;
        else if (rounded >= 3) f3++;
        else if (rounded >= 2) f2++;
        else f1++;
      }

      final count = snap.docs.length;
      return SellerRating(
        averageRating: count > 0 ? total / count : 0.0,
        totalReviews: count,
        fiveStar: f5,
        fourStar: f4,
        threeStar: f3,
        twoStar: f2,
        oneStar: f1,
      );
    } catch (e) {
      return SellerRating();
    }
  }

  Stream<SellerRating> streamSellerRating(String sellerId) {
    return _db
        .collection('reviews')
        .where('sellerId', isEqualTo: sellerId)
        .snapshots()
        .map((snap) {
      if (snap.docs.isEmpty) return SellerRating();

      int total = 0;
      int f5 = 0, f4 = 0, f3 = 0, f2 = 0, f1 = 0;

      for (var doc in snap.docs) {
        final r = (doc.data()['rating'] as num?)?.toDouble() ?? 0;
        total += r.toInt();
        final rounded = r.round();
        if (rounded >= 5) f5++;
        else if (rounded >= 4) f4++;
        else if (rounded >= 3) f3++;
        else if (rounded >= 2) f2++;
        else f1++;
      }

      final count = snap.docs.length;
      return SellerRating(
        averageRating: count > 0 ? total / count : 0.0,
        totalReviews: count,
        fiveStar: f5,
        fourStar: f4,
        threeStar: f3,
        twoStar: f2,
        oneStar: f1,
      );
    });
  }

  Future<Review?> getReviewForProduct({
    required String productId,
    required String userId,
  }) async {
    final snap = await _db
        .collection('reviews')
        .where('productId', isEqualTo: productId)
        .where('userId', isEqualTo: userId)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return Review.fromFirestore(snap.docs.first);
  }

  Future<void> submitReview({
    required String productId,
    required String sellerId,
    required String userId,
    required String userName,
    String? userImage,
    required double rating,
    required String comment,
    bool isVerifiedPurchase = false,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) await user.getIdToken(true);

    final data = {
      'productId': productId,
      'sellerId': sellerId,
      'userId': userId,
      'userName': userName,
      'userImage': userImage ?? '',
      'rating': rating,
      'comment': comment,
      'createdAt': FieldValue.serverTimestamp(),
      'images': [],
      'helpfulCount': 0,
      'isVerifiedPurchase': isVerifiedPurchase,
    };

    final existing = await _db
        .collection('reviews')
        .where('productId', isEqualTo: productId)
        .where('userId', isEqualTo: userId)
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      await _db.collection('reviews').doc(existing.docs.first.id).update(data);
    } else {
      await _db.collection('reviews').add(data);
    }

    // Product ratings also refresh the product's aggregated rating/count.
    if (!productId.startsWith('seller_')) {
      await _recomputeProductRating(productId);
    }

    try {
      if (user?.uid != sellerId) {
        await NotificationService().sendNotification(
          userId: sellerId,
          title: 'New Rating!',
          body: '$userName rated you $rating stars',
          data: {
            'type': 'review',
            'rating': rating.toString(),
          },
        );
      }
    } catch (e) {
      // non-critical
    }
  }

  /// Recomputes products/{id} rating via server admin SDK (rules forbid client updates).
  Future<void> _recomputeProductRating(String productId) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final token = await user.getIdToken();
      await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/api/products/$productId/rating'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      // non-critical
    }
  }
}
