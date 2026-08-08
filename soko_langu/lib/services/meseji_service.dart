import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/network_error.dart';
import '../utils/phone_utils.dart';
import 'api_config.dart';

class MesejiService {
  /// Shared SMS sender — proxies through our backend so the
  /// Meseji API key stays server-side.
  static Future<bool> sendSms({
    required String phone,
    required String message,
  }) async {
    final normalized = PhoneUtils.toE164(phone);
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      final res = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/sms/send'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'phone': normalized, 'message': message}),
      );
      if (kDebugMode) {
        debugPrint('MesejiService.sendSms: status ${res.statusCode}');
      }
      return res.statusCode == 200;
    } catch (e) {
      if (kDebugMode) debugPrint('MesejiService.sendSms error: $e');
      return false;
    }
  }

  /// OTP is now generated + stored + verified server-side.
  /// Client just delegates: POST /api/auth/send-otp
  Future<void> sendOtp(String phone) async {
    final url = '${ApiConfig.baseUrl}/api/auth/send-otp';
    debugPrint('MesejiService.sendOtp: POST $url phone=$phone');
    try {
      final res = await http
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'phone': phone}),
          )
          .timeout(const Duration(seconds: 30));
      debugPrint('MesejiService.sendOtp: status ${res.statusCode}');
      if (res.statusCode != 200) {
        final body = jsonDecode(res.body);
        debugPrint('MesejiService.sendOtp: body=$body');
        throw NetworkError(
          message: 'send-otp failed: ${body['error']}',
          userMessage: body['error'] ?? 'Imeshindwa kutuma OTP. Jaribu tena.',
        );
      }
    } on NetworkError {
      rethrow;
    } catch (e) {
      debugPrint('MesejiService.sendOtp error: $e');
      throw NetworkError(
        message: 'send-otp error: $e',
        userMessage: 'Mtandao dhaifu. Angalia muunganisho wako.',
      );
    }
  }
}
