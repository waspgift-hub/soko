import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class Review {
  final String id;
  final String productId;
  final String sellerId;
  final String userId;
  final String userName;
  final String? userImage;
  final double rating;
  final String comment;
  final DateTime createdAt;
  final List<String> images;
  final int helpfulCount;
  final bool isVerifiedPurchase;
  final List<String> likedBy;
  final String? sellerReply;
  final DateTime? sellerReplyAt;

  Review({
    required this.id,
    required this.productId,
    required this.sellerId,
    required this.userId,
    required this.userName,
    this.userImage,
    required this.rating,
    required this.comment,
    required this.createdAt,
    this.images = const [],
    this.helpfulCount = 0,
    this.isVerifiedPurchase = false,
    this.likedBy = const [],
    this.sellerReply,
    this.sellerReplyAt,
  });

  factory Review.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return Review(
      id: doc.id,
      productId: data['productId'] ?? '',
      sellerId: data['sellerId'] ?? '',
      userId: data['userId'] ?? '',
      userName: data['userName'] ?? 'Anonymous',
      userImage: data['userImage'],
      rating: (data['rating'] ?? 0).toDouble(),
      comment: data['comment'] ?? '',
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      images: List<String>.from(data['images'] ?? []),
      helpfulCount: data['helpfulCount'] ?? 0,
      isVerifiedPurchase: data['isVerifiedPurchase'] ?? false,
      likedBy: List<String>.from(data['likedBy'] ?? []),
      sellerReply: data['sellerReply'],
      sellerReplyAt: data['sellerReplyAt'] is Timestamp
          ? (data['sellerReplyAt'] as Timestamp).toDate()
          : null,
    );
  }

  bool get hasLiked {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid != null && likedBy.contains(uid);
  }

  Map<String, dynamic> toMap() => {
    'productId': productId,
    'sellerId': sellerId,
    'userId': userId,
    'userName': userName,
    'userImage': userImage,
    'rating': rating,
    'comment': comment,
    'createdAt': FieldValue.serverTimestamp(),
    'images': images,
    'helpfulCount': helpfulCount,
    'isVerifiedPurchase': isVerifiedPurchase,
  };
}
