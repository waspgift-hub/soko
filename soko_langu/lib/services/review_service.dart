import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../models/review_model.dart';
import 'notification_service.dart';
import '../utils/network_error.dart';
import 'api_config.dart';

class ReviewService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final NotificationService _notif = NotificationService();

  // =========================
  // 🏷 GET PRODUCT SELLER ID
  // =========================
  Future<String?> getProductSellerId(String productId) async {
    try {
      final doc = await _db.collection('products').doc(productId).get();
      if (!doc.exists) return null;
      return doc.data()?['sellerId'] as String?;
    } catch (_) {
      return null;
    }
  }

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
          userMessage: 'auth_login_required',
        );
      await user.reload();
      await user.getIdToken(true);

      final productDoc = await _db
          .collection('products')
          .doc(productId)
          .get();
      final productData = productDoc.data();
      final sellerId = productData?['sellerId'] as String? ?? '';

      // Sellers cannot review their own products
      if (sellerId == user.uid) {
        throw NetworkError(
          message: "Cannot rate your own product",
          userMessage: 'You cannot rate your own product',
        );
      }

      // Verified purchase = buyer has a delivered/completed order for this product.
      final isVerified = await _isVerifiedPurchase(productId, user.uid);

      await _db.collection("reviews").add({
        'productId': productId,
        'sellerId': sellerId,
        'userId': user.uid,
        'userName': user.displayName ?? user.email ?? 'Anonymous',
        'userImage': user.photoURL,
        'rating': rating,
        'comment': comment,
        'createdAt': FieldValue.serverTimestamp(),
        'images': images,
        'helpfulCount': 0,
        'likedBy': [],
        'isVerifiedPurchase': isVerified,
      });

      // Update product rating via server admin SDK (client rules forbid product updates)
      await _recomputeProductRating(productId);

      // Notify seller
      try {
        if (sellerId.isNotEmpty) {
          _notif.sendNotification(
            userId: sellerId,
            title: 'New Review!',
            body:
                '${user.displayName ?? "Someone"} rated your product $rating stars',
            data: {
              'type': 'review',
              'productId': productId,
              'rating': rating.toString(),
            },
          );
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

  /// Whether this buyer has a delivered/completed order for the product.
  Future<bool> _isVerifiedPurchase(String productId, String userId) async {
    try {
      final snap = await _db
          .collection('orders')
          .where('buyerId', isEqualTo: userId)
          .where('productId', isEqualTo: productId)
          .where('status', whereIn: ['delivered', 'completed'])
          .limit(1)
          .get();
      return snap.docs.isNotEmpty;
    } catch (e) {
      return false;
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
  // 👍 TOGGLE HELPFUL (like/unlike)
  // =========================
  Future<void> toggleHelpful(String reviewId, {required bool isLiked}) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw NetworkError(
          message: "User not logged in",
          userMessage: 'auth_login_required',
        );

      if (isLiked) {
        // Unlike: remove uid from likedBy, decrement helpfulCount
        await _db.collection("reviews").doc(reviewId).update({
          'likedBy': FieldValue.arrayRemove([user.uid]),
          'helpfulCount': FieldValue.increment(-1),
        });
      } else {
        // Like: add uid to likedBy, increment helpfulCount
        await _db.collection("reviews").doc(reviewId).update({
          'likedBy': FieldValue.arrayUnion([user.uid]),
          'helpfulCount': FieldValue.increment(1),
        });
      }
    } catch (e) {
      throw NetworkError(
          message: "Failed to toggle helpful: $e",
          userMessage: translateError(e),
          originalError: e,
        );
    }
  }

  // =========================
  // 💬 SELLER REPLY TO A REVIEW
  // =========================
  Future<void> replyToReview(String reviewId, String reply) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw NetworkError(
          message: "User not logged in",
          userMessage: 'auth_login_required',
        );
      await _db.collection("reviews").doc(reviewId).update({
        'sellerReply': reply,
        'sellerReplyAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw NetworkError(
          message: "Failed to reply to review: $e",
          userMessage: translateError(e),
          originalError: e,
        );
    }
  }

  // =========================
  // 🔄 RECOMPUTE PRODUCT RATING (server admin SDK)
  // =========================
  Future<void> _recomputeProductRating(String productId) async {
    try {
      final user = _auth.currentUser;
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
      debugPrint('ReviewService recompute rating: $e');
    }
  }
}
