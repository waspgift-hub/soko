import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import '../models/product_model.dart';

class SearchResult {
  final String id;
  final String type;
  final String displayName;
  final String? description;
  final double? price;
  final String? image;
  final String? sellerName;
  final String? category;
  final double? rating;
  final int? reviewCount;
  final String? location;
  final double? latitude;
  final double? longitude;
  final bool isBoosted;
  final bool kycApproved;
  final double? discount;

  SearchResult({
    required this.id,
    required this.type,
    required this.displayName,
    this.description,
    this.price,
    this.image,
    this.sellerName,
    this.category,
    this.rating,
    this.reviewCount,
    this.location,
    this.latitude,
    this.longitude,
    this.isBoosted = false,
    this.kycApproved = false,
    this.discount,
  });

  factory SearchResult.fromMap(Map<String, dynamic> map) {
    return SearchResult(
      id: map['id'] as String? ?? '',
      type: map['type'] as String? ?? map['sourceType'] as String? ?? '',
      displayName: map['displayName'] as String? ?? '',
      description: map['description'] as String?,
      price: (map['price'] as num?)?.toDouble(),
      image: map['image'] as String?,
      sellerName: map['sellerName'] as String?,
      category: map['category'] as String?,
      rating: (map['rating'] as num?)?.toDouble(),
      reviewCount: (map['reviewCount'] as num?)?.toInt(),
      location: map['location'] as String?,
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      isBoosted: map['isBoosted'] as bool? ?? false,
      kycApproved: map['kycApproved'] as bool? ?? false,
      discount: (map['discount'] as num?)?.toDouble(),
    );
  }

  factory SearchResult.fromProduct(Product p) {
    return SearchResult(
      id: p.id,
      type: 'product',
      displayName: p.name,
      description: p.description,
      price: p.price,
      image: p.images.isNotEmpty ? p.images[0] : null,
      sellerName: p.sellerName,
      category: p.category,
      rating: p.rating,
      reviewCount: p.reviewCount,
      location: p.location,
      isBoosted: p.isBoostedValid,
      kycApproved: p.sellerKycApproved,
    );
  }
}

class SearchSuggestion {
  final String text;
  final String type;
  final String? image;
  final double? price;
  final String? id;

  SearchSuggestion({
    required this.text,
    required this.type,
    this.image,
    this.price,
    this.id,
  });

  factory SearchSuggestion.fromMap(Map<String, dynamic> map) {
    return SearchSuggestion(
      text: map['text'] as String? ?? '',
      type: map['type'] as String? ?? '',
      image: map['image'] as String?,
      price: (map['price'] as num?)?.toDouble(),
      id: map['id'] as String?,
    );
  }
}

class SearchResponse {
  final List<SearchResult> results;
  final Map<String, List<SearchResult>> sources;
  final int total;
  final int page;
  final bool hasMore;
  final String? correction;
  final String query;

  SearchResponse({
    required this.results,
    required this.sources,
    required this.total,
    required this.page,
    required this.hasMore,
    this.correction,
    required this.query,
  });  factory SearchResponse.fromMap(Map<String, dynamic> map) {
    final resultsList = (map['results'] as List<dynamic>?)
            ?.map((e) => SearchResult.fromMap(e as Map<String, dynamic>))
            .toList() ??
        [];

    final sourcesMap = <String, List<SearchResult>>{};
    if (map['sources'] is Map) {
      (map['sources'] as Map<String, dynamic>).forEach((key, value) {
        sourcesMap[key] = (value as List<dynamic>)
            .map((e) => SearchResult.fromMap(e as Map<String, dynamic>))
            .toList();
      });
    }

    return SearchResponse(
      results: resultsList,
      sources: sourcesMap,
      total: map['total'] as int? ?? 0,
      page: map['page'] as int? ?? 0,
      hasMore: map['hasMore'] as bool? ?? false,
      correction: map['correction'] as String?,
      query: map['query'] as String? ?? '',
    );
  }

  factory SearchResponse.fromProducts(List<Product> products, String query) {
    final results = products.map((p) => SearchResult.fromProduct(p)).toList();
    return SearchResponse(
      results: results,
      sources: {'products': results},
      total: results.length,
      page: 0,
      hasMore: false,
      query: query,
    );
  }
}

class MostRatedData {
  final List<SearchResult> products;
  final List<SearchResult> sellers;
  const MostRatedData({required this.products, required this.sellers});
}

class SearchService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const String _base = '${ApiConfig.baseUrl}/api/search';

  Future<Map<String, String>> _headers() async {
    final user = _auth.currentUser;
    final token = await user?.getIdToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<dynamic> _post(String endpoint, Map<String, dynamic> body) async {
    final headers = await _headers();
    final response = await http.post(
      Uri.parse('$_base/$endpoint'),
      headers: headers,
      body: jsonEncode(body),
    );
    if (response.statusCode >= 400) {
      final err = _tryParseError(response.body);
      throw Exception(err);
    }
    return jsonDecode(response.body);
  }

  String _tryParseError(String body) {
    try { return (jsonDecode(body) as Map)['error'] as String? ?? 'Request failed'; }
    catch (_) { return 'Request failed'; }
  }

  Future<SearchResponse> globalSearch({
    required String query,
    String type = 'all',
    int page = 0,
    int pageSize = 20,
    Map<String, dynamic>? filters,
  }) async {
    try {
      final data = await _post('global-search', {
        'query': query,
        'type': type,
        'page': page,
        'pageSize': pageSize,
        if (filters != null) 'filters': filters,
      });
      final serverResp = SearchResponse.fromMap(data as Map<String, dynamic>);
      // If server returned 0 results (search_index empty), use Firestore fallback
      if (serverResp.total == 0) {
        print('[SearchService] Server returned 0 results, using Firestore fallback');
        return _firestoreSearch(query: query, type: type, pageSize: pageSize);
      }
      return serverResp;
    } catch (e) {
      print('[SearchService] Server search failed, using Firestore fallback: $e');
      return _firestoreSearch(query: query, type: type, pageSize: pageSize);
    }
  }

  Future<SearchResponse> _firestoreSearch({
    required String query,
    String type = 'all',
    int pageSize = 30,
  }) async {
    final q = query.trim().toLowerCase();
    final words = q.split(RegExp(r'\s+')).where((w) => w.length >= 2).toList();
    if (words.isEmpty) {
      return SearchResponse(results: [], sources: {}, total: 0, page: 0, hasMore: false, query: query);
    }

    try {
      List<Product> products = [];
      if (words.length == 1) {
        final snap = await _db.collection('products')
            .where('searchKeywords', arrayContains: words[0])
            .where('isActive', isEqualTo: true)
            .limit(pageSize)
            .get();
        products = snap.docs.map((doc) => Product.fromFirestore(doc)).toList();
      } else {
        final snap = await _db.collection('products')
            .where('searchKeywords', arrayContainsAny: words.take(10).toList())
            .where('isActive', isEqualTo: true)
            .limit(pageSize)
            .get();
        products = snap.docs.map((doc) => Product.fromFirestore(doc)).toList();
      }

      products = products.where((p) =>
        words.every((w) =>
          p.name.toLowerCase().contains(w) ||
          p.description.toLowerCase().contains(w))).toList();

      return SearchResponse.fromProducts(products, query);
    } catch (e) {
      print('[SearchService] Firestore search fallback also failed: $e');
      return SearchResponse(results: [], sources: {}, total: 0, page: 0, hasMore: false, query: query);
    }
  }

  Future<List<SearchSuggestion>> autocomplete(String query) async {
    try {
      final data = await _post('autocomplete', {'query': query});
      final list = (data as Map<String, dynamic>)['suggestions'] as List<dynamic>? ?? [];
      return list.map((e) => SearchSuggestion.fromMap(e as Map<String, dynamic>)).toList();
    } catch (e) {
      print('[SearchService] Autocomplete server failed: $e');
      return _firestoreAutocomplete(query);
    }
  }

  Future<List<SearchSuggestion>> _firestoreAutocomplete(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];
    try {
      final snap = await _db.collection('products')
          .where('searchName', isGreaterThanOrEqualTo: q)
          .where('searchName', isLessThanOrEqualTo: '$q\uf8ff')
          .where('isActive', isEqualTo: true)
          .limit(10)
          .get();
      return snap.docs.map((doc) {
        final data = doc.data();
        return SearchSuggestion(
          text: data['name'] as String? ?? '',
          type: 'product',
          image: (data['images'] as List?)?.isNotEmpty == true
              ? (data['images'] as List)[0] as String
              : null,
          price: (data['price'] as num?)?.toDouble(),
          id: doc.id,
        );
      }).toList();
    } catch (e) {
      print('[SearchService] Firestore autocomplete failed: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getTrendingSearches() async {
    try {
      final data = await _post('trending', {});
      final list = (data as Map<String, dynamic>)['trending'] as List<dynamic>? ?? [];
      return list.cast<Map<String, dynamic>>();
    } catch (e) {
      print('[SearchService] Trending server failed, returning empty: $e');
      return [];
    }
  }

  /// Fetches most-rated products and sellers for the initial search view.
  Future<MostRatedData?> getMostRated({int limit = 10}) async {
    try {
      final data = await _post('most-rated', {'limit': limit});
      final map = data as Map<String, dynamic>;
      if (map['success'] != true) return null;
      final products = (map['products'] as List<dynamic>? ?? [])
          .map((e) => SearchResult.fromMap(e as Map<String, dynamic>))
          .toList();
      final sellers = (map['sellers'] as List<dynamic>? ?? [])
          .map((e) => SearchResult.fromMap(e as Map<String, dynamic>))
          .toList();
      return MostRatedData(products: products, sellers: sellers);
    } catch (e) {
      print('[SearchService] Most-rated failed: $e');
      return null;
    }
  }

  Future<void> recordClick({
    required String resultId,
    required String resultType,
    String? query,
  }) async {
    try {
      await _post('record-click', {
        'resultId': resultId,
        'resultType': resultType,
        if (query != null) 'query': query,
      });
    } catch (e) {
      // non-critical, silently ignore
    }
  }
}
