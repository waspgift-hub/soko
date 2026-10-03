import 'dart:typed_data';

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

  /// Embedded cover art bytes, if the file/track has any.
  ///
  /// Read from the device, never downloaded: the artwork is already inside the
  /// audio file, so this costs no network and no permission beyond the media
  /// permission already required to list songs.
  final Uint8List? artwork;

  /// True when this track genuinely has no artwork. Distinguishes "not loaded
  /// yet" from "the song has none", so the UI can show a placeholder instead of
  /// an image that never loads.
  final bool artworkMissing;

  const LocalSong({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.path,
    required this.durationMs,
    this.artwork,
    this.artworkMissing = false,
  });

  /// Album art, falling back to the song's own art.
  ///
  /// Album-level art lives on one representative track, so grouping the library
  /// by album and asking that track for its art is how an album cover is found.
  Uint8List? get albumArtwork => artwork;

  String get displayArtist => (artist.isEmpty || artist == 'Unknown') ? '' : artist;
  String get displayAlbum => album == 'Unknown' ? '' : album;

  LocalSong withArtwork(Uint8List? bytes, {bool missing = false}) => LocalSong(
        id: id,
        title: title,
        artist: artist,
        album: album,
        path: path,
        durationMs: durationMs,
        artwork: bytes,
        artworkMissing: missing,
      );

  /// Case-insensitive match across the fields a user would actually type.
  bool matches(String query) {
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return true;
    return title.toLowerCase().contains(q) ||
        displayArtist.toLowerCase().contains(q) ||
        displayAlbum.toLowerCase().contains(q);
  }
}

/// An album grouped out of the device library.
class LocalAlbum {
  final String name;
  final String artist;
  final List<LocalSong> songs;
  final Uint8List? artwork;

  const LocalAlbum({
    required this.name,
    required this.artist,
    required this.songs,
    this.artwork,
  });

  Duration get duration =>
      Duration(milliseconds: songs.fold(0, (sum, s) => sum + s.durationMs));
}

/// Reads the on-device music library. Desktop and web have no media store,
/// so every entry point degrades to an empty result there instead of
/// throwing into the UI.
class MusicLibraryService {
  final OnAudioQuery _query = OnAudioQuery();

  bool get isSupportedPlatform => !kIsWeb;

  /// Songs scanned before artwork lookups start. Reading embedded art is a
  /// per-song file read, so doing it for a 5,000-track library during the first
  /// frame would stall the UI for seconds.
  static const int _coverScanLimit = 200;

  /// Whether to read embedded art during [loadSongs]. On by default because a
  /// song list without covers is the thing users notice first; the scan is
  /// bounded by [_coverScanLimit] precisely so it stays cheap.
  static const bool _queryArtwork = true;

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

  /// Loads songs, attaching cover art to the first [_coverScanLimit] of them.
  ///
  /// Covers for the rest resolve lazily via [artworkFor] when a row scrolls
  /// into view, so a large library still opens immediately.
  Future<List<LocalSong>> loadSongs({int coverScanLimit = _coverScanLimit}) async {
    if (!isSupportedPlatform) return const [];
    try {
      if (!await hasPermission()) return const [];
      final songs = await _query.querySongs(
        sortType: SongSortType.TITLE,
        orderType: OrderType.ASC_OR_SMALLER,
        uriType: UriType.EXTERNAL,
        ignoreCase: true,
      );
      final limit = coverScanLimit < 0 ? songs.length : coverScanLimit;
      final out = <LocalSong>[];
      for (var i = 0; i < songs.length; i++) {
        final s = songs[i];
        if (s.data.isEmpty) continue;
        LocalSong song = LocalSong(
          id: s.id.toString(),
          title: s.title.isEmpty ? s.displayNameWOExt : s.title,
          artist: (s.artist ?? '').isEmpty ? 'Unknown' : s.artist!,
          album: s.album ?? '',
          path: s.data,
          durationMs: s.duration ?? 0,
        );
        if (_queryArtwork && i < limit) {
          song = song.withArtwork(
            await artworkFor(song.id),
            missing: false,
          );
        }
        out.add(song);
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// Cover bytes for one song, or null when the track has none.
  ///
  /// Every failure path returns null rather than throwing: a corrupt embedded
  /// image must not take the music library down with it.
  Future<Uint8List?> artworkFor(String songId) async {
    if (!isSupportedPlatform) return null;
    final id = int.tryParse(songId);
    if (id == null) return null;
    try {
      final bytes = await _query.queryArtwork(id, ArtworkType.AUDIO);
      if (bytes == null || bytes.isEmpty) return null;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  /// Groups songs into albums, taking cover art from the first track that has
  /// any. Used for the album grid.
  List<LocalAlbum> albumsOf(List<LocalSong> songs) {
    final byKey = <String, List<LocalSong>>{};
    for (final s in songs) {
      final key = '${s.displayAlbum}|${s.displayArtist}';
      (byKey[key] ??= <LocalSong>[]).add(s);
    }
    final out = <LocalAlbum>[];
    byKey.forEach((_, tracks) {
      final album = tracks.first.displayAlbum.isEmpty
          ? 'Unknown album'
          : tracks.first.displayAlbum;
      Uint8List? art;
      for (final t in tracks) {
        if (t.artwork != null) {
          art = t.artwork;
          break;
        }
      }
      out.add(LocalAlbum(
        name: album,
        artist: tracks.first.displayArtist,
        songs: List<LocalSong>.unmodifiable(tracks),
        artwork: art,
      ));
    });
    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  /// Filters the library by title, artist or album.
  static List<LocalSong> search(List<LocalSong> songs, String query) {
    final q = query.trim();
    if (q.isEmpty) return songs;
    return songs.where((s) => s.matches(q)).toList();
  }
}
