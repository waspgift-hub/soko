import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';

const String agoraAppId = '408c0734a8d54f8cae2a17e840b96d86';
const String defaultChannel = 'soko_langu_test';

Future<String> getAgoraToken({
  required String channelName,
  int uid = 0,
  String role = 'audience',
}) async {
  try {
    final resp = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/api/agora-token'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'channelName': channelName,
        'uid': uid,
        'role': role,
      }),
    );
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body);
      return data['token'] as String;
    }
  } catch (_) {}
  return '';
}
