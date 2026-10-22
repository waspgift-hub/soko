import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/music_track.dart';

class MusicApi {
  MusicApi({String? baseUrl, http.Client? client})
      : baseUrl = (baseUrl ?? const String.fromEnvironment('MUSIC_API_URL', defaultValue: 'https://soko-vibe-music-backend.sokovibe-co-tz.workers.dev')).replaceAll(RegExp(r'/

  final String baseUrl;
  final http.Client _client;

  Future<List<MusicTrack>> search(String query) async {
    if (query.trim().isEmpty) return [];
    final uri = Uri.parse('$baseUrl/search').replace(queryParameters: {'q': query.trim()});
    final response = await _client.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('Music API error: ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final results = (decoded['results'] as List? ?? const []);
    return results.map((e) => MusicTrack.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<String> downloadUrl(String id) async {
    final response = await _client.get(Uri.parse('$baseUrl/play/$id')).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) throw Exception('Unable to retrieve download permissions');
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final track = decoded['track'] is Map ? Map<String, dynamic>.from(decoded['track'] as Map) : decoded;
    final allowed = track['audiodownload_allowed'] == true || track['audiodownload_allowed'] == 1;
    final url = track['audiodownload']?.toString();
    if (!allowed || url == null || url.isEmpty) {
      throw Exception('This track is streaming-only under its current license.');
    }
    return url;
  }

  Future<String> playUrl(String id) async {
    final response = await http.get(Uri.parse('$baseUrl/play/$id')).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) throw Exception('Unable to start playback');
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final track = decoded['track'] is Map ? Map<String, dynamic>.from(decoded['track'] as Map) : decoded;
    final url = track['streaming_url']?.toString();
    if (url == null || url.isEmpty) throw Exception('No playable source returned');
    return url;
  }
}
), ''),
        _client = client ?? http.Client();

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

  Future<String> downloadUrl(String id) async {
    final response = await http.get(Uri.parse('$baseUrl/play/$id')).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) throw Exception('Unable to retrieve download permissions');
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final track = decoded['track'] is Map ? Map<String, dynamic>.from(decoded['track'] as Map) : decoded;
    final allowed = track['audiodownload_allowed'] == true || track['audiodownload_allowed'] == 1;
    final url = track['audiodownload']?.toString();
    if (!allowed || url == null || url.isEmpty) {
      throw Exception('This track is streaming-only under its current license.');
    }
    return url;
  }

  Future<String> playUrl(String id) async {
    final response = await http.get(Uri.parse('$baseUrl/play/$id')).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) throw Exception('Unable to start playback');
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final track = decoded['track'] is Map ? Map<String, dynamic>.from(decoded['track'] as Map) : decoded;
    final url = track['streaming_url']?.toString();
    if (url == null || url.isEmpty) throw Exception('No playable source returned');
    return url;
  }
}
