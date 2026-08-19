import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/consent_record.dart';
import 'api_config.dart';
import 'package:http/http.dart' as http;

/// Captures clickwrap evidence and persists it to Firestore + server.
///
/// Evidence fields follow the legal requirements for a Clickwrap Agreement
/// as established under the Tanzania PDPA 2022, Section 23 (consent must be
/// specific, informed, and freely given).
class ConsentRecordingService {
  ConsentRecordingService._();
  static final instance = ConsentRecordingService._();

  /// Current document versions — increment on every substantive change.
  static const tosVersion = 'ToS_v2.0';
  static const ppVersion = 'PP_v2.0';

  final _db = FirebaseFirestore.instance;

  /// Records the user's consent event and persists it.
  ///
  /// Call this after the user checks the consent box AND successfully registers.
  Future<void> recordConsent(String userId) async {
    final deviceInfo = await _getDeviceInfo();
    final packageInfo = await PackageInfo.fromPlatform();

    final record = ConsentRecord(
      userId: userId,
      deviceId: deviceInfo['deviceId'],
      acceptedAt: DateTime.now().toUtc(),
      tosVersion: tosVersion,
      ppVersion: ppVersion,
      explicitAction: 'Checked_Consent_Box_and_Clicked_Register',
      deviceInfo: '${deviceInfo['os']} ${deviceInfo['osVersion']} | ${deviceInfo['model']}',
      platform: defaultTargetPlatform == TargetPlatform.android ? 'android' : 'ios',
      appVersion: packageInfo.version,
    );

    // Fire-and-forget both writes — consent is already captured in the
    // local Firestore write; server is for server-side audit trail.
    _writeToFirestore(userId, record);
    _sendToServer(record);
  }

  /// Persists consent record to Firestore for direct querying.
  Future<void> _writeToFirestore(String userId, ConsentRecord record) async {
    try {
      await _db.collection('consentRecords').doc(userId).set({
        ...record.toJson(),
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // Never block registration on consent logging failure
      debugPrint('ConsentRecording: Firestore write failed: $e');
    }
  }

  /// Sends consent evidence to server for tamper-evident logging.
  Future<void> _sendToServer(ConsentRecord record) async {
    try {
      await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/consent/record'),
        headers: {'Content-Type': 'application/json'},
        body: record.toJsonString(),
      ).timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('ConsentRecording: Server write failed: $e');
    }
  }

  /// Captures device fingerprint for the consent record.
  Future<Map<String, String>> _getDeviceInfo() async {
    final plugin = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        final android = await plugin.androidInfo;
        return {
          'os': 'Android',
          'osVersion': android.version.release,
          'model': '${android.manufacturer} ${android.model}',
          'deviceId': android.id,
        };
      } else if (Platform.isIOS) {
        final ios = await plugin.iosInfo;
        return {
          'os': 'iOS',
          'osVersion': ios.systemVersion,
          'model': ios.model,
          'deviceId': ios.identifierForVendor ?? 'unknown',
        };
      }
    } catch (_) {}
    return {
      'os': defaultTargetPlatform.name,
      'osVersion': 'unknown',
      'model': 'unknown',
      'deviceId': 'unknown',
    };
  }
}
