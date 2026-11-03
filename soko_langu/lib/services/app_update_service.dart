import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'api_config.dart';

/// Server-controlled release metadata. Unpublished records never prompt.
class AppReleaseInfo {
  const AppReleaseInfo({
    required this.published,
    required this.latestVersion,
    required this.latestBuild,
    required this.minSupportedBuild,
    required this.urgency,
    required this.releaseNotes,
    required this.androidDownloadUrl,
    required this.iosDownloadUrl,
  });

  final bool published;
  final String latestVersion;
  final int latestBuild;
  final int minSupportedBuild;
  final String urgency;
  final String releaseNotes;
  final String androidDownloadUrl;
  final String iosDownloadUrl;

  factory AppReleaseInfo.fromJson(Map<String, dynamic> json) {
    return AppReleaseInfo(
      published: json['published'] == true,
      latestVersion: json['latestVersion']?.toString() ?? '',
      latestBuild: int.tryParse('${json['latestBuild']}') ?? 0,
      minSupportedBuild: int.tryParse('${json['minSupportedBuild']}') ?? 0,
      urgency: json['urgency']?.toString() ?? 'none',
      releaseNotes: json['releaseNotes']?.toString() ?? '',
      androidDownloadUrl: json['androidDownloadUrl']?.toString() ?? '',
      iosDownloadUrl: json['iosDownloadUrl']?.toString() ?? '',
    );
  }

  bool isNewerThan(int installedBuild) =>
      published && latestBuild > installedBuild;

  bool isRequiredFor(int installedBuild) =>
      published &&
      urgency == 'required' &&
      minSupportedBuild > 0 &&
      installedBuild < minSupportedBuild;
}

class AppUpdateService {
  AppUpdateService._();
  static final AppUpdateService instance = AppUpdateService._();

  static const _timeout = Duration(seconds: 8);

  AppReleaseInfo? lastFetched;

  Future<AppReleaseInfo?> fetch() async {
    try {
      final res = await http
          .get(Uri.parse(ApiConfig.v1('/admin/config/app-version')))
          .timeout(_timeout);
      if (res.statusCode != 200) return lastFetched;
      final decoded = jsonDecode(res.body);
      final data = decoded is Map && decoded['data'] is Map
          ? Map<String, dynamic>.from(decoded['data'] as Map)
          : <String, dynamic>{};
      lastFetched = AppReleaseInfo.fromJson(data);
      return lastFetched;
    } catch (e) {
      if (kDebugMode) debugPrint('[AppUpdate] fetch skipped: $e');
      return lastFetched;
    }
  }

  Future<AppReleaseInfo?> checkAgainstInstalled() async {
    final remote = await fetch();
    if (remote == null || !remote.published) return null;
    final info = await PackageInfo.fromPlatform();
    final build = int.tryParse(info.buildNumber) ?? 0;
    if (!remote.isNewerThan(build) && !remote.isRequiredFor(build)) {
      return null;
    }
    return remote;
  }
}
