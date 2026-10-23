import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/music_track.dart';

/// Flutter client for the SokoVibe Music v2 Cloudflare Worker.
/// Provider credentials must remain server-side.
class MusicApi {
  MusicApi({String? baseUrl, http.Client? client})
      : baseUrl = (baseUrl ??
                const String.fromEnvironment(
                  'MUSIC_API_URL',
                  defaultValue:
                      'https://soko-vibe-music-backend.wapalila.workers.dev',
                ))
            .replaceAll(RegExp(r'/+$'), ''),
        _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;
  static const _timeout = Duration(seconds: 15);

  Future<Map<String, dynamic>> checkHealth() async {
    final response = await _get(Uri.parse('$baseUrl/api/health'));
    final decoded = _decodeObject(response.body);
    _throwIfFailed(response, decoded, 'Health check failed');
    return decoded;
  }

  Future<List<MusicTrack>> search(
    String query, {
    int page = 1,
    int limit = 20,
  }) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return <MusicTrack>[];
    if (normalized.length > 200 || page < 1 || limit < 1 || limit > 50) {
      throw const MusicApiException(
        'Search query or pagination values are invalid.',
        category: 'VALIDATION_ERROR',
      );
    }
    final uri = Uri.parse('$baseUrl/search').replace(queryParameters: {
      'q': normalized,
      'page': '$page',
      'limit': '$limit',
    });
    final decoded = await _getJson(uri, 'Music search failed');
    return _tracksFrom(decoded, const ['results', 'tracks', 'data']);
  }

  Future<List<MusicTrack>> searchPost(
    String query, {
    int page = 1,
    int limit = 20,
  }) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return <MusicTrack>[];
    if (normalized.length > 200 || page < 1 || limit < 1 || limit > 50) {
      throw const MusicApiException(
        'Search query or pagination values are invalid.',
        category: 'VALIDATION_ERROR',
      );
    }
    final decoded = await _postJson('/api/search', {
      'query': normalized,
      'page': page,
      'limit': limit,
    });
    return _tracksFrom(decoded, const ['results', 'tracks', 'data']);
  }

  Future<MusicTrack> getTrack(String id) async {
    final normalized = id.trim();
    if (!RegExp(r'^\d+$').hasMatch(normalized)) {
      throw const MusicApiException(
        'Invalid track ID.',
        category: 'VALIDATION_ERROR',
      );
    }
    final decoded = await _getJson(
      Uri.parse('$baseUrl/play/$normalized'),
      'Unable to load track',
    );
    final rawTrack = decoded['track'];
    final track = MusicTrack.fromJson(
      rawTrack is Map
          ? Map<String, dynamic>.from(rawTrack)
          : decoded,
    );
    if (track.id.isEmpty) {
      throw const MusicApiException(
        'The music service returned track metadata without an ID.',
        category: 'INVALID_RESPONSE',
      );
    }
    return track;
  }

  Future<String> playUrl(String id, {String? streamUrl}) async {
    // Search results already contain the provider stream URL. Reuse it when
    // valid to avoid a second backend request before playback starts.
    final direct = streamUrl?.trim();
    final directUri = direct == null ? null : Uri.tryParse(direct);
    if (directUri != null &&
        directUri.scheme == 'https' &&
        directUri.host.isNotEmpty) {
      return directUri.toString();
    }

    final track = await getTrack(id);
    if (!track.canStream || track.streamUrl == null) {
      throw const MusicApiException(
        'No valid playable HTTPS audio source was returned.',
        category: 'NO_STREAM',
      );
    }
    return track.streamUrl!;
  }

  /// The v2 Worker does not document a /download/:id route. Resolve the
  /// track metadata and use Jamendo's audiodownload URL only when its explicit
  /// audiodownload_allowed flag is true. Never treat a stream URL as a download.
  Future<String> downloadUrl(String id) async {
    final track = await getTrack(id);
    if (!track.canDownload || track.downloadUrl == null) {
      throw const MusicApiException(
        'This track is not marked as downloadable by its provider.',
        category: 'DOWNLOAD_NOT_ALLOWED',
      );
    }
    return track.downloadUrl!;
  }

  Future<List<MusicTrack>> recommend({
    String mood = '',
    String genre = 'afrobeat',
    String language = '',
    int limit = 10,
  }) async {
    if (limit < 1 || limit > 50) {
      throw const MusicApiException(
        'Limit must be between 1 and 50.',
        category: 'VALIDATION_ERROR',
      );
    }
    final decoded = await _postJson('/api/recommend', {
      'mood': mood,
      'genre': genre,
      'language': language,
      'limit': limit,
    });
    return _tracksFrom(
      decoded,
      const ['recommendations', 'results', 'tracks', 'data'],
    );
  }

  Future<String> generateLyrics({
    required String theme,
    String genre = 'afrobeat',
    String language = 'Swahili',
  }) async {
    if (theme.trim().isEmpty) {
      throw const MusicApiException(
        'Enter a theme for the lyrics.',
        category: 'VALIDATION_ERROR',
      );
    }
    final decoded = await _postJson('/api/lyrics', {
      'theme': theme.trim(),
      'genre': genre,
      'language': language,
    });
    final lyrics = (decoded['lyrics'] ?? decoded['text'])?.toString().trim() ?? '';
    if (lyrics.isEmpty) {
      throw const MusicApiException(
        'Lyrics response was empty.',
        category: 'INVALID_RESPONSE',
      );
    }
    return lyrics;
  }

  Future<Map<String, dynamic>> _getJson(Uri uri, String fallback) async {
    final response = await _get(uri);
    final decoded = _decodeObject(response.body);
    _throwIfFailed(response, decoded, fallback);
    return decoded;
  }

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('$baseUrl$path'),
            headers: const {
              'accept': 'application/json',
              'content-type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const MusicApiException(
        'The music service timed out. Please retry.',
        category: 'PROVIDER_TIMEOUT',
      );
    } on http.ClientException {
      throw const MusicApiException(
        'Cannot connect to the music service. Check your internet.',
        category: 'NETWORK_ERROR',
      );
    }
    final decoded = _decodeObject(response.body);
    _throwIfFailed(response, decoded, 'Music request failed');
    return decoded;
  }

  Future<http.Response> _get(Uri uri) async {
    try {
      return await _client
          .get(uri, headers: const {'accept': 'application/json'})
          .timeout(_timeout);
    } on TimeoutException {
      throw const MusicApiException(
        'The music service timed out. Please retry.',
        category: 'PROVIDER_TIMEOUT',
      );
    } on http.ClientException {
      throw const MusicApiException(
        'Cannot connect to the music service. Check your internet.',
        category: 'NETWORK_ERROR',
      );
    }
  }

  List<MusicTrack> _tracksFrom(
    Map<String, dynamic> decoded,
    List<String> possibleKeys,
  ) {
    dynamic raw;
    for (final key in possibleKeys) {
      if (decoded[key] is List) {
        raw = decoded[key];
        break;
      }
    }
    // Some Workers wrap arrays in { data: { results: [...] } }.
    if (raw == null && decoded['data'] is Map) {
      final nested = Map<String, dynamic>.from(decoded['data'] as Map);
      for (final key in possibleKeys) {
        if (nested[key] is List) {
          raw = nested[key];
          break;
        }
      }
    }
    if (raw is! List) {
      throw const MusicApiException(
        'The music service response did not contain a track list.',
        category: 'INVALID_RESPONSE',
      );
    }
    return raw
        .whereType<Map>()
        .map((item) => MusicTrack.fromJson(Map<String, dynamic>.from(item)))
        .where((track) => track.id.isNotEmpty)
        .toList(growable: false);
  }

  void _throwIfFailed(
    http.Response response,
    Map<String, dynamic> decoded,
    String fallback,
  ) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw MusicApiException(
        _errorMessage(decoded, '$fallback (HTTP ${response.statusCode})'),
        category: (decoded['error_category'] ??
                decoded['errorCode'] ??
                decoded['code'] ??
                'REQUEST_FAILED')
            .toString(),
        statusCode: response.statusCode,
      );
    }
    if (decoded['success'] == false || decoded['ok'] == false) {
      throw MusicApiException(
        _errorMessage(decoded, fallback),
        category: (decoded['error_category'] ??
                decoded['errorCode'] ??
                decoded['code'] ??
                'REQUEST_FAILED')
            .toString(),
        statusCode: response.statusCode,
      );
    }
  }

  Map<String, dynamic> _decodeObject(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      throw const MusicApiException(
        'The music service returned an invalid response.',
        category: 'INVALID_RESPONSE',
      );
    } on FormatException {
      throw const MusicApiException(
        'The music service returned an invalid response.',
        category: 'INVALID_RESPONSE',
      );
    }
  }

  String _errorMessage(Map<String, dynamic> decoded, String fallback) {
    final value =
        (decoded['message'] ?? decoded['error_description'] ?? decoded['error'])
            ?.toString()
            .trim();
    final category =
        (decoded['error_category'] ?? decoded['errorCode'] ?? decoded['code'])
            ?.toString()
            .trim();
    if (value == null || value.isEmpty) {
      return category == null || category.isEmpty
          ? fallback
          : '$fallback [$category]';
    }
    if (category == null || category.isEmpty || value.contains(category)) {
      return value;
    }
    return '$value [$category]';
  }

  void close() => _client.close();
}

class MusicApiException implements Exception {
  const MusicApiException(
    this.message, {
    this.category = 'MUSIC_API_ERROR',
    this.statusCode,
  });

  final String message;
  final String category;
  final int? statusCode;

  @override
  String toString() => message;
}
