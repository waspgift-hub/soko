import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../models/product_model.dart';
import '../models/category_model.dart';
import 'api_config.dart';
import '../utils/category_icons.dart';
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
  final Future<String> Function()? _authToken;

  ProductApiClient({
    http.Client? httpClient,
    Future<String> Function()? authToken,
  }) : _http = httpClient ?? http.Client(),
       _authToken = authToken;

  /// {success, data, pagination}
  Future<({List<Product> items, int page, int limit, int total})>
      fetchProducts({
    int page = 1,
    int limit = 20,
    String? query,
    String? categoryId,
    String? subcategory,
    String? sellerId,
    String? brand,
    List<String>? ids,
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
        if (sellerId != null && sellerId.trim().isNotEmpty)
          'sellerId': sellerId.trim(),
        if (brand != null && brand.trim().isNotEmpty)
          'brand': brand.trim(),
        if (ids != null && ids.isNotEmpty) 'ids': ids.take(50).join(','),
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

  /// The signed-in seller's own listings (drafts included). The endpoint
  /// authenticates via the Firebase ID token, same as the wallet/order bridges.
  Future<List<Product>> fetchMyProducts({int page = 1, int limit = 50}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const [];
    final token = await user.getIdToken();
    final uri = Uri.parse(
      ApiConfig.v1('/products/seller'),
    ).replace(queryParameters: {'page': '$page', 'limit': '$limit'});
    try {
      final res = await _http
          .get(uri, headers: {
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
          })
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) {
        throw NetworkError(
          message: 'My products fetch failed: ${res.statusCode}',
          userMessage: ErrorKeys.poorNetwork,
        );
      }
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      final data = body is Map<String, dynamic> ? body['data'] : null;
      if (data is! Map<String, dynamic>) return const [];
      return _itemsFrom(data);
    } on NetworkError {
      rethrow;
    } catch (e) {
      throw NetworkError(
        message: 'My products fetch error: $e',
        userMessage: ErrorKeys.poorNetwork,
        originalError: e,
      );
    }
  }

  /// A seller's public shop products. [sellerId] is either the Postgres
  /// SellerProfile id or the legacy Firebase UID; the server resolves both.
  Future<List<Product>> fetchSellerProducts(
    String sellerId, {
    int limit = 50,
  }) async {
    final res = await fetchProducts(sellerId: sellerId, limit: limit);
    return res.items;
  }

  /// Batch fetch by external ids (uuid, slug, or the legacy Firestore id
  /// captured in the snapshot) for wishlist / recently-viewed rehydration.
  Future<List<Product>> fetchProductsByIds(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final res = await fetchProducts(ids: ids, limit: ids.length);
    return res.items;
  }

  List<Product> _itemsFrom(Map<String, dynamic> data) {
    return (data['items'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(Product.fromApi)
        .toList();
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
              icon: r.iconUrl ?? CategoryIconNames.package,
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
    int page = 1,
    int limit = 50,
  }) async {
    await fetchCategories();
    final id = _categoryIdByName?[name.trim().toLowerCase()];
    if (id == null) return const [];
    final res = await fetchProducts(
      categoryId: id,
      subcategory: subcategory,
      page: page,
      limit: limit,
    );
    return res.items;
  }

  /// Like [fetchProductsByCategoryName] but returns the resolved uuid, or null
  /// when the name is unknown to the Postgres category tree.
  Future<String?> resolveCategoryId(String categoryName) async {
    await fetchCategories();
    return _categoryIdByName?[categoryName.trim().toLowerCase()];
  }

  /// Forward the Firebase UID to the seller hub so fraud/analytics keep the
  /// legacy consumer's identity. Injectable for tests that run without a real
  /// Firebase app.
  Future<String> _token() async {
    final provider = _authToken;
    if (provider != null) return provider();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw NetworkError(
        message: 'Not authenticated',
        userMessage: 'Please log in to continue.',
      );
    }
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw NetworkError(
        message: 'Not authenticated',
        userMessage: 'Please log in to continue.',
      );
    }
    return token;
  }

  Future<Map<String, dynamic>> _authorizedJson(
    String method,
    String path,
    Map<String, dynamic> body,
  ) async {
    final token = await _token();
    final uri = Uri.parse(ApiConfig.v1(path));
    try {
      final request = http.Request(method, uri);
      request.headers['Accept'] = 'application/json';
      request.headers['Authorization'] = 'Bearer $token';
      if (body.isNotEmpty) {
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode(body);
      }
      final res = await http.Response.fromStream(
        await _http.send(request).timeout(const Duration(seconds: 25)),
      );
      if (res.statusCode < 200 || res.statusCode >= 300) {
        String? serverMessage;
        try {
          final errBody = jsonDecode(utf8.decode(res.bodyBytes));
          if (errBody is Map<String, dynamic>) {
            serverMessage = errBody['error']?.toString();
          }
        } catch (_) {}
        throw NetworkError(
          message: '$path failed: ${res.statusCode} ${serverMessage ?? ''}',
          userMessage: serverMessage ?? ErrorKeys.poorNetwork,
          originalError: Exception('HTTP ${res.statusCode}'),
        );
      }
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      return decoded is Map<String, dynamic> ? decoded : const {};
    } on NetworkError {
      rethrow;
    } catch (e) {
      throw NetworkError(
        message: '$path error: $e',
        userMessage: ErrorKeys.poorNetwork,
        originalError: e,
      );
    }
  }

  /// Creates a published-worthy draft (status `draft`) carrying the full
  /// Firestore-shape legacy metadata in its snapshot, then returns the new
  /// Postgres product id (uuid). Callers [publishProduct] after attaching
  /// media-bearing fields, matching the legacy `isActive: true` write.
  Future<String> createProduct({
    required String name,
    required String description,
    required double price,
    required int stock,
    String? category,
    String? categoryId,
    required String subcategory,
    List<String> images = const [],
    List<Map<String, dynamic>>? imageMetadata,
    String? videoUrl,
    bool isWholesale = false,
    List<Map<String, dynamic>>? wholesaleTiers,
    List<Map<String, dynamic>>? variants,
    Map<String, dynamic>? attributes,
    String? brand,
    String condition = 'new',
    String location = 'Tanzania',
    String district = '',
    String? barcode,
    List<String>? searchKeywords,
  }) async {
    final body = <String, dynamic>{
      'title': name,
      'description': description,
      'price': price.round(),
      'stock': stock,
      'categoryId': ?categoryId,
      'category': category,
      'subcategory': subcategory,
      'images': images,
      'imageMetadata': imageMetadata ?? const [],
      'videoUrl': videoUrl,
      'isWholesale': isWholesale,
      'wholesaleTiers': wholesaleTiers ?? const [],
      'variants': variants ?? const [],
      'attributes': attributes ?? const {},
      'brand': brand,
      'condition': condition,
      'location': location,
      'district': district,
      'barcode': barcode,
      'searchKeywords': searchKeywords ?? const [],
    };
    final response = await _authorizedJson('POST', '/products', body);
    final data = response['data'] is Map<String, dynamic>
        ? response['data'] as Map<String, dynamic>
        : null;
    final id = data?['id']?.toString() ?? '';
    if (id.isEmpty) {
      throw NetworkError(
        message: 'Create product returned no id',
        userMessage: ErrorKeys.poorNetwork,
      );
    }
    return id;
  }

  /// Patches a listing the seller owns. Only the keys present are merged; the
  /// server folds the legacy metadata into the snapshot JSON.
  Future<void> updateProduct(
    String id, {
    String? name,
    String? description,
    double? price,
    String? category,
    String? categoryId,
    String? subcategory,
    int? stock,
    bool? isWholesale,
    List<Map<String, dynamic>>? wholesaleTiers,
    List<Map<String, dynamic>>? variants,
    String? brand,
    String? condition,
    List<String>? images,
    List<Map<String, dynamic>>? imageMetadata,
    String? videoUrl,
    String? location,
    String? district,
    String? barcode,
    List<String>? searchKeywords,
  }) async {
    final body = <String, dynamic>{
      'title': ?name,
      'description': ?description,
      'price': ?(price?.round()),
      'categoryId': ?categoryId,
      'category': ?category,
      'subcategory': ?subcategory,
      'stock': ?stock,
      'isWholesale': ?isWholesale,
      'wholesaleTiers': ?wholesaleTiers,
      'variants': ?variants,
      'brand': ?brand,
      'condition': ?condition,
      'images': ?images,
      'imageMetadata': ?imageMetadata,
      'videoUrl': ?videoUrl,
      'location': ?location,
      'district': ?district,
      'barcode': ?barcode,
      'searchKeywords': ?searchKeywords,
    };
    await _authorizedJson('PUT', '/products/$id', body);
  }

  /// Publishes a draft so it appears in the public feed (legacy `isActive`).
  Future<void> publishProduct(String id) async {
    await _authorizedJson('POST', '/products/$id/publish', const {});
  }

  /// Soft-deletes a listing the seller owns (legacy delete semantics).
  Future<void> deleteProduct(String id) async {
    await _authorizedJson('DELETE', '/products/$id', const {});
  }
}