import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/music_track.dart';

/// Client for the SokoVibe Music Cloudflare Worker. Never ship provider secrets in Flutter.
class MusicApi {
  MusicApi({String? baseUrl, http.Client? client})
      : baseUrl = (baseUrl ?? const String.fromEnvironment('MUSIC_API_URL',
          defaultValue: 'https://soko-vibe-music-backend.sokovibe-co-tz.workers.dev'))
          .replaceAll(RegExp(r'/+$'), ''),
        _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;
  static const _timeout = Duration(seconds: 15);

  Future<Map<String, dynamic>> checkHealth() async {
    final response = await _get(Uri.parse('$baseUrl/api/health'));
    final decoded = _decodeObject(response.body);
    if (response.statusCode != 200) {
      throw MusicApiException(_errorMessage(decoded, 'Health check failed (${response.statusCode}).'),
          category: decoded['error']?.toString() ?? 'HEALTH_CHECK_FAILED',
          statusCode: response.statusCode);
    }
    return decoded;
  }

  Future<List<MusicTrack>> search(String query, {int page = 1, int limit = 20}) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return <MusicTrack>[];
    if (normalized.length > 200 || page < 1 || limit < 1 || limit > 50) {
      throw const MusicApiException('Search query or pagination values are invalid.', category: 'VALIDATION_ERROR');
    }
    final uri = Uri.parse('$baseUrl/search').replace(queryParameters: {
      'q': normalized, 'page': '$page', 'limit': '$limit',
    });
    return _tracksFromResponse(await _get(uri), 'Music search failed');
  }

  Future<List<MusicTrack>> searchPost(String query, {int page = 1, int limit = 20}) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return <MusicTrack>[];
    final decoded = await _postJson('/api/search', {'query': normalized, 'page': page, 'limit': limit});
    final raw = decoded['results'];
    if (raw is! List) throw const MusicApiException('Invalid search response.', category: 'INVALID_RESPONSE');
    return raw.whereType<Map>().map((e) => MusicTrack.fromJson(Map<String, dynamic>.from(e))).toList(growable: false);
  }

  Future<MusicTrack> getTrack(String id) async {
    final normalized = id.trim();
    if (!RegExp(r'^\d+$').hasMatch(normalized)) {
      throw const MusicApiException('Invalid track ID.', category: 'VALIDATION_ERROR');
    }
    final response = await _get(Uri.parse('$baseUrl/play/$normalized'));
    final decoded = _decodeObject(response.body);
    if (response.statusCode != 200) {
      throw MusicApiException(_errorMessage(decoded, 'Unable to load track (${response.statusCode}).'),
          category: decoded['error']?.toString() ?? 'TRACK_REQUEST_FAILED', statusCode: response.statusCode);
    }
    final track = decoded['track'];
    return MusicTrack.fromJson(track is Map ? Map<String, dynamic>.from(track) : decoded);
  }

  Future<String> playUrl(String id) async {
    final track = await getTrack(id);
    if (!track.canStream || track.streamUrl == null) {
      throw const MusicApiException('No valid playable HTTPS audio source was returned.', category: 'NO_STREAM');
    }
    return track.streamUrl!;
  }

  Future<List<MusicTrack>> recommend({String mood = '', String genre = 'afrobeat', String language = '', int limit = 10}) async {
    if (limit < 1 || limit > 50) throw const MusicApiException('Limit must be between 1 and 50.', category: 'VALIDATION_ERROR');
    final decoded = await _postJson('/api/recommend', {'mood': mood, 'genre': genre, 'language': language, 'limit': limit});
    final raw = decoded['recommendations'];
    if (raw is! List) throw const MusicApiException('Invalid recommendations response.', category: 'INVALID_RESPONSE');
    return raw.whereType<Map>().map((e) => MusicTrack.fromJson(Map<String, dynamic>.from(e))).toList(growable: false);
  }

  Future<String> generateLyrics({required String theme, String genre = 'afrobeat', String language = 'Swahili'}) async {
    final decoded = await _postJson('/api/lyrics', {'theme': theme, 'genre': genre, 'language': language});
    final lyrics = decoded['lyrics']?.toString().trim() ?? '';
    if (lyrics.isEmpty) throw const MusicApiException('Lyrics response was empty.', category: 'INVALID_RESPONSE');
    return lyrics;
  }

  Future<Map<String, dynamic>> _postJson(String path, Map<String, dynamic> body) async {
    http.Response response;
    try {
      response = await _client.post(Uri.parse('$baseUrl$path'),
          headers: const {'accept': 'application/json', 'content-type': 'application/json'},
          body: jsonEncode(body)).timeout(_timeout);
    } on TimeoutException {
      throw const MusicApiException('The music service timed out. Please retry.', category: 'PROVIDER_TIMEOUT');
    } on http.ClientException {
      throw const MusicApiException('Cannot connect to the music service. Check your internet.', category: 'NETWORK_ERROR');
    }
    final decoded = _decodeObject(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw MusicApiException(_errorMessage(decoded, 'Music request failed (${response.statusCode}).'),
          category: decoded['error']?.toString() ?? 'REQUEST_FAILED', statusCode: response.statusCode);
    }
    return decoded;
  }

  List<MusicTrack> _tracksFromResponse(http.Response response, String fallback) {
    final decoded = _decodeObject(response.body);
    if (response.statusCode != 200) {
      throw MusicApiException(_errorMessage(decoded, '$fallback (${response.statusCode}).'),
          category: decoded['error']?.toString() ?? 'REQUEST_FAILED', statusCode: response.statusCode);
    }
    final raw = decoded['results'];
    if (raw is! List) throw const MusicApiException('Invalid music search response.', category: 'INVALID_RESPONSE');
    return raw.whereType<Map>().map((e) => MusicTrack.fromJson(Map<String, dynamic>.from(e))).toList(growable: false);
  }

  Future<http.Response> _get(Uri uri) async {
    try {
      return await _client.get(uri, headers: const {'accept': 'application/json'}).timeout(_timeout);
    } on TimeoutException {
      throw const MusicApiException('The music service timed out. Please retry.', category: 'PROVIDER_TIMEOUT');
    } on http.ClientException {
      throw const MusicApiException('Cannot connect to the music service. Check your internet.', category: 'NETWORK_ERROR');
    }
  }

  Map<String, dynamic> _decodeObject(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      throw const MusicApiException('The music service returned an invalid response.', category: 'INVALID_RESPONSE');
    } on FormatException {
      throw const MusicApiException('The music service returned an invalid response.', category: 'INVALID_RESPONSE');
    }
  }

  String _errorMessage(Map<String, dynamic> decoded, String fallback) {
    final value = decoded['message']?.toString().trim();
    return value == null || value.isEmpty ? fallback : value;
  }

  void close() => _client.close();
}

class MusicApiException implements Exception {
  const MusicApiException(this.message, {this.category = 'MUSIC_API_ERROR', this.statusCode});
  final String message;
  final String category;
  final int? statusCode;
  @override
  String toString() => message;
}
