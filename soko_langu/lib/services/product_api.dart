import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/product_model.dart';
import 'api_config.dart';
import '../utils/network_error.dart';

/// Server-backed product catalog client (`/api/v1/products`).
///
/// Phase C bridge: reads flow through Postgres (Prisma) on the server instead
/// of direct Firestore queries. Callers use [ProductRepository], which falls
/// back to the existing Firestore service when the API is unreachable so the
/// app never shows an empty feed during the migration window.
///
/// Envelope (server): `{ success: true, data: { items, pagination } }` for
/// list, `{ success: true, data: product }` for detail. `price` is a JSON
/// number (server serializes BigInt→Number).
class ProductApiClient {
  final http.Client _http;

  ProductApiClient({http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  /// {success, data, pagination}
  Future<({List<Product> items, int page, int limit, int total})>
      fetchProducts({
    int page = 1,
    int limit = 20,
    String? query,
    String? categoryId,
    int? minPrice,
    int? maxPrice,
  }) async {
    try {
      final params = <String, String>{
        'page': '$page',
        'limit': '$limit',
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
        'categoryId': ?categoryId,
        if (minPrice != null) 'minPrice': '$minPrice',
        if (maxPrice != null) 'maxPrice': '$maxPrice',
      };
      final uri = Uri.parse(ApiConfig.v1('/products'))
          .replace(queryParameters: params);
      final res = await _http
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) {
        throw NetworkError(
          message: 'Product fetch failed: ${res.statusCode}',
          userMessage: ErrorKeys.poorNetwork,
        );
      }
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      final data = body is Map<String, dynamic> ? body['data'] : null;
      if (data is! Map<String, dynamic>) {
        return (items: <Product>[], page: page, limit: limit, total: 0);
      }
      final items = (data['items'] as List? ?? const [])
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
    } on NetworkError {
      rethrow;
    } catch (e) {
      throw NetworkError(
        message: 'Product fetch error: $e',
        userMessage: ErrorKeys.poorNetwork,
        originalError: e,
      );
    }
  }

  /// Fetches a single product by id or slug.
  Future<Product?> fetchProduct(String idOrSlug) async {
    try {
      final uri = Uri.parse(ApiConfig.v1('/products/$idOrSlug'));
      final res = await _http
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 404) return null;
      if (res.statusCode != 200) {
        throw NetworkError(
          message: 'Product fetch failed: ${res.statusCode}',
          userMessage: ErrorKeys.poorNetwork,
        );
      }
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      final data = body is Map<String, dynamic> ? body['data'] : null;
      if (data is! Map<String, dynamic>) return null;
      return Product.fromApi(data);
    } on NetworkError {
      rethrow;
    } catch (e) {
      throw NetworkError(
        message: 'Product fetch error: $e',
        userMessage: ErrorKeys.poorNetwork,
        originalError: e,
      );
    }
  }
}