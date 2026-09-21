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
  /// `{success: false, error, code}` on failure. `code` is the server error
  /// code — `KYC_FEE_UNPAID` (HTTP 402) tells the caller to collect the
  /// one-time fee before resubmitting.
  Future<Map<String, dynamic>> submit({
    required String fullName,
    String? firstName,
    String? middleName,
    String? lastName,
    required String idType,
    required String idNumber,
    String? idImageUrl,
    String? selfieUrl,
    String? dateOfBirth,
    String? address,
    String? phone,
    String? email,
    String? shopVideoUrl,
  }) async {
    final uri = Uri.parse(ApiConfig.v1('/kyc/submit'));
    final res = await _http
        .post(
          uri,
          headers: await _authHeaders(),
          body: jsonEncode({
            'fullName': fullName,
            'firstName': ?firstName,
            'middleName': ?middleName,
            'lastName': ?lastName,
            'idType': idType,
            'idNumber': idNumber,
            'idImageUrl': ?idImageUrl,
            'selfieUrl': ?selfieUrl,
            'dateOfBirth': ?dateOfBirth,
            'address': ?address,
            'phone': ?phone,
            'email': ?email,
            'shopVideoUrl': ?shopVideoUrl,
          }),
        )
        .timeout(const Duration(seconds: 15));
    final body = jsonDecode(utf8.decode(res.bodyBytes));

    if (res.statusCode != 200) {
      final err = body is Map<String, dynamic> ? body['error'] : null;
      final code = err is Map<String, dynamic>
          ? err['code']?.toString()
          : null;
      final msg = err is Map<String, dynamic>
          ? (err['message']?.toString() ?? 'KYC submission failed')
          : 'KYC submission failed';
      return {
        'success': false,
        'error': msg,
        'code': ?code,
      };
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

  /// Sends a 6-digit OTP to the seller's phone (via SMS). `phone` should be in
  /// the local Tanzanian format (e.g. `0712 345 678`); the server normalizes
  /// it. Returns `{success, sent, expiresInSec}`.
  Future<Map<String, dynamic>> sendPhoneOtp(String phone) async {
    final uri = Uri.parse(ApiConfig.v1('/kyc/verify/phone/send'));
    final res = await _http
        .post(uri,
            headers: await _authHeaders(), body: jsonEncode({'value': phone}))
        .timeout(const Duration(seconds: 15));
    return _flatten(res, action: 'KYC phone OTP');
  }

  /// Verifies the phone OTP. Returns `{success, verified}`.
  Future<Map<String, dynamic>> verifyPhoneOtp({
    required String phone,
    required String otp,
  }) async {
    final uri = Uri.parse(ApiConfig.v1('/kyc/verify/phone/confirm'));
    final res = await _http
        .post(uri,
            headers: await _authHeaders(), body: jsonEncode({'value': phone, 'otp': otp}))
        .timeout(const Duration(seconds: 15));
    return _flatten(res, action: 'KYC phone OTP verify');
  }

  /// Sends a 6-digit OTP to the seller's email address via the mailer.
  Future<Map<String, dynamic>> sendEmailOtp(String email) async {
    final uri = Uri.parse(ApiConfig.v1('/kyc/verify/email/send'));
    final res = await _http
        .post(uri,
            headers: await _authHeaders(), body: jsonEncode({'value': email}))
        .timeout(const Duration(seconds: 15));
    return _flatten(res, action: 'KYC email OTP');
  }

  /// Verifies the email OTP. Returns `{success, verified}`.
  Future<Map<String, dynamic>> verifyEmailOtp({
    required String email,
    required String otp,
  }) async {
    final uri = Uri.parse(ApiConfig.v1('/kyc/verify/email/confirm'));
    final res = await _http
        .post(uri,
            headers: await _authHeaders(), body: jsonEncode({'value': email, 'otp': otp}))
        .timeout(const Duration(seconds: 15));
    return _flatten(res, action: 'KYC email OTP verify');
  }

  /// Flattens the v1 envelope: `{success: true, ...data}` on success,
  /// `{success: false, error, code}` on failure. Server error bodies carry a
  /// nested `{code, message}` object, which callers pass into translation.
  Map<String, dynamic> _flatten(
    http.Response res, {
    String action = 'KYC request',
  }) {
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    if (res.statusCode != 200) {
      final err = body is Map<String, dynamic> ? body['error'] : null;
      final code = err is Map<String, dynamic>
          ? err['code']?.toString()
          : null;
      final raw = err is Map<String, dynamic>
          ? err['message']?.toString()
          : null;
      return {
        'success': false,
        'error': raw ?? '$action failed (${res.statusCode})',
        'code': ?code,
      };
    }
    final data = body is Map<String, dynamic> ? body['data'] : null;
    return {
      'success': true,
      if (data is Map<String, dynamic>) ...data,
    };
  }

  /// Whether the caller's one-time verification fee is settled.
  ///
  /// Returns the fee data map: `{paid, amount}` plus `orderId`/`paidAt`
  /// when already paid. The screen polls this while a USSD push is open.
  Future<Map<String, dynamic>> fetchFeeStatus() async {
    final uri = Uri.parse(ApiConfig.v1('/kyc/fee/status'));
    final res = await _http
        .get(uri, headers: await _authHeaders())
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw _errorFor(res.statusCode, action: 'KYC fee status');
    }
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    final data = body is Map<String, dynamic> ? body['data'] : null;
    return data is Map<String, dynamic> ? data : {'paid': false};
  }

  /// Starts a ClickPesa collection for the one-time verification fee.
  ///
  /// `paymentMethod` is 'ussd_push' or 'billpay'. Success flattens the
  /// server data under `{success: true, ...}` — `billPayNumber` for billpay,
  /// `orderId` for both. Failures return `{success: false, error, code}`
  /// like [submit]. 20s timeout because BillPay creates the control number
  /// synchronously via an external API call.
  Future<Map<String, dynamic>> initiateFee({
    required String phone,
    String paymentMethod = 'ussd_push',
  }) async {
    final uri = Uri.parse(ApiConfig.v1('/kyc/fee/initiate'));
    final res = await _http
        .post(
          uri,
          headers: await _authHeaders(),
          body: jsonEncode({'phone': phone, 'paymentMethod': paymentMethod}),
        )
        .timeout(const Duration(seconds: 20));
    final body = jsonDecode(utf8.decode(res.bodyBytes));

    if (res.statusCode != 200) {
      final err = body is Map<String, dynamic> ? body['error'] : null;
      final code = err is Map<String, dynamic>
          ? err['code']?.toString()
          : null;
      final msg = err is Map<String, dynamic>
          ? (err['message']?.toString() ?? 'Fee initiation failed')
          : 'Fee initiation failed';
      return {
        'success': false,
        'error': msg,
        'code': ?code,
      };
    }

    final data = body is Map<String, dynamic> ? body['data'] : null;
    return {
      'success': true,
      if (data is Map<String, dynamic>) ...data,
    };
  }
}