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

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

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

  Future<void> _sendReport(ErrorReport report) async {
    try {
      final fingerprint = _generateFingerprint(report);
      final existing = await _firestore
          .collection('system_errors')
          .where('fingerprint', isEqualTo: fingerprint)
          .limit(1)
          .get();
      if (existing.docs.isNotEmpty) {
        final doc = existing.docs.first;
        final data = doc.data();
        final count = (data['occurrenceCount'] as int? ?? 1) + 1;
        await doc.reference.update({
          'occurrenceCount': count,
          'lastSeen': Timestamp.fromDate(DateTime.now()),
          'status': 'Open',
        });
      } else {
        await _firestore.collection('system_errors').add({
          ...report.toMap(),
          'fingerprint': fingerprint,
        });
      }
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
