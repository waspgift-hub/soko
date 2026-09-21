import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../models/sponsored_campaign.dart';
import 'api_config.dart';
import '../utils/network_error.dart';

class SponsoredService {
  final http.Client _http;
  final Future<String> Function()? _authToken;

  SponsoredService({
    http.Client? httpClient,
    Future<String> Function()? authToken,
  })  : _http = httpClient ?? http.Client(),
        _authToken = authToken;

  Future<Map<String, String>> _authHeaders() async {
    final token = await _authToken?.call() ?? FirebaseAuth.instance.currentUser?.getIdToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Fetch the seller's campaigns with optional status filter.
  Future<List<SponsoredCampaign>> listCampaigns({String? status, int page = 1, int limit = 20}) async {
    final params = <String, String>{
      'page': '$page',
      'limit': '$limit',
      'status': ?status,
    };
    final uri = Uri.parse(ApiConfig.v1('/sponsored/campaigns')).replace(queryParameters: params);
    final res = await _http.get(uri, headers: await _authHeaders());
    if (res.statusCode >= 400) {
      throw NetworkError(message: 'Failed to fetch campaigns: ${res.statusCode}', userMessage: ErrorKeys.poorNetwork);
    }
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    if (body is! Map<String, dynamic> || body['data'] is! Map<String, dynamic>) return [];
    final items = (body['data']['items'] as List? ?? const []);
    return items.whereType<Map<String, dynamic>>().map((e) => SponsoredCampaign.fromApi(e)).toList();
  }

  /// Fetch a single campaign by id.
  Future<SponsoredCampaign?> getCampaign(String id) async {
    final uri = Uri.parse(ApiConfig.v1('/sponsored/campaigns/$id'));
    final res = await _http.get(uri, headers: await _authHeaders());
    if (res.statusCode == 404) return null;
    if (res.statusCode >= 400) {
      throw NetworkError(message: 'Failed to fetch campaign: ${res.statusCode}', userMessage: ErrorKeys.poorNetwork);
    }
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    if (body is! Map<String, dynamic> || body['data'] is! Map<String, dynamic>) return null;
    return SponsoredCampaign.fromApi(body['data'] as Map<String, dynamic>);
  }

  /// Create a draft campaign.
  Future<SponsoredCampaign> createCampaign({
    required String name,
    required int dailyBudgetTzs,
    required int totalBudgetTzs,
    required int bidAmountTzs,
    required String placement,
    required DateTime startsAt,
    required DateTime expiresAt,
    List<String> productIds = const [],
    bool isAllProducts = false,
  }) async {
    final uri = Uri.parse(ApiConfig.v1('/sponsored/campaigns'));
    final res = await _http.post(
      uri,
      headers: await _authHeaders(),
      body: jsonEncode({
        'name': name,
        'dailyBudgetTzs': dailyBudgetTzs,
        'totalBudgetTzs': totalBudgetTzs,
        'bidAmountTzs': bidAmountTzs,
        'placement': placement,
        'startsAt': startsAt.toIso8601String(),
        'expiresAt': expiresAt.toIso8601String(),
        'productIds': productIds,
        'isAllProducts': isAllProducts,
      }),
    );
    if (res.statusCode >= 400) {
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      throw NetworkError(
        message: body['error'] ?? 'Failed to create campaign',
        userMessage: body['error'] ?? 'Failed to create campaign',
      );
    }
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    return SponsoredCampaign.fromApi(body['data'] as Map<String, dynamic>);
  }

  /// Update a campaign (name, bid, status).
  Future<SponsoredCampaign> updateCampaign(String id, {String? name, int? bidAmountTzs, String? status}) async {
    final uri = Uri.parse(ApiConfig.v1('/sponsored/campaigns/$id'));
    final res = await _http.put(
      uri,
      headers: await _authHeaders(),
      body: jsonEncode({
        'name': ?name,
        'bidAmountTzs': ?bidAmountTzs,
        'status': ?status,
      }),
    );
    if (res.statusCode >= 400) {
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      throw NetworkError(message: body['error'] ?? 'Failed to update campaign', userMessage: ErrorKeys.poorNetwork);
    }
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    return SponsoredCampaign.fromApi(body['data'] as Map<String, dynamic>);
  }

  /// Pause a campaign.
  Future<void> pauseCampaign(String id) async {
    final uri = Uri.parse(ApiConfig.v1('/sponsored/campaigns/$id/pause'));
    final res = await _http.post(uri, headers: await _authHeaders());
    if (res.statusCode >= 400) {
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      throw NetworkError(message: body['error'] ?? 'Failed to pause campaign', userMessage: ErrorKeys.poorNetwork);
    }
  }

  /// Resume a campaign.
  Future<void> resumeCampaign(String id) async {
    final uri = Uri.parse(ApiConfig.v1('/sponsored/campaigns/$id/resume'));
    final res = await _http.post(uri, headers: await _authHeaders());
    if (res.statusCode >= 400) {
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      throw NetworkError(message: body['error'] ?? 'Failed to resume campaign', userMessage: ErrorKeys.poorNetwork);
    }
  }

  /// Cancel a campaign.
  Future<void> cancelCampaign(String id) async {
    final uri = Uri.parse(ApiConfig.v1('/sponsored/campaigns/$id/cancel'));
    final res = await _http.post(uri, headers: await _authHeaders());
    if (res.statusCode >= 400) {
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      throw NetworkError(message: body['error'] ?? 'Failed to cancel campaign', userMessage: ErrorKeys.poorNetwork);
    }
  }

  /// Initiate payment for a campaign.
  Future<Map<String, dynamic>> initiatePayment({
    required String campaignId,
    required String phone,
    required String paymentMethod,
  }) async {
    final uri = Uri.parse(ApiConfig.v1('/sponsored/campaigns/$campaignId/pay'));
    final res = await _http.post(
      uri,
      headers: await _authHeaders(),
      body: jsonEncode({'phone': phone, 'paymentMethod': paymentMethod}),
    );
    if (res.statusCode >= 400) {
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      throw NetworkError(message: body['error'] ?? 'Failed to initiate payment', userMessage: ErrorKeys.poorNetwork);
    }
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    return body['data'] as Map<String, dynamic>;
  }

  /// Get campaign metrics.
  Future<SponsoredMetrics?> getCampaignMetrics(String campaignId, {int days = 30}) async {
    final uri = Uri.parse(ApiConfig.v1('/sponsored/campaigns/$campaignId/metrics')).replace(
      queryParameters: {'days': '$days'},
    );
    final res = await _http.get(uri, headers: await _authHeaders());
    if (res.statusCode >= 400) {
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      throw NetworkError(message: body['error'] ?? 'Failed to fetch metrics', userMessage: ErrorKeys.poorNetwork);
    }
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    if (body is! Map<String, dynamic> || body['data'] is! Map<String, dynamic>) return null;
    return SponsoredMetrics.fromApi(body['data'] as Map<String, dynamic>);
  }

  /// Fetch available budget tier presets.
  Future<List<BudgetTier>> fetchBudgetTiers() async {
    final uri = Uri.parse(ApiConfig.v1('/sponsored/budget-tiers'));
    final res = await _http.get(uri, headers: await _authHeaders());
    if (res.statusCode >= 400) {
      throw NetworkError(message: 'Failed to fetch budget tiers', userMessage: ErrorKeys.poorNetwork);
    }
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    if (body is! Map<String, dynamic>) return [];
    final list = (body['data'] as List? ?? const []);
    return list.whereType<Map<String, dynamic>>().map((e) => BudgetTier.fromJson(e)).toList();
  }

  /// Record a click on a sponsored placement (for fraud tracking).
  Future<void> recordClick({required String campaignId, required String productId}) async {
    final uri = Uri.parse(ApiConfig.v1('/sponsored/placement/click'));
    final res = await _http.post(
      uri,
      headers: await _authHeaders(),
      body: jsonEncode({'campaignId': campaignId, 'productId': productId}),
    );
    // Non-blocking: failure is logged but doesn't break the UX.
    if (res.statusCode >= 400) {
      // ignore — click attribution is best-effort
    }
  }

  // ── Admin ──────────────────────────────────────────────────────────────
  // These call /sponsored/admin/* which accepts the caller's Firebase token
  // when the Postgres user has an admin role (verifyAdmin also still honours
  // the shared x-admin-secret for legacy tooling).

  /// Platform-wide sponsored metrics for the admin panel.
  Future<({AdminSponsoredSummary summary, List<SponsoredCampaign> campaigns})>
      adminMetrics({int days = 30}) async {
    final uri = Uri.parse(ApiConfig.v1('/sponsored/admin/metrics'))
        .replace(queryParameters: {'days': '$days'});
    final res = await _http.get(uri, headers: await _authHeaders());
    if (res.statusCode >= 400) {
      throw NetworkError(message: 'Failed to fetch admin metrics: ${res.statusCode}', userMessage: ErrorKeys.poorNetwork);
    }
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    final data = body is Map<String, dynamic> && body['data'] is Map<String, dynamic>
        ? body['data'] as Map<String, dynamic>
        : <String, dynamic>{};
    final campaigns = (data['campaigns'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(SponsoredCampaign.fromApi)
        .toList();
    return (summary: AdminSponsoredSummary.fromApi(data), campaigns: campaigns);
  }

  /// List campaigns platform-wide for the admin panel.
  Future<List<SponsoredCampaign>> adminListCampaigns({String? status, int page = 1, int limit = 50}) async {
    final uri = Uri.parse(ApiConfig.v1('/sponsored/admin/campaigns')).replace(queryParameters: {
      'page': '$page',
      'limit': '$limit',
      'status': ?status,
    });
    final res = await _http.get(uri, headers: await _authHeaders());
    if (res.statusCode >= 400) {
      throw NetworkError(message: 'Failed to fetch campaigns: ${res.statusCode}', userMessage: ErrorKeys.poorNetwork);
    }
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    if (body is! Map<String, dynamic> || body['data'] is! Map<String, dynamic>) return [];
    final items = (body['data']['campaigns'] as List? ?? const []);
    return items.whereType<Map<String, dynamic>>().map(SponsoredCampaign.fromApi).toList();
  }

  /// Fetch a single campaign with audit history (admin).
  Future<SponsoredCampaign?> adminGetCampaign(String id) async {
    final uri = Uri.parse(ApiConfig.v1('/sponsored/admin/campaigns/$id'));
    final res = await _http.get(uri, headers: await _authHeaders());
    if (res.statusCode == 404) return null;
    if (res.statusCode >= 400) {
      throw NetworkError(message: 'Failed to fetch campaign: ${res.statusCode}', userMessage: ErrorKeys.poorNetwork);
    }
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    if (body is! Map<String, dynamic> || body['data'] is! Map<String, dynamic>) return null;
    return SponsoredCampaign.fromApi(body['data'] as Map<String, dynamic>);
  }

  Future<void> _adminPost(String path, {Map<String, dynamic>? body}) async {
    final uri = Uri.parse(ApiConfig.v1('/sponsored/admin/campaigns/$path'));
    final res = await _http.post(
      uri,
      headers: await _authHeaders(),
      body: body == null ? null : jsonEncode(body),
    );
    if (res.statusCode >= 400) {
      final parsed = _tryError(res.body);
      throw NetworkError(message: parsed, userMessage: parsed);
    }
  }

  String _tryError(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] != null) return decoded['error'].toString();
    } catch (_) {}
    return 'Request failed';
  }

  Future<void> adminApprove(String id) => _adminPost('$id/approve');
  Future<void> adminReject(String id, {String? reason}) =>
      _adminPost('$id/reject', body: {'reason': ?reason});
  Future<void> adminPause(String id) => _adminPost('$id/pause');
  Future<void> adminResume(String id) => _adminPost('$id/resume');
  Future<void> adminEnd(String id) => _adminPost('$id/end');

  /// Fetch admin settings + effective limits.
  Future<SponsoredLimits> adminGetLimits() async {
    final uri = Uri.parse(ApiConfig.v1('/sponsored/admin/settings'));
    final res = await _http.get(uri, headers: await _authHeaders());
    if (res.statusCode >= 400) {
      throw NetworkError(message: 'Failed to fetch settings', userMessage: ErrorKeys.poorNetwork);
    }
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    final data = body is Map<String, dynamic> && body['data'] is Map<String, dynamic>
        ? body['data'] as Map<String, dynamic>
        : <String, dynamic>{};
    final limits = data['limits'] is Map<String, dynamic>
        ? data['limits'] as Map<String, dynamic>
        : <String, dynamic>{};
    return SponsoredLimits.fromApi(limits);
  }

  /// Update a single admin setting.
  Future<void> adminUpdateSetting(String key, String value, {String? description}) async {
    final uri = Uri.parse(ApiConfig.v1('/sponsored/admin/settings'));
    final res = await _http.put(
      uri,
      headers: await _authHeaders(),
      body: jsonEncode({'key': key, 'value': value, 'description': ?description}),
    );
    if (res.statusCode >= 400) {
      final parsed = _tryError(res.body);
      throw NetworkError(message: parsed, userMessage: parsed);
    }
  }

  /// Manually reconcile expired / out-of-budget campaign statuses.
  Future<void> adminSweep() async {
    final uri = Uri.parse(ApiConfig.v1('/sponsored/admin/sweep'));
    final res = await _http.post(uri, headers: await _authHeaders());
    if (res.statusCode >= 400) {
      final parsed = _tryError(res.body);
      throw NetworkError(message: parsed, userMessage: parsed);
    }
  }
}
