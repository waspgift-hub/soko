import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:on_audio_query/on_audio_query.dart';

/// Centralized permission handling for music features.
class MusicPermissionService {
  static final MusicPermissionService instance = MusicPermissionService._();
  MusicPermissionService._();

  final OnAudioQuery _audioQuery = OnAudioQuery();

  /// Permission states cached to avoid re-requesting.
  bool _storageGranted = false;
  bool _notificationGranted = false;

  bool get storageGranted => _storageGranted;
  bool get notificationGranted => _notificationGranted;

  /// Check all needed permissions without prompting.
  Future<void> checkStatus() async {
    _storageGranted = await _audioQuery.permissionsStatus();
    if (!kIsWeb) {
      _notificationGranted = await Permission.notification.status.isGranted;
    } else {
      _notificationGranted = true;
    }
  }

  /// Request storage/media read permission (for local MP3 files).
  /// Returns true if granted.
  Future<bool> requestStorage() async {
    if (_storageGranted) return true;
    _storageGranted = await _audioQuery.permissionsRequest();
    return _storageGranted;
  }

  /// Request notification permission (Android 13+).
  /// Returns true if granted.
  Future<bool> requestNotification() async {
    if (_notificationGranted) return true;
    if (!kIsWeb) {
      final status = await Permission.notification.request();
      _notificationGranted = status.isGranted;
    } else {
      _notificationGranted = true;
    }
    return _notificationGranted;
  }

  /// Request all music-related permissions.
  Future<bool> requestAll() async {
    final s = await requestStorage();
    final n = await requestNotification();
    return s && n;
  }

  /// Reset cached states so next call re-checks.
  void reset() {
    _storageGranted = false;
    _notificationGranted = false;
  }
}
