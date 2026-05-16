import 'package:flutter_test/flutter_test.dart';
import 'package:soko_langu/models/cart_model.dart';

void main() {
  group('CartItem', () {
    test('constructor sets fields correctly', () {
      final item = CartItem(
        productId: 'p1',
        name: 'Test Product',
        price: 25000,
        image: 'https://example.com/img.jpg',
        quantity: 3,
        sellerId: 'seller1',
        selectedVariant: {'size': 'large'},
      );

      expect(item.productId, 'p1');
      expect(item.name, 'Test Product');
      expect(item.price, 25000);
      expect(item.image, 'https://example.com/img.jpg');
      expect(item.quantity, 3);
      expect(item.sellerId, 'seller1');
      expect(item.selectedVariant, {'size': 'large'});
    });

    test('totalPrice calculates correctly', () {
      final item = CartItem(
        productId: 'p1',
        name: 'Test',
        price: 10000,
        quantity: 5,
        sellerId: 's1',
      );
      expect(item.totalPrice, 50000);
    });

    test('fromMap parses correctly', () {
      final item = CartItem.fromMap({
        'productId': 'p1',
        'name': 'Item',
        'price': 15000,
        'image': 'img.jpg',
        'quantity': 2,
        'sellerId': 's1',
        'selectedVariant': null,
      });

      expect(item.productId, 'p1');
      expect(item.price, 15000);
      expect(item.quantity, 2);
    });

    test('fromMap handles missing fields with defaults', () {
      final item = CartItem.fromMap({});
      expect(item.productId, '');
      expect(item.name, '');
      expect(item.price, 0.0);
      expect(item.quantity, 1);
      expect(item.sellerId, '');
      expect(item.image, null);
    });

    test('toMap serializes correctly', () {
      final item = CartItem(
        productId: 'p1',
        name: 'Item',
        price: 5000,
        image: null,
        quantity: 1,
        sellerId: 's1',
      );
      final map = item.toMap();
      expect(map['productId'], 'p1');
      expect(map['name'], 'Item');
      expect(map['price'], 5000);
      expect(map['quantity'], 1);
      expect(map['sellerId'], 's1');
    });

    test('fromMap/toMap round-trip', () {
      final original = CartItem(
        productId: 'p1',
        name: 'Widget',
        price: 9999.5,
        image: 'img.png',
        quantity: 4,
        sellerId: 's2',
        selectedVariant: {'color': 'red'},
      );
      final restored = CartItem.fromMap(original.toMap());
      expect(restored.productId, original.productId);
      expect(restored.name, original.name);
      expect(restored.price, original.price);
      expect(restored.image, original.image);
      expect(restored.quantity, original.quantity);
      expect(restored.sellerId, original.sellerId);
      expect(restored.selectedVariant, original.selectedVariant);
    });
  });
}
