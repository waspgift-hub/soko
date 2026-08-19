import 'dart:convert';

/// Immutable record of a user's clickwrap consent event.
///
/// Stored in Firestore under `consentRecords/{uid}` and sent to the server
/// for tamper-evident logging. Designed as litigation-grade evidence under
/// the Tanzania PDPA 2022 (Section 23 — lawful basis: consent).
class ConsentRecord {
  final String userId;
  final String? deviceId;
  final DateTime acceptedAt;
  final String? ipAddress;
  final String tosVersion;
  final String ppVersion;
  final String explicitAction;
  final String deviceInfo;
  final String platform;
  final String appVersion;

  const ConsentRecord({
    required this.userId,
    this.deviceId,
    required this.acceptedAt,
    this.ipAddress,
    required this.tosVersion,
    required this.ppVersion,
    required this.explicitAction,
    required this.deviceInfo,
    required this.platform,
    required this.appVersion,
  });

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'deviceId': deviceId,
    'acceptedAt': acceptedAt.toUtc().toIso8601String(),
    'ipAddress': ipAddress,
    'tosVersion': tosVersion,
    'ppVersion': ppVersion,
    'explicitAction': explicitAction,
    'deviceInfo': deviceInfo,
    'platform': platform,
    'appVersion': appVersion,
  };

  String toJsonString() => jsonEncode(toJson());

  factory ConsentRecord.fromJson(Map<String, dynamic> json) {
    return ConsentRecord(
      userId: json['userId'] as String,
      deviceId: json['deviceId'] as String?,
      acceptedAt: DateTime.parse(json['acceptedAt'] as String),
      ipAddress: json['ipAddress'] as String?,
      tosVersion: json['tosVersion'] as String,
      ppVersion: json['ppVersion'] as String,
      explicitAction: json['explicitAction'] as String,
      deviceInfo: json['deviceInfo'] as String,
      platform: json['platform'] as String,
      appVersion: json['appVersion'] as String,
    );
  }
}
