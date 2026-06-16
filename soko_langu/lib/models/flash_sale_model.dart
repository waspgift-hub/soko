import 'package:cloud_firestore/cloud_firestore.dart';

class FlashSale {
  final String id;
  final String productId;
  final String productName;
  final String productImage;
  final double originalPrice;
  final double salePrice;
  final double discountPercent;
  final String sellerId;
  final String sellerName;
  final String sellerPhone;
  final String location;
  final DateTime startTime;
  final DateTime endTime;
  final int stock;
  final int soldCount;
  final bool isActive;
  final DateTime createdAt;

  FlashSale({
    required this.id,
    required this.productId,
    required this.productName,
    this.productImage = '',
    required this.originalPrice,
    required this.salePrice,
    required this.discountPercent,
    required this.sellerId,
    this.sellerName = '',
    this.sellerPhone = '',
    this.location = '',
    required this.startTime,
    required this.endTime,
    this.stock = 0,
    this.soldCount = 0,
    this.isActive = true,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory FlashSale.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    DateTime ts(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is String) return DateTime.parse(v);
      return DateTime.now();
    }

    return FlashSale(
      id: doc.id,
      productId: data['productId'] ?? '',
      productName: data['productName'] ?? '',
      productImage: data['productImage'] ?? '',
      originalPrice: (data['originalPrice'] ?? 0).toDouble(),
      salePrice: (data['salePrice'] ?? 0).toDouble(),
      discountPercent: (data['discountPercent'] ?? 0).toDouble(),
      sellerId: data['sellerId'] ?? '',
      sellerName: data['sellerName'] ?? '',
      sellerPhone: data['sellerPhone'] ?? '',
      location: data['location'] ?? '',
      stock: data['stock'] ?? 0,
      soldCount: data['soldCount'] ?? 0,
      isActive: data['isActive'] ?? true,
      startTime: ts(data['startTime']),
      endTime: ts(data['endTime']),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
    'productId': productId,
    'productName': productName,
    'productImage': productImage,
    'originalPrice': originalPrice,
    'salePrice': salePrice,
    'discountPercent': discountPercent,
    'sellerId': sellerId,
    'sellerName': sellerName,
    'sellerPhone': sellerPhone,
    'location': location,
    'stock': stock,
    'soldCount': soldCount,
    'isActive': isActive,
    'startTime': Timestamp.fromDate(startTime),
    'endTime': Timestamp.fromDate(endTime),
    'createdAt': Timestamp.fromDate(createdAt),
  };

  Duration get remainingTime => endTime.difference(DateTime.now());
  bool get isExpired => DateTime.now().isAfter(endTime);
  bool get isUpcoming => DateTime.now().isBefore(startTime);
}
