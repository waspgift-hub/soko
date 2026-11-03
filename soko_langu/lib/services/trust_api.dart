import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';

/// Server-backed seller Trust Passport client (`/api/v1/trust`).
///
/// Reads the seller's verification, fulfillment, dispatch and dispute
/// indicators from Postgres instead of the legacy Firestore compat endpoint.
/// The v1 endpoint resolves the seller by Firebase UID as well as by Postgres
/// UUID, so the caller may pass either. Behind [ApiConfig.kUseTrustApi].
class TrustApiClient {
  final http.Client _http;
  final Future<String?> Function() _token;

  TrustApiClient({
    http.Client? httpClient,
    Future<String?> Function()? tokenProvider,
  }) : _http = httpClient ?? http.Client(),
       _token = tokenProvider ?? _defaultToken;

  static Future<String?> _defaultToken() async =>
      FirebaseAuth.instance.currentUser?.getIdToken();

  /// Fetches the trust passport for a seller. Returns the raw data envelope
  /// (`{ seller, metrics, indicators }`) or null on 404 / best-effort failure.
  Future<Map<String, dynamic>?> fetchPassport(String sellerId) async {
    final uri = Uri.parse(ApiConfig.v1('/trust/sellers/$sellerId/passport'));
    try {
      final res = await _http
          .get(uri, headers: await _headers())
          .timeout(const Duration(seconds: 12));
      if (res.statusCode == 404) return null;
      if (res.statusCode != 200) return null;

      final body = jsonDecode(utf8.decode(res.bodyBytes));
      final data = body is Map<String, dynamic> && body['data'] is Map<String, dynamic>
          ? body['data'] as Map<String, dynamic>
          : null;
      return data;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, String>> _headers() async {
    final token = await _token();
    final headers = {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
    if (token != null) headers['Authorization'] = 'Bearer $token';
    return headers;
  }
}