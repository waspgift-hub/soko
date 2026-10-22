import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/music_track.dart';

/// Keeps app-managed offline tracks and lets users import audio via Android's
/// system file picker. Only save provider tracks when their terms explicitly
/// permit downloading; a stream URL alone is not download permission.
class OfflineMusicService {
  static const _indexKey = 'offline_music_index_v1';
  Future<Directory> _directory() async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory('${root.path}/offline_music');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<List<OfflineTrack>> list() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_indexKey);
    if (raw == null) return <OfflineTrack>[];
    try {
      final decoded = jsonDecode(raw) as List;
      final tracks = decoded
          .whereType<Map>()
          .map((item) => OfflineTrack.fromJson(Map<String, dynamic>.from(item)))
          .where((track) => File(track.path).existsSync())
          .toList();
      return tracks;
    } catch (_) {
      return <OfflineTrack>[];
    }
  }

  Future<OfflineTrack> download(MusicTrack track, String audioUrl) async {
    if (track.license.trim().isEmpty) {
      throw const OfflineMusicException(
        'This track has no license information. Check the provider terms before downloading.',
      );
    }
    final uri = Uri.tryParse(audioUrl);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw const OfflineMusicException('The audio source is not a valid HTTPS URL.');
    }
    final response = await http.get(uri).timeout(const Duration(seconds: 60));
    if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
      throw const OfflineMusicException('Download failed. Please try again.');
    }
    final dir = await _directory();
    final safeId = track.id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final file = File('${dir.path}/$safeId.mp3');
    await file.writeAsBytes(response.bodyBytes, flush: true);
    final saved = OfflineTrack(
      id: track.id, title: track.title, artist: track.artist, path: file.path,
      source: 'Jamendo', license: track.license,
    );
    final existing = await list();
    final updated = <OfflineTrack>[
      saved,
      ...existing.where((item) => item.id != saved.id),
    ];
    await _saveIndex(updated);
    return saved;
  }

  Future<List<OfflineTrack>> importLocalAudio() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio, allowMultiple: true, withData: false,
    );
    if (result == null) return list();
    final dir = await _directory();
    final tracks = await list();
    for (final picked in result.files) {
      final path = picked.path;
      if (path == null) continue;
      final source = File(path);
      if (!await source.exists()) continue;
      final target = File('${dir.path}/local_${DateTime.now().microsecondsSinceEpoch}_${_safeName(picked.name)}');
      await source.copy(target.path);
      tracks.insert(0, OfflineTrack(
        id: 'local_${target.uri.pathSegments.last}',
        title: picked.name.replaceFirst(RegExp(r'\.[^.]+$'), ''),
        artist: 'Local music', path: target.path, source: 'Device', license: '',
      ));
    }
    await _saveIndex(tracks);
    return tracks;
  }

  Future<void> remove(OfflineTrack track) async {
    final file = File(track.path);
    if (await file.exists()) await file.delete();
    final tracks = await list();
    await _saveIndex(tracks.where((item) => item.path != track.path).toList());
  }

  Future<void> _saveIndex(List<OfflineTrack> tracks) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_indexKey, jsonEncode(tracks.map((e) => e.toJson()).toList()));
  }

  String _safeName(String value) => value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
}

class OfflineTrack {
  const OfflineTrack({required this.id, required this.title, required this.artist,
    required this.path, required this.source, required this.license});
  final String id, title, artist, path, source, license;
  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id, 'title': title, 'artist': artist, 'path': path, 'source': source, 'license': license,
  };
  factory OfflineTrack.fromJson(Map<String, dynamic> json) => OfflineTrack(
    id: '${json['id'] ?? ''}', title: '${json['title'] ?? 'Unknown track'}',
    artist: '${json['artist'] ?? 'Unknown artist'}', path: '${json['path'] ?? ''}',
    source: '${json['source'] ?? 'Device'}', license: '${json['license'] ?? ''}',
  );
}

class OfflineMusicException implements Exception {
  const OfflineMusicException(this.message);
  final String message;
  @override String toString() => message;
}