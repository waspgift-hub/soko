import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';

/// A YouTube video from the server-side search proxy. The key lives on the
/// server, so the app only ever sees ids/titles — playback uses the official
/// nocookie embed, never a download.
class YouTubeVideo {
  final String videoId;
  final String title;
  final String channel;
  final String thumbnail;

  const YouTubeVideo({
    required this.videoId,
    required this.title,
    required this.channel,
    required this.thumbnail,
  });

  String get watchUrl => 'https://www.youtube.com/watch?v=$videoId';
}

/// Pure response parser — unit-tested without network.
List<YouTubeVideo> parseYouTubeResults(dynamic decoded) {
  final data = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  final items = data['items'];
  if (items is! List) return const [];
  return items.whereType<Map>().map((raw) {
    String str(String key) => (raw[key] ?? '').toString();
    return YouTubeVideo(
      videoId: str('videoId'),
      title: str('title'),
      channel: str('channel'),
      thumbnail: str('thumbnail'),
    );
  }).where((v) => v.videoId.isNotEmpty).toList();
}

class YouTubeSearchService {
  /// Throws [StateError] with 'YOUTUBE_NOT_CONFIGURED' when the server has no
  /// key (the UI hides the tab gracefully); returns [] on any other failure.
  Future<List<YouTubeVideo>> search(String query) async {
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token == null) return const [];
      final uri = ApiConfig.v1(
        '/youtube/search?q=${Uri.encodeQueryComponent(query)}&maxResults=10',
      );
      final res = await http
          .get(
            Uri.parse(uri),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 15));
      final body = jsonDecode(res.body);
      if (res.statusCode == 503 &&
          body is Map &&
          body['error'] == 'YOUTUBE_NOT_CONFIGURED') {
        throw StateError('YOUTUBE_NOT_CONFIGURED');
      }
      if (res.statusCode != 200) return const [];
      return parseYouTubeResults(body);
    } catch (e) {
      if (e is StateError) rethrow;
      return const [];
    }
  }
}
