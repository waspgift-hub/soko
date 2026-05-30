import 'package:flutter_test/flutter_test.dart';
import 'package:soko_langu/models/order_model.dart';

void main() {
  group('OrderItem', () {
    test('constructor sets fields', () {
      final item = OrderItem(
        productId: 'p1', name: 'Item', price: 15000, quantity: 2, image: 'img.jpg',
      );
      expect(item.productId, 'p1');
      expect(item.name, 'Item');
      expect(item.price, 15000);
      expect(item.quantity, 2);
      expect(item.image, 'img.jpg');
      expect(item.isReviewed, false);
    });

    test('totalPrice calculates correctly', () {
      final item = OrderItem(
        productId: 'p1', name: 'Item', price: 10000, quantity: 3,
      );
      expect(item.totalPrice, 30000);
    });

    test('fromMap parses correctly', () {
      final item = OrderItem.fromMap({
        'productId': 'p1', 'name': 'Item', 'price': 20000, 'quantity': 1,
        'image': 'img.jpg', 'isReviewed': true,
      });
      expect(item.productId, 'p1');
      expect(item.price, 20000);
      expect(item.isReviewed, true);
    });

    test('fromMap handles missing fields', () {
      final item = OrderItem.fromMap({});
      expect(item.productId, '');
      expect(item.price, 0.0);
      expect(item.quantity, 1);
      expect(item.image, null);
      expect(item.isReviewed, false);
    });

    test('toMap serializes correctly', () {
      final item = OrderItem(
        productId: 'p1', name: 'Item', price: 5000, quantity: 2,
      );
      final map = item.toMap();
      expect(map['productId'], 'p1');
      expect(map['price'], 5000);
      expect(map['quantity'], 2);
    });
  });

  group('Order', () {
    test('_parseStatus returns correct enum', () {
      expect(OrderStatus.pending.toString(), 'OrderStatus.pending');
      expect(OrderStatus.confirmed.toString(), 'OrderStatus.confirmed');
      expect(OrderStatus.delivered.toString(), 'OrderStatus.delivered');
      expect(OrderStatus.cancelled.toString(), 'OrderStatus.cancelled');
    });

    test('statusText returns correct labels', () {
      final base = Order(
        id: 'o1', buyerId: 'b1', buyerName: 'Buyer',
        sellerId: 's1', items: [], totalAmount: 0,
        status: OrderStatus.pending, createdAt: DateTime.now(),
      );
      expect(base.statusText, 'Pending');

      final shipped = Order(
        id: 'o2', buyerId: 'b1', buyerName: 'Buyer',
        sellerId: 's1', items: [], totalAmount: 0,
        status: OrderStatus.shipped, createdAt: DateTime.now(),
      );
      expect(shipped.statusText, 'Shipped');

      final cancelled = Order(
        id: 'o3', buyerId: 'b1', buyerName: 'Buyer',
        sellerId: 's1', items: [], totalAmount: 0,
        status: OrderStatus.cancelled, createdAt: DateTime.now(),
      );
      expect(cancelled.statusText, 'Cancelled');
    });

    test('toMap contains expected keys', () {
      final order = Order(
        id: 'o1', buyerId: 'b1', buyerName: 'Buyer',
        sellerId: 's1',
        items: [OrderItem(productId: 'p1', name: 'Item', price: 1000, quantity: 2)],
        totalAmount: 2000, status: OrderStatus.pending, createdAt: DateTime.now(),
        shippingAddress: 'Dar es Salaam',
        paymentMethod: 'M-Pesa',
      );
      final map = order.toMap();
      expect(map['buyerId'], 'b1');
      expect(map['totalAmount'], 2000);
      expect(map['status'], 'pending');
      expect(map['shippingAddress'], 'Dar es Salaam');
      expect(map['paymentMethod'], 'M-Pesa');
      expect(map['items'], isA<List>());
    });

    test('constructor defaults reviewedProductIds to empty list', () {
      final order = Order(
        id: 'o1', buyerId: 'b1', buyerName: 'B',
        sellerId: 's1', items: [], totalAmount: 0,
        status: OrderStatus.pending, createdAt: DateTime.now(),
      );
      expect(order.reviewedProductIds, []);
    });
  });
}
