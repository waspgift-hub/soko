import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/music_track.dart';

/// Client for the SokoVibe Music Cloudflare Worker.
/// Never ship provider secrets in the Flutter application.
class MusicApi {
  MusicApi({String? baseUrl, http.Client? client})
      : baseUrl = (baseUrl ??
                const String.fromEnvironment(
                  'MUSIC_API_URL',
                  defaultValue:
                      'https://soko-vibe-music-backend.sokovibe-co-tz.workers.dev',
                ))
            .replaceAll(RegExp(r'/+$'), ''),
        _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;
  static const _timeout = Duration(seconds: 12);

  Future<List<MusicTrack>> search(String query) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return <MusicTrack>[];
    final uri = Uri.parse('$baseUrl/search')
        .replace(queryParameters: <String, String>{'q': normalized});
    final response = await _get(uri);
    final decoded = _decodeObject(response.body);
    if (response.statusCode != 200) {
      throw MusicApiException(_errorMessage(decoded, 'Music search failed (' +
          response.statusCode.toString() + ').'));
    }
    final rawResults = decoded['results'];
    if (rawResults is! List) {
      throw const MusicApiException('The music service returned an invalid response.');
    }
    return rawResults
        .whereType<Map>()
        .map((item) => MusicTrack.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }

  Future<String> playUrl(String id) async {
    final normalizedId = id.trim();
    if (normalizedId.isEmpty ||
        !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(normalizedId)) {
      throw const MusicApiException('Invalid track ID.');
    }
    final response = await _get(Uri.parse('$baseUrl/play/$normalizedId'));
    final decoded = _decodeObject(response.body);
    if (response.statusCode != 200) {
      throw MusicApiException(_errorMessage(decoded, 'Unable to play this track (' +
          response.statusCode.toString() + ').'));
    }
    final parsed = Uri.tryParse(decoded['streaming_url']?.toString() ?? '');
    if (parsed == null || parsed.scheme != 'https' || parsed.host.isEmpty) {
      throw const MusicApiException('No valid playable audio source was returned.');
    }
    return parsed.toString();
  }

  Future<http.Response> _get(Uri uri) async {
    try {
      return await _client.get(uri, headers: const <String, String>{
        'accept': 'application/json',
      }).timeout(_timeout);
    } on TimeoutException {
      throw const MusicApiException('The music service took too long. Please retry.');
    } on http.ClientException {
      throw const MusicApiException('Cannot connect to the music service. Check your internet.');
    }
  }

  Map<String, dynamic> _decodeObject(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      throw const MusicApiException('The music service returned an invalid response.');
    } on FormatException {
      throw const MusicApiException('The music service returned an invalid response.');
    }
  }

  String _errorMessage(Map<String, dynamic> decoded, String fallback) {
    final message = decoded['message']?.toString().trim();
    return message == null || message.isEmpty ? fallback : message;
  }

  void close() => _client.close();
}

class MusicApiException implements Exception {
  const MusicApiException(this.message);
  final String message;
  @override
  String toString() => message;
}