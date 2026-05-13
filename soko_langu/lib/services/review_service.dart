import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/review_model.dart';
import 'notification_service.dart';

class ReviewService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final NotificationService _notif = NotificationService();

  // =========================
  // 🔍 GET USER'S REVIEW FOR A PRODUCT
  // =========================
  Future<Review?> getUserReviewForProduct(String productId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return null;

      final snapshot = await _db
          .collection("reviews")
          .where("productId", isEqualTo: productId)
          .where("userId", isEqualTo: user.uid)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) return null;
      return Review.fromFirestore(snapshot.docs.first);
    } catch (e) {
      return null;
    }
  }

  // =========================
  // 📝 ADD REVIEW
  // =========================
  Future<void> addReview({
    required String productId,
    required double rating,
    required String comment,
    List<String> images = const [],
    String? orderId,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception("User not logged in");

      final isVerified = orderId != null;

      final userDoc = await _db.collection('users').doc(user.uid).get();
      final tier = userDoc.data()?['accountTier'] as String? ?? 'free';

      await _db.collection("reviews").add({
        'productId': productId,
        'userId': user.uid,
        'userName': user.displayName ?? user.email ?? 'Anonymous',
        'userImage': user.photoURL,
        'userTier': tier,
        'rating': rating,
        'comment': comment,
        'createdAt': FieldValue.serverTimestamp(),
        'images': images,
        'helpfulCount': 0,
        'isVerifiedPurchase': isVerified,
      });

      // Mark order item as reviewed
      if (isVerified) {
        await _markOrderItemReviewed(orderId, productId);
      }

      // Update product rating
      await _updateProductRating(productId, rating);

      // Notify seller
      try {
        final productDoc = await _db
            .collection('products')
            .doc(productId)
            .get();
        if (productDoc.exists) {
          final sellerId = productDoc.data()?['sellerId'] as String?;
          if (sellerId != null) {
            _notif.sendNotification(
              userId: sellerId,
              title: 'New Review!',
              body:
                  '${user.displayName ?? "Someone"} rated your product $rating stars',
            );
          }
        }
      } catch (_) {}
    } catch (e) {
      throw Exception("Failed to add review: $e");
    }
  }

  // =========================
  // ✅ MARK ORDER ITEM AS REVIEWED
  // =========================
  Future<void> _markOrderItemReviewed(String orderId, String productId) async {
    try {
      await _db.collection("orders").doc(orderId).update({
        'reviewedProductIds': FieldValue.arrayUnion([productId]),
      });
    } catch (e) {
      // Silently fail — rating is more important than the flag
    }
  }

  // =========================
  // 📡 GET PRODUCT REVIEWS
  // =========================
  Stream<List<Review>> getProductReviews(String productId) {
    return _db
        .collection("reviews")
        .where("productId", isEqualTo: productId)
        .snapshots()
        .map((snapshot) {
          final reviews = snapshot.docs
              .map((doc) => Review.fromFirestore(doc))
              .toList();
          reviews.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return reviews;
        });
  }

  // =========================
  // 👍 MARK HELPFUL
  // =========================
  Future<void> markHelpful(String reviewId) async {
    try {
      await _db.collection("reviews").doc(reviewId).update({
        'helpfulCount': FieldValue.increment(1),
      });
    } catch (e) {
      throw Exception("Failed to mark helpful: $e");
    }
  }

  // =========================
  // 🔄 UPDATE PRODUCT RATING
  // =========================
  Future<void> _updateProductRating(String productId, double newRating) async {
    try {
      final reviews = await _db
          .collection("reviews")
          .where("productId", isEqualTo: productId)
          .get();

      final reviewList = reviews.docs;
      final totalRating = reviewList.fold<double>(
        0,
        (total, doc) => total + (doc.data()['rating'] ?? 0).toDouble(),
      );
      final averageRating = totalRating / reviewList.length;

      await _db.collection("products").doc(productId).update({
        'rating': averageRating,
        'reviewCount': reviewList.length,
      });
    } catch (e) {
      throw Exception("Failed to update product rating: $e");
    }
  }
}
