import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:soko_vibe/services/api_config.dart';

/// Live smoke tests against the deployed backend.
///
/// These verify reachability, envelope shape and latency budget for the
/// services the search/auth/marketplace screens depend on. They hit the real
/// API (no mocks) by design — run them whenever the backend is redeployed:
///
///   flutter test test/services/live_api_smoke_test.dart
const _budget = Duration(seconds: 20);

Future<http.Response> _get(Uri uri) =>
    http.get(uri, headers: {'Accept': 'application/json'}).timeout(_budget);

Future<http.Response> _post(Uri uri) => http
    .post(
      uri,
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: '{}',
    )
    .timeout(_budget);

void main() {
  group('live services smoke (${ApiConfig.baseUrl})', () {
    test('/api/v1/products — success envelope with items list', () async {
      final res = await _get(Uri.parse('${ApiConfig.v1('/products')}?limit=5'));
      expect(res.statusCode, 200, reason: 'catalog endpoint must answer 200');
      final body =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      expect(body['success'], isTrue);
      expect(body['data'], isA<Map<String, dynamic>>());
      expect((body['data'] as Map)['items'], isA<List<dynamic>>());
    });

    test('/api/v1/search/products — ranked search answers', () async {
      // The ranked search is the hot path behind the search screen; a stall
      // here is exactly what users see as "the app froze". Retry once because
      // mobile carriers intermittently drop the first attempt.
      http.Response res;
      try {
        res = await _get(
          Uri.parse('${ApiConfig.v1('/search/products')}?q=phone&limit=5'),
        );
      } catch (_) {
        res = await _get(
          Uri.parse('${ApiConfig.v1('/search/products')}?q=phone&limit=5'),
        );
      }
      expect(res.statusCode, 200);
      final body =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      expect(body['success'], isTrue);
      expect((body['data'] as Map)['products'], isA<List<dynamic>>());
    });

    test('/api/search/trending — answers within budget', () async {
      final res = await _post(
        Uri.parse('${ApiConfig.baseUrl}/api/search/trending'),
      );
      expect(res.statusCode, 200);
      final body =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      expect(
        body.containsKey('success') || body.containsKey('trending'),
        isTrue,
      );
    });

    test('/api/search/most-rated — answers within budget', () async {
      final res = await _post(
        Uri.parse('${ApiConfig.baseUrl}/api/search/most-rated'),
      );
      expect(res.statusCode, 200);
      final body =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      expect(body['success'] ?? body.containsKey('products'), isTrue);
    });

    test('/api/search/autocomplete — no 5xx, no hang', () async {
      // Without an auth token (or with an empty query) the server may reject
      // with 400/401 — a 5xx or timeout is what actually breaks the app's
      // suggestion box, so only those are treated as failures.
      final res = await _post(
        Uri.parse('${ApiConfig.baseUrl}/api/search/autocomplete'),
      );
      expect(res.statusCode, lessThan(500));
    });
  });
}
