import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/review_model.dart';
import 'notification_service.dart';
import '../utils/network_error.dart';

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
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw NetworkError(
          message: "User not logged in",
          userMessage: 'Please log in to continue.',
        );
      await user.reload();
      await user.getIdToken(true);

      const isVerified = false;

      await _db.collection("reviews").add({
        'productId': productId,
        'userId': user.uid,
        'userName': user.displayName ?? user.email ?? 'Anonymous',
        'userImage': user.photoURL,
        'rating': rating,
        'comment': comment,
        'createdAt': FieldValue.serverTimestamp(),
        'images': images,
        'helpfulCount': 0,
        'isVerifiedPurchase': isVerified,
      });

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
      } catch (e) {
        debugPrint('ReviewService sendNotification: $e');
      }
    } catch (e) {
      throw NetworkError(
          message: "Failed to add review: $e",
          userMessage: translateError(e),
          originalError: e,
        );
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
      throw NetworkError(
          message: "Failed to mark helpful: $e",
          userMessage: translateError(e),
          originalError: e,
        );
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
      throw NetworkError(
          message: "Failed to update product rating: $e",
          userMessage: translateError(e),
          originalError: e,
        );
    }
  }
}
