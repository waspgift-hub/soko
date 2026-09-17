import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:soko_vibe/models/product_model.dart';
import 'package:soko_vibe/services/product_api.dart';

void main() {
  group('Product.fromApi', () {
    test('maps a full server DTO correctly', () {
      final json = {
        'id': 'prod-1',
        'title': 'iPhone 15 Pro',
        'slug': 'iphone-15-pro',
        'description': 'Brand new sealed',
        'price': 2800000,
        'currency': 'TZS',
        'stock': 5,
        'status': 'published',
        'condition': 'new',
        'createdAt': '2026-09-01T10:00:00Z',
        'seller': {
          'id': '11111111-1111-1111-1111-111111111111',
          'storeName': 'John Store',
          'storeSlug': 'john-store',
        },
        'media': [
          {'type': 'image', 'r2Key': 'products/abc.jpg', 'sortOrder': 0},
        ],
        'category': {'id': 'cat-1', 'name': 'Electronics', 'slug': 'electronics'},
      };

      final p = Product.fromApi(json);
      expect(p.id, 'prod-1');
      expect(p.name, 'iPhone 15 Pro');
      expect(p.price, 2800000);
      expect(p.stock, 5);
      expect(p.sellerName, 'John Store');
      expect(p.category, 'Electronics');
      expect(p.images, ['https://media.soko-vibe.co.tz/products/abc.jpg']);
      expect(p.createdAt, DateTime.parse('2026-09-01T10:00:00Z').toLocal());
    });

    test('falls back to snapshot legacy fields (detail DTO)', () {
      final json = {
        'id': 'prod-2',
        'title': 'Sofa',
        'price': 350000,
        'createdAt': '2026-08-01T00:00:00Z',
        'media': [],
        'snapshot': {
          'sellerName': 'Mama Nne',
          'category': 'Furniture',
          'subcategory': 'Sofas',
          'location': 'Dar es Salaam',
          'district': 'Ilala',
          'images': ['https://res.cloudinary.com/example/sofa.jpg'],
          'brand': 'Ashley',
          'condition': 'used_good',
          'sellerKycApproved': true,
          'rating': 4.2,
          'reviewCount': 7,
          'soldCount': 2,
          'viewCount': 50,
          'isBoosted': true,
          'boostTier': 'gold',
        },
      };

      final p = Product.fromApi(json);
      expect(p.name, 'Sofa');
      expect(p.sellerName, 'Mama Nne');
      expect(p.category, 'Furniture');
      expect(p.subcategory, 'Sofas');
      expect(p.location, 'Dar es Salaam');
      expect(p.district, 'Ilala');
      expect(p.images.length, 1);
      expect(p.brand, 'Ashley');
      expect(p.condition, 'used_good');
      expect(p.sellerKycApproved, true);
      expect(p.rating, 4.2);
      expect(p.reviewCount, 7);
      expect(p.soldCount, 2);
      expect(p.viewCount, 50);
      expect(p.isBoosted, true);
      expect(p.boostTier, 'gold');
    });

    test('passes absolute media URLs through untouched (migrated catalog)', () {
      final p = Product.fromApi({
        'id': 'mig-1',
        'title': 'Migrated',
        'price': 5000,
        'createdAt': '2026-07-30T19:33:13Z',
        'media': [
          {
            'type': 'image',
            'r2Key': 'https://res.cloudinary.com/dgbsohnl4/image/upload/v1/p.jpg',
            'sortOrder': 0,
          },
          {
            'type': 'video',
            'r2Key': 'https://res.cloudinary.com/dgbsohnl4/video/upload/v1/c.mp4',
            'sortOrder': 1,
          },
        ],
      });
      expect(p.images, [
        'https://res.cloudinary.com/dgbsohnl4/image/upload/v1/p.jpg',
        'https://res.cloudinary.com/dgbsohnl4/video/upload/v1/c.mp4',
      ]);
    });

    test('parses legacy Firestore timestamps and snapshot isFeatured', () {
      final p = Product.fromApi({
        'id': 'mig-2',
        'title': 'Boosted',
        'price': 2000,
        'createdAt': '2026-07-30T19:33:13Z',
        'media': [],
        'snapshot': {
          'images': ['https://res.cloudinary.com/dgbsohnl4/image/upload/v1/b.jpg'],
          'isFeatured': true,
          'isBoosted': true,
          'boostTier': 'gold',
          'boostedUntil': {'_seconds': 1787307973, '_nanoseconds': 21294000},
          'featuredUntil': {'_seconds': 1787307973, '_nanoseconds': 0},
        },
      });
      expect(p.isFeatured, true);
      expect(p.isBoosted, true);
      expect(p.boostTier, 'gold');
      expect(p.boostedUntil!.millisecondsSinceEpoch, 1787307973 * 1000);
      expect(p.featuredUntil!.millisecondsSinceEpoch, 1787307973 * 1000);
      expect(p.images, ['https://res.cloudinary.com/dgbsohnl4/image/upload/v1/b.jpg']);
    });

    test('handles empty payload with defaults', () {
      final p = Product.fromApi(const {});
      expect(p.name, '');
      expect(p.price, 0);
      expect(p.category, 'General');
      expect(p.currency, 'TZS');
      expect(p.stock, 0);
      expect(p.images, isEmpty);
    });

    test('supports seller map from list DTO shape', () {
      final p = Product.fromApi({
        'id': 'x',
        'title': 'Kettle',
        'price': 45,
        'createdAt': '2026-07-01T00:00:00Z',
        'seller': {'id': 's1', 'storeName': 'Shop A'},
      });
      expect(p.sellerName, 'Shop A');
    });
  });

  group('ProductApiClient', () {
    test('parses list envelope into paginated products', () async {
      final client = ProductApiClient(
        httpClient: MockClient((request) async {
          expect(request.url.path, '/api/v1/products');
          expect(request.url.queryParameters['page'], '2');
          expect(request.url.queryParameters['limit'], '25');
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'items': [
                  {
                    'id': 'p1',
                    'title': 'A',
                    'price': 100,
                    'createdAt': '2026-09-01T00:00:00Z',
                    'seller': {'storeName': 'X'},
                    'media': [],
                  },
                  {
                    'id': 'p2',
                    'title': 'B',
                    'price': 200,
                    'createdAt': '2026-09-02T00:00:00Z',
                    'seller': {'storeName': 'Y'},
                    'media': [],
                  },
                ],
                'pagination': {'page': 2, 'limit': 25, 'total': 42},
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final res = await client.fetchProducts(page: 2, limit: 25);
      expect(res.items.length, 2);
      expect(res.page, 2);
      expect(res.limit, 25);
      expect(res.total, 42);
      expect(res.items.first.name, 'A');
    });

    test('returns default pagination when pagination missing', () async {
      final client = ProductApiClient(
        httpClient: MockClient((request) async {
          return http.Response(jsonEncode({
            'success': true,
            'data': {'items': []},
          }), 200, headers: {'content-type': 'application/json'});
        }),
      );
      final res = await client.fetchProducts();
      expect(res.items, isEmpty);
      expect(res.total, 0);
    });

    test('returns product for detail endpoint', () async {
      final client = ProductApiClient(
        httpClient: MockClient((request) async {
          expect(request.url.path, '/api/v1/products/prod-9');
          return http.Response(jsonEncode({
            'success': true,
            'data': {
              'id': 'prod-9',
              'title': 'Shoes',
              'price': 120000,
              'createdAt': '2026-09-01T00:00:00Z',
              'seller': {'storeName': 'Nike Store'},
              'media': [{'type': 'image', 'r2Key': 'k/shoes.jpg'}],
            },
          }), 200, headers: {'content-type': 'application/json'});
        }),
      );
      final p = await client.fetchProduct('prod-9');
      expect(p, isNotNull);
      expect(p!.name, 'Shoes');
      expect(p.sellerName, 'Nike Store');
      expect(p.images, ['https://media.soko-vibe.co.tz/k/shoes.jpg']);
    });

    test('returns null on 404', () async {
      final client = ProductApiClient(
        httpClient: MockClient((request) async => http.Response('{"error":"Not found"}', 404)),
      );
      expect(await client.fetchProduct('missing'), isNull);
    });

    test('passes query/category/min/max params', () async {
      Uri? captured;
      final client = ProductApiClient(
        httpClient: MockClient((request) async {
          captured = request.url;
          return http.Response(jsonEncode({
            'success': true,
            'data': {'items': []},
          }), 200, headers: {'content-type': 'application/json'});
        }),
      );
      await client.fetchProducts(
        query: 'simu',
        categoryId: 'cat-9',
        minPrice: 1000,
        maxPrice: 500000,
      );
      final q = captured!.queryParameters;
      expect(q['q'], 'simu');
      expect(q['categoryId'], 'cat-9');
      expect(q['minPrice'], '1000');
      expect(q['maxPrice'], '500000');
    });

    test('passes boosted/featured/subcategory filters', () async {
      Uri? captured;
      final client = ProductApiClient(
        httpClient: MockClient((request) async {
          captured = request.url;
          return http.Response(jsonEncode({
            'success': true,
            'data': {'items': []},
          }), 200, headers: {'content-type': 'application/json'});
        }),
      );
      await client.fetchProducts(
        boosted: true,
        featured: true,
        subcategory: 'Smartphones',
      );
      final q = captured!.queryParameters;
      expect(q['boosted'], 'true');
      expect(q['featured'], 'true');
      expect(q['subcategory'], 'Smartphones');
    });

    test('maps the flattened category tree into Category + SubCategory', () async {
      final client = ProductApiClient(
        httpClient: MockClient((request) async {
          expect(request.url.path, '/api/v1/products/categories');
          return http.Response(jsonEncode({
            'success': true,
            'data': [
              {'id': 'cat-e', 'name': 'Electronics', 'slug': 'electronics', 'parentId': null, 'iconUrl': 'https://i/e.png', 'sortOrder': 1},
              {'id': 'cat-e-phones', 'name': 'Phones & Tablets', 'slug': 'phones', 'parentId': 'cat-e', 'iconUrl': null, 'sortOrder': 0},
              {'id': 'cat-f', 'name': 'Fashion', 'slug': 'fashion', 'parentId': null, 'iconUrl': null, 'sortOrder': 2},
            ],
          }), 200, headers: {'content-type': 'application/json'});
        }),
      );
      final cats = await client.fetchCategories();
      expect(cats.length, 2);
      expect(cats.first.name, 'Electronics');
      expect(cats.first.icon, 'https://i/e.png');
      expect(cats.first.subcategories.single.name, 'Phones & Tablets');
      expect(cats.first.subcategories.single.id, 'phones');
      expect(cats.last.order, 2);
    });

    test('resolves a legacy category name to uuid and filters by it', () async {
      Uri? productsUri;
      final client = ProductApiClient(
        httpClient: MockClient((request) async {
          if (request.url.path == '/api/v1/products/categories') {
            return http.Response(jsonEncode({
              'success': true,
              'data': [
                {'id': 'cat-e', 'name': 'Electronics', 'slug': 'electronics', 'parentId': null, 'sortOrder': 1},
              ],
            }), 200, headers: {'content-type': 'application/json'});
          }
          productsUri = request.url;
          return http.Response(jsonEncode({
            'success': true,
            'data': {
              'items': [{
                'id': 'p1', 'title': 'Phone', 'price': 100,
                'createdAt': '2026-09-01T00:00:00Z',
                'seller': {'storeName': 'X'}, 'media': [],
              }],
              'pagination': {'page': 1, 'limit': 50, 'total': 1},
            },
          }), 200, headers: {'content-type': 'application/json'});
        }),
      );
      final items = await client.fetchProductsByCategoryName(
        'Electronics',
        subcategory: 'Phones',
      );
      expect(items.single.name, 'Phone');
      expect(productsUri!.queryParameters['categoryId'], 'cat-e');
      expect(productsUri!.queryParameters['subcategory'], 'Phones');
    });

    test('returns empty when category name resolves to nothing', () async {
      final client = ProductApiClient(
        httpClient: MockClient((request) async {
          return http.Response(jsonEncode({
            'success': true,
            'data': [
              {'id': 'cat-e', 'name': 'Electronics', 'slug': 'electronics', 'parentId': null, 'sortOrder': 1},
            ],
          }), 200, headers: {'content-type': 'application/json'});
        }),
      );
      final items = await client.fetchProductsByCategoryName('Unknown');
      expect(items, isEmpty);
    });

    test('reads list-card legacy fields from the projected snapshot', () async {
      final p = Product.fromApi({
        'id': 'list-1',
        'title': 'Amani Chair',
        'price': 85000,
        'createdAt': '2026-09-05T00:00:00Z',
        'seller': {'storeName': 'Furniture Co'},
        'media': [],
        'snapshot': {
          'category': 'Home & Garden',
          'subcategory': 'Furniture',
          'location': 'Arusha',
          'district': 'Ilala',
          'isBoosted': true,
          'boostTier': 'gold',
          'boostedUntil': {'_seconds': 1787307973, '_nanoseconds': 0},
          'isFeatured': true,
          'rating': 4.8,
          'soldCount': 12,
          'viewCount': 300,
        },
      });
      expect(p.category, 'Home & Garden');
      expect(p.subcategory, 'Furniture');
      expect(p.location, 'Arusha');
      expect(p.district, 'Ilala');
      expect(p.isBoosted, true);
      expect(p.isFeatured, true);
      expect(p.boostTier, 'gold');
      expect(p.boostedUntil!.millisecondsSinceEpoch, 1787307973 * 1000);
      expect(p.rating, 4.8);
      expect(p.soldCount, 12);
      expect(p.viewCount, 300);
    });
  });
}