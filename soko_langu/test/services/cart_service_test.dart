import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:soko_vibe/models/cart_item.dart';
import 'package:soko_vibe/models/product_model.dart';
import 'package:soko_vibe/services/cart_service.dart';

Product _product({
  required String id,
  required String sellerId,
  required String sellerName,
  required double price,
  String name = 'Item',
  int stock = 10,
}) {
  return Product(
    id: id,
    name: name,
    description: '',
    price: price,
    images: ['https://example.com/$id.jpg'],
    sellerId: sellerId,
    sellerName: sellerName,
    category: 'Electronics',
    subcategory: '',
    location: 'Dar',
    createdAt: DateTime(2025, 1, 1),
    stock: stock,
  );
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('cart_test');
    Hive.init(tempDir.path);
    await CartService.init();
  });

  tearDown(() async {
    await CartService().clearAll();
    await Hive.close();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('empty cart has no items and zero subtotal', () {
    final svc = CartService();
    expect(svc.items, isEmpty);
    expect(svc.count, 0);
    expect(svc.subtotal, 0);
    expect(svc.grouped(), isEmpty);
  });

  test('add groups items by seller and accumulates subtotal', () async {
    final svc = CartService();
    await svc.add(
      product: _product(id: 'a1', sellerId: 's1', sellerName: 'Seller One', price: 10000),
      quantity: 2,
    );
    await svc.add(
      product: _product(id: 'b1', sellerId: 's2', sellerName: 'Seller Two', price: 5000),
      quantity: 1,
    );
    expect(svc.count, 2);
    expect(svc.subtotal, 25000);
    final groups = svc.grouped();
    expect(groups.length, 2);
    expect(groups['s1']!.single.sellerName, 'Seller One');
  });

  test('add merges the same product+variant by summing quantity', () async {
    final svc = CartService();
    final product = _product(id: 'a1', sellerId: 's1', sellerName: 'S', price: 10000);
    await svc.add(product: product, quantity: 2, variantId: 'red');
    await svc.add(product: product, quantity: 3, variantId: 'red');
    expect(svc.count, 1);
    final item = svc.items.single;
    expect(item.quantity, 5);
    expect(item.variantId, 'red');
    expect(item.lineTotal, 50000);
  });

  test('add keeps distinct variants separate', () async {
    final svc = CartService();
    final product = _product(id: 'a1', sellerId: 's1', sellerName: 'S', price: 10000);
    await svc.add(product: product, quantity: 1, variantId: 'red');
    await svc.add(product: product, quantity: 1, variantId: 'blue');
    expect(svc.count, 2);
  });

  test('honours the unit price the buyer accepted (wholesale aware)', () async {
    final svc = CartService();
    final product = _product(id: 'a1', sellerId: 's1', sellerName: 'S', price: 20000);
    await svc.add(product: product, quantity: 5, unitPrice: 16000);
    expect(svc.items.single.unitPrice, 16000);
    expect(svc.subtotal, 80000);
  });

  test('updateQty persists the new quantity', () async {
    final svc = CartService();
    final product = _product(id: 'a1', sellerId: 's1', sellerName: 'S', price: 10000);
    await svc.add(product: product, quantity: 2);
    await svc.updateQty(product.id, null, 7);
    expect(svc.items.single.quantity, 7);
    expect(svc.subtotal, 70000);
  });

  test('updateQty is a no-op for missing item', () async {
    final svc = CartService();
    await svc.updateQty('missing', null, 3);
    expect(svc.count, 0);
  });

  test('remove deletes a single line', () async {
    final svc = CartService();
    final p = _product(id: 'a1', sellerId: 's1', sellerName: 'S', price: 10000);
    final q = _product(id: 'a2', sellerId: 's1', sellerName: 'S', price: 9000);
    await svc.add(product: p, quantity: 1);
    await svc.add(product: q, quantity: 1);
    await svc.remove(p.id, null);
    expect(svc.count, 1);
    expect(svc.items.single.productId, 'a2');
  });

  test('clearSeller removes only that sellers lines', () async {
    final svc = CartService();
    await svc.add(
      product: _product(id: 'a1', sellerId: 's1', sellerName: 'S1', price: 10000),
      quantity: 1,
    );
    await svc.add(
      product: _product(id: 'b1', sellerId: 's2', sellerName: 'S2', price: 9000),
      quantity: 1,
    );
    await svc.clearSeller('s1');
    expect(svc.count, 1);
    expect(svc.items.single.sellerId, 's2');
  });

  test('clearAll empties the cart', () async {
    final svc = CartService();
    await svc.add(
      product: _product(id: 'a1', sellerId: 's1', sellerName: 'S1', price: 10000),
      quantity: 1,
    );
    await svc.clearAll();
    expect(svc.count, 0);
  });

  test('watch() emits updated items after an add', () async {
    final svc = CartService();
    final emitted = svc.watch().first;
    await svc.add(
      product: _product(id: 'a1', sellerId: 's1', sellerName: 'S', price: 10000),
      quantity: 2,
    );
    final items = await emitted;
    expect(items.length, 1);
    expect(items.single.quantity, 2);
  });

  test('toCartItem extension maps a Product to a CartItem', () {
    final p = _product(id: 'a1', sellerId: 's1', sellerName: 'S', price: 10000);
    final item = p.toCartItem(quantity: 3, unitPrice: 8000);
    expect(item.productId, 'a1');
    expect(item.productImage, 'https://example.com/a1.jpg');
    expect(item.quantity, 3);
    expect(item.unitPrice, 8000);
    expect(item.sellerId, 's1');
    expect(item.stock, 10);
  });
}