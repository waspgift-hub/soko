import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/music_track.dart';

class DownloadedTrack {
  const DownloadedTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.image,
    required this.filePath,
    required this.downloadedAt,
  });

  final String id;
  final String title;
  final String artist;
  final String image;
  final String filePath;
  final DateTime downloadedAt;

  MusicTrack toMusicTrack() => MusicTrack(
        id: id,
        title: title,
        artist: artist,
        image: image,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'image': image,
        'filePath': filePath,
        'downloadedAt': downloadedAt.toIso8601String(),
      };

  factory DownloadedTrack.fromJson(Map<String, dynamic> json) =>
      DownloadedTrack(
        id: json['id'].toString(),
        title: (json['title'] ?? 'Unknown title').toString(),
        artist: (json['artist'] ?? 'Unknown artist').toString(),
        image: (json['image'] ?? '').toString(),
        filePath: json['filePath'].toString(),
        downloadedAt: DateTime.tryParse(
              (json['downloadedAt'] ?? '').toString(),
            ) ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}

/// Downloads audio into the app's private documents directory so it remains
/// available offline without broad external-storage permissions.
class DownloadService {
  DownloadService._();
  static final DownloadService instance = DownloadService._();

  static const _indexKey = 'sokovibe_music_download_index_v1';

  Future<List<DownloadedTrack>> list() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_indexKey) ?? const <String>[];
    final result = <DownloadedTrack>[];
    for (final entry in raw) {
      try {
        final item = DownloadedTrack.fromJson(
          Map<String, dynamic>.from(jsonDecode(entry) as Map),
        );
        if (await File(item.filePath).exists()) result.add(item);
      } catch (_) {
        // Ignore one corrupt index entry instead of breaking the downloads page.
      }
    }
    result.sort((a, b) => b.downloadedAt.compareTo(a.downloadedAt));
    return result;
  }

  Future<DownloadedTrack> download(MusicTrack track, String sourceUrl) async {
    final uri = Uri.tryParse(sourceUrl);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw const DownloadException('The music provider returned an invalid download URL.');
    }
    final response = await http.get(uri).timeout(const Duration(seconds: 90));
    if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
      throw DownloadException('Download failed (HTTP ${response.statusCode}).');
    }

    final docs = await getApplicationDocumentsDirectory();
    final directory = Directory('${docs.path}/SokoVibeMusic');
    await directory.create(recursive: true);
    final safeId = track.id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    if (safeId.isEmpty) {
      throw const DownloadException('This track has no valid ID and cannot be saved.');
    }
    final file = File('${directory.path}/$safeId.mp3');
    try {
      await file.writeAsBytes(response.bodyBytes, flush: true);
      final item = DownloadedTrack(
        id: track.id,
        title: track.title,
        artist: track.artist,
        image: track.image,
        filePath: file.path,
        downloadedAt: DateTime.now(),
      );
      final all = await list();
      final updated = <DownloadedTrack>[
        item,
        ...all.where((saved) => saved.id != item.id),
      ];
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _indexKey,
        updated.map((saved) => jsonEncode(saved.toJson())).toList(),
      );
      return item;
    } catch (_) {
      if (await file.exists()) await file.delete();
      rethrow;
    }
  }

  Future<void> delete(DownloadedTrack item) async {
    final file = File(item.filePath);
    if (await file.exists()) await file.delete();
    final remaining = (await list()).where((saved) => saved.id != item.id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _indexKey,
      remaining.map((saved) => jsonEncode(saved.toJson())).toList(),
    );
  }
}

class DownloadException implements Exception {
  const DownloadException(this.message);
  final String message;
  @override
  String toString() => message;
}
