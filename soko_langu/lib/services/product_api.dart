import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/product_model.dart';
import '../models/category_model.dart';
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
    String? subcategory,
    bool boosted = false,
    bool featured = false,
    int? minPrice,
    int? maxPrice,
  }) async {
    try {
      final params = <String, String>{
        'page': '$page',
        'limit': '$limit',
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
        'categoryId': ?categoryId,
        if (subcategory != null && subcategory.trim().isNotEmpty)
          'subcategory': subcategory.trim(),
        if (boosted) 'boosted': 'true',
        if (featured) 'featured': 'true',
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

  /// Boosted products for the home "featured" carousel. Mirrors the legacy
  /// Firestore read (`isBoosted == true`) via the server's snapshot filter;
  /// callers must still drop rows whose boost window expired.
  Future<List<Product>> fetchFeatured({int limit = 20}) async {
    final res = await fetchProducts(boosted: true, limit: limit);
    return res.items;
  }

  List<Category>? _categories;
  Map<String, String>? _categoryIdByName;

  /// Public category tree (server flattens parents + children, keeps them
  /// ordered by sortOrder). Cached in memory: the list is near-static.
  Future<List<Category>> fetchCategories() async {
    if (_categories != null) return _categories!;
    try {
      final uri = Uri.parse(ApiConfig.v1('/products/categories'));
      final res = await _http
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) {
        throw NetworkError(
          message: 'Categories fetch failed: ${res.statusCode}',
          userMessage: ErrorKeys.poorNetwork,
        );
      }
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      final rows = (body is Map<String, dynamic> ? body['data'] : null);
      if (rows is! List) return const [];
      final raw = rows
          .whereType<Map<String, dynamic>>()
          .map(
            (r) => (
              id: r['id']?.toString() ?? '',
              name: r['name']?.toString() ?? '',
              slug: r['slug']?.toString() ?? '',
              parentId: r['parentId']?.toString(),
              iconUrl: r['iconUrl']?.toString(),
              sortOrder: (r['sortOrder'] ?? 0) as int,
            ),
          )
          .toList();
      final byParent = <String, List<SubCategory>>{};
      for (final r in raw.where((r) => r.parentId != null)) {
        byParent.putIfAbsent(r.parentId!, () => []).add(
              SubCategory(
                id: r.slug.isNotEmpty ? r.slug : r.id,
                name: r.name,
                nameSw: r.name,
              ),
            );
      }
      _categories = raw
          .where((r) => r.parentId == null)
          .map(
            (r) => Category(
              id: r.id,
              name: r.name,
              nameSw: r.name,
              icon: r.iconUrl ?? '📦',
              subcategories: byParent[r.id] ?? const [],
              isActive: true,
              order: r.sortOrder,
            ),
          )
          .toList()
        ..sort((a, b) => a.order.compareTo(b.order));
      // Legacy products carry the category as a plain name string; map both the
      // root name and each subcategory name to the parent's Postgres uuid so
      // the category page can filter the list API server-side.
      _categoryIdByName = {};
      for (final c in _categories!) {
        _categoryIdByName![c.name.toLowerCase()] = c.id;
        _categoryIdByName![c.nameSw.toLowerCase()] = c.id;
        for (final sp in c.subcategories) {
          _categoryIdByName![sp.name.toLowerCase()] = c.id;
        }
      }
      return _categories!;
    } on NetworkError {
      rethrow;
    } catch (e) {
      throw NetworkError(
        message: 'Categories fetch error: $e',
        userMessage: ErrorKeys.poorNetwork,
        originalError: e,
      );
    }
  }

  /// Resolves a legacy category name (as stored on Firestore products) to the
  /// Postgres category uuid, then lists that category's published products.
  /// A name with no match yields an empty list rather than a broad query.
  Future<List<Product>> fetchProductsByCategoryName(
    String name, {
    String? subcategory,
    int limit = 50,
  }) async {
    await fetchCategories();
    final id = _categoryIdByName?[name.trim().toLowerCase()];
    if (id == null) return const [];
    final res = await fetchProducts(
      categoryId: id,
      subcategory: subcategory,
      limit: limit,
    );
    return res.items;
  }
}