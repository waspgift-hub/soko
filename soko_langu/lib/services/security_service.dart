import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

class SecurityService {
  static final SecurityService _instance = SecurityService._();
  factory SecurityService() => _instance;
  SecurityService._();

  bool _initialized = false;
  bool? _isDeviceSecure;

  /// Whether the emulator/root checks already ran, so heavy checks (subprocess
  /// spawn) happen once per process rather than on every initialize() call.
  bool _emulatorResolved = false;
  bool _emulatorResult = false;

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
        if (await _isEmulator()) return false;
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

  Future<bool> _isEmulator() async {
    // Once it's resolved, cache it — getprop subprocess spawn is expensive.
    if (_emulatorResolved) return _emulatorResult;
    try {
      if (Platform.isAndroid) {
        final props = <String>['goldfish', 'ranchu', 'generic'];
        final hardware = await _readProp('ro.hardware');
        final bootloader = await _readProp('ro.bootloader');
        _emulatorResult = props.any(
          (p) => hardware.contains(p) || bootloader.contains(p),
        );
      }
    } catch (e) {
      debugPrint('Security isEmulator: $e');
    }
    _emulatorResolved = true;
    return _emulatorResult;
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

  /// Reads a system property WITHOUT blocking the main isolate. A sync
  /// Process.runSync here stalls the UI (ANR on Android) while the shell
  /// spawns, so we spawn async and hard-cap the wait at 2s.
  Future<String> _readProp(String name) async {
    try {
      final process = await Process.start('getprop', [name]);
      final out = await process.stdout
          .transform(const Utf8Decoder())
          .join()
          .timeout(const Duration(seconds: 2), onTimeout: () {
        process.kill();
        return '';
      });
      await process.exitCode.timeout(const Duration(seconds: 2), onTimeout: () {
        process.kill();
        return -1;
      });
      return out.trim();
    } catch (e) {
      debugPrint('Security readProp: $e');
      return '';
    }
  }

  bool get isDebugMode => kDebugMode;
}
