import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path_provider/path_provider.dart';

import '../models/soko_media_item.dart';
import 'video_query_service.dart';

/// Reads the device's local media and normalizes manual imports into
/// [SokoMediaItem]s.
///
/// Music comes from the on_audio_query MediaStore scan; video has no public
/// API in that package, so it reuses the app's native [VideoQueryService]
/// channel. Album art is fetched on demand with a disk-backed cache keyed by
/// album so the notification and Now Playing screen can show the artwork.
class MediaLibraryService {
  MediaLibraryService._();

  static final MediaLibraryService instance = MediaLibraryService._();

  final OnAudioQuery _audioQuery = OnAudioQuery();
  final Map<String, String> _albumArtFile = {}; // "album|artist" -> file path
  final Map<String, Uint8List> _albumArtData = {}; // "album|artist" -> bytes
  Directory? _artDir;

  static List<String> get audioExtensions =>
      const ['mp3', 'm4a', 'aac', 'wav', 'ogg', 'oga', 'flac', 'opus', 'aiff', 'amr'];

  static List<String> get videoExtensions =>
      const ['mp4', 'mkv', 'webm', 'mov', 'avi', '3gp', 'wmv', 'm4v'];

  Future<Directory> _ensureArtDir() async {
    if (_artDir != null) return _artDir!;
    final dir =
        Directory('${(await getApplicationCacheDirectory()).path}/soko_media_art');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return _artDir = dir;
  }

  /// Whether the app can read the Android MediaStore/IOS media library.
  Future<bool> hasPermission() async {
    if (kIsWeb) return true;
    try {
      return await _audioQuery.permissionsStatus();
    } catch (e) {
      debugPrint('MediaLibraryService.hasPermission: $e');
      return false;
    }
  }

  /// Requests runtime storage permission from the user on first grant.
  Future<bool> requestPermission() async {
    if (kIsWeb) return true;
    try {
      return await _audioQuery.permissionsRequest();
    } catch (e) {
      debugPrint('MediaLibraryService.requestPermission: $e');
      return false;
    }
  }

  /// Scans music from the device MediaStore (tagged audio files only).
  Future<List<SokoMediaItem>> scanMusic() async {
    try {
      final songs = await _audioQuery.querySongs(
        sortType: SongSortType.TITLE,
        orderType: OrderType.ASC_OR_SMALLER,
      );
      return songs
          .where((s) => s.title.trim().isNotEmpty)
          .map(
            (s) => SokoMediaItem(
              id: 'song_${s.id}',
              title: s.title,
              artist: s.artist,
              album: s.album,
              uri: s.uri ?? s.data,
              type: SokoMediaType.audio,
              duration: Duration(milliseconds: s.duration ?? 0),
            ),
          )
          .toList();
    } catch (e) {
      debugPrint('MediaLibraryService.scanMusic: $e');
      return const [];
    }
  }

  /// Scans videos from the device via the native query channel.
  Future<List<SokoMediaItem>> scanVideos() async {
    try {
      final raw = await VideoQueryService.queryVideos();
      return raw
          .where((v) => (v['displayName'] as String? ?? '').trim().isNotEmpty)
          .map(
            (v) {
              final name = v['displayName'] as String;
              final contentUri = v['contentUri'] as String? ?? '';
              return SokoMediaItem(
                id: 'video_${v['id'] ?? name}',
                title: name,
                uri: contentUri.isNotEmpty
                    ? contentUri
                    : (v['data'] as String? ?? ''),
                type: SokoMediaType.video,
                duration: Duration(milliseconds: (v['duration'] as num? ?? 0).toInt()),
              );
            },
          )
          .toList();
    } catch (e) {
      debugPrint('MediaLibraryService.scanVideos: $e');
      return const [];
    }
  }

  /// Picks audio/video files with the system file picker (no storage
  /// permission needed — the picker grants temporary access per selection).
  Future<List<SokoMediaItem>> importFiles() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: [...audioExtensions, ...videoExtensions],
        allowMultiple: true,
      );
      if (result == null || result.files.isEmpty) return const [];
      final items = <SokoMediaItem>[];
      for (final f in result.files) {
        final path = f.path;
        final name = f.name;
        if (path == null || name.isEmpty) continue;
        final ext = _extensionOf(name);
        final isVideo = videoExtensions.contains(ext);
        final isAudio = audioExtensions.contains(ext);
        if (!isAudio && !isVideo) continue;
        items.add(
          SokoMediaItem(
            id: 'file_$path',
            title: name,
            uri: Uri.file(path).toString(),
            type: isVideo ? SokoMediaType.video : SokoMediaType.audio,
            fromImport: true,
            duration: Duration.zero, // read from the file at playback time
          ),
        );
      }
      return items;
    } catch (e) {
      debugPrint('MediaLibraryService.importFiles: $e');
      return const [];
    }
  }

  /// Resolves the album-art file URI for [item], fetching and caching on
  /// first request. Only MediaStore items carry queryable art — imported
  /// files return null and fall back to a generated disc.
  Future<String?> artworkUri(SokoMediaItem item) async {
    if (item.type != SokoMediaType.audio || item.fromImport) return null;
    if (!item.uri.startsWith('content://')) {
      // Old Android exposes raw paths; those have no queryable artwork either.
      return null;
    }
    final songId = int.tryParse(item.id.replaceFirst('song_', ''));
    if (songId == null) return null;
    final key = '${item.album ?? ''}|${item.artist ?? ''}';
    final cached = _albumArtFile[key];
    if (cached != null) {
      if (File(cached).existsSync()) return Uri.file(cached).toString();
      _albumArtFile.remove(key);
    }
    try {
      var data = _albumArtData[key];
      if (data == null) {
        data = await _audioQuery.queryArtwork(
          songId,
          ArtworkType.AUDIO,
          size: 512,
          quality: 85,
        );
        if (data == null || data.isEmpty) return null;
        _albumArtData[key] = data;
      }
      final dir = await _ensureArtDir();
      final safeKey = key.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final file = File('${dir.path}/$safeKey.jpg');
      if (!file.existsSync()) await file.writeAsBytes(data);
      _albumArtFile[key] = file.path;
      return Uri.file(file.path).toString();
    } catch (e) {
      debugPrint('MediaLibraryService.artworkUri: $e');
      return null;
    }
  }

  /// Resolves artwork for a list of items with a small concurrency bound so
  /// large libraries never block the caller with a long await chain.
  Future<List<String?>> resolveArtwork(List<SokoMediaItem> items) async {
    final out = List<String?>.filled(items.length, null);
    var next = 0;
    Future<void> worker() async {
      while (true) {
        final i = next++;
        if (i >= items.length) return;
        out[i] = await artworkUri(items[i]);
      }
    }

    await Future.wait([for (var w = 0; w < 6; w++) worker()]);
    return out;
  }

  String _extensionOf(String name) {
    final dot = name.lastIndexOf('.');
    return dot >= 0 ? name.substring(dot + 1).toLowerCase() : '';
  }
}