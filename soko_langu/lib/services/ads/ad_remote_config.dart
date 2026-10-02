import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'ad_config.dart';
import 'ad_frequency_controller.dart';

/// Admin-controlled runtime configuration for the whole ad system.
///
/// Source of truth is the Firestore document `app_settings/ad_config`, written
/// only by the admin SDK through `PUT /api/v1/admin/config/ads`. Every field is
/// optional and every parse failure falls back to the compiled default, so a
/// partial or malformed admin edit can never take ads down or accidentally
/// enable them.
///
/// `firestore.rules` restricts `app_settings` writes to `isAdmin()`, and the
/// server route is additionally behind `authenticateAdmin`, so the config cannot
/// be changed by an ordinary client.
@immutable
class AdRemoteConfig {
  const AdRemoteConfig({
    this.adsEnabled = true,
    this.bannerEnabled = true,
    this.nativeEnabled = true,
    this.interstitialEnabled = true,
    this.rewardedEnabled = true,
    this.disabledPlacements = const {},
    this.disabledScreens = const {},
    this.adsExemptBlueTickEnabled = true,
    this.searchVerifiedBoost = 0.0,
    this.maxSearchVerifiedBoost = 0.25,
    this.allowBoostToOutrankRelevance = false,
    this.policy = AdFrequencyPolicy.defaults,
    this.version = 0,
    this.loadedAt,
  });

  final bool adsEnabled;
  final bool bannerEnabled;
  final bool nativeEnabled;
  final bool interstitialEnabled;
  final bool rewardedEnabled;

  /// Placement ids (`AdPlacement.id`) admin has switched off.
  final Set<String> disabledPlacements;

  /// Screens (`AdScreen.name`) admin has switched off.
  final Set<String> disabledScreens;

  /// Master switch for the Blue Tick ad exemption. Turning this off makes every
  /// seller see ads again regardless of verification — an emergency lever, not
  /// the default.
  final bool adsExemptBlueTickEnabled;

  /// Additive ranking boost applied to verified sellers. Expressed as a
  /// fraction of the maximum achievable relevance score so it can never
  /// outweigh relevance unless explicitly allowed.
  final double searchVerifiedBoost;

  /// Hard ceiling for [searchVerifiedBoost], enforced client-side and
  /// server-side so a mistyped admin value cannot make verification dominate.
  final double maxSearchVerifiedBoost;

  /// When false (the default) the boost is clamped inside the relevance band,
  /// which is what keeps an irrelevant result from outranking a relevant one.
  final bool allowBoostToOutrankRelevance;

  final AdFrequencyPolicy policy;

  /// Monotonic admin revision, useful in logs and in tests.
  final int version;

  final DateTime? loadedAt;

  static const String firestoreDocId = 'ad_config';

  bool isFormatEnabled(AdFormat format) => switch (format) {
        AdFormat.banner => bannerEnabled,
        AdFormat.native => nativeEnabled,
        AdFormat.interstitial => interstitialEnabled,
        AdFormat.rewarded => rewardedEnabled,
      };

  bool isScreenEnabled(AdScreen screen) =>
      !disabledScreens.contains(screen.name);

  bool isPlacementEnabled(AdPlacement placement) =>
      adsEnabled &&
      !disabledPlacements.contains(placement.id) &&
      isScreenEnabled(placement.screen) &&
      isFormatEnabled(placement.format);

  factory AdRemoteConfig.fromMap(Map<String, dynamic>? raw) {
    if (raw == null || raw.isEmpty) return const AdRemoteConfig();
    bool b(String key, bool fallback) => raw[key] is bool ? raw[key] as bool : fallback;
    // A malformed number must fall back, not throw: a partial admin edit can
    // never take the ad system down or silently switch it off.
    double d(String key, double fallback) {
      final v = raw[key];
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v) ?? fallback;
      return fallback;
    }

    int i(String key, int fallback) {
      final v = raw[key];
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? fallback;
      return fallback;
    }

    final maxBoost = d('maxSearchVerifiedBoost', 0.25).clamp(0.0, 1.0);
    final boost = d('searchVerifiedBoost', 0.0).clamp(0.0, maxBoost);

    Set<String> stringSet(String key) {
      final v = raw[key];
      if (v is List) return v.map((e) => '$e').toSet();
      if (v is Map) return v.keys.map((e) => '$e').toSet();
      return const {};
    }

    final frequencyRaw = raw['frequency'];
    final frequency = frequencyRaw is Map
        ? frequencyRaw.cast<String, dynamic>()
        : null;

    return AdRemoteConfig(
      adsEnabled: b('adsEnabled', true),
      bannerEnabled: b('bannerEnabled', true),
      nativeEnabled: b('nativeEnabled', true),
      interstitialEnabled: b('interstitialEnabled', true),
      rewardedEnabled: b('rewardedEnabled', true),
      disabledPlacements: stringSet('disabledPlacements'),
      disabledScreens: stringSet('disabledScreens'),
      adsExemptBlueTickEnabled:
          b('adsExemptBlueTickEnabled', true),
      searchVerifiedBoost: boost,
      maxSearchVerifiedBoost: maxBoost,
      allowBoostToOutrankRelevance:
          b('allowBoostToOutrankRelevance', false),
      policy: AdFrequencyPolicy.fromMap(frequency),
      version: i('version', 0),
    );
  }

  Map<String, dynamic> toMap() => {
        'adsEnabled': adsEnabled,
        'bannerEnabled': bannerEnabled,
        'nativeEnabled': nativeEnabled,
        'interstitialEnabled': interstitialEnabled,
        'rewardedEnabled': rewardedEnabled,
        'disabledPlacements': disabledPlacements.toList(),
        'disabledScreens': disabledScreens.toList(),
        'adsExemptBlueTickEnabled': adsExemptBlueTickEnabled,
        'searchVerifiedBoost': searchVerifiedBoost,
        'maxSearchVerifiedBoost': maxSearchVerifiedBoost,
        'allowBoostToOutrankRelevance': allowBoostToOutrankRelevance,
        'frequency': {
          'maxInterstitialsPerSession': policy.maxInterstitialsPerSession,
          'maxAdsPerSession': policy.maxAdsPerSession,
          'minIntervalBetweenInterstitialsMs':
              policy.minIntervalBetweenInterstitials.inMilliseconds,
          'minTimeAfterLaunchMs': policy.minTimeAfterLaunch.inMilliseconds,
          'minTimeAfterAnyAdMs': policy.minTimeAfterAnyAd.inMilliseconds,
          'minGapBetweenInlineAdsMs':
              policy.minGapBetweenInlineAds.inMilliseconds,
          'maxLoadAttemptsPerHour': policy.maxLoadAttemptsPerHour,
          'retryBackoffBaseMs': policy.retryBackoffBase.inMilliseconds,
          'maxRetryBackoffMs': policy.maxRetryBackoff.inMilliseconds,
          'dailyInterstitialCeiling': policy.dailyInterstitialCeiling,
          'gateTtlMs': policy.gateTtl.inMilliseconds,
        },
        'version': version,
      };

  /// Full copy so the admin screen can treat the config as a single immutable
  /// draft value instead of rebuilding every field by hand on each toggle.
  AdRemoteConfig copyWith({
    bool? adsEnabled,
    bool? bannerEnabled,
    bool? nativeEnabled,
    bool? interstitialEnabled,
    bool? rewardedEnabled,
    Set<String>? disabledPlacements,
    Set<String>? disabledScreens,
    bool? adsExemptBlueTickEnabled,
    double? searchVerifiedBoost,
    double? maxSearchVerifiedBoost,
    bool? allowBoostToOutrankRelevance,
    AdFrequencyPolicy? policy,
    int? version,
    DateTime? loadedAt,
  }) =>
      AdRemoteConfig(
        adsEnabled: adsEnabled ?? this.adsEnabled,
        bannerEnabled: bannerEnabled ?? this.bannerEnabled,
        nativeEnabled: nativeEnabled ?? this.nativeEnabled,
        interstitialEnabled: interstitialEnabled ?? this.interstitialEnabled,
        rewardedEnabled: rewardedEnabled ?? this.rewardedEnabled,
        disabledPlacements: disabledPlacements ?? this.disabledPlacements,
        disabledScreens: disabledScreens ?? this.disabledScreens,
        adsExemptBlueTickEnabled:
            adsExemptBlueTickEnabled ?? this.adsExemptBlueTickEnabled,
        searchVerifiedBoost: searchVerifiedBoost ?? this.searchVerifiedBoost,
        maxSearchVerifiedBoost: maxSearchVerifiedBoost ?? this.maxSearchVerifiedBoost,
        allowBoostToOutrankRelevance:
            allowBoostToOutrankRelevance ?? this.allowBoostToOutrankRelevance,
        policy: policy ?? this.policy,
        version: version ?? this.version,
        loadedAt: loadedAt ?? this.loadedAt,
      );
}

/// Streams `app_settings/ad_config` and exposes the last good value.
///
/// Offline behaviour is deliberate: on read failure the last known config is
/// kept, and on first launch with no network the compiled defaults are used.
// That means an offline device never shows ads it should not and never crashes.
class AdRemoteConfigService extends ChangeNotifier {
  AdRemoteConfigService({FirebaseFirestore? firestore}) : _injected = firestore;

  final FirebaseFirestore? _injected;
  FirebaseFirestore? _db;

  /// Resolved lazily so constructing the service never touches Firebase. Tests
  /// exercise the config purely through [overrideForTesting].
  FirebaseFirestore get _firestore => _db ??= _injected ?? FirebaseFirestore.instance;

  AdRemoteConfig _config = const AdRemoteConfig();
  AdRemoteConfig get config => _config;

  bool _loadedOnce = false;
  bool get hasLoaded => _loadedOnce;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;

  /// Loads once, then keeps listening so an admin change reaches connected
  /// devices without a Play Store release.
  Future<void> start() async {
    if (_sub != null) return;
    try {
      _sub = _firestore
          .collection('app_settings')
          .doc(AdRemoteConfig.firestoreDocId)
          .snapshots()
          .listen((snap) {
        _loadedOnce = true;
        final next = AdRemoteConfig.fromMap(snap.data());
        if (next.version == _config.version &&
            next.adsEnabled == _config.adsEnabled &&
            next.disabledPlacements.length ==
                _config.disabledPlacements.length) {
          return;
        }
        _config = next;
        notifyListeners();
      }, onError: (Object _) {
        // Denied or offline: keep the compiled defaults / last good value.
        _loadedOnce = true;
        notifyListeners();
      });
    } catch (_) {
      _loadedOnce = true;
      notifyListeners();
    }
  }

  /// Applies a config value immediately, ahead of the Firestore stream.
  ///
  /// Used by the admin screen for the optimistic preview after a successful
  /// server write, so the admin's own device reflects the change without
  /// waiting for the round-trip. The stream reconciles it moments later.
  void applyOptimistic(AdRemoteConfig next) {
    _config = next;
    _loadedOnce = true;
    notifyListeners();
  }

  /// Replaces the live config in memory. Used by tests, which have no Firestore.
  @visibleForTesting
  void overrideForTesting(AdRemoteConfig next) {
    _config = next;
    _loadedOnce = true;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }
}
