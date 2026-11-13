import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

enum ErrorSeverity {
  info,
  warning,
  error,
  critical,
}

class ErrorReport {
  final String errorId;
  final DateTime timestamp;
  final String environment;
  final ErrorSeverity severity;
  final String errorType;
  final String errorMessage;
  final String? sanitizedTechnicalError;
  final String? stackTrace;
  final String? apiEndpoint;
  final int? httpStatus;
  final String? requestMethod;
  final String? feature;
  final String? screen;
  final String? userId;
  final String? appVersion;
  final String? buildNumber;
  final String? platform;
  final String? osVersion;
  final String? deviceModel;
  final String? networkState;
  final String? locale;
  final String? currentRoute;
  final String? requestId;
  final String? correlationId;
  final String? backendService;
  final String? databaseService;
  final Map<String, dynamic>? extraData;

  ErrorReport({
    required this.errorId,
    required this.timestamp,
    required this.environment,
    required this.severity,
    required this.errorType,
    required this.errorMessage,
    this.sanitizedTechnicalError,
    this.stackTrace,
    this.apiEndpoint,
    this.httpStatus,
    this.requestMethod,
    this.feature,
    this.screen,
    this.userId,
    this.appVersion,
    this.buildNumber,
    this.platform,
    this.osVersion,
    this.deviceModel,
    this.networkState,
    this.locale,
    this.currentRoute,
    this.requestId,
    this.correlationId,
    this.backendService,
    this.databaseService,
    this.extraData,
  });

  Map<String, dynamic> toMap() {
    return {
      'errorId': errorId,
      'timestamp': Timestamp.fromDate(timestamp),
      'environment': environment,
      'severity': severity.name,
      'errorType': errorType,
      'errorMessage': errorMessage,
      'sanitizedTechnicalError': sanitizedTechnicalError,
      'stackTrace': stackTrace,
      'apiEndpoint': apiEndpoint,
      'httpStatus': httpStatus,
      'requestMethod': requestMethod,
      'feature': feature,
      'screen': screen,
      'userId': userId,
      'appVersion': appVersion,
      'buildNumber': buildNumber,
      'platform': platform,
      'osVersion': osVersion,
      'deviceModel': deviceModel,
      'networkState': networkState,
      'locale': locale,
      'currentRoute': currentRoute,
      'requestId': requestId,
      'correlationId': correlationId,
      'backendService': backendService,
      'databaseService': databaseService,
      'extraData': extraData,
      'status': 'Open',
      'occurrenceCount': 1,
      'firstSeen': Timestamp.fromDate(timestamp),
      'lastSeen': Timestamp.fromDate(timestamp),
    };
  }
}

class ErrorReportingService {
  static final ErrorReportingService _instance = ErrorReportingService._internal();
  factory ErrorReportingService() => _instance;
  ErrorReportingService._internal();

  // Resolved lazily: `FirebaseFirestore.instance` throws when Firebase has not
  // finished initializing, and this singleton is constructed from catch blocks
  // and error paths that can run before (or without) init. A field initializer
  // would turn a reporting failure into a second, harder failure.
  FirebaseFirestore? _firestoreOrNull;
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  FirebaseFirestore? get _firestore => _firestoreOrNull ??= _tryFirestore();

  static FirebaseFirestore? _tryFirestore() {
    try {
      return FirebaseFirestore.instance;
    } catch (_) {
      return null;
    }
  }

  String? _lastErrorId;

  String? get lastErrorId => _lastErrorId;

  Future<String> reportError({
    required dynamic error,
    required String userMessage,
    ErrorSeverity severity = ErrorSeverity.error,
    String? feature,
    String? screen,
    String? apiEndpoint,
    int? httpStatus,
    String? requestMethod,
    String? stackTrace,
    Map<String, dynamic>? extraData,
  }) async {
    try {
      final report = await _buildReport(
        error: error,
        userMessage: userMessage,
        severity: severity,
        feature: feature,
        screen: screen,
        apiEndpoint: apiEndpoint,
        httpStatus: httpStatus,
        requestMethod: requestMethod,
        stackTrace: stackTrace,
        extraData: extraData,
      );
      await _sendReport(report);
      _lastErrorId = report.errorId;
      return report.errorId;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to report error: $e');
      }
      return '';
    }
  }

  Future<ErrorReport> _buildReport({
    required dynamic error,
    required String userMessage,
    required ErrorSeverity severity,
    String? feature,
    String? screen,
    String? apiEndpoint,
    int? httpStatus,
    String? requestMethod,
    String? stackTrace,
    Map<String, dynamic>? extraData,
  }) async {
    final packageInfo = await PackageInfo.fromPlatform();
    final user = FirebaseAuth.instance.currentUser;
    final env = kDebugMode ? 'debug' : 'production';
    String platform = 'unknown';
    String? osVersion;
    String? deviceModel;

    try {
      if (Platform.isAndroid) {
        final info = await _deviceInfo.androidInfo;
        platform = 'android';
        osVersion = info.version.release;
        deviceModel = '${info.brand} ${info.model}';
      } else if (Platform.isIOS) {
        final info = await _deviceInfo.iosInfo;
        platform = 'ios';
        osVersion = info.systemVersion;
        deviceModel = info.utsname.machine;
      }
    } catch (_) {}

    final errorId = 'SV-${DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase()}${(DateTime.now().microsecond % 1000).toString().padLeft(3, '0')}';

    String sanitizedTech = error.toString();
    if (sanitizedTech.length > 1000) {
      sanitizedTech = sanitizedTech.substring(0, 1000);
    }
    sanitizedTech = _sanitize(sanitizedTech);

    return ErrorReport(
      errorId: errorId,
      timestamp: DateTime.now(),
      environment: env,
      severity: severity,
      errorType: error.runtimeType.toString(),
      errorMessage: userMessage,
      sanitizedTechnicalError: sanitizedTech,
      stackTrace: stackTrace != null ? _sanitize(stackTrace) : null,
      apiEndpoint: _sanitize(apiEndpoint),
      httpStatus: httpStatus,
      requestMethod: requestMethod,
      feature: feature,
      screen: screen,
      userId: user?.uid,
      appVersion: packageInfo.version,
      buildNumber: packageInfo.buildNumber,
      platform: platform,
      osVersion: osVersion,
      deviceModel: deviceModel,
      locale: Platform.localeName,
      extraData: extraData != null ? _sanitizeMap(extraData) : null,
    );
  }

  String _generateFingerprint(ErrorReport report) {
    final parts = [
      report.feature ?? 'unknown',
      report.errorType,
      report.apiEndpoint ?? 'unknown',
      report.errorMessage.length > 100 ? report.errorMessage.substring(0, 100) : report.errorMessage,
    ];
    return parts.join('|');
  }

  // ── Flood control ────────────────────────────────────────
  //
  // `FlutterError.onError` fires ONCE PER FRAME for a build error, so a layout
  // overflow or a bad setState in a timer produced ~60 reports/second, each one
  // doing a Firestore READ plus a WRITE. That is how a client-side bug turns into
  // a Firestore bill, and it also means the error signal was drowned by its own
  // volume.
  //
  // Three limits, applied before any network call:
  //   1. per-fingerprint rate limit (5 reports / 10 min) — the count is still
  //      incremented so frequency is visible,
  //   2. global ceiling (50 distinct fingerprints) so 50 different errors cannot
  //      bypass the per-fingerprint limit,
  //   3. a single in-flight send, because overlapping reports used to race on
  //      the same dedupe query.
  static const Duration _fingerprintWindow = Duration(minutes: 10);
  static const int _fingerprintBudget = 5;
  static const int _globalFingerprintCap = 50;

  final Map<String, List<DateTime>> _recentByFingerprint = {};
  final List<String> _recentOrder = [];
  bool _sending = false;
  final List<ErrorReport> _pending = [];

  /// True when this fingerprint has already been reported [budget] times inside
  /// the window. Counts the occurrence locally so the suppression is visible.
  bool _consumeBudget(String fingerprint) {
    final now = DateTime.now();
    final hits = _recentByFingerprint[fingerprint] ?? [];
    final cutoff = now.subtract(_fingerprintWindow);
    final recent = hits.where((t) => t.isAfter(cutoff)).toList();

    if (_recentOrder.length >= _globalFingerprintCap) {
      _recentOrder.removeAt(0);
    }
    if (!_recentByFingerprint.containsKey(fingerprint)) {
      _recentOrder.add(fingerprint);
    }

    if (recent.length >= _fingerprintBudget) {
      _recentByFingerprint[fingerprint] = recent;
      return false;
    }

    recent.add(now);
    _recentByFingerprint[fingerprint] = recent;
    return true;
  }

  /// Drops fingerprints whose most recent hit has aged out, so the maps cannot
  /// grow without bound across a long session.
  void _sweepFingerprints() {
    final cutoff = DateTime.now().subtract(_fingerprintWindow);
    _recentByFingerprint.removeWhere((_, hits) {
      if (hits.isEmpty) return true;
      return !hits.last.isAfter(cutoff);
    });
    _recentOrder.removeWhere(
      (f) => !_recentByFingerprint.containsKey(f),
    );
  }

  Future<void> _sendReport(ErrorReport report) async {
    // No Firebase (startup race, offline-only path, unit test): reporting is
    // best-effort by design, so drop the report rather than throw into the
    // caller that was already handling an error.
    if (_firestore == null) return;

    final fingerprint = _generateFingerprint(report);
    if (!_consumeBudget(fingerprint)) {
      // Suppressed locally. The occurrence is still counted in the local budget,
      // so a genuine spike shows up as "stopped reporting" rather than silence.
      return;
    }

    // Serialise sends. Previously N concurrent reports all ran the same
    // read-then-write dedupe, so the first occurrence produced N duplicate docs.
    if (_sending) {
      if (_pending.length < 20) _pending.add(report);
      return;
    }
    _sending = true;
    try {
      do {
        await _persist(report);
        _sweepFingerprints();
        if (_pending.isEmpty) break;
        report = _pending.removeAt(0);
      } while (_pending.isNotEmpty);
    } finally {
      _sending = false;
      if (_pending.isNotEmpty) {
        final rest = _pending.toList();
        _pending.clear();
        for (final r in rest) {
          unawaited(_sendReport(r));
        }
      }
    }
  }

  Future<void> _persist(ErrorReport report) async {
    final firestore = _firestore!;
    try {
      final fingerprint = _generateFingerprint(report);
      // Deterministic document id keyed on the fingerprint. The old code did
      // read(fingerprint) → decide → write, which is not atomic: two reports
      // that raced both saw "no doc" and both created one, and every report cost
      // a Firestore READ. A merged set against a deterministic id is a single
      // write, and FieldValue.increment keeps occurrenceCount accurate without
      // the read.
      final ref = firestore
          .collection('system_errors')
          .doc(fingerprint.hashCode.abs().toRadixString(16));
      await ref.set({
        ...report.toMap(),
        'fingerprint': fingerprint,
        'occurrenceCount': FieldValue.increment(1),
        'lastSeen': Timestamp.fromDate(DateTime.now()),
        'status': 'Open',
      }, SetOptions(merge: true));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to send report: $e');
      }
    }
  }

  String _sanitize(String? input) {
    if (input == null) return '';
    String s = input;
    s = s.replaceAll(RegExp(r'password[=:]\s*\S+', caseSensitive: false), 'password=[REDACTED]');
    s = s.replaceAll(RegExp(r'token[=:]\s*\S+', caseSensitive: false), 'token=[REDACTED]');
    s = s.replaceAll(RegExp(r'key[=:]\s*\S+', caseSensitive: false), 'key=[REDACTED]');
    s = s.replaceAll(RegExp(r'authorization[=:]\s*\S+', caseSensitive: false), 'authorization=[REDACTED]');
    s = s.replaceAll(RegExp(r'bearer\s+\S+', caseSensitive: false), 'bearer [REDACTED]');
    return s;
  }

  Map<String, dynamic> _sanitizeMap(Map<String, dynamic> data) {
    final result = <String, dynamic>{};
    for (final entry in data.entries) {
      final key = entry.key.toLowerCase();
      if (key.contains('password') || key.contains('token') || key.contains('secret') || key.contains('key') || key.contains('otp') || key.contains('card') || key.contains('credential')) {
        result[entry.key] = '[REDACTED]';
      } else if (entry.value is String) {
        result[entry.key] = _sanitize(entry.value as String);
      } else if (entry.value is Map<String, dynamic>) {
        result[entry.key] = _sanitizeMap(entry.value as Map<String, dynamic>);
      } else {
        result[entry.key] = entry.value;
      }
    }
    return result;
  }
}
