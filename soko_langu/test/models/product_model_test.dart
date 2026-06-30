import 'package:flutter_test/flutter_test.dart';
import 'package:soko_vibe/models/product_model.dart';

void main() {
  group('ProductVariant', () {
    test('constructor sets fields', () {
      final v = ProductVariant(id: 'v1', name: 'Size', value: 'Large', stock: 5);
      expect(v.id, 'v1');
      expect(v.name, 'Size');
      expect(v.value, 'Large');
      expect(v.stock, 5);
    });

    test('fromMap parses correctly', () {
      final v = ProductVariant.fromMap({'name': 'Color', 'value': 'Red', 'stock': 3}, 'v2');
      expect(v.id, 'v2');
      expect(v.name, 'Color');
      expect(v.value, 'Red');
      expect(v.stock, 3);
    });

    test('fromMap handles missing fields', () {
      final v = ProductVariant.fromMap({}, 'v3');
      expect(v.name, '');
      expect(v.value, '');
      expect(v.stock, 0);
      expect(v.priceAdjustment, null);
    });

    test('toMap serializes', () {
      final v = ProductVariant(id: 'v1', name: 'Size', value: 'XL', priceAdjustment: 2000, stock: 10);
      final map = v.toMap();
      expect(map['name'], 'Size');
      expect(map['value'], 'XL');
      expect(map['priceAdjustment'], 2000);
      expect(map['stock'], 10);
    });
  });

  group('WholesaleTier', () {
    test('constructor sets fields', () {
      final t = WholesaleTier(minQuantity: 10, pricePerUnit: 8000);
      expect(t.minQuantity, 10);
      expect(t.pricePerUnit, 8000);
    });

    test('fromMap parses correctly', () {
      final t = WholesaleTier.fromMap({'minQuantity': 5, 'pricePerUnit': 9000});
      expect(t.minQuantity, 5);
      expect(t.pricePerUnit, 9000);
    });

    test('fromMap handles missing fields', () {
      final t = WholesaleTier.fromMap({});
      expect(t.minQuantity, 0);
      expect(t.pricePerUnit, 0.0);
    });

    test('toMap serializes', () {
      final t = WholesaleTier(minQuantity: 20, pricePerUnit: 7500);
      final map = t.toMap();
      expect(map['minQuantity'], 20);
      expect(map['pricePerUnit'], 7500);
    });
  });

  group('Product', () {
    final base = Product(
      id: 'prod1',
      name: 'Test Product',
      description: 'A great product',
      price: 50000,
      images: ['img1.jpg'],
      sellerId: 'seller1',
      sellerName: 'John',
      category: 'Electronics',
      subcategory: 'Phones',
      location: 'Dar es Salaam',
      createdAt: DateTime(2025, 1, 1),
      stock: 100,
    );

    test('constructor sets fields', () {
      expect(base.id, 'prod1');
      expect(base.name, 'Test Product');
      expect(base.price, 50000);
      expect(base.isWholesale, false);
      expect(base.isActive, true);
    });

    test('isFeaturedValid false when not featured', () {
      expect(base.isFeaturedValid, false);
    });

    test('isFeaturedValid false when featuredUntil is null', () {
      final p = Product(
        id: 'p1', name: 'P', description: '', price: 100,
        images: [], sellerId: 's1', sellerName: 'S',
        category: 'C', subcategory: '', location: 'L',
        createdAt: DateTime.now(), stock: 1,
        isFeatured: true, featuredUntil: null,
      );
      expect(p.isFeaturedValid, false);
    });

    test('isFeaturedValid true when featured and in future', () {
      final p = Product(
        id: 'p1', name: 'P', description: '', price: 100,
        images: [], sellerId: 's1', sellerName: 'S',
        category: 'C', subcategory: '', location: 'L',
        createdAt: DateTime.now(), stock: 1,
        isFeatured: true, featuredUntil: DateTime.now().add(const Duration(days: 1)),
      );
      expect(p.isFeaturedValid, true);
    });

    test('isFeaturedValid false when expired', () {
      final p = Product(
        id: 'p1', name: 'P', description: '', price: 100,
        images: [], sellerId: 's1', sellerName: 'S',
        category: 'C', subcategory: '', location: 'L',
        createdAt: DateTime.now(), stock: 1,
        isFeatured: true, featuredUntil: DateTime.now().subtract(const Duration(days: 1)),
      );
      expect(p.isFeaturedValid, false);
    });

    test('getWholesalePrice returns base price when not wholesale', () {
      expect(base.getWholesalePrice(100), 50000);
    });

    test('getWholesalePrice returns base price when no tiers', () {
      final p = Product(
        id: 'p1', name: 'P', description: '', price: 10000,
        images: [], sellerId: 's1', sellerName: 'S',
        category: 'C', subcategory: '', location: 'L',
        createdAt: DateTime.now(), stock: 1,
        isWholesale: true, wholesaleTiers: [],
      );
      expect(p.getWholesalePrice(5), 10000);
    });

    test('getWholesalePrice returns correct tier', () {
      final tiers = [
        WholesaleTier(minQuantity: 5, pricePerUnit: 9000),
        WholesaleTier(minQuantity: 10, pricePerUnit: 8000),
        WholesaleTier(minQuantity: 50, pricePerUnit: 7000),
      ];
      final p = Product(
        id: 'p1', name: 'P', description: '', price: 10000,
        images: [], sellerId: 's1', sellerName: 'S',
        category: 'C', subcategory: '', location: 'L',
        createdAt: DateTime.now(), stock: 1,
        isWholesale: true, wholesaleTiers: tiers,
      );
      expect(p.getWholesalePrice(1), 10000);
      expect(p.getWholesalePrice(5), 9000);
      expect(p.getWholesalePrice(7), 9000);
      expect(p.getWholesalePrice(10), 8000);
      expect(p.getWholesalePrice(25), 8000);
      expect(p.getWholesalePrice(50), 7000);
      expect(p.getWholesalePrice(100), 7000);
    });

    test('getWholesalePrice uses highest applicable tier', () {
      final tiers = [
        WholesaleTier(minQuantity: 3, pricePerUnit: 8000),
        WholesaleTier(minQuantity: 10, pricePerUnit: 6000),
      ];
      final p = Product(
        id: 'p1', name: 'P', description: '', price: 10000,
        images: [], sellerId: 's1', sellerName: 'S',
        category: 'C', subcategory: '', location: 'L',
        createdAt: DateTime.now(), stock: 1,
        isWholesale: true, wholesaleTiers: tiers,
      );
      expect(p.getWholesalePrice(10), 6000);
    });
  });
}
