import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

import '../api_config.dart';
import '../../models/ai_chat_models.dart';
import '../../utils/network_error.dart';
import 'agent_models.dart';

class AgentService {
  AgentService({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;

  Future<String> _token() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw NetworkError(message: 'Not authenticated', userMessage: 'Please log in to continue.');
    }
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw NetworkError(message: 'Not authenticated', userMessage: 'Please log in to continue.');
    }
    return token;
  }

  Future<Map<String, String>> _headers() async {
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Authorization': 'Bearer ${await _token()}',
    };
  }

  Future<List<AgentToolDefinition>> getTools() async {
    final res = await _http
        .get(Uri.parse('${ApiConfig.baseUrl}/api/agent/tools'), headers: await _headers())
        .timeout(const Duration(seconds: 15));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw NetworkError(message: 'Failed to load tools: ${res.statusCode}',
          userMessage: translateHttpStatus(res.statusCode));
    }
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    final data = body['data'] as List? ?? [];
    return data.map((e) => AgentToolDefinition.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<AgentPermission>> listPermissions() async {
    final res = await _http
        .get(Uri.parse('${ApiConfig.baseUrl}/api/agent/permissions'), headers: await _headers())
        .timeout(const Duration(seconds: 15));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw NetworkError(message: 'Failed to load permissions: ${res.statusCode}',
          userMessage: translateHttpStatus(res.statusCode));
    }
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    final data = body['data'] as List? ?? [];
    return data.map((e) => AgentPermission.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<AgentPermission> grantPermission({
    required String scope,
    int? ttlMs,
    String? reason,
  }) async {
    final body = <String, dynamic>{'scope': scope};
    if (ttlMs != null) body['ttlMs'] = ttlMs;
    if (reason != null) body['reason'] = reason;
    final res = await _http
        .post(
          Uri.parse('${ApiConfig.baseUrl}/api/agent/permissions/grant'),
          headers: await _headers(),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw NetworkError(message: 'Failed to grant permission: ${res.statusCode}',
          userMessage: translateHttpStatus(res.statusCode));
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    return AgentPermission.fromJson(decoded['data'] as Map<String, dynamic>);
  }

  Future<void> revokePermission({String? scope, String? permissionId}) async {
    final res = await _http
        .delete(
          Uri.parse('${ApiConfig.baseUrl}/api/agent/permissions/revoke'),
          headers: await _headers(),
          body: jsonEncode({'scope': scope, 'permissionId': permissionId}),
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw NetworkError(message: 'Failed to revoke permission: ${res.statusCode}',
          userMessage: translateHttpStatus(res.statusCode));
    }
  }

  Future<List<AgentPendingAction>> listActions({String? status}) async {
    final params = <String, String>{};
    if (status != null && status.isNotEmpty) params['status'] = status;
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/agent/actions').replace(queryParameters: params);
    final res = await _http.get(uri, headers: await _headers()).timeout(const Duration(seconds: 15));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw NetworkError(message: 'Failed to load actions: ${res.statusCode}',
          userMessage: translateHttpStatus(res.statusCode));
    }
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    final data = body['data'] as List? ?? [];
    return data.map((e) => AgentPendingAction.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<AgentPendingAction> approveAction(String actionId) async {
    final res = await _http
        .post(
          Uri.parse('${ApiConfig.baseUrl}/api/agent/actions/$actionId/approve'),
          headers: await _headers(),
          body: jsonEncode({}),
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw NetworkError(message: 'Failed to approve action: ${res.statusCode}',
          userMessage: translateHttpStatus(res.statusCode));
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    return AgentPendingAction.fromJson(decoded['data'] as Map<String, dynamic>);
  }

  Future<AgentPendingAction> denyAction(String actionId, {String? reason}) async {
    final res = await _http
        .post(
          Uri.parse('${ApiConfig.baseUrl}/api/agent/actions/$actionId/deny'),
          headers: await _headers(),
          body: jsonEncode({'reason': reason ?? 'User denied'}),
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw NetworkError(message: 'Failed to deny action: ${res.statusCode}',
          userMessage: translateHttpStatus(res.statusCode));
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    return AgentPendingAction.fromJson(decoded['data'] as Map<String, dynamic>);
  }

  Future<AgentPendingAction> cancelAction(String actionId) async {
    final res = await _http
        .post(
          Uri.parse('${ApiConfig.baseUrl}/api/agent/actions/$actionId/cancel'),
          headers: await _headers(),
          body: jsonEncode({}),
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw NetworkError(message: 'Failed to cancel action: ${res.statusCode}',
          userMessage: translateHttpStatus(res.statusCode));
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    return AgentPendingAction.fromJson(decoded['data'] as Map<String, dynamic>);
  }

  Future<AgentPendingAction> executeAction(String actionId, {String? idempotencyKey}) async {
    final res = await _http
        .post(
          Uri.parse('${ApiConfig.baseUrl}/api/agent/actions/$actionId/execute'),
          headers: await _headers(),
          body: jsonEncode({'idempotencyKey': idempotencyKey ?? 'exec_$actionId'}),
        )
        .timeout(const Duration(seconds: 60));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw NetworkError(message: 'Failed to execute action: ${res.statusCode}',
          userMessage: translateHttpStatus(res.statusCode));
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    return AgentPendingAction.fromJson(decoded['data'] as Map<String, dynamic>);
  }

  Stream<AgentStreamEvent> sendTurnStream({
    required String conversationId,
    required String text,
    List<AiMessage>? messages,
    String? productContext,
    String? catalogStatus,
    String locale = 'sw',
    String model = 'openai/gpt-oss-120b',
  }) async* {
    final token = await _token();
    final request = http.Request('POST', Uri.parse('${ApiConfig.baseUrl}/api/agent/chat'));
    request.headers.addAll({
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
      'Accept': 'text/event-stream',
    });
    request.body = jsonEncode({
      'text': text,
      'messages': messages
          ?.map((m) => {'role': m.role, 'content': m.content})
          .toList(),
      'productContext': productContext,
      'catalogStatus': catalogStatus,
      'locale': locale,
      'model': model,
    });

    final streamed = await _http.send(request).timeout(const Duration(seconds: 30));
    if (streamed.statusCode != 200) {
      throw NetworkError(
        message: 'Send failed: ${streamed.statusCode}',
        userMessage: translateHttpStatus(streamed.statusCode),
      );
    }

    final buffer = StringBuffer();
    await for (final chunk in streamed.stream.transform(utf8.decoder)) {
      buffer.write(chunk);
      while (true) {
        final textStr = buffer.toString();
        final idx = textStr.indexOf('\n\n');
        if (idx < 0) break;
        final event = textStr.substring(0, idx);
        buffer.clear();
        buffer.write(textStr.substring(idx + 2));
        final parsed = _parseSseEvent(event);
        if (parsed != null) yield AgentStreamEvent.fromJson(parsed);
      }
    }
  }

  Map<String, dynamic>? _parseSseEvent(String raw) {
    String? eventName;
    final dataLines = <String>[];
    for (final line in raw.split('\n')) {
      if (line.startsWith('event:')) {
        eventName = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        dataLines.add(line.substring(5).trim());
      }
    }
    if (dataLines.isEmpty) return null;
    try {
      final data = jsonDecode(dataLines.join('\n')) as Map<String, dynamic>;
      return {'event': eventName ?? 'message', 'data': data};
    } catch (_) {
      return null;
    }
  }
}
