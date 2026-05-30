import 'package:cloud_firestore/cloud_firestore.dart';

class FlashSale {
  final String id;
  final String productId;
  final String productName;
  final String productImage;
  final String sellerId;
  final String sellerName;
  final String sellerPhone;
  final String location;
  final String category;
  final double originalPrice;
  final double flashPrice;
  final double discountPercent;
  final DateTime startTime;
  final DateTime endTime;
  final int maxQuantity;
  final int soldQuantity;
  final String status;
  final bool isActive;
  final String aiReason;
  final double commission;
  final double sellerReceives;

  FlashSale({
    required this.id,
    required this.productId,
    required this.productName,
    required this.productImage,
    required this.sellerId,
    required this.sellerName,
    required this.sellerPhone,
    required this.location,
    required this.category,
    required this.originalPrice,
    required this.flashPrice,
    required this.discountPercent,
    required this.startTime,
    required this.endTime,
    required this.maxQuantity,
    required this.soldQuantity,
    required this.status,
    required this.isActive,
    required this.aiReason,
    required this.commission,
    required this.sellerReceives,
  });

  bool get isLive => isActive && status == 'active' && DateTime.now().isBefore(endTime) && soldQuantity < maxQuantity;

  Duration get timeRemaining => endTime.isAfter(DateTime.now()) ? endTime.difference(DateTime.now()) : Duration.zero;

  factory FlashSale.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return FlashSale(
      id: doc.id,
      productId: data['productId'] ?? '',
      productName: data['productName'] ?? '',
      productImage: data['productImage'] ?? '',
      sellerId: data['sellerId'] ?? '',
      sellerName: data['sellerName'] ?? '',
      sellerPhone: data['sellerPhone'] ?? '',
      location: data['location'] ?? '',
      category: data['category'] ?? '',
      originalPrice: (data['originalPrice'] ?? 0).toDouble(),
      flashPrice: (data['flashPrice'] ?? 0).toDouble(),
      discountPercent: (data['discountPercent'] ?? 0).toDouble(),
      startTime: data['startTime'] is Timestamp ? (data['startTime'] as Timestamp).toDate() : DateTime.now(),
      endTime: data['endTime'] is Timestamp ? (data['endTime'] as Timestamp).toDate() : DateTime.now(),
      maxQuantity: data['maxQuantity'] ?? 10,
      soldQuantity: data['soldQuantity'] ?? 0,
      status: data['status'] ?? 'active',
      isActive: data['isActive'] ?? true,
      aiReason: data['aiReason'] ?? '',
      commission: (data['commission'] ?? 0).toDouble(),
      sellerReceives: (data['sellerReceives'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toMap() => {
    'productId': productId,
    'productName': productName,
    'productImage': productImage,
    'sellerId': sellerId,
    'sellerName': sellerName,
    'sellerPhone': sellerPhone,
    'location': location,
    'category': category,
    'originalPrice': originalPrice,
    'flashPrice': flashPrice,
    'discountPercent': discountPercent,
    'startTime': Timestamp.fromDate(startTime),
    'endTime': Timestamp.fromDate(endTime),
    'maxQuantity': maxQuantity,
    'soldQuantity': soldQuantity,
    'status': status,
    'isActive': isActive,
    'aiReason': aiReason,
    'commission': commission,
    'sellerReceives': sellerReceives,
  };
}
