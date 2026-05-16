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
  // Serverless mode: Return empty string to use App ID directly
  return '';
}
