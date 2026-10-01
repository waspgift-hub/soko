import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:on_audio_query/on_audio_query.dart';

/// A song stored on the user's own device (MediaStore on Android, Media
/// Library on iOS). Playing the user's own files is fully offline and needs
/// no server, no key and no rights beyond the OS media permission.
class LocalSong {
  final String id;
  final String title;
  final String artist;
  final String album;
  final String path;
  final int durationMs;

  const LocalSong({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.path,
    required this.durationMs,
  });
}

/// Reads the on-device music library. Desktop and web have no media store,
/// so every entry point degrades to an empty result there instead of
/// throwing into the UI.
class MusicLibraryService {
  final OnAudioQuery _query = OnAudioQuery();

  bool get isSupportedPlatform => !kIsWeb;

  Future<bool> hasPermission() async {
    if (!isSupportedPlatform) return false;
    try {
      return await _query.permissionsStatus();
    } catch (_) {
      return false;
    }
  }

  Future<bool> requestPermission() async {
    if (!isSupportedPlatform) return false;
    try {
      return await _query.permissionsRequest();
    } catch (_) {
      return false;
    }
  }

  Future<List<LocalSong>> loadSongs() async {
    if (!isSupportedPlatform) return const [];
    try {
      if (!await hasPermission()) return const [];
      final songs = await _query.querySongs(
        sortType: SongSortType.TITLE,
        orderType: OrderType.ASC_OR_SMALLER,
        uriType: UriType.EXTERNAL,
        ignoreCase: true,
      );
      return songs
          .where((s) => s.data.isNotEmpty)
          .map(
            (s) => LocalSong(
              id: s.id.toString(),
              title: s.title.isEmpty ? s.displayNameWOExt : s.title,
              artist: (s.artist ?? '').isEmpty ? 'Unknown' : s.artist!,
              album: s.album ?? '',
              path: s.data,
              durationMs: s.duration ?? 0,
            ),
          )
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
