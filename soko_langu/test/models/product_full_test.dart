import 'package:flutter_test/flutter_test.dart';
import 'package:soko_vibe/models/product_model.dart';

void main() {
  group('Product model — constructor tests', () {
    test('creates product with all required fields', () {
      final product = Product(
        id: 'p1',
        name: 'Sneakers',
        description: 'Nice shoes',
        price: 45000,
        images: ['img1.jpg', 'img2.jpg'],
        imageMetadata: const [],
        sellerId: 'u1',
        sellerName: 'Amina',
        category: 'Fashion',
        subcategory: 'Shoes',
        location: 'Dar',
        createdAt: DateTime(2025, 6, 15),
        stock: 5,
      );

      expect(product.id, 'p1');
      expect(product.name, 'Sneakers');
      expect(product.price, 45000);
      expect(product.images, ['img1.jpg', 'img2.jpg']);
      expect(product.sellerId, 'u1');
      expect(product.category, 'Fashion');
      expect(product.stock, 5);
      expect(product.isWholesale, false);
      expect(product.rating, 0.0);
      expect(product.brand, isNull);
      expect(product.condition, 'new');
    });

    test('creates product with all optional fields', () {
      final product = Product(
        id: 'p2',
        name: 'Bulk Items',
        description: 'Wholesale deal',
        price: 10000,
        currency: 'TZS',
        images: ['a.jpg'],
        sellerId: 'u2',
        sellerName: 'Seller',
        category: 'Electronics',
        subcategory: 'Phones',
        location: 'Arusha',
        district: 'Arusha CC',
        createdAt: DateTime(2025, 1, 1),
        stock: 100,
        isWholesale: true,
        wholesaleTiers: [
          WholesaleTier(minQuantity: 10, pricePerUnit: 8000),
          WholesaleTier(minQuantity: 50, pricePerUnit: 6000),
        ],
        variants: [
          ProductVariant(id: 'v1', name: 'Color', value: 'Red', stock: 5),
        ],
        attributes: {'weight': '200g'},
        isActive: true,
        isFeatured: true,
        featuredUntil: DateTime(2025, 12, 31),
        rating: 4.8,
        reviewCount: 20,
        soldCount: 30,
        viewCount: 500,
        brand: 'Nike',
        condition: 'new',
        isBoosted: true,
        boostedUntil: DateTime(2025, 8, 1),
        boostTier: 'gold',
      );

      expect(product.isWholesale, true);
      expect(product.wholesaleTiers.length, 2);
      expect(product.wholesaleTiers[0].minQuantity, 10);
      expect(product.wholesaleTiers[0].pricePerUnit, 8000);
      expect(product.variants.length, 1);
      expect(product.rating, 4.8);
      expect(product.brand, 'Nike');
      expect(product.boostTier, 'gold');
    });

    test('isFeaturedValid false when not featured', () {
      final product = Product(
        id: 'p3', name: 'X', description: '', price: 100,
        images: [], sellerId: 'u', sellerName: 'S', category: 'C',
        subcategory: '', location: 'L', createdAt: DateTime.now(), stock: 1,
      );
      expect(product.isFeaturedValid, false);
    });

    test('isFeaturedValid false when featuredUntil is null', () {
      final product = Product(
        id: 'p4', name: 'X', description: '', price: 100,
        images: [], sellerId: 'u', sellerName: 'S', category: 'C',
        subcategory: '', location: 'L', createdAt: DateTime.now(), stock: 1,
        isFeatured: true,
      );
      expect(product.isFeaturedValid, false);
    });

    test('isFeaturedValid true when featured and in future', () {
      final product = Product(
        id: 'p5', name: 'X', description: '', price: 100,
        images: [], sellerId: 'u', sellerName: 'S', category: 'C',
        subcategory: '', location: 'L', createdAt: DateTime.now(), stock: 1,
        isFeatured: true,
        featuredUntil: DateTime.now().add(const Duration(days: 30)),
      );
      expect(product.isFeaturedValid, true);
    });

    test('getWholesalePrice returns base price when not wholesale', () {
      final product = Product(
        id: 'p6', name: 'Basic', description: '', price: 20000,
        images: [], sellerId: 'u', sellerName: 'S', category: 'C',
        subcategory: '', location: 'L', createdAt: DateTime.now(), stock: 1,
      );
      expect(product.getWholesalePrice(1), 20000);
    });

    test('getWholesalePrice returns correct tier price', () {
      final product = Product(
        id: 'p7', name: 'Bulk', description: '', price: 10000,
        images: [], sellerId: 'u', sellerName: 'S', category: 'C',
        subcategory: '', location: 'L', createdAt: DateTime.now(), stock: 100,
        isWholesale: true,
        wholesaleTiers: [
          WholesaleTier(minQuantity: 5, pricePerUnit: 8000),
          WholesaleTier(minQuantity: 20, pricePerUnit: 6000),
        ],
      );
      expect(product.getWholesalePrice(3), 10000);
      expect(product.getWholesalePrice(5), 8000);
      expect(product.getWholesalePrice(20), 6000);
      expect(product.getWholesalePrice(100), 6000);
    });

    test('imageMetadata defaults to empty list', () {
      final product = Product(
        id: 'p8', name: 'X', description: '', price: 100,
        images: ['a.jpg'], sellerId: 'u', sellerName: 'S', category: 'C',
        subcategory: '', location: 'L', createdAt: DateTime.now(), stock: 1,
      );
      expect(product.imageMetadata, isNotNull);
      expect(product.imageMetadata, isEmpty);
    });

    test('imageMetadata round-trips through toMap', () {
      final product = Product(
        id: 'p9', name: 'X', description: '', price: 100,
        images: ['a.jpg'], sellerId: 'u', sellerName: 'S', category: 'C',
        subcategory: '', location: 'L', createdAt: DateTime.now(), stock: 1,
        imageMetadata: [
          {'width': 1024, 'height': 768},
          {'width': 800, 'height': 800},
        ],
      );
      final map = product.toMap();
      final meta = map['imageMetadata'] as List;
      expect(meta.length, 2);
      expect(meta[0]['width'], 1024);
      expect(meta[0]['height'], 768);
    });

    test('maxOrder and unit fields align with quantity system', () {
      final product = Product(
        id: 'p10', name: 'X', description: '', price: 100,
        images: [], sellerId: 'u', sellerName: 'S', category: 'C',
        subcategory: '', location: 'L', createdAt: DateTime.now(), stock: 50,
        unit: 'pcs',
        minOrder: 2,
        maxOrder: 20,
      );
      expect(product.unit, 'pcs');
      expect(product.minOrder, 2);
      expect(product.maxOrder, 20);
    });
  });

  group('ProductVariant', () {
    test('fromMap round-trip', () {
      final map = {'name': 'Color', 'value': 'Red', 'stock': 5, 'priceAdjustment': 1000.0};
      final v = ProductVariant.fromMap(map, 'v1');
      expect(v.id, 'v1');
      expect(v.name, 'Color');
      expect(v.value, 'Red');
      expect(v.stock, 5);
      expect(v.priceAdjustment, 1000.0);

      final back = v.toMap();
      expect(back['name'], 'Color');
      expect(back['stock'], 5);
    });

    test('fromMap handles missing fields', () {
      final v = ProductVariant.fromMap({}, 'v2');
      expect(v.name, '');
      expect(v.value, '');
      expect(v.stock, 0);
      expect(v.priceAdjustment, isNull);
    });
  });

  group('WholesaleTier', () {
    test('fromMap round-trip', () {
      final map = {'minQuantity': 10, 'pricePerUnit': 5000.0};
      final t = WholesaleTier.fromMap(map);
      expect(t.minQuantity, 10);
      expect(t.pricePerUnit, 5000.0);

      final back = t.toMap();
      expect(back['minQuantity'], 10);
      expect(back['pricePerUnit'], 5000.0);
    });

    test('fromMap handles missing fields', () {
      final t = WholesaleTier.fromMap({});
      expect(t.minQuantity, 0);
      expect(t.pricePerUnit, 0.0);
    });
  });
}
