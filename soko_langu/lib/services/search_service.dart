import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'api_config.dart';

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
  });

  factory SearchResponse.fromMap(Map<String, dynamic> map) {
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
}

class SearchService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
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
    final data = await _post('global-search', {
      'query': query,
      'type': type,
      'page': page,
      'pageSize': pageSize,
      if (filters != null) 'filters': filters,
    });
    return SearchResponse.fromMap(data as Map<String, dynamic>);
  }

  Future<List<SearchSuggestion>> autocomplete(String query) async {
    final data = await _post('autocomplete', {'query': query});
    final list = (data as Map<String, dynamic>)['suggestions'] as List<dynamic>? ?? [];
    return list.map((e) => SearchSuggestion.fromMap(e as Map<String, dynamic>)).toList();
  }

  Future<List<Map<String, dynamic>>> getTrendingSearches() async {
    final data = await _post('trending', {});
    final list = (data as Map<String, dynamic>)['trending'] as List<dynamic>? ?? [];
    return list.cast<Map<String, dynamic>>();
  }

  Future<void> recordClick({
    required String resultId,
    required String resultType,
    String? query,
  }) async {
    await _post('record-click', {
      'resultId': resultId,
      'resultType': resultType,
      if (query != null) 'query': query,
    });
  }
}
