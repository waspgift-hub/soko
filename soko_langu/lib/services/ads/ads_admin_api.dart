import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../../models/seller_verification.dart';
import '../api_config.dart';
import 'ad_remote_config.dart';

/// Admin client for the ad system and Blue Tick grants.
///
/// Every write goes to a server route behind `authenticateAdmin`; the client
/// never writes `app_settings/ad_config` or `users/{uid}.trust` directly. That
/// keeps the trust boundary in one place and means every change lands in the
/// audit log.
class AdsAdminApiClient {
  AdsAdminApiClient({
    http.Client? httpClient,
    Future<String?> Function()? tokenProvider,
  })  : _http = httpClient ?? http.Client(),
        _token = tokenProvider ?? _defaultToken;

  static Future<String?> _defaultToken() async =>
      FirebaseAuth.instance.currentUser?.getIdToken();

  final http.Client _http;
  final Future<String?> Function() _token;

  Future<Map<String, String>> _headers() async {
    final token = await _token();
    final headers = {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
    if (token != null) headers['Authorization'] = 'Bearer $token';
    return headers;
  }

  Future<AdRemoteConfig?> fetchConfig() async {
    try {
      final res = await _http
          .get(Uri.parse(ApiConfig.v1('/admin/config/ads')),
              headers: await _headers())
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      final data = _dataOf(body);
      return data == null ? null : AdRemoteConfig.fromMap(data);
    } catch (_) {
      return null;
    }
  }

  /// Persists the configuration server-side and returns the stored value.
  Future<AdRemoteConfig?> saveConfig(AdRemoteConfig next) async {
    try {
      final res = await _http
          .put(
            Uri.parse(ApiConfig.v1('/admin/config/ads')),
            headers: await _headers(),
            body: jsonEncode({'config': next.toMap()}),
          )
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      final data = _dataOf(body);
      return data == null ? null : AdRemoteConfig.fromMap(data);
    } catch (_) {
      return null;
    }
  }

  /// Reads the derived Blue Tick state for a seller without changing anything.
  Future<SellerVerification?> fetchBlueTick(String sellerId) async {
    try {
      final res = await _http
          .get(Uri.parse(ApiConfig.v1('/admin/sellers/$sellerId/blue-tick')),
              headers: await _headers())
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return null;
      final data = _dataOf(jsonDecode(utf8.decode(res.bodyBytes)));
      if (data == null) return null;
      return SellerVerification(
        sellerId: sellerId,
        kycStatus: KycStatus.parse((data['kyc'] as Map?)?['status']),
        kycApproved: (data['kyc'] as Map?)?['approved'] == true,
        blueTick: BlueTickStatus.parse(data['blueTick']),
      );
    } catch (_) {
      return null;
    }
  }

  /// Grants or revokes the Blue Tick.
  ///
  /// The server refuses a grant unless KYC is genuinely APPROVED, and refuses
  /// to accept the state from this call in any case — the decision is always
  /// derived server-side.
  Future<SellerVerification?> setBlueTick(
    String sellerId, {
    required bool grant,
  }) async {
    try {
      final res = await _http
          .put(
            Uri.parse(ApiConfig.v1('/admin/sellers/$sellerId/blue-tick')),
            headers: await _headers(),
            body: jsonEncode({'action': grant ? 'grant' : 'revoke'}),
          )
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return null;
      final data = _dataOf(jsonDecode(utf8.decode(res.bodyBytes)));
      if (data == null) return null;
      return SellerVerification(
        sellerId: sellerId,
        kycStatus: KycStatus.parse((data['kyc'] as Map?)?['status']),
        kycApproved: (data['kyc'] as Map?)?['approved'] == true,
        blueTick: BlueTickStatus.parse(data['blueTick']),
      );
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? _dataOf(dynamic body) {
    if (body is Map && body['data'] is Map) {
      return (body['data'] as Map).cast<String, dynamic>();
    }
    if (body is Map) return body.cast<String, dynamic>();
    return null;
  }

  void dispose() => _http.close();
}
