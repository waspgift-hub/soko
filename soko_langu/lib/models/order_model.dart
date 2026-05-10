import 'package:cloud_firestore/cloud_firestore.dart';

enum OrderStatus {
  pending,
  confirmed,
  processing,
  shipped,
  delivered,
  cancelled,
}

class OrderItem {
  final String productId;
  final String name;
  final double price;
  final int quantity;
  final String? image;
  final bool isReviewed;

  OrderItem({
    required this.productId,
    required this.name,
    required this.price,
    required this.quantity,
    this.image,
    this.isReviewed = false,
  });

  factory OrderItem.fromMap(Map<String, dynamic> map) {
    return OrderItem(
      productId: map['productId'] ?? '',
      name: map['name'] ?? '',
      price: (map['price'] ?? 0).toDouble(),
      quantity: map['quantity'] ?? 1,
      image: map['image'],
      isReviewed: map['isReviewed'] ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
    'productId': productId,
    'name': name,
    'price': price,
    'quantity': quantity,
    'image': image,
    'isReviewed': isReviewed,
  };

  double get totalPrice => price * quantity;
}

class Order {
  final String id;
  final String buyerId;
  final String buyerName;
  final String sellerId;
  final List<OrderItem> items;
  final double totalAmount;
  final OrderStatus status;
  final DateTime createdAt;
  final String? shippingAddress;
  final String? paymentMethod;
  final String? paymentMethodName;
  final String? paymentNumber;
  final String? trackingNumber;
  final List<String> reviewedProductIds;

  Order({
    required this.id,
    required this.buyerId,
    required this.buyerName,
    required this.sellerId,
    required this.items,
    required this.totalAmount,
    required this.status,
    required this.createdAt,
    this.shippingAddress,
    this.paymentMethod,
    this.paymentMethodName,
    this.paymentNumber,
    this.trackingNumber,
    this.reviewedProductIds = const [],
  });

  factory Order.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

    List<OrderItem> items = [];
    if (data['items'] != null) {
      for (var item in (data['items'] as List)) {
        if (item is Map<String, dynamic>) {
          items.add(OrderItem.fromMap(item));
        }
      }
    }

    return Order(
      id: doc.id,
      buyerId: data['buyerId'] ?? '',
      buyerName: data['buyerName'] ?? '',
      sellerId: data['sellerId'] ?? '',
      items: items,
      totalAmount: (data['totalAmount'] ?? 0).toDouble(),
      status: _parseStatus(data['status'] ?? 'pending'),
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      shippingAddress: data['shippingAddress'],
      paymentMethod: data['paymentMethod'],
      paymentMethodName: data['paymentMethodName'],
      paymentNumber: data['paymentNumber'],
      trackingNumber: data['trackingNumber'],
      reviewedProductIds: List<String>.from(data['reviewedProductIds'] ?? []),
    );
  }

  static OrderStatus _parseStatus(String status) {
    switch (status) {
      case 'confirmed':
        return OrderStatus.confirmed;
      case 'processing':
        return OrderStatus.processing;
      case 'shipped':
        return OrderStatus.shipped;
      case 'delivered':
        return OrderStatus.delivered;
      case 'cancelled':
        return OrderStatus.cancelled;
      default:
        return OrderStatus.pending;
    }
  }

  Map<String, dynamic> toMap() => {
    'buyerId': buyerId,
    'buyerName': buyerName,
    'sellerId': sellerId,
    'items': items.map((item) => item.toMap()).toList(),
    'totalAmount': totalAmount,
    'status': status.toString().split('.').last,
    'createdAt': FieldValue.serverTimestamp(),
    'shippingAddress': shippingAddress,
    'paymentMethod': paymentMethod,
    'paymentMethodName': paymentMethodName,
    'paymentNumber': paymentNumber,
    'trackingNumber': trackingNumber,
    'reviewedProductIds': reviewedProductIds,
  };

  String get statusText {
    switch (status) {
      case OrderStatus.pending:
        return 'Pending';
      case OrderStatus.confirmed:
        return 'Confirmed';
      case OrderStatus.processing:
        return 'Processing';
      case OrderStatus.shipped:
        return 'Shipped';
      case OrderStatus.delivered:
        return 'Delivered';
      case OrderStatus.cancelled:
        return 'Cancelled';
    }
  }
}
