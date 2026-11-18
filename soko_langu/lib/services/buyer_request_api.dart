import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../models/buyer_request_model.dart';
import 'api_config.dart';
import '../utils/network_error.dart';

/// Server-backed buyer-requests client (`/api/v1/buyer-requests`).
class BuyerRequestApiClient {
  final http.Client _http;
  final Future<String?> Function() _token;

  BuyerRequestApiClient({
    http.Client? httpClient,
    Future<String?> Function()? tokenProvider,
  })  : _http = httpClient ?? http.Client(),
        _token = tokenProvider ?? _defaultToken;

  static Future<String?> _defaultToken() async =>
      FirebaseAuth.instance.currentUser?.getIdToken();

  Future<Map<String, String>> _headers({bool contentType = false}) async {
    final token = await _token();
    if (token == null) {
      throw NetworkError(message: 'Buyer request requires auth', userMessage: ErrorKeys.sessionExpired);
    }
    return {
      'Accept': 'application/json',
      if (contentType) 'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  static Map<String, dynamic> _dataOf(http.Response res) {
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    if (body is! Map<String, dynamic>) return const <String, dynamic>{};
    if (body['data'] is Map<String, dynamic>) return body['data'] as Map<String, dynamic>;
    return body;
  }

  static NetworkError _errorFor(http.Response res, {required String action}) {
    final userMessage = switch (res.statusCode) {
      401 => ErrorKeys.sessionExpired,
      403 => ErrorKeys.noPermission,
      404 => ErrorKeys.notFound,
      _ => ErrorKeys.generic,
    };
    return NetworkError(message: 'Buyer request $action failed: ${res.statusCode}', userMessage: userMessage);
  }

  static Map<String, dynamic> _actionResult(http.Response res, String action) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw _errorFor(res, action: action);
    }
    return _dataOf(res);
  }

  Future<Map<String, dynamic>> getConfig() async {
    final uri = Uri.parse(ApiConfig.v1('/buyer-requests/config'));
    final res = await _http.get(uri, headers: await _headers()).timeout(const Duration(seconds: 15));
    return _actionResult(res, 'config');
  }

  Future<({List<BuyerRequest> items, int total, bool hasMore})> listFeed({
    String? q,
    String? category,
    String? location,
    int? minBudget,
    int? maxBudget,
    String sort = 'newest',
    int page = 1,
    int limit = 20,
  }) async {
    final params = <String, String>{
      'page': '$page',
      'limit': '$limit',
      'sort': sort,
      if (q != null && q.isNotEmpty) 'q': q,
      if (category != null && category.isNotEmpty) 'category': category,
      if (location != null && location.isNotEmpty) 'location': location,
      if (minBudget != null) 'minBudget': '$minBudget',
      if (maxBudget != null) 'maxBudget': '$maxBudget',
    };
    final uri = Uri.parse(ApiConfig.v1('/buyer-requests')).replace(queryParameters: params);
    final res = await _http.get(uri, headers: await _headers()).timeout(const Duration(seconds: 15));
    final data = _actionResult(res, 'list');
    final items = (data['items'] is List)
        ? (data['items'] as List).whereType<Map<String, dynamic>>().map(BuyerRequest.fromJson).toList()
        : const <BuyerRequest>[];
    final pagination = data['pagination'] is Map ? data['pagination'] as Map<String, dynamic> : const <String, dynamic>{};
    return (
      items: items,
      total: (pagination['total'] as num?)?.toInt() ?? items.length,
      hasMore: pagination['hasMore'] == true,
    );
  }

  Future<({List<BuyerRequest> items, Map<String, int> counts})> listMine({String category = 'all', int page = 1, int limit = 50}) async {
    final uri = Uri.parse(ApiConfig.v1('/buyer-requests/mine')).replace(queryParameters: {'category': category, 'page': '$page', 'limit': '$limit'});
    final res = await _http.get(uri, headers: await _headers()).timeout(const Duration(seconds: 15));
    final data = _actionResult(res, 'mine');
    final items = (data['items'] is List)
        ? (data['items'] as List).whereType<Map<String, dynamic>>().map(BuyerRequest.fromJson).toList()
        : const <BuyerRequest>[];
    final counts = <String, int>{};
    if (data['counts'] is Map) {
      (data['counts'] as Map).forEach((k, v) => counts[k.toString()] = (v as num?)?.toInt() ?? 0);
    }
    return (items: items, counts: counts);
  }

  Future<BuyerRequest?> getDetail(String id) async {
    final uri = Uri.parse(ApiConfig.v1('/buyer-requests/$id'));
    final res = await _http.get(uri, headers: await _headers()).timeout(const Duration(seconds: 15));
    if (res.statusCode == 404) return null;
    final data = _actionResult(res, 'detail');
    if (data.isEmpty) return null;
    return BuyerRequest.fromJson(data);
  }

  Future<BuyerRequest> create(Map<String, dynamic> body) async {
    final uri = Uri.parse(ApiConfig.v1('/buyer-requests'));
    final res = await _http.post(uri, headers: await _headers(contentType: true), body: jsonEncode(body)).timeout(const Duration(seconds: 15));
    final data = _actionResult(res, 'create');
    return BuyerRequest.fromJson(data);
  }

  Future<BuyerRequest> update(String id, Map<String, dynamic> patch) async {
    final uri = Uri.parse(ApiConfig.v1('/buyer-requests/$id'));
    final res = await _http.patch(uri, headers: await _headers(contentType: true), body: jsonEncode(patch)).timeout(const Duration(seconds: 15));
    final data = _actionResult(res, 'update');
    return BuyerRequest.fromJson(data);
  }

  Future<BuyerRequest> extend(String id, {int? hours}) async {
    final uri = Uri.parse(ApiConfig.v1('/buyer-requests/$id/extend'));
    final res = await _http.post(uri, headers: await _headers(contentType: true), body: jsonEncode({'hours': ?hours})).timeout(const Duration(seconds: 15));
    final data = _actionResult(res, 'extend');
    return BuyerRequest.fromJson(data);
  }

  Future<BuyerRequest> close(String id) async {
    final uri = Uri.parse(ApiConfig.v1('/buyer-requests/$id/close'));
    final res = await _http.post(uri, headers: await _headers()).timeout(const Duration(seconds: 15));
    final data = _actionResult(res, 'close');
    return BuyerRequest.fromJson(data);
  }

  Future<BuyerRequest> reopen(String id) async {
    final uri = Uri.parse(ApiConfig.v1('/buyer-requests/$id/reopen'));
    final res = await _http.post(uri, headers: await _headers()).timeout(const Duration(seconds: 15));
    final data = _actionResult(res, 'reopen');
    return BuyerRequest.fromJson(data);
  }

  Future<void> trackView(String id) async {
    final uri = Uri.parse(ApiConfig.v1('/buyer-requests/$id/view'));
    final res = await _http.post(uri, headers: await _headers()).timeout(const Duration(seconds: 15));
    _actionResult(res, 'view');
  }

  Future<List<BuyerRequestView>> listViews(String id) async {
    final uri = Uri.parse(ApiConfig.v1('/buyer-requests/$id/views'));
    final res = await _http.get(uri, headers: await _headers()).timeout(const Duration(seconds: 15));
    final data = _actionResult(res, 'views');
    final items = (data['items'] is List) ? (data['items'] as List).whereType<Map<String, dynamic>>().map(BuyerRequestView.fromJson).toList() : const <BuyerRequestView>[];
    return items;
  }

  Future<({List<BuyerRequestOffer> items, int offersCount, int offerLimit})> listOffers(String id) async {
    final uri = Uri.parse(ApiConfig.v1('/buyer-requests/$id/offers'));
    final res = await _http.get(uri, headers: await _headers()).timeout(const Duration(seconds: 15));
    final data = _actionResult(res, 'offers');
    final items = (data['items'] is List) ? (data['items'] as List).whereType<Map<String, dynamic>>().map(BuyerRequestOffer.fromJson).toList() : const <BuyerRequestOffer>[];
    return (items: items, offersCount: (data['offersCount'] as num?)?.toInt() ?? items.length, offerLimit: (data['offerLimit'] as num?)?.toInt() ?? 0);
  }

  Future<Map<String, dynamic>> createOffer(String id, Map<String, dynamic> body) async {
    final uri = Uri.parse(ApiConfig.v1('/buyer-requests/$id/offers'));
    final res = await _http.post(uri, headers: await _headers(contentType: true), body: jsonEncode(body)).timeout(const Duration(seconds: 15));
    return _actionResult(res, 'offer');
  }

  Future<void> withdrawOffer(String id, String offerId) async {
    final uri = Uri.parse(ApiConfig.v1('/buyer-requests/$id/offers/$offerId'));
    final res = await _http.delete(uri, headers: await _headers()).timeout(const Duration(seconds: 15));
    _actionResult(res, 'withdraw');
  }

  Future<Map<String, dynamic>> decideOffer(String id, String offerId, String action) async {
    final uri = Uri.parse(ApiConfig.v1('/buyer-requests/$id/offers/$offerId/decide'));
    final res = await _http.post(uri, headers: await _headers(contentType: true), body: jsonEncode({'action': action})).timeout(const Duration(seconds: 15));
    return _actionResult(res, 'decide');
  }

  Future<Map<String, dynamic>> sellerContact(String id, String sellerId, {String lang = 'sw'}) async {
    final uri = Uri.parse(ApiConfig.v1('/buyer-requests/$id/sellers/$sellerId/contact')).replace(queryParameters: {'lang': lang});
    final res = await _http.get(uri, headers: await _headers()).timeout(const Duration(seconds: 15));
    return _actionResult(res, 'contact');
  }

  Future<void> recordWhatsappClick(String id, String sellerId) async {
    final uri = Uri.parse(ApiConfig.v1('/buyer-requests/$id/sellers/$sellerId/whatsapp-click'));
    final res = await _http.post(uri, headers: await _headers()).timeout(const Duration(seconds: 15));
    _actionResult(res, 'click');
  }
}