import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/models.dart';

class LaunchSubscribeResult {
  final bool ok;
  final bool duplicate;
  final String message;

  const LaunchSubscribeResult({
    required this.ok,
    required this.duplicate,
    required this.message,
  });
}

class LaunchContactResult {
  final bool ok;
  final String message;
  const LaunchContactResult({required this.ok, required this.message});
}

class LaunchApi {
  LaunchApi({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  Future<LaunchSubscribeResult> subscribe({
    required String email,
    String? name,
    String userType = 'both',
    required bool consent,
    required String lang,
    required int formStartedAt,
    required String turnstileToken,
    String source = 'web_launch',
  }) async {
    final uri = Uri.parse('${SokoLinks.apiBase}/api/v1/launch/subscribe');
    try {
      final response = await _client
          .post(
            uri,
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'email': email.trim(),
              'name': (name ?? '').trim(),
              'userType': userType,
              'consent': consent,
              'lang': lang,
              'source': source,
              'formStartedAt': formStartedAt,
              'website': '',
              'cf-turnstile-response': turnstileToken,
            }),
          )
          .timeout(const Duration(seconds: 15));

      Map<String, dynamic> body = {};
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) body = decoded;
      } catch (_) {}

      final data = body['data'] is Map<String, dynamic>
          ? body['data'] as Map<String, dynamic>
          : <String, dynamic>{};
      final message =
          (data['message'] ?? body['message'] ?? body['error'] ?? '')
              .toString();
      final duplicate = data['status'] == 'duplicate';
      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          body['success'] == true) {
        return LaunchSubscribeResult(
          ok: true,
          duplicate: duplicate,
          message: message,
        );
      }
      if (response.statusCode == 429) {
        return const LaunchSubscribeResult(
          ok: false,
          duplicate: false,
          message: 'RATE_LIMITED',
        );
      }
      if (response.statusCode == 400 || response.statusCode == 403 || response.statusCode == 503) {
        return LaunchSubscribeResult(
          ok: false,
          duplicate: false,
          message: message.isNotEmpty ? message : 'INVALID_INPUT',
        );
      }
      return LaunchSubscribeResult(
        ok: false,
        duplicate: false,
        message: message.isNotEmpty ? message : 'SERVER_ERROR',
      );
    } catch (_) {
      return const LaunchSubscribeResult(
        ok: false,
        duplicate: false,
        message: 'NETWORK_ERROR',
      );
    }
  }

  Future<LaunchContactResult> contact({
    required String email,
    required String subject,
    required String message,
    String? name,
    required String lang,
    required int formStartedAt,
    required String turnstileToken,
  }) async {
    final uri = Uri.parse('${SokoLinks.apiBase}/api/v1/contact');
    try {
      final response = await _client
          .post(
            uri,
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'email': email.trim(),
              'name': (name ?? '').trim(),
              'subject': subject.trim(),
              'message': message.trim(),
              'lang': lang,
              'formStartedAt': formStartedAt,
              'website': '',
              'cf-turnstile-response': turnstileToken,
            }),
          )
          .timeout(const Duration(seconds: 15));
      Map<String, dynamic> body = {};
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) body = decoded;
      } catch (_) {}
      final data = body['data'] is Map<String, dynamic>
          ? body['data'] as Map<String, dynamic>
          : <String, dynamic>{};
      final msg = (data['message'] ?? body['message'] ?? body['error'] ?? '')
          .toString();
      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          body['success'] == true) {
        return LaunchContactResult(ok: true, message: msg);
      }
      if (response.statusCode == 429) {
        return const LaunchContactResult(ok: false, message: 'RATE_LIMITED');
      }
      if (response.statusCode == 403 || response.statusCode == 503) {
        return LaunchContactResult(
          ok: false,
          message: msg.isNotEmpty ? msg : 'TURNSTILE_FAILED',
        );
      }
      return LaunchContactResult(
        ok: false,
        message: msg.isNotEmpty ? msg : 'SERVER_ERROR',
      );
    } catch (_) {
      return const LaunchContactResult(ok: false, message: 'NETWORK_ERROR');
    }
  }
}
