import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../utils/network_error.dart';
import 'api_config.dart';
import 'localization_service.dart';

class MesejiService {
  /// OTP is generated + stored + verified server-side.
  /// Client just delegates: POST /api/auth/send-otp
  Future<void> sendOtp(String phone) async {
    final url = ApiConfig.v1('/auth/send-otp');
    final lang = await LocalizationService().getLanguage();
    debugPrint('MesejiService.sendOtp: POST $url phone=$phone');
    try {
      final res = await http
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'phone': phone, 'langCode': lang}),
          )
          .timeout(const Duration(seconds: 30));
      debugPrint('MesejiService.sendOtp: status ${res.statusCode}');
      if (res.statusCode != 200) {
        final body = jsonDecode(res.body);
        debugPrint('MesejiService.sendOtp: body=$body');
        throw NetworkError(
          message: 'send-otp failed: ${body['error']}',
          userMessage: body['error'] ?? 'auth_otp_send_failed',
        );
      }
    } on NetworkError {
      rethrow;
    } catch (e) {
      debugPrint('MesejiService.sendOtp error: $e');
      throw NetworkError(
        message: 'send-otp error: $e',
        userMessage: ErrorKeys.poorNetwork,
      );
    }
  }

  /// Verifies a 6-digit OTP against the server. Returns true if valid.
  Future<bool> verifyOtp(String phone, String otp) async {
    final url = ApiConfig.v1('/auth/verify-otp');
    try {
      final res = await http
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'phone': phone, 'otp': otp}),
          )
          .timeout(const Duration(seconds: 30));
      final body = jsonDecode(res.body);
      if (res.statusCode == 200 && body['valid'] == true) return true;
      throw NetworkError(
        message: 'verify-otp failed: ${body['error']}',
        userMessage: body['error'] ?? 'auth_otp_invalid',
      );
    } on NetworkError {
      rethrow;
    } catch (e) {
      throw NetworkError(
        message: 'verify-otp error: $e',
        userMessage: ErrorKeys.poorNetwork,
      );
    }
  }
}
