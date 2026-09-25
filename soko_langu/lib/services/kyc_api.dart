import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import '../utils/network_error.dart';

/// Server-backed KYC client (/api/v1/kyc).
///
/// Phase D bridge: submission and status reads go through Postgres (Prisma)
/// behind [ApiConfig.kUseKycApi] instead of the Firestore users/{uid}.kyc
/// embedded doc. The v1 API returns a standard envelope; this client flattens
/// responses to the same map shapes [KycService] already returns so kyc_screen
/// needs zero changes.
class KycApiClient {
  final http.Client _http;
  final Future<String?> Function() _token;

  KycApiClient({
    http.Client? httpClient,
    Future<String?> Function()? tokenProvider,
  })  : _http = httpClient ?? http.Client(),
        _token = tokenProvider ?? _defaultToken;

  static Future<String?> _defaultToken() async =>
      FirebaseAuth.instance.currentUser?.getIdToken();

  Future<Map<String, String>> _authHeaders() async {
    final token = await _token();
    return {
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  NetworkError _errorFor(int status, {String action = 'KYC request'}) =>
      NetworkError(
        message: '$action failed ($status)',
        userMessage: ErrorKeys.poorNetwork,
      );

  /// The authenticated user's KYC status, or null when no application exists.
  ///
  /// Returns the legacy-shaped map `{'kyc': {...}}` so the caller's
  /// `result?['kyc']` access works unchanged.
  Future<Map<String, dynamic>?> fetchStatus(String userId) async {
    final uri = Uri.parse(
      ApiConfig.v1('/kyc/status/${Uri.encodeComponent(userId)}'),
    );
    final res = await _http
        .get(uri, headers: await _authHeaders())
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw _errorFor(res.statusCode, action: 'KYC status');
    }
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    final data =
        body is Map<String, dynamic> ? body['data'] : <String, dynamic>{};
    final kyc = data is Map<String, dynamic> ? data['kyc'] : null;
    return {'kyc': kyc is Map<String, dynamic> ? kyc : {'status': 'none'}};
  }

  /// Submits or resubmits a KYC application.
  ///
  /// Returns the legacy-shaped map so [KycService] can pass it straight
  /// through: `{success: true, approved, reason, message}` on success,
  /// `{success: false, error}` on validation failure.
  Future<Map<String, dynamic>> submit({
    required String fullName,
    required String idType,
    required String idNumber,
    String? idImageUrl,
    String? selfieUrl,
  }) async {
    final uri = Uri.parse(ApiConfig.v1('/kyc/submit'));
    final res = await _http
        .post(
          uri,
          headers: await _authHeaders(),
          body: jsonEncode({
            'fullName': fullName,
            'idType': idType,
            'idNumber': idNumber,
            if (idImageUrl != null) 'idImageUrl': idImageUrl,
            if (selfieUrl != null) 'selfieUrl': selfieUrl,
          }),
        )
        .timeout(const Duration(seconds: 15));
    final body = jsonDecode(utf8.decode(res.bodyBytes));

    if (res.statusCode != 200) {
      final err =
          body is Map<String, dynamic> ? body['error'] : null;
      final msg = err is Map<String, dynamic>
          ? (err['message']?.toString() ?? 'KYC submission failed')
          : 'KYC submission failed';
      return {'success': false, 'error': msg};
    }

    final data =
        body is Map<String, dynamic> ? body['data'] : <String, dynamic>{};
    return {
      'success': true,
      'approved': data?['approved'] as bool? ?? false,
      'reason': data?['reason']?.toString() ?? '',
      'message': data?['message']?.toString() ?? '',
    };
  }
}