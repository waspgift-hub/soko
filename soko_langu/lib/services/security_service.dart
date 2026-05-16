import 'dart:io';
import 'package:flutter/foundation.dart';

class SecurityService {
  static final SecurityService _instance = SecurityService._();
  factory SecurityService() => _instance;
  SecurityService._();

  bool _initialized = false;
  bool? _isDeviceSecure;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _isDeviceSecure = await _checkDeviceSecurity();
    if (_isDeviceSecure == false) {
      debugPrint('SECURITY: Device appears compromised!');
    }
  }

  bool get isDeviceSecure => _isDeviceSecure ?? true;

  Future<bool> _checkDeviceSecurity() async {
    if (kIsWeb) return true;

    try {
      if (Platform.isAndroid) {
        if (_hasKnownRootPackages()) return false;
        if (_isEmulator()) return false;
      }
      if (Platform.isIOS) {
        if (_isJailbroken()) return false;
      }
      if (kDebugMode) return false;
      return true;
    } catch (e) {
      debugPrint('Security checkDevice: $e');
      return true;
    }
  }

  bool _hasKnownRootPackages() {
    try {
      final paths = [
        '/system/app/Superuser.apk',
        '/sbin/su',
        '/system/bin/su',
        '/system/xbin/su',
        '/data/local/xbin/su',
        '/data/local/bin/su',
        '/system/sd/xbin/su',
        '/system/bin/failsafe/su',
        '/data/local/su',
      ];
      for (final path in paths) {
        if (File(path).existsSync()) return true;
      }
    } catch (e) {
      debugPrint('Security rootPackages: $e');
    }
    return false;
  }

  bool _isEmulator() {
    try {
      if (Platform.isAndroid) {
        final props = <String>['goldfish', 'ranchu', 'generic'];
        final hardware = _readProp('ro.hardware');
        final bootloader = _readProp('ro.bootloader');
        for (final p in props) {
          if (hardware.contains(p) || bootloader.contains(p)) return true;
        }
      }
    } catch (e) {
      debugPrint('Security isEmulator: $e');
    }
    return false;
  }

  bool _isJailbroken() {
    try {
      final paths = [
        '/Applications/Cydia.app',
        '/Library/MobileSubstrate/MobileSubstrate.dylib',
        '/bin/bash',
        '/usr/sbin/sshd',
        '/etc/apt',
        '/private/var/lib/apt',
      ];
      for (final path in paths) {
        if (File(path).existsSync()) return true;
      }
    } catch (e) {
      debugPrint('Security isJailbroken: $e');
    }
    return false;
  }

  String _readProp(String name) {
    try {
      final result = Process.runSync('getprop', [name]);
      return result.stdout.toString().trim();
    } catch (e) {
      debugPrint('Security readProp: $e');
      return '';
    }
  }

  bool get isDebugMode => kDebugMode;
}
