import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/product_model.dart';
import '../models/product_search_result.dart';
import 'api_config.dart';
import 'search_api.dart';

class ProductSearchService {
  static final ProductSearchService _instance = ProductSearchService._internal();
  factory ProductSearchService() => _instance;
  ProductSearchService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final SearchApiClient _search = SearchApiClient();

  ProductSearchResult _fromProduct(Product p) => ProductSearchResult(
        productId: p.id,
        productName: p.name,
        description: p.description,
        firstImage: p.images.isNotEmpty ? p.images.first : null,
        price: p.price,
        sellerId: p.sellerId,
        sellerName: p.sellerName,
        sellerPhone: p.sellerPhone ?? '',
        location: p.location,
        rating: p.rating,
        reviewCount: p.reviewCount,
        category: p.category,
        subcategory: p.subcategory,
        brand: p.brand,
        condition: p.condition,
        stock: p.stock,
        soldCount: p.soldCount,
        viewCount: p.viewCount,
        isWholesale: p.isWholesale,
      );

  ProductSearchResult? _mapDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    try {
      final data = doc.data();
      // Only fully-submitted listings may be surfaced to the AI — a product
      // missing its name, price, or seller is an incomplete/draft submission.
      final name = (data['name'] as String? ?? '').trim();
      final price = (data['price'] as num?)?.toDouble() ?? 0;
      final sellerId = (data['sellerId'] as String? ?? '').trim();
      if (name.isEmpty || price <= 0 || sellerId.isEmpty) return null;
      return ProductSearchResult.fromFirestore(doc.id, data);
    } catch (_) {
      return null;
    }
  }

  List<String> _tokens(String query) => query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .map((t) => t.trim())
      .where((t) => t.length > 1)
      .toList();

  bool _matchesTokens(Map<String, dynamic> data, List<String> tokens) {
    if (tokens.isEmpty) return false;
    final haystack =
        '${data['name']} ${data['description']} ${data['brand']} '
                '${data['category']} ${data['subcategory']} ${data['location']} '
                '${data['sellerName']}'
            .toLowerCase();
    return tokens.any((t) => haystack.contains(t));
  }

  Future<List<ProductSearchResult>> searchProducts(String query) async {
    if (query.trim().isEmpty) return [];

    // Ranked Postgres search first; fall back to Firestore only when the API
    // is down or the catalog misses — matches SearchService's migration rule.
    if (ApiConfig.kUseSearchApi) {
      final apiResults = await _search.fetchProducts(query: query, limit: 20);
      if (apiResults != null && apiResults.items.isNotEmpty) {
        return apiResults.items.take(10).map(_fromProduct).toList();
      }
    }

    final lower = query.toLowerCase().trim();
    final tokens = _tokens(query);
    final seenIds = <String>{};
    final results = <ProductSearchResult>[];

    void addDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
      if (!seenIds.add(doc.id)) return;
      final item = _mapDoc(doc);
      if (item != null) results.add(item);
    }

    try {
      final snap = await _db
          .collection('products')
          .where('isActive', isEqualTo: true)
          .limit(120)
          .get();
      for (final doc in snap.docs) {
        final data = doc.data();
        final name = (data['name'] as String? ?? '').toLowerCase();
        final brand = (data['brand'] as String? ?? '').toLowerCase();
        final category = (data['category'] as String? ?? '').toLowerCase();
        if (name.startsWith(lower) || brand.startsWith(lower) || category.startsWith(lower)) {
          addDoc(doc);
        }
      }

      if (results.length < 8 && tokens.isNotEmpty) {
        for (final doc in snap.docs) {
          if (_matchesTokens(doc.data(), tokens)) addDoc(doc);
          if (results.length >= 12) break;
        }
      }
    } catch (_) {}

    results.sort((a, b) {
      final aName = a.productName.toLowerCase();
      final bName = b.productName.toLowerCase();
      final aExact = aName == lower || aName.contains(lower);
      final bExact = bName == lower || bName.contains(lower);
      if (aExact != bExact) return aExact ? -1 : 1;
      return b.soldCount.compareTo(a.soldCount);
    });

    return results.take(10).toList();
  }
}
