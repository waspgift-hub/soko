import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/music_track.dart';

class MusicApi {
  MusicApi({String? baseUrl})
      : baseUrl = (baseUrl ??
                const String.fromEnvironment(
                  'MUSIC_API_URL',
                  defaultValue:
                      'https://soko-vibe-music-backend.sokovibe-co-tz.workers.dev',
                ))
            .replaceAll(RegExp(r'/+$'), '');

  final String baseUrl;

  Future<List<MusicTrack>> search(String query) async {
    final term = query.trim();
    if (term.isEmpty) return const [];
    final uri = Uri.parse('$baseUrl/search')
        .replace(queryParameters: {'q': term});
    final response = await http.get(uri, headers: const {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw MusicApiException('Music search failed (HTTP ${response.statusCode}).');
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw const MusicApiException('Music service returned invalid JSON.');
    }

    final List<dynamic> results;
    if (decoded is List) {
      results = decoded;
    } else if (decoded is Map<String, dynamic>) {
      final candidate = decoded['results'] ?? decoded['tracks'] ?? decoded['data'];
      if (candidate is! List) {
        throw MusicApiException(
          (decoded['error'] ?? decoded['message'] ?? 'Music service returned no track list.').toString(),
        );
      }
      results = candidate;
    } else {
      throw const MusicApiException('Unexpected music search response.');
    }

    return results
        .whereType<Map>()
        .map((item) => MusicTrack.fromJson(Map<String, dynamic>.from(item)))
        .where((track) => track.id.isNotEmpty && track.title.isNotEmpty)
        .toList(growable: false);
  }

  Future<String> playUrl(String id, {String? streamUrl}) async {
    final direct = streamUrl?.trim();
    if (direct != null && direct.isNotEmpty) {
      final parsed = Uri.tryParse(direct);
      if (parsed != null &&
          (parsed.scheme == 'https' || parsed.scheme == 'http') &&
          parsed.host.isNotEmpty) return direct;
    }
    final uri = Uri.parse('$baseUrl/play/$id');
    final response = await http.get(uri, headers: const {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw MusicApiException('This track has no playable stream (HTTP ${response.statusCode}).');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      final value = decoded['streaming_url'] ?? decoded['audio'] ?? decoded['url'];
      final stream = value?.toString();
      final parsed = stream == null ? null : Uri.tryParse(stream);
      if (parsed != null &&
          (parsed.scheme == 'https' || parsed.scheme == 'http') &&
          parsed.host.isNotEmpty) return stream!;
    }
    throw const MusicApiException('No playable stream was provided.');
  }
}

class MusicApiException implements Exception {
  const MusicApiException(this.message);
  final String message;
  @override
  String toString() => message;
}
