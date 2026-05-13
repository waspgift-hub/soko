import 'package:cloud_firestore/cloud_firestore.dart';

class Review {
  final String id;
  final String productId;
  final String userId;
  final String userName;
  final String? userImage;
  final String userTier;
  final double rating;
  final String comment;
  final DateTime createdAt;
  final List<String> images;
  final int helpfulCount;
  final bool isVerifiedPurchase;

  Review({
    required this.id,
    required this.productId,
    required this.userId,
    required this.userName,
    this.userImage,
    this.userTier = 'free',
    required this.rating,
    required this.comment,
    required this.createdAt,
    this.images = const [],
    this.helpfulCount = 0,
    this.isVerifiedPurchase = false,
  });

  factory Review.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return Review(
      id: doc.id,
      productId: data['productId'] ?? '',
      userId: data['userId'] ?? '',
      userName: data['userName'] ?? 'Anonymous',
      userImage: data['userImage'],
      userTier: data['userTier'] as String? ?? 'free',
      rating: (data['rating'] ?? 0).toDouble(),
      comment: data['comment'] ?? '',
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      images: List<String>.from(data['images'] ?? []),
      helpfulCount: data['helpfulCount'] ?? 0,
      isVerifiedPurchase: data['isVerifiedPurchase'] ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
    'productId': productId,
    'userId': userId,
    'userName': userName,
    'userImage': userImage,
    'userTier': userTier,
    'rating': rating,
    'comment': comment,
    'createdAt': FieldValue.serverTimestamp(),
    'images': images,
    'helpfulCount': helpfulCount,
    'isVerifiedPurchase': isVerifiedPurchase,
  };
}
