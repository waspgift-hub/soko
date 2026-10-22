import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/music_track.dart';

class MusicApi {
  MusicApi({String? baseUrl, http.Client? client})
      : baseUrl = (baseUrl ??
                const String.fromEnvironment(
                  'MUSIC_API_URL',
                  defaultValue:
                      'https://soko-vibe-music-backend.wapalila.workers.dev',
                ))
            .replaceAll(RegExp(r'/$'), ''),
        _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  Future<List<MusicTrack>> search(String query) async {
    if (query.trim().isEmpty) return <MusicTrack>[];
    final uri = Uri.parse('$baseUrl/search')
        .replace(queryParameters: {'q': query.trim()});
    final response =
        await _client.get(uri).timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw Exception('Music API error: HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Music API returned an invalid response.');
    }
    final rawResults = decoded['results'];
    if (rawResults is! List) {
      throw const FormatException('Music API response is missing results.');
    }
    return rawResults
        .whereType<Map>()
        .map((item) => MusicTrack.fromJson(Map<String, dynamic>.from(item)))
        .where((track) => track.id.isNotEmpty)
        .toList();
  }

  /// Resolve a track through the Worker and return Jamendo's HTTPS stream URL.
  /// The Worker returns track metadata as JSON; passing /play/:id directly to
  /// just_audio would attempt to decode JSON as audio.
  Future<String> playUrl(String id) async {
    if (id.trim().isEmpty) {
      throw const FormatException('This track has no valid ID.');
    }
    final uri = Uri.parse('$baseUrl/play/${Uri.encodeComponent(id)}');
    final response =
        await _client.get(uri).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('Could not load this track (HTTP ${response.statusCode}).');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> || decoded['track'] is! Map) {
      throw const FormatException('Music API returned invalid playback data.');
    }
    final track = Map<String, dynamic>.from(decoded['track'] as Map);
    final stream = Uri.tryParse((track['streaming_url'] ?? '').toString());
    if (stream == null || stream.scheme != 'https' || stream.host.isEmpty) {
      throw const FormatException('This track has no valid audio stream.');
    }
    return stream.toString();
  }

  /// /download/:id validates Jamendo's audiodownload_allowed flag on the
  /// server, then redirects to the licensed download URL. DownloadService
  /// follows that redirect and saves the audio bytes locally.
  Future<String> downloadUrl(String id) async {
    if (id.trim().isEmpty) {
      throw const FormatException('This track has no valid ID.');
    }
    return '$baseUrl/download/${Uri.encodeComponent(id)}';
  }

  void close() => _client.close();
}
