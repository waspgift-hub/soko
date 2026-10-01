import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// One timed lyric line parsed from LRC text.
class LyricLine {
  final Duration timestamp;
  final String text;

  const LyricLine(this.timestamp, this.text);

  @override
  bool operator ==(Object other) =>
      other is LyricLine &&
      other.timestamp == timestamp &&
      other.text == text;

  @override
  int get hashCode => Object.hash(timestamp, text);

  @override
  String toString() => '[${timestamp.inMilliseconds}] $text';
}

/// A track's lyrics, with time-synced lines when the provider has them.
class Lyrics {
  final List<LyricLine> synced;
  final List<String> plain;
  final bool instrumental;

  const Lyrics({
    this.synced = const [],
    this.plain = const [],
    this.instrumental = false,
  });

  static const empty = Lyrics();

  /// True when there is nothing at all to render, so callers can distinguish
  /// "no lyrics exist" from "lyrics are still loading".
  bool get isEmpty => synced.isEmpty && plain.isEmpty && !instrumental;

  /// True when we can highlight a line as playback advances.
  bool get hasSynced => synced.isNotEmpty;

  /// Index of the line active at [position], or -1 before the first line.
  ///
  /// Binary search because this runs on every position tick; a linear scan over
  /// a 60-line lyric on a 10 Hz timer is wasteful.
  int activeIndexAt(Duration position) {
    if (synced.isEmpty) return -1;
    if (position < synced.first.timestamp) return -1;
    var lo = 0;
    var hi = synced.length - 1;
    var found = 0;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (synced[mid].timestamp <= position) {
        found = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return found;
  }

  /// All text, time-synced when available. Used for search and for the plain
  /// (non-scrolling) view.
  List<String> get displayLines =>
      synced.isNotEmpty ? synced.map((l) => l.text).toList() : plain;
}

/// Parses the LRC subset LRCLIB returns.
///
/// Format is one or more `[mm:ss.xx]` tags per line followed by the text, with
/// optional `[ar:]`-style metadata tags. Multiple timestamps on one line mean
/// the same text repeats (a shared chorus), so each tag yields its own entry.
class LrcParser {
  const LrcParser();

  static final RegExp _timeTag = RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');
  static final RegExp _metadataTag = RegExp(r'^\[(ar|ti|al|by|offset|length|au):', caseSensitive: false);

  /// Parses [raw] into time-ordered lines. Untimed or malformed input yields
  /// an empty list rather than throwing — a lyrics provider is best-effort and
  /// must never take the player down.
  List<LyricLine> parse(String raw) {
    if (raw.trim().isEmpty) return const [];
    final lines = <LyricLine>[];
    for (final rawLine in raw.split(RegExp(r'\r\n|\r|\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (_metadataTag.hasMatch(line)) continue;

      final matches = _timeTag.allMatches(line);
      if (matches.isEmpty) continue;

      // Text after the last tag belongs to every tag on this line.
      final text = line.substring(matches.last.end).trim();
      for (final m in matches) {
        final min = int.tryParse(m.group(1)!);
        final sec = int.tryParse(m.group(2)!);
        if (min == null || sec == null) continue;
        // Fractional part is 2 or 3 digits (centiseconds / milliseconds).
        final fracRaw = m.group(3) ?? '0';
        final fracMs = fracRaw.length == 3
            ? int.parse(fracRaw)
            : int.parse(fracRaw.padRight(3, '0'));
        lines.add(
          LyricLine(Duration(minutes: min, seconds: sec, milliseconds: fracMs), text),
        );
      }
    }
    lines.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return List.unmodifiable(lines);
  }
}

/// Fetches lyrics from LRCLIB, a free crowdsourced library with no API key.
///
/// Tries the exact-signature endpoint first (`/api/get`) because it matches on
/// duration and is far more accurate, then falls back to a keyword search
/// (`/api/search`) for tracks whose album or duration differs locally — a
/// common case for files bought from a store with edited metadata.
class LyricsService {
  LyricsService({http.Client? client}) : _client = client ?? http.Client();

  static const String host = 'https://lrclib.net';
  static const Duration _timeout = Duration(seconds: 8);

  final http.Client _client;

  /// Matches the shipped track signature. Duration must match within about two
  /// seconds or LRCLIB returns nothing.
  Future<Lyrics> fetchExact({
    required String track,
    required String artist,
    required String album,
    required Duration duration,
  }) async {
    if (track.trim().isEmpty) return Lyrics.empty;
    final uri = Uri.parse('$host/api/get').replace(
      queryParameters: {
        'track_name': track,
        'artist_name': artist.isEmpty ? 'Unknown' : artist,
        'album_name': album.isEmpty ? 'Unknown' : album,
        'duration': '${duration.inSeconds}',
      },
    );
    try {
      final res = await _client.get(uri).timeout(_timeout);
      if (res.statusCode != 200) return Lyrics.empty;
      return _decode(jsonDecode(res.body));
    } catch (_) {
      return Lyrics.empty;
    }
  }

  /// Keyword search, used when [fetchExact] finds nothing.
  ///
  /// Picks the best candidate rather than the first: prefers a synced-lyrics
  /// result, then the smallest duration gap, so a remix or live version with
  /// the same title does not win over the studio cut.
  Future<Lyrics> search({
    required String track,
    String artist = '',
    Duration? duration,
  }) async {
    if (track.trim().isEmpty) return Lyrics.empty;
    final uri = Uri.parse('$host/api/search').replace(
      queryParameters: {
        if (artist.trim().isNotEmpty) 'artist_name': artist,
        'track_name': track,
      },
    );
    List<dynamic> items;
    try {
      final res = await _client.get(uri).timeout(_timeout);
      if (res.statusCode != 200) return Lyrics.empty;
      final decoded = jsonDecode(res.body);
      if (decoded is! List) return Lyrics.empty;
      items = decoded;
    } catch (_) {
      return Lyrics.empty;
    }

    dynamic best;
    var bestScore = -1 << 62;
    for (final item in items) {
      if (item is! Map) continue;
      final score = _candidateScore(item, duration);
      if (score > bestScore) {
        bestScore = score;
        best = item;
      }
    }
    if (best == null) return Lyrics.empty;
    return _decode(best);
  }

  /// Exact match, then search. The order matters: search alone regularly picks
  /// a karaoke or cover version of the same title.
  Future<Lyrics> fetch({
    required String track,
    String artist = '',
    String album = '',
    Duration? duration,
  }) async {
    if (duration != null && duration > Duration.zero) {
      final exact = await fetchExact(
        track: track,
        artist: artist,
        album: album,
        duration: duration,
      );
      if (!exact.isEmpty) return exact;
    }
    return search(track: track, artist: artist, duration: duration);
  }

  /// Higher is better. Synced lyrics dominate, then duration proximity.
  static int _candidateScore(Map<dynamic, dynamic> item, Duration? duration) {
    final hasSynced = (item['syncedLyrics'] as String?)?.trim().isNotEmpty ?? false;
    var score = hasSynced ? 1000 : 0;
    final seconds = (item['duration'] as num?)?.toDouble();
    if (seconds != null && duration != null) {
      final gap = (seconds - duration.inMilliseconds / 1000).abs();
      // 10 points per second of drift, floored at 0.
      score += (100 - gap * 10).round().clamp(0, 100);
    }
    return score;
  }

  Lyrics _decode(dynamic json) {
    if (json is! Map) return Lyrics.empty;
    final instrumental = json['instrumental'] == true;
    final syncedRaw = (json['syncedLyrics'] as String?) ?? '';
    final plainRaw = (json['plainLyrics'] as String?) ?? '';
    final synced = const LrcParser().parse(syncedRaw);
    final plain = plainRaw
        .split(RegExp(r'\r\n|\r|\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList(growable: false);
    // An instrumental track often carries a single "[au: instrumental]" marker;
    // report it so the UI can say "instrumental" instead of "lyrics not found".
    return Lyrics(synced: synced, plain: plain, instrumental: instrumental);
  }

  void dispose() => _client.close();
}
