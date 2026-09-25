import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/product_model.dart';
import 'api_config.dart';

/// Server-backed product search client (`/api/v1/search/products`).
///
/// Phase C search bridge: ranked product search runs against Postgres (Prisma)
/// when [ApiConfig.kUseSearchApi] is enabled, replacing the legacy global-search
/// index + Firestore fallback in [SearchService]. Returns null (not throws)
/// when the request fails or the Postgres catalog is empty so callers can fall
/// back to the legacy path during the migration window.
class SearchApiClient {
  final http.Client _http;

  SearchApiClient({http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  /// Product search. Returns null on non-200 / malformed / empty responses.
  Future<({List<Product> items, int page, int limit, int total})?>
      fetchProducts({
    required String query,
    int page = 1,
    int limit = 20,
    String? sort,
    int? minPrice,
    int? maxPrice,
  }) async {
    if (query.trim().isEmpty) return null;
    final params = <String, String>{
      'q': query.trim(),
      'page': '$page',
      'limit': '$limit',
      if (sort != null && sort.trim().isNotEmpty) 'sort': sort.trim(),
      if (minPrice != null) 'minPrice': minPrice.toString(),
      if (maxPrice != null) 'maxPrice': maxPrice.toString(),
    };
    try {
      final uri = Uri.parse(
        ApiConfig.v1('/search/products'),
      ).replace(queryParameters: params);
      final response = await _http
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return null;

      final body = jsonDecode(utf8.decode(response.bodyBytes));
      final data = body is Map<String, dynamic> ? body['data'] : null;
      if (data is! Map<String, dynamic>) return null;

      final items =
          (data['products'] as List? ?? const [])
              .whereType<Map<String, dynamic>>()
              .map(Product.fromApi)
              .toList();

      final pagination =
          data['pagination'] is Map<String, dynamic>
              ? data['pagination'] as Map<String, dynamic>
              : const <String, dynamic>{};

      return (
        items: items,
        page: (pagination['page'] ?? page) as int,
        limit: (pagination['limit'] ?? limit) as int,
        total: (pagination['total'] ?? items.length) as int,
      );
    } catch (_) {
      return null;
    }
  }
}