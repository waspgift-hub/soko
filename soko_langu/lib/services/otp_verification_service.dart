/// Centralized OTP verification service.
///
/// Wraps all existing backend OTP operations so the universal
/// [OtpVerificationScreen] does not duplicate send/verify logic per flow.
///
/// The service is intentionally thin: it only calls the existing backend
/// endpoints (`/auth/send-otp`, `/auth/verify-otp`, `/auth/send-email-otp`,
/// `/auth/verify-email-otp`) and translates network/transport failures into
/// [OtpVerificationResult] objects. It never invents a successful
/// verification and never caches a verified state locally.
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/otp_verification_models.dart';
import '../services/api_config.dart';
import '../utils/network_error.dart';

/// Shared OTP send/verify service. Instantiate once and provide via the
/// widget tree or inject into the controller.
class OtpVerificationService {
  OtpVerificationService({
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final http.Client _http;

  static const Duration _sendTimeout = Duration(seconds: 30);
  static const Duration _verifyTimeout = Duration(seconds: 30);

  /// Send an OTP to [destination] over [channel]. Returns a result whose
  /// [success] is true only when the backend accepted the send request.
  Future<OtpVerificationResult> sendOtp({
    required String destination,
    required OtpChannel channel,
    String langCode = 'sw',
  }) async {
    final isPhone = channel == OtpChannel.phone;
    final url = isPhone
        ? ApiConfig.v1('/auth/send-otp')
        : ApiConfig.v1('/auth/send-email-otp');

    try {
      final body = <String, dynamic>{
        if (isPhone) 'phone': destination,
        if (!isPhone) 'email': destination.trim().toLowerCase(),
        'langCode': langCode,
      };

      final res = await _http
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_sendTimeout);

      if (res.statusCode == 200) {
        return const OtpVerificationResult.success();
      }

      final decoded = _safeJsonDecode(res.body);
      return OtpVerificationResult.failure(
        errorCode: decoded?['error'] ?? 'auth_otp_send_failed',
        userMessage: _errorMessageForCode(
          decoded?['error'] ?? 'auth_otp_send_failed',
        ),
      );
    } on NetworkError catch (e) {
      return OtpVerificationResult.failure(
        errorCode: 'auth_otp_send_failed',
        userMessage: e.userMessage ?? _errorMessageForCode('auth_otp_send_failed'),
      );
    } catch (e) {
      return OtpVerificationResult.failure(
        errorCode: 'auth_otp_send_failed',
        userMessage: _errorMessageForCode('auth_otp_send_failed'),
      );
    }
  }

  /// Verify an OTP against the backend. Returns [success]: true only when the
  /// backend confirms the code is valid, single-use, unexpired, and within
  /// attempt limits.
  Future<OtpVerificationResult> verifyOtp({
    required String destination,
    required String otp,
    required OtpChannel channel,
  }) async {
    final isPhone = channel == OtpChannel.phone;
    final url = isPhone
        ? ApiConfig.v1('/auth/verify-otp')
        : ApiConfig.v1('/auth/verify-email-otp');

    try {
      final body = <String, dynamic>{
        if (isPhone) 'phone': destination,
        if (!isPhone) 'email': destination.trim().toLowerCase(),
        'otp': otp,
        'code': otp,
      };

      final res = await _http
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_verifyTimeout);

      if (res.statusCode == 200) {
        final decoded = _safeJsonDecode(res.body);
        if (decoded?['valid'] == true || decoded?['success'] == true) {
          return const OtpVerificationResult.success();
        }
        return OtpVerificationResult.failure(
          errorCode: decoded?['error'] ?? 'auth_otp_invalid',
          userMessage: _errorMessageForCode(
            decoded?['error'] ?? 'auth_otp_invalid',
          ),
        );
      }

      final decoded = _safeJsonDecode(res.body);
      return OtpVerificationResult.failure(
        errorCode: decoded?['error'] ?? 'auth_otp_invalid',
        userMessage: _errorMessageForCode(decoded?['error'] ?? 'auth_otp_invalid'),
      );
    } on NetworkError catch (e) {
      return OtpVerificationResult.failure(
        errorCode: 'auth_otp_invalid',
        userMessage: e.userMessage ?? _errorMessageForCode('auth_otp_invalid'),
      );
    } catch (e) {
      return OtpVerificationResult.failure(
        errorCode: 'auth_otp_invalid',
        userMessage: _errorMessageForCode('auth_otp_invalid'),
      );
    }
  }

  dynamic _safeJsonDecode(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  String _errorMessageForCode(String code) {
    switch (code) {
      case 'auth_otp_invalid':
        return 'OTP si sahihi. Angalia na jaribu tena.';
      case 'auth_otp_expired':
        return 'OTP imeisha muda. Tuma msimbo mpya.';
      case 'auth_otp_rate_limited':
        return 'Umejaribu mara nyingi sana. Subiri kidogo na jaribu tena.';
      case 'auth_otp_send_failed':
        return 'Imeshindwa kutuma OTP. Jaribu tena.';
      case 'auth_otp_cooldown':
        return 'Subiri kidogo kabla ya kuomba msimbo mwingine.';
      default:
        return 'Hitilafu yalimia. Jaribu tena.';
    }
  }
}
