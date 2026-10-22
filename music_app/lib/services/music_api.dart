import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/music_track.dart';

class MusicApi {
  MusicApi({String? baseUrl, http.Client? client})
      : baseUrl = (baseUrl ??
                const String.fromEnvironment(
                  'MUSIC_API_URL',
                  defaultValue:
                      'https://music-api.sokovibe-co-tz.workers.dev',
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
        await _client.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('Music API error: ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final results = decoded['results'] as List? ?? const <dynamic>[];
    return results
        .map((item) => MusicTrack.fromJson(
              Map<String, dynamic>.from(item as Map),
            ))
        .toList();
  }

  Future<Map<String, dynamic>> _fetchTrack(String id) async {
    final response = await _client
        .get(Uri.parse('$baseUrl/play/${Uri.encodeComponent(id)}'))
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('Music provider could not retrieve this track.');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return decoded['track'] is Map
        ? Map<String, dynamic>.from(decoded['track'] as Map)
        : decoded;
  }

  Future<String> playUrl(String id) async {
    final track = await _fetchTrack(id);
    final url = track['streaming_url']?.toString();
    if (url == null || url.isEmpty || Uri.tryParse(url)?.scheme != 'https') {
      throw Exception('No valid playable source returned.');
    }
    return url;
  }

  Future<String> downloadUrl(String id) async {
    final track = await _fetchTrack(id);
    final allowed = track['audiodownload_allowed'] == true ||
        track['audiodownload_allowed'] == 1;
    final url = track['audiodownload']?.toString();
    if (!allowed ||
        url == null ||
        url.isEmpty ||
        Uri.tryParse(url)?.scheme != 'https') {
      throw Exception(
        'This track is streaming-only under its current license.',
      );
    }
    return url;
  }
}
