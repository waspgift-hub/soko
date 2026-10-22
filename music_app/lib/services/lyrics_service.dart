import 'dart:convert';
import 'package:http/http.dart' as http;

class TrackLyrics {
  final String trackName;
  final String artistName;
  final String? plainLyrics;
  final String? syncedLyrics;
  final bool instrumental;

  const TrackLyrics({
    required this.trackName,
    required this.artistName,
    this.plainLyrics,
    this.syncedLyrics,
    this.instrumental = false,
  });

  factory TrackLyrics.fromJson(Map<String, dynamic> json) => TrackLyrics(
        trackName: (json['trackName'] ?? json['name'] ?? 'Unknown track').toString(),
        artistName: (json['artistName'] ?? 'Unknown artist').toString(),
        plainLyrics: json['plainLyrics'] as String?,
        syncedLyrics: json['syncedLyrics'] as String?,
        instrumental: json['instrumental'] == true,
      );

  String? get displayText {
    final synced = syncedLyrics?.trim();
    if (synced != null && synced.isNotEmpty) return synced;
    final plain = plainLyrics?.trim();
    return (plain == null || plain.isEmpty) ? null : plain;
  }
}

class LyricsService {
  LyricsService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const _baseUrl = 'https://lrclib.net/api';
  static const _userAgent = 'SokoVibeMusic/0.1.0 (https://github.com/waspgift-hub/soko)';

  Future<TrackLyrics?> findLyrics({
    required String title,
    required String artist,
    String? album,
    Duration? duration,
  }) async {
    final exactParams = <String, String>{
      'track_name': title,
      'artist_name': artist,
      if (album != null && album.trim().isNotEmpty) 'album_name': album,
      if (duration != null && duration.inSeconds > 0 && duration.inSeconds <= 3600)
        'duration': '${duration.inSeconds}',
    };

    try {
      final exactUri = Uri.parse('$_baseUrl/get').replace(queryParameters: exactParams);
      final exact = await _client.get(exactUri, headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 12));
      if (exact.statusCode == 200) {
        final json = jsonDecode(exact.body);
        if (json is Map<String, dynamic>) return TrackLyrics.fromJson(json);
      } else if (exact.statusCode == 429) {
        throw const LyricsException('Lyrics service is busy. Please wait and try again.');
      }
    } catch (e) {
      if (e is LyricsException) rethrow;
      // Continue to a keyword search if the exact lookup failed.
    }

    try {
      final searchUri = Uri.parse('$_baseUrl/search').replace(queryParameters: {
        'track_name': title,
        'artist_name': artist,
      });
      final response = await _client.get(searchUri, headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 12));
      if (response.statusCode == 429) {
        throw const LyricsException('Too many lyrics requests. Please wait and try again.');
      }
      if (response.statusCode != 200) {
        throw const LyricsException('Lyrics could not be loaded right now.');
      }
      final results = jsonDecode(response.body);
      if (results is List) {
        for (final item in results) {
          if (item is Map<String, dynamic>) {
            final result = TrackLyrics.fromJson(item);
            final sameTitle = result.trackName.toLowerCase().trim() == title.toLowerCase().trim();
            final sameArtist = result.artistName.toLowerCase().trim() == artist.toLowerCase().trim();
            if (sameTitle && sameArtist && result.displayText != null) return result;
          }
        }
        // Return a result only when it contains lyrics and metadata is reasonably relevant.
        for (final item in results) {
          if (item is Map<String, dynamic>) {
            final result = TrackLyrics.fromJson(item);
            if (result.displayText != null &&
                result.trackName.toLowerCase().contains(title.toLowerCase())) {
              return result;
            }
          }
        }
      }
      return null;
    } on LyricsException {
      rethrow;
    } catch (_) {
      throw const LyricsException('Could not connect to the lyrics service. Check your connection.');
    }
  }
}

class LyricsException implements Exception {
  const LyricsException(this.message);
  final String message;
  @override
  String toString() => message;
}
