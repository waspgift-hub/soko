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

class LaunchApi {
  LaunchApi({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  Future<LaunchSubscribeResult> subscribe({
    required String email,
    String? name,
    required String lang,
    required int formStartedAt,
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
              'lang': lang,
              'source': 'web_launch',
              'formStartedAt': formStartedAt,
              'website': '',
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
      final message = (data['message'] ?? body['message'] ?? body['error'] ?? '').toString();
      final duplicate = data['status'] == 'duplicate';
      if (response.statusCode >= 200 && response.statusCode < 300 && body['success'] == true) {
        return LaunchSubscribeResult(ok: true, duplicate: duplicate, message: message);
      }
      if (response.statusCode == 429) {
        return const LaunchSubscribeResult(ok: false, duplicate: false, message: 'Too many requests. Please try again later.');
      }
      if (response.statusCode == 400) {
        return LaunchSubscribeResult(ok: false, duplicate: false, message: message.isNotEmpty ? message : 'Please enter a valid email address.');
      }
      return LaunchSubscribeResult(ok: false, duplicate: false, message: message.isNotEmpty ? message : 'Something went wrong. Please try again.');
    } catch (_) {
      return const LaunchSubscribeResult(ok: false, duplicate: false, message: 'Unable to connect right now. Please try again.');
    }
  }
}
