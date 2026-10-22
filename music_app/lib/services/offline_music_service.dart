import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/music_track.dart';

/// Manages app-private offline files and imports selected local audio.
/// Provider downloads require explicit Jamendo download permission and an HTTPS URL.
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
      return decoded
          .whereType<Map>()
          .map((item) => OfflineTrack.fromJson(Map<String, dynamic>.from(item)))
          .where((track) => File(track.path).existsSync())
          .toList();
    } catch (_) {
      return <OfflineTrack>[];
    }
  }

  /// audioUrl is optional for compatibility, but if supplied must exactly match
  /// the provider's permitted audiodownload URL, never the streaming URL.
  Future<OfflineTrack> download(MusicTrack track, [String? audioUrl]) async {
    if (!track.canDownload || track.downloadUrl == null) {
      throw const OfflineMusicException(
        'Jamendo does not explicitly allow downloading this track.',
      );
    }
    final requestedUri = Uri.tryParse(audioUrl ?? track.downloadUrl!);
    final allowedUri = Uri.tryParse(track.downloadUrl!);
    if (requestedUri == null ||
        allowedUri == null ||
        requestedUri.scheme != 'https' ||
        requestedUri.host.isEmpty ||
        requestedUri.toString() != allowedUri.toString()) {
      throw const OfflineMusicException(
        'Download URL does not match the permitted HTTPS download URL.',
      );
    }

    final response = await http
        .get(requestedUri, headers: const {'Accept': 'audio/*'})
        .timeout(const Duration(seconds: 60));
    final finalUri = response.request?.url;
    if (response.statusCode != 200 ||
        response.bodyBytes.isEmpty ||
        finalUri == null ||
        finalUri.scheme != 'https' ||
        finalUri.host.isEmpty) {
      throw const OfflineMusicException('Download failed or the provider redirected to an invalid URL.');
    }
    final contentType = response.headers['content-type']?.toLowerCase() ?? '';
    if (contentType.contains('text/html') || contentType.contains('application/json')) {
      throw const OfflineMusicException('Provider did not return an audio file.');
    }

    final dir = await _directory();
    final safeId = track.id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final file = File('${dir.path}/$safeId.mp3');
    await file.writeAsBytes(response.bodyBytes, flush: true);
    final saved = OfflineTrack(
      id: track.id,
      title: track.title,
      artist: track.artist,
      path: file.path,
      source: 'Jamendo',
      license: track.license,
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
        artist: 'Local music',
        path: target.path,
        source: 'Device',
        license: '',
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

  String _safeName(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
}

class OfflineTrack {
  const OfflineTrack({
    required this.id, required this.title, required this.artist,
    required this.path, required this.source, required this.license,
  });
  final String id, title, artist, path, source, license;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id, 'title': title, 'artist': artist, 'path': path,
        'source': source, 'license': license,
      };

  factory OfflineTrack.fromJson(Map<String, dynamic> json) => OfflineTrack(
        id: '${json['id'] ?? ''}',
        title: '${json['title'] ?? 'Unknown track'}',
        artist: '${json['artist'] ?? 'Unknown artist'}',
        path: '${json['path'] ?? ''}',
        source: '${json['source'] ?? 'Device'}',
        license: '${json['license'] ?? ''}',
      );
}

class OfflineMusicException implements Exception {
  const OfflineMusicException(this.message);
  final String message;
  @override
  String toString() => message;
}
