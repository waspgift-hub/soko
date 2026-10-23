import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reads actual audio rows from Android MediaStore. No mock catalog is used.
class OnDeviceMusicService {
  static const MethodChannel _channel = MethodChannel('soko_lang/audio_library');
  static const String _permissionAskedKey = 'music_audio_permission_requested_v1';
  static const String onboardingSeenKey = 'sokovibe_music_onboarding_seen_v1';

  Future<Permission> _audioPermission() async {
    if (!Platform.isAndroid) return Permission.audio;
    final info = await DeviceInfoPlugin().androidInfo;
    return info.version.sdkInt >= 33 ? Permission.audio : Permission.storage;
  }

  Future<bool> get hasPermission async => (await _audioPermission()).isGranted;

  /// Requests Android's media permission once. If the user previously denied it,
  /// open system settings instead of repeatedly showing the permission dialog.
  Future<bool> requestPermissionOnce() async {
    final prefs = await SharedPreferences.getInstance();
    final permission = await _audioPermission();
    if (await permission.isGranted) return true;

    final alreadyAsked = prefs.getBool(_permissionAskedKey) ?? false;
    if (alreadyAsked) {
      await openAppSettings();
      return false;
    }

    final status = await permission.request();
    await prefs.setBool(_permissionAskedKey, true);
    return status.isGranted;
  }

  Future<List<Map<String, dynamic>>> scan() async {
    if (!Platform.isAndroid) return <Map<String, dynamic>>[];
    if (!await hasPermission) {
      throw const PlatformException(
        code: 'AUDIO_PERMISSION_REQUIRED',
        message: 'Ruhusa ya kusoma muziki wa kwenye kifaa inahitajika.',
      );
    }
    final result = await _channel.invokeListMethod<dynamic>('queryAudio');
    return (result ?? const <dynamic>[])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) => (item['contentUri'] as String?)?.startsWith('content://') ?? false)
        .toList(growable: false);
  }

  Future<bool> hasSeenOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(onboardingSeenKey) ?? false;
  }

  Future<void> markOnboardingSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(onboardingSeenKey, true);
  }
}
