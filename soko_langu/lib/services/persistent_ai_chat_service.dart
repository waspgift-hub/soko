import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

import 'api_config.dart';
import '../models/ai_chat_models.dart';
import '../utils/network_error.dart';

/// Client for the persistent AI chat backend.
///
/// Replaces the in-memory history in GroqService with server-side persistence.
/// All requests are authenticated via Firebase ID token.
class PersistentAiChatService {
  PersistentAiChatService({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;

  Future<String> _token() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw NetworkError(message: 'Not authenticated', userMessage: 'Please log in to continue.');
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

  // ─── Conversations ─────────────────────────────────────────────────────

  Future<AiConversation> createConversation({String? title}) async {
    final res = await _http.post(
      Uri.parse('${ApiConfig.baseUrl}/api/ai/chats'),
      headers: await _headers(),
      body: jsonEncode({'title': title ?? ''}),
    ).timeout(const Duration(seconds: 15));
    _checkStatus(res);
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    return AiConversation.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<({List<AiConversation> items, String? nextCursor})> listConversations({
    int limit = 20,
    String? cursor,
  }) async {
    final params = <String, String>{'limit': '$limit'};
    if (cursor != null) params['cursor'] = cursor;
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/ai/chats').replace(queryParameters: params);
    final res = await _http.get(uri, headers: await _headers()).timeout(const Duration(seconds: 15));
    _checkStatus(res);
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    final data = body['data'] as Map<String, dynamic>;
    final items = (data['items'] as List? ?? [])
        .map((e) => AiConversation.fromJson(e as Map<String, dynamic>))
        .toList();
    return (items: items, nextCursor: data['nextCursor']?.toString());
  }

  Future<AiConversation> getConversation(String conversationId) async {
    final res = await _http.get(
      Uri.parse('${ApiConfig.baseUrl}/api/ai/chats/$conversationId'),
      headers: await _headers(),
    ).timeout(const Duration(seconds: 15));
    _checkStatus(res);
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    return AiConversation.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<void> deleteConversation(String conversationId) async {
    final res = await _http.delete(
      Uri.parse('${ApiConfig.baseUrl}/api/ai/chats/$conversationId'),
      headers: await _headers(),
    ).timeout(const Duration(seconds: 15));
    _checkStatus(res);
  }

  Future<void> deleteAllConversations() async {
    final res = await _http.delete(
      Uri.parse('${ApiConfig.baseUrl}/api/ai/chats'),
      headers: await _headers(),
    ).timeout(const Duration(seconds: 15));
    _checkStatus(res);
  }

  // ─── Messages ──────────────────────────────────────────────────────────

  Future<({List<AiMessage> items, String? nextCursor})> listMessages({
    required String conversationId,
    int limit = 30,
    String? before,
  }) async {
    final params = <String, String>{'limit': '$limit'};
    if (before != null) params['before'] = before;
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/ai/chats/$conversationId/messages')
        .replace(queryParameters: params);
    final res = await _http.get(uri, headers: await _headers()).timeout(const Duration(seconds: 15));
    _checkStatus(res);
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    final data = body['data'] as Map<String, dynamic>;
    final items = (data['items'] as List? ?? [])
        .map((e) => AiMessage.fromJson(e as Map<String, dynamic>))
        .toList();
    return (items: items, nextCursor: data['nextCursor']?.toString());
  }

  /// Sends a turn and yields SSE events.
  ///
  /// Events: 'start' { userMessage, assistantMessageId }, 'delta' { text },
  /// 'done' { messageId, content, provider, ... }, 'error' { code, message, partial, retryable }.
  Stream<Map<String, dynamic>> sendMessageStream({
    required String conversationId,
    required String text,
    String? clientMessageId,
    String? productContext,
    String? catalogStatus,
    String locale = 'sw',
    String model = 'openai/gpt-oss-120b',
  }) async* {
    final token = await _token();
    final request = http.Request('POST', Uri.parse('${ApiConfig.baseUrl}/api/ai/chats/$conversationId/messages'));
    request.headers['Content-Type'] = 'application/json';
    request.headers['Authorization'] = 'Bearer $token';
    request.headers['Accept'] = 'text/event-stream';
    request.body = jsonEncode({
      'text': text,
      'clientMessageId': ?clientMessageId,
      'productContext': ?productContext,
      'catalogStatus': ?catalogStatus,
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
      // Process complete SSE events.
      while (true) {
        final text = buffer.toString();
        final idx = text.indexOf('\n\n');
        if (idx < 0) break;
        final event = text.substring(0, idx);
        buffer.clear();
        buffer.write(text.substring(idx + 2));
        final parsed = _parseSseEvent(event);
        if (parsed != null) yield parsed;
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

  Future<void> deleteMessage(String messageId) async {
    final res = await _http.delete(
      Uri.parse('${ApiConfig.baseUrl}/api/ai/messages/$messageId'),
      headers: await _headers(),
    ).timeout(const Duration(seconds: 15));
    _checkStatus(res);
  }

  // ─── Memory ────────────────────────────────────────────────────────────

  Future<List<AiMemory>> listMemories() async {
    final res = await _http.get(
      Uri.parse('${ApiConfig.baseUrl}/api/ai/memory'),
      headers: await _headers(),
    ).timeout(const Duration(seconds: 15));
    _checkStatus(res);
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    final data = body['data'] as Map<String, dynamic>;
    return (data['items'] as List? ?? [])
        .map((e) => AiMemory.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> clearMemories() async {
    final res = await _http.delete(
      Uri.parse('${ApiConfig.baseUrl}/api/ai/memory'),
      headers: await _headers(),
    ).timeout(const Duration(seconds: 15));
    _checkStatus(res);
  }

  // ─── Preferences ───────────────────────────────────────────────────────

  Future<AiPreferences> getPreferences() async {
    final res = await _http.get(
      Uri.parse('${ApiConfig.baseUrl}/api/ai/preferences'),
      headers: await _headers(),
    ).timeout(const Duration(seconds: 15));
    _checkStatus(res);
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    return AiPreferences.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<AiPreferences> updatePreferences({
    bool? memoryEnabled,
    bool? chatHistoryEnabled,
    bool? voiceEnabled,
    String? preferredLanguage,
    String? responseStyle,
  }) async {
    final body = <String, dynamic>{};
    if (memoryEnabled != null) body['memoryEnabled'] = memoryEnabled;
    if (chatHistoryEnabled != null) body['chatHistoryEnabled'] = chatHistoryEnabled;
    if (voiceEnabled != null) body['voiceEnabled'] = voiceEnabled;
    if (preferredLanguage != null) body['preferredLanguage'] = preferredLanguage;
    if (responseStyle != null) body['responseStyle'] = responseStyle;
    final res = await _http.patch(
      Uri.parse('${ApiConfig.baseUrl}/api/ai/preferences'),
      headers: await _headers(),
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 15));
    _checkStatus(res);
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    return AiPreferences.fromJson(decoded['data'] as Map<String, dynamic>);
  }

  // ─── Voice ──────────────────────────────────────────────────────────────

  Future<({bool ok, String? reason, String audioUrl})> requestVoice(String messageId, {bool force = false}) async {
    final res = await _http.post(
      Uri.parse('${ApiConfig.baseUrl}/api/ai/messages/$messageId/voice'),
      headers: await _headers(),
      body: jsonEncode({'force': force}),
    ).timeout(const Duration(seconds: 20));
    _checkStatus(res);
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    final data = body['data'] as Map<String, dynamic>;
    return (
      ok: data['ok'] == true,
      reason: data['reason']?.toString(),
      audioUrl: data['audioUrl']?.toString() ?? '',
    );
  }

  String voiceUrl(String messageId) => '${ApiConfig.baseUrl}/api/ai/messages/$messageId/voice';

  void _checkStatus(http.Response res) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw NetworkError(
        message: 'Request failed: ${res.statusCode}',
        userMessage: translateHttpStatus(res.statusCode),
      );
    }
  }
}