import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ad_config.dart';

/// Every tunable frequency number lives here. Remote config may override these
/// at runtime (see `ad_remote_config.dart`), but the compiled defaults are the
/// floor and the only values used when the remote document is absent, unreadable
/// or offline.
@immutable
class AdFrequencyPolicy {
  const AdFrequencyPolicy({
    this.maxInterstitialsPerSession = 4,
    this.maxAdsPerSession = 12,
    this.minIntervalBetweenInterstitials = const Duration(minutes: 5),
    this.minTimeAfterLaunch = const Duration(minutes: 2),
    this.minTimeAfterAnyAd = const Duration(minutes: 2),
    this.minGapBetweenInlineAds = const Duration(seconds: 45),
    this.maxLoadAttemptsPerHour = 12,
    this.retryBackoffBase = const Duration(seconds: 45),
    this.maxRetryBackoff = const Duration(minutes: 15),
    this.dailyInterstitialCeiling = 20,
    this.gateTtl = const Duration(days: 30),
  });

  final int maxInterstitialsPerSession;
  final int maxAdsPerSession;
  final Duration minIntervalBetweenInterstitials;
  final Duration minTimeAfterLaunch;
  final Duration minTimeAfterAnyAd;
  final Duration minGapBetweenInlineAds;
  final int maxLoadAttemptsPerHour;
  final Duration retryBackoffBase;
  final Duration maxRetryBackoff;
  final int dailyInterstitialCeiling;
  final Duration gateTtl;

  AdFrequencyPolicy copyWith({
    int? maxInterstitialsPerSession,
    int? maxAdsPerSession,
    Duration? minIntervalBetweenInterstitials,
    Duration? minTimeAfterLaunch,
    Duration? minTimeAfterAnyAd,
    Duration? minGapBetweenInlineAds,
    int? maxLoadAttemptsPerHour,
    Duration? retryBackoffBase,
    Duration? maxRetryBackoff,
    int? dailyInterstitialCeiling,
    Duration? gateTtl,
  }) =>
      AdFrequencyPolicy(
        maxInterstitialsPerSession: maxInterstitialsPerSession ??
            this.maxInterstitialsPerSession,
        maxAdsPerSession: maxAdsPerSession ?? this.maxAdsPerSession,
        minIntervalBetweenInterstitials: minIntervalBetweenInterstitials ??
            this.minIntervalBetweenInterstitials,
        minTimeAfterLaunch: minTimeAfterLaunch ?? this.minTimeAfterLaunch,
        minTimeAfterAnyAd: minTimeAfterAnyAd ?? this.minTimeAfterAnyAd,
        minGapBetweenInlineAds:
            minGapBetweenInlineAds ?? this.minGapBetweenInlineAds,
        maxLoadAttemptsPerHour:
            maxLoadAttemptsPerHour ?? this.maxLoadAttemptsPerHour,
        retryBackoffBase: retryBackoffBase ?? this.retryBackoffBase,
        maxRetryBackoff: maxRetryBackoff ?? this.maxRetryBackoff,
        dailyInterstitialCeiling:
            dailyInterstitialCeiling ?? this.dailyInterstitialCeiling,
        gateTtl: gateTtl ?? this.gateTtl,
      );

  static const AdFrequencyPolicy defaults = AdFrequencyPolicy();

  static Duration _dur(dynamic v, Duration fallback) {
    if (v is num) return Duration(milliseconds: v.toInt() < 0 ? 0 : v.toInt());
    if (v is String) {
      final parsed = int.tryParse(v);
      if (parsed == null || parsed < 0) return fallback;
      return Duration(milliseconds: parsed);
    }
    return fallback;
  }

  static int _int(dynamic v, int fallback) {
    if (v is num) return v.toInt() < 0 ? fallback : v.toInt();
    if (v is String) {
      final parsed = int.tryParse(v);
      if (parsed == null || parsed < 0) return fallback;
      return parsed;
    }
    return fallback;
  }

  /// Parses the remote override map. Unknown or malformed keys fall back to the
  /// compiled default so a partial admin edit can never produce a null policy.
  factory AdFrequencyPolicy.fromMap(Map<String, dynamic>? raw) {
    if (raw == null || raw.isEmpty) return defaults;
    return AdFrequencyPolicy(
      maxInterstitialsPerSession: _int(
          raw['maxInterstitialsPerSession'],
          defaults.maxInterstitialsPerSession),
      maxAdsPerSession:
          _int(raw['maxAdsPerSession'], defaults.maxAdsPerSession),
      minIntervalBetweenInterstitials: _dur(
          raw['minIntervalBetweenInterstitialsMs'],
          defaults.minIntervalBetweenInterstitials),
      minTimeAfterLaunch: _dur(
          raw['minTimeAfterLaunchMs'], defaults.minTimeAfterLaunch),
      minTimeAfterAnyAd:
          _dur(raw['minTimeAfterAnyAdMs'], defaults.minTimeAfterAnyAd),
      minGapBetweenInlineAds: _dur(
          raw['minGapBetweenInlineAdsMs'], defaults.minGapBetweenInlineAds),
      maxLoadAttemptsPerHour: _int(
          raw['maxLoadAttemptsPerHour'], defaults.maxLoadAttemptsPerHour),
      retryBackoffBase:
          _dur(raw['retryBackoffBaseMs'], defaults.retryBackoffBase),
      maxRetryBackoff:
          _dur(raw['maxRetryBackoffMs'], defaults.maxRetryBackoff),
      dailyInterstitialCeiling: _int(
          raw['dailyInterstitialCeiling'], defaults.dailyInterstitialCeiling),
      gateTtl: _dur(raw['gateTtlMs'], defaults.gateTtl),
    );
  }
}

/// Why a fullscreen ad was not shown. Surfaced in debug builds so a placement
/// that silently never fires can be diagnosed from the log.
enum AdSuppressionReason {
  adsDisabled,
  ineligibleUser,
  criticalFlow,
  screenNotAllowed,
  placementDisabled,
  sdkNotReady,
  notLoaded,
  sessionCap,
  dailyCap,
  intervalNotElapsed,
  afterLaunchGrace,
  afterAnyAdGap,
  backoff,
  alreadyShowing,
}

/// Outcome of a frequency/eligibility decision. [allowed] is the only field the
/// AdManager branches on; [reason] and [retryAfter] exist for diagnostics.
@immutable
class AdDecision {
  const AdDecision.allow()
      : allowed = true,
        reason = null,
        until = null;
  const AdDecision.deny(this.reason, {this.until}) : allowed = false;

  final bool allowed;
  final AdSuppressionReason? reason;
  final DateTime? until;

  @override
  String toString() =>
      allowed ? 'AdDecision.allow' : 'AdDecision.deny(${reason!.name})';
}

/// Centralized, persisted frequency control for every ad format.
///
/// Design rules:
/// * Session counters are in-memory and reset by [beginSession]; wall-clock
///   caps are persisted so force-quitting the app cannot reset them.
/// * All persisted state is namespaced by account uid. [adoptAccount] wipes the
///   namespace when the signed-in user changes, so a second account on the same
///   device never inherits the previous account's session.
/// * Load failures apply exponential backoff per placement id instead of the
///   old unconditional 15-second retry loop, which could hammer the SDK four
///   times a minute forever when there was no fill.
class AdFrequencyController extends ChangeNotifier {
  AdFrequencyController({SharedPreferences? prefs, AdFrequencyPolicy? policy})
      : _injectedPrefs = prefs,
        _policy = policy ?? AdFrequencyPolicy.defaults;

  static const String _prefix = 'adfreq.v1';

  SharedPreferences? _injectedPrefs;
  SharedPreferences? _prefs;
  bool _ready = false;
  AdFrequencyPolicy _policy;

  DateTime? _sessionStartedAt;
  int _sessionInterstitials = 0;
  int _sessionAds = 0;

  /// Owner of the persisted counters. Null means signed out.
  String? _accountId;

  /// Write-through mirror of persisted timestamps.
  ///
  /// Writes to SharedPreferences are `unawaited`, so a synchronous read right
  /// after a write would see `null`. That let a banner slot re-request a
  /// creative on the very next rebuild and bypass its own backoff. Persistence
  /// remains the source of truth across restarts; this only makes
  /// read-after-write consistent.
  final Map<String, DateTime> _timeCache = {};

  /// Write-through mirror of the persisted integer counters, for the same
  /// read-after-write reason as [_timeCache].
  final Map<String, int> _intCache = {};

  int _readInt(String key, [int fallback = 0]) =>
      _intCache[_ns(key)] ?? _prefs?.getInt(_ns(key)) ?? fallback;

  void _writeInt(String key, int value) {
    final namespaced = _ns(key);
    _intCache[namespaced] = value;
    unawaited(_prefs?.setInt(namespaced, value));
  }

  void _clearInt(String key) {
    _intCache.remove(_ns(key));
    unawaited(_prefs?.remove(_ns(key)));
  }

  String _ns(String key) =>
      _accountId == null ? '$_prefix.guest.$key' : '$_prefix.$_accountId.$key';

  AdFrequencyPolicy get policy => _policy;

  void updatePolicy(AdFrequencyPolicy next) {
    if (identical(next, _policy)) return;
    _policy = next;
    notifyListeners();
  }

  Future<void> _ensureReady() async {
    if (_ready) return;
    _prefs = _injectedPrefs ?? await SharedPreferences.getInstance();
    _ready = true;
  }

  /// Called once per app launch. Resets session counters and re-reads the
  /// persisted wall-clock state.
  Future<void> beginSession({DateTime? now}) async {
    await _ensureReady();
    _sessionStartedAt = now ?? DateTime.now();
    _sessionInterstitials = 0;
    _sessionAds = 0;
    notifyListeners();
  }

  /// Switches the persisted-counter namespace, clearing in-memory counters so a
  /// different account starts from a clean slate.
  Future<void> adoptAccount(String? uid) async {
    if (uid == _accountId) return;
    await _ensureReady();
    _accountId = uid;
    // The namespace changes, so every cached timestamp is now stale.
    _timeCache.clear();
    _sessionInterstitials = 0;
    _sessionAds = 0;
    notifyListeners();
  }

  int get sessionInterstitials => _sessionInterstitials;
  int get sessionAds => _sessionAds;

  DateTime? _readTime(String key) {
    final namespaced = _ns(key);
    final cached = _timeCache[namespaced];
    if (cached != null) return cached;
    final ms = _prefs?.getInt(namespaced);
    if (ms == null) return null;
    final value = DateTime.fromMillisecondsSinceEpoch(ms);
    _timeCache[namespaced] = value;
    return value;
  }

  void _writeTime(String key, DateTime value) {
    final namespaced = _ns(key);
    _timeCache[namespaced] = value;
    unawaited(_prefs?.setInt(namespaced, value.millisecondsSinceEpoch));
  }

  void _clearTime(String key) {
    _timeCache.remove(_ns(key));
    unawaited(_prefs?.remove(_ns(key)));
  }

  String _dayStamp(DateTime now) =>
      '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

  int _dailyCount(DateTime now) {
    final prefs = _prefs;
    if (prefs == null) return 0;
    if (prefs.getString(_ns('dayStamp')) != _dayStamp(now)) return 0;
    return prefs.getInt(_ns('dayCount')) ?? 0;
  }

  /// Decides whether a fullscreen ad may be shown for [placement] right now.
  ///
  /// Order matters: capability and eligibility are checked before frequency so a
  /// Blue Tick seller is excluded before any counter is touched.
  AdDecision canShowFullscreen({
    required AdPlacement placement,
    required bool adsEnabled,
    required bool userEligible,
    required bool sdkReady,
    bool adLoaded = false,
    required String? currentRoute,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();

    // Critical flow first: it is the strongest statement and the clearest reason,
    // regardless of why else the user might be excluded.
    if (isAdCriticalRoute(currentRoute)) {
      return const AdDecision.deny(AdSuppressionReason.criticalFlow);
    }
    if (!adsEnabled) {
      return const AdDecision.deny(AdSuppressionReason.adsDisabled);
    }
    if (!userEligible) {
      return const AdDecision.deny(AdSuppressionReason.ineligibleUser);
    }
    if (!interstitialCapableScreens.contains(placement.screen)) {
      return const AdDecision.deny(AdSuppressionReason.screenNotAllowed);
    }
    if (!sdkReady) {
      return const AdDecision.deny(AdSuppressionReason.sdkNotReady);
    }

    final backoffUntil = _readTime('backoff.${placement.id}');
    if (backoffUntil != null && at.isBefore(backoffUntil)) {
      return AdDecision.deny(AdSuppressionReason.backoff, until: backoffUntil);
    }

    if (!adLoaded) {
      return const AdDecision.deny(AdSuppressionReason.notLoaded);
    }

    if (_sessionInterstitials >= _policy.maxInterstitialsPerSession) {
      return const AdDecision.deny(AdSuppressionReason.sessionCap);
    }
    if (_sessionAds >= _policy.maxAdsPerSession) {
      return const AdDecision.deny(AdSuppressionReason.sessionCap);
    }
    if (_dailyCount(at) >= _policy.dailyInterstitialCeiling) {
      return const AdDecision.deny(AdSuppressionReason.dailyCap);
    }

    final launched = _sessionStartedAt;
    if (launched == null ||
        at.difference(launched) < _policy.minTimeAfterLaunch) {
      return AdDecision.deny(
        AdSuppressionReason.afterLaunchGrace,
        until: launched?.add(_policy.minTimeAfterLaunch),
      );
    }

    final lastAny = _readTime('lastAnyAd');
    if (lastAny != null && at.difference(lastAny) < _policy.minTimeAfterAnyAd) {
      return AdDecision.deny(
        AdSuppressionReason.afterAnyAdGap,
        until: lastAny.add(_policy.minTimeAfterAnyAd),
      );
    }

    final lastInter = _readTime('lastInterstitial');
    if (lastInter != null &&
        at.difference(lastInter) < _policy.minIntervalBetweenInterstitials) {
      return AdDecision.deny(
        AdSuppressionReason.intervalNotElapsed,
        until: lastInter.add(_policy.minIntervalBetweenInterstitials),
      );
    }

    return const AdDecision.allow();
  }

  /// Same rules as [canShowFullscreen] but for inline (banner/native) formats,
  /// which only need the session cap and the "not immediately after another ad"
  /// spacing rule.
  AdDecision canShowInline({
    required AdPlacement placement,
    required bool adsEnabled,
    required bool userEligible,
    required String? currentRoute,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    if (isAdCriticalRoute(currentRoute)) {
      return const AdDecision.deny(AdSuppressionReason.criticalFlow);
    }
    if (!adsEnabled) {
      return const AdDecision.deny(AdSuppressionReason.adsDisabled);
    }
    if (!userEligible) {
      return const AdDecision.deny(AdSuppressionReason.ineligibleUser);
    }
    if (_sessionAds >= _policy.maxAdsPerSession) {
      return const AdDecision.deny(AdSuppressionReason.sessionCap);
    }
    final lastAny = _readTime('lastAnyAd');
    if (placement.isInFeed &&
        lastAny != null &&
        at.difference(lastAny) < _policy.minGapBetweenInlineAds) {
      return AdDecision.deny(
        AdSuppressionReason.afterAnyAdGap,
        until: lastAny.add(_policy.minGapBetweenInlineAds),
      );
    }
    return const AdDecision.allow();
  }

  void recordShown(AdPlacement placement, {DateTime? now}) {
    final at = now ?? DateTime.now();
    _sessionAds++;
    if (placement.format == AdFormat.interstitial) {
      _sessionInterstitials++;
      _writeTime('lastInterstitial', at);
      final prefs = _prefs;
      if (prefs != null) {
        if (prefs.getString(_ns('dayStamp')) != _dayStamp(at)) {
          unawaited(prefs.setString(_ns('dayStamp'), _dayStamp(at)));
          unawaited(prefs.setInt(_ns('dayCount'), 1));
        } else {
          unawaited(prefs.setInt(
              _ns('dayCount'), (prefs.getInt(_ns('dayCount')) ?? 0) + 1));
        }
      }
    }
    _writeTime('lastAnyAd', at);
    notifyListeners();
  }

  /// Applies exponential backoff for [placementId] after a failed load.
  ///
  /// Replaces the previous unbounded 15-second retry: the delay doubles per
  /// consecutive failure and is capped, and the hourly attempt budget stops a
  /// no-fill network from being retried at all once the budget is spent.
  void recordLoadFailure(String placementId, {DateTime? now}) {
    final at = now ?? DateTime.now();

    // Deliberately not gated on SharedPreferences being ready: the in-memory
    // cache is authoritative for the current session, and an early return here
    // would let a no-fill banner retry on every rebuild until prefs load.
    final failures = _readInt('fail.$placementId') + 1;
    _writeInt('fail.$placementId', failures);

    final budgetKey = 'budget.$placementId';
    final budget = _readInt(budgetKey) + 1;
    if (budget > _policy.maxLoadAttemptsPerHour) {
      _writeTime('backoff.$placementId', at.add(_policy.maxRetryBackoff));
      _writeInt(budgetKey, 0);
      return;
    }
    _writeInt(budgetKey, budget);

    final exponent = math.min(failures - 1, 10);
    final delayMs = math.min(
      _policy.retryBackoffBase.inMilliseconds * math.pow(2, exponent).toInt(),
      _policy.maxRetryBackoff.inMilliseconds,
    );
    _writeTime(
        'backoff.$placementId', at.add(Duration(milliseconds: delayMs)));
  }

  void recordLoadSuccess(String placementId) {
    _clearTime('backoff.$placementId');
    _clearInt('fail.$placementId');
    _clearInt('budget.$placementId');
  }

  /// When the next attempt for [placementId] is allowed, or null if it may be
  /// attempted immediately.
  DateTime? nextAttemptAt(String placementId) => _readTime('backoff.$placementId');

  // ─── Rewarded gate persistence ────────────────────────────────────────────
  //
  // The previous implementation stored a bare bool that never expired, so
  // `unlock_request_<id>` stayed unlocked forever with no reset path. The gate is
  // now a timestamp and [AdFrequencyPolicy.gateTtl] gives it an expiry.

  Future<bool> hasPassedGate(String action) async {
    await _ensureReady();
    final at = _readTime('gate.$action');
    if (at == null) return false;
    if (DateTime.now().difference(at) >= _policy.gateTtl) {
      await resetGate(action);
      return false;
    }
    return true;
  }

  Future<void> markGatePassed(String action) async {
    await _ensureReady();
    _writeTime('gate.$action', DateTime.now());
  }

  Future<void> resetGate(String action) async {
    await _ensureReady();
    _clearTime('gate.$action');
  }

  @visibleForTesting
  void debugSeed(String key, DateTime value) => _writeTime(key, value);

  @visibleForTesting
  int get debugSessionInterstitials => _sessionInterstitials;

  @visibleForTesting
  int get debugSessionAds => _sessionAds;
}
