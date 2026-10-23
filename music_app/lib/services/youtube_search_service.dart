import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/music_track.dart';

/// Keyless metadata search using public Invidious-compatible instances.
/// Playback deliberately opens the official YouTube watch page; this service
/// does not extract or proxy YouTube audio streams.
class YoutubeSearchService {
  YoutubeSearchService({
    http.Client? client,
    List<String>? instances,
  })  : _client = client ?? http.Client(),
        _instances = instances ?? _defaultInstances;

  final http.Client _client;
  final List<String> _instances;

  static const List<String> _defaultInstances = <String>[
    'https://inv.nadeko.net',
    'https://invidious.nerdvpn.de',
    'https://invidious.privacyredirect.com',
  ];

  Future<List<MusicTrack>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return <MusicTrack>[];

    Object? lastError;
    for (final instance in _instances) {
      try {
        final uri = Uri.parse('$instance/api/v1/search').replace(
          queryParameters: <String, String>{'q': trimmed, 'type': 'video'},
        );
        final response = await _client
            .get(uri, headers: const <String, String>{'Accept': 'application/json'})
            .timeout(const Duration(seconds: 8));
        if (response.statusCode != 200) {
          throw Exception('Search provider returned HTTP ${response.statusCode}.');
        }
        final decoded = jsonDecode(response.body);
        if (decoded is! List) {
          throw const FormatException('Search provider returned an invalid result list.');
        }
        return decoded.whereType<Map>().map((raw) {
          final item = Map<String, dynamic>.from(raw);
          final id = (item['videoId'] ?? '').toString().trim();
          final title = (item['title'] ?? 'Unknown title').toString();
          final artist = (item['author'] ?? 'Unknown channel').toString();
          final thumbnails = item['videoThumbnails'];
          var image = '';
          if (thumbnails is List) {
            for (final thumbnail in thumbnails.whereType<Map>()) {
              final candidate = (thumbnail['url'] ?? '').toString();
              if (candidate.isNotEmpty) image = candidate;
            }
          }
          if (image.isEmpty && id.isNotEmpty) {
            image = 'https://i.ytimg.com/vi/$id/hqdefault.jpg';
          } else if (image.startsWith('/')) {
            image = Uri.parse(instance).resolve(image).toString();
          }
          return MusicTrack(
            id: id,
            title: title,
            artist: artist,
            image: image,
            streamUrl: null,
            downloadUrl: null,
            downloadAllowed: false,
            source: 'youtube',
          );
        }).where((track) => track.id.isNotEmpty).toList();
      } catch (error) {
        lastError = error;
      }
    }
    throw Exception(
      'YouTube search is temporarily unavailable. Try again later. (${lastError ?? 'No search instances configured'})',
    );
  }

  void close() => _client.close();
}
