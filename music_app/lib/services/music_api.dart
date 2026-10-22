import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/music_track.dart';

class MusicApi {
  MusicApi({String? baseUrl}) : baseUrl = (baseUrl ?? const String.fromEnvironment('MUSIC_API_URL', defaultValue: 'https://music-api.sokovibe.co.tz')).replaceAll(RegExp(r'/$'), '');

  final String baseUrl;

  Future<List<MusicTrack>> search(String query) async {
    if (query.trim().isEmpty) return [];
    final uri = Uri.parse('$baseUrl/search').replace(queryParameters: {'q': query.trim()});
    final response = await http.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('Music API error: ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final results = (decoded['results'] as List? ?? const []);
    return results.map((e) => MusicTrack.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<String> playUrl(String id) async {
    final response = await http.get(Uri.parse('$baseUrl/play/$id')).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) throw Exception('Unable to start playback');
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final url = decoded['streaming_url']?.toString();
    if (url == null || url.isEmpty) throw Exception('No playable source returned');
    return url;
  }
}
