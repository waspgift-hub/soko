import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_config.dart';

const String agoraAppId = '408c0734a8d54f8cae2a17e840b96d86';
const String defaultChannel = 'soko_langu_test';

Future<String> getAgoraToken({
  required String channelName,
  int uid = 0,
  String role = 'audience',
  int retries = 2,
}) async {
  for (int attempt = 0; attempt <= retries; attempt++) {
    try {
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/agora-token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'channelName': channelName,
          'uid': uid,
          'role': role,
        }),
      ).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final token = data['token'] as String?;
        if (token != null && token.isNotEmpty) return token;
      }
      debugPrint('AgoraToken attempt $attempt: status ${resp.statusCode}');
    } catch (e) {
      debugPrint('AgoraToken attempt $attempt: $e');
    }
    if (attempt < retries) {
      await Future.delayed(Duration(seconds: 1 << attempt));
    }
  }
  return '';
}
