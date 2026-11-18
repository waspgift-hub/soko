import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/buyer_request_model.dart';
import 'api_config.dart';
import 'auth_token.dart';

class BuyerRequestService {
  Future<String?> _token() => AuthToken.current();

  Map<String, String> _headers(String? token) => {
        'Content-Type': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

  Uri _uri(String path, [Map<String, String>? query]) {
    final uri = Uri.parse(ApiConfig.v1(path));
    if (query == null || query.isEmpty) return uri;
    return uri.replace(queryParameters: query);
  }

  Future<Map<String, dynamic>?> _get(String path, {Map<String, String>? query}) async {
    final token = await _token();
    final res = await http
        .get(_uri(path, query), headers: _headers(token))
        .timeout(const Duration(seconds: 15));
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final body = jsonDecode(res.body);
      if (body is Map<String, dynamic>) {
        final data = body['data'];
        if (data is Map<String, dynamic>) return data;
        if (data is List) return {'items': data};
      }
    }
    throw BuyerRequestException(res.statusCode, _extractError(res.body));
  }

  Future<Map<String, dynamic>?> _post(String path, {Object? body}) async {
    final token = await _token();
    final res = await http
        .post(_uri(path), headers: _headers(token), body: body == null ? null : jsonEncode(body))
        .timeout(const Duration(seconds: 15));
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) {
        final data = decoded['data'];
        if (data is Map<String, dynamic>) return data;
        if (data is List) return {'items': data};
        return decoded;
      }
      return null;
    }
    throw BuyerRequestException(res.statusCode, _extractError(res.body));
  }

  Future<Map<String, dynamic>?> _patch(String path, {Object? body}) async {
    final token = await _token();
    final res = await http
        .patch(_uri(path), headers: _headers(token), body: body == null ? null : jsonEncode(body))
        .timeout(const Duration(seconds: 15));
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) {
        final data = decoded['data'];
        if (data is Map<String, dynamic>) return data;
        return decoded;
      }
      return null;
    }
    throw BuyerRequestException(res.statusCode, _extractError(res.body));
  }

  Future<void> _delete(String path) async {
    final token = await _token();
    final res = await http
        .delete(_uri(path), headers: _headers(token))
        .timeout(const Duration(seconds: 15));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw BuyerRequestException(res.statusCode, _extractError(res.body));
    }
  }

  String _extractError(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return (decoded['message'] ?? decoded['error'] ?? decoded['code'] ?? 'Request failed').toString();
      }
    } catch (_) {}
    return body.isEmpty ? 'Request failed' : body;
  }

  // ---- Config -----------------------------------------------------------
  Future<Map<String, dynamic>> getConfig() async {
    final data = await _get('/buyer-requests/config');
    return data ?? const {};
  }

  // ---- Feed -------------------------------------------------------------
  Future<BuyerRequestPage> listFeed({
    String? q,
    String? category,
    String? location,
    int? minBudget,
    int? maxBudget,
    String sort = 'newest',
    int page = 1,
    int limit = 20,
  }) async {
    final query = <String, String>{
      'sort': sort,
      'page': '$page',
      'limit': '$limit',
      if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
      if (location != null && location.trim().isNotEmpty) 'location': location.trim(),
      if (minBudget != null && minBudget > 0) 'minBudget': '$minBudget',
      if (maxBudget != null && maxBudget > 0) 'maxBudget': '$maxBudget',
    };
    final data = await _get('/buyer-requests', query: query);
    final items = (data?['items'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(BuyerRequest.fromJson)
        .toList();
    final pag = (data?['pagination'] as Map?)?.cast<String, dynamic>() ?? const {};
    return BuyerRequestPage(
      items: items,
      page: (pag['page'] as num?)?.toInt() ?? page,
      limit: (pag['limit'] as num?)?.toInt() ?? limit,
      total: (pag['total'] as num?)?.toInt() ?? items.length,
      hasMore: pag['hasMore'] == true,
    );
  }

  // ---- Mine -------------------------------------------------------------
  Future<BuyerRequestMinePage> listMine({
    String category = 'all',
    int page = 1,
    int limit = 20,
  }) async {
    final data = await _get('/buyer-requests/mine', query: {
      'category': category,
      'page': '$page',
      'limit': '$limit',
    });
    final items = (data?['items'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(BuyerRequest.fromJson)
        .toList();
    final counts = (data?['counts'] as Map?)?.cast<String, dynamic>() ?? const {};
    final pag = (data?['pagination'] as Map?)?.cast<String, dynamic>() ?? const {};
    return BuyerRequestMinePage(
      items: items,
      counts: counts.map((k, v) => MapEntry(k, (v as num?)?.toInt() ?? 0)),
      page: (pag['page'] as num?)?.toInt() ?? page,
      limit: (pag['limit'] as num?)?.toInt() ?? limit,
      total: (pag['total'] as num?)?.toInt() ?? items.length,
      hasMore: pag['hasMore'] == true,
    );
  }

  // ---- Detail -----------------------------------------------------------
  Future<BuyerRequest> getDetail(String id) async {
    final data = await _get('/buyer-requests/$id');
    return BuyerRequest.fromJson(data ?? const {});
  }

  // ---- Create -----------------------------------------------------------
  Future<BuyerRequest> create(Map<String, dynamic> input) async {
    final data = await _post('/buyer-requests', body: input);
    return BuyerRequest.fromJson(data ?? const {});
  }

  // ---- Buyer management -------------------------------------------------
  Future<BuyerRequest> update(String id, Map<String, dynamic> patch) async {
    final data = await _patch('/buyer-requests/$id', body: patch);
    return BuyerRequest.fromJson(data ?? const {});
  }

  Future<BuyerRequest> extend(String id, {int? hours}) async {
    final data = await _post('/buyer-requests/$id/extend', body: hours == null ? {} : {'hours': hours});
    return BuyerRequest.fromJson(data ?? const {});
  }

  Future<BuyerRequest> close(String id) async {
    final data = await _post('/buyer-requests/$id/close');
    return BuyerRequest.fromJson(data ?? const {});
  }

  Future<BuyerRequest> reopen(String id) async {
    final data = await _post('/buyer-requests/$id/reopen');
    return BuyerRequest.fromJson(data ?? const {});
  }

  Future<void> trackView(String id) async {
    try {
      await _post('/buyer-requests/$id/view');
    } catch (_) {}
  }

  Future<List<BuyerRequestView>> listViews(String id) async {
    final data = await _get('/buyer-requests/$id/views');
    return (data?['items'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(BuyerRequestView.fromJson)
        .toList();
  }

  // ---- Offers -----------------------------------------------------------
  Future<BuyerRequestOffersPage> listOffers(String id) async {
    final data = await _get('/buyer-requests/$id/offers');
    final items = (data?['items'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(BuyerRequestOffer.fromJson)
        .toList();
    return BuyerRequestOffersPage(
      items: items,
      offersCount: (data?['offersCount'] as num?)?.toInt() ?? items.length,
      offerLimit: (data?['offerLimit'] as num?)?.toInt() ?? 0,
      status: (data?['status'] ?? 'active').toString(),
    );
  }

  Future<Map<String, dynamic>> createOffer(String id, Map<String, dynamic> input) async {
    final data = await _post('/buyer-requests/$id/offers', body: input);
    return data ?? const {};
  }

  Future<void> withdrawOffer(String id, String offerId) async {
    await _delete('/buyer-requests/$id/offers/$offerId');
  }

  Future<Map<String, dynamic>> decideOffer(String id, String offerId, String action) async {
    final data = await _post('/buyer-requests/$id/offers/$offerId/decide', body: {'action': action});
    return data ?? const {};
  }

  // ---- Contact ----------------------------------------------------------
  Future<Map<String, dynamic>> sellerContact(String id, String sellerId, {String lang = 'sw'}) async {
    final data = await _get('/buyer-requests/$id/sellers/$sellerId/contact', query: {'lang': lang});
    return data ?? const {};
  }

  Future<void> recordWhatsappClick(String id, String sellerId) async {
    try {
      await _post('/buyer-requests/$id/sellers/$sellerId/whatsapp-click');
    } catch (_) {}
  }

  Future<Map<String, dynamic>> getHistory(String id) async {
    final data = await _get('/buyer-requests/$id/history');
    return data ?? const {};
  }

  Future<Map<String, dynamic>> getNotificationPrefs() async {
    final data = await _get('/buyer-requests/notification-preferences');
    return data ?? const {};
  }

  // ---- Admin ------------------------------------------------------------
  Future<Map<String, dynamic>> adminDashboard() async {
    final data = await _get('/admin/buyer-requests/dashboard');
    return data ?? const {};
  }

  Future<Map<String, dynamic>> adminList({String? status, String? buyerUid, int page = 1, int limit = 30}) async {
    final q = <String, String>{'page': '$page', 'limit': '$limit'};
    if (status != null && status.isNotEmpty) q['status'] = status;
    if (buyerUid != null && buyerUid.isNotEmpty) q['buyerUid'] = buyerUid;
    final data = await _get('/admin/buyer-requests', query: q);
    return data ?? const {};
  }

  Future<Map<String, dynamic>> adminDetail(String id) async {
    final data = await _get('/admin/buyer-requests/$id');
    return data ?? const {};
  }

  Future<Map<String, dynamic>> adminModerate(String id, {required String action, String? reason, int? hours}) async {
    final body = <String, dynamic>{'action': action};
    if (reason != null) body['reason'] = reason;
    if (hours != null) body['hours'] = hours;
    final data = await _post('/admin/buyer-requests/$id/moderate', body: body);
    return data ?? const {};
  }

  Future<Map<String, dynamic>> adminUpdateConfig(Map<String, dynamic> patch) async {
    final data = await _patch('/admin/buyer-requests/config', body: patch);
    return data ?? const {};
  }

  Future<Map<String, dynamic>> adminConfig() async {
    final data = await _get('/admin/buyer-requests/config');
    return data ?? const {};
  }

  Future<Map<String, dynamic>> updateNotificationPrefs({
    bool? pushEnabled,
    bool? buyerRequestViews,
    bool? buyerRequestOffers,
  }) async {
    final body = <String, dynamic>{};
    if (pushEnabled != null) body['pushEnabled'] = pushEnabled;
    if (buyerRequestViews != null) body['buyerRequestViews'] = buyerRequestViews;
    if (buyerRequestOffers != null) body['buyerRequestOffers'] = buyerRequestOffers;
    final data = await _patch('/buyer-requests/notification-preferences', body: body);
    return data ?? const {};
  }
}

class BuyerRequestPage {
  const BuyerRequestPage({
    required this.items,
    this.page = 1,
    this.limit = 20,
    this.total = 0,
    this.hasMore = false,
  });
  final List<BuyerRequest> items;
  final int page;
  final int limit;
  final int total;
  final bool hasMore;
}

class BuyerRequestMinePage {
  const BuyerRequestMinePage({
    required this.items,
    this.counts = const {},
    this.page = 1,
    this.limit = 20,
    this.total = 0,
    this.hasMore = false,
  });
  final List<BuyerRequest> items;
  final Map<String, int> counts;
  final int page;
  final int limit;
  final int total;
  final bool hasMore;
}

class BuyerRequestOffersPage {
  const BuyerRequestOffersPage({
    required this.items,
    this.offersCount = 0,
    this.offerLimit = 0,
    this.status = 'active',
  });
  final List<BuyerRequestOffer> items;
  final int offersCount;
  final int offerLimit;
  final String status;
}

class BuyerRequestException implements Exception {
  BuyerRequestException(this.statusCode, this.message);
  final int statusCode;
  final String message;
  @override
  String toString() => 'BuyerRequestException($statusCode): $message';
}
