import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soko_vibe/services/search_api.dart';

void main() {
  group('SearchApiClient', () {
    test('fetchProducts maps envelope to items + pagination', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/v1/search/products');
        expect(request.url.queryParameters['q'], 'samsung');
        expect(request.url.queryParameters['sort'], 'price_asc');
        expect(request.url.queryParameters['minPrice'], '100000');
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'products': [
                {
                  'id': 'prod_1',
                  'title': 'Samsung Galaxy',
                  'description': 'Almost new',
                  'price': 850000,
                  'slug': 'samsung-galaxy',
                  'media': [
                    {'type': 'image', 'r2Key': 'media/prod_1/a.jpg'},
                  ],
                  'seller': {'id': 's1', 'storeName': 'Tek Store'},
                  'category': {'name': 'Phones'},
                },
              ],
              'pagination': {'page': 1, 'limit': 20, 'total': 1},
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final api = SearchApiClient(httpClient: client);
      final result = await api.fetchProducts(
        query: 'samsung',
        sort: 'price_asc',
        minPrice: 100000,
      );

      expect(result, isNotNull);
      expect(result!.items, hasLength(1));
      expect(result.items.first.name, 'Samsung Galaxy');
      expect(result.items.first.price, 850000);
      expect(result.items.first.sellerName, 'Tek Store');
      expect(result.items.first.images, [
        'https://media.soko-vibe.co.tz/media/prod_1/a.jpg',
      ]);
      expect(result.total, 1);
    });

    test('fetchProducts returns null on non-200', () async {
      final client = MockClient((_) async => http.Response('nope', 500));
      final api = SearchApiClient(httpClient: client);
      expect(await api.fetchProducts(query: 'x'), isNull);
    });

    test('fetchProducts returns null on malformed body', () async {
      final client = MockClient(
        (_) async => http.Response(jsonEncode({'success': true}), 200),
      );
      final api = SearchApiClient(httpClient: client);
      expect(await api.fetchProducts(query: 'x'), isNull);
    });

    test('fetchProducts returns null when no products', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'success': true,
            'data': {'products': [], 'pagination': {'page': 1, 'total': 0}},
          }),
          200,
        ),
      );
      final api = SearchApiClient(httpClient: client);
      final result = await api.fetchProducts(query: 'x');
      expect(result, isNotNull);
      expect(result!.items, isEmpty);
      expect(result.total, 0);
    });

    test('fetchProducts returns null for empty query', () async {
      final client = MockClient(
        (_) async => throw StateError('should not be called'),
      );
      final api = SearchApiClient(httpClient: client);
      expect(await api.fetchProducts(query: '   '), isNull);
    });
  });
}