import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:provider/provider.dart';

import '../seller_verification_service.dart';
import 'ad_config.dart';
import 'ad_eligibility_source.dart';
import 'ad_frequency_controller.dart';
import 'ad_remote_config.dart';

/// The single entry point for every ad in the Soko Vibe app.
///
/// Responsibilities, all centralised here so no screen ever touches
/// `google_mobile_ads` directly:
///
/// * SDK bootstrap and readiness gating (fixes the old race where a banner
///   could load before `MobileAds.instance.initialize()` resolved).
/// * Banner / native / interstitial / rewarded load, cache and preload.
/// * Eligibility: master switch, per-format switch, per-placement switch,
///   per-screen switch, account state and the Blue Tick ad exemption.
/// * Frequency control via [AdFrequencyController] for all formats.
/// * Critical-flow suppression driven by the current route.
/// * Failed-load backoff and full lifecycle disposal.
///
/// Screens use `AdSlot` for inline formats and call [showInterstitial] /
/// [showRewarded] at deliberate transition points. There is no per-screen ad
/// code anywhere else in the tree.
class AdManager extends ChangeNotifier {
  AdManager({
    AdFrequencyController? frequency,
    AdRemoteConfigService? remoteConfig,
    AdEligibilitySource? verification,
    AdSdkGateway? sdk,
    bool sdkReady = false,
  })  : _frequency = frequency ?? AdFrequencyController(),
        _remoteConfig = remoteConfig ?? AdRemoteConfigService(),
        _eligibility = verification ?? SellerVerificationService(),
        _sdk = sdk ?? const PlatformAdSdk(),
        // Only a test injects readiness; production leaves it false so every load
        // is gated behind a completed initialize().
        _sdkReady = sdkReady {
    _frequency.addListener(_onFrequencyChanged);
    _remoteConfig.addListener(_onRemoteConfigChanged);
    _eligibility.addListener(_onVerificationChanged);
  }

  final AdFrequencyController _frequency;
  final AdRemoteConfigService _remoteConfig;
  final AdEligibilitySource _eligibility;
  final AdSdkGateway _sdk;

  bool _sdkReady;
  bool _initializing = false;
  bool _fullscreenInFlight = false;
  String? _currentRoute;

  InterstitialAd? _interstitial;
  RewardedAd? _rewarded;
  bool _interstitialLoading = false;
  bool _rewardedLoading = false;
  Timer? _retryTimer;

  /// One cached banner per size class. A banner is expensive to build (platform
  /// view), so every `AdSlot` on a screen shares one instance.
  final Map<String, BannerAd> _banners = {};
  final Map<String, bool> _bannerLoaded = {};

  AdFrequencyController get frequency => _frequency;
  AdRemoteConfigService get remoteConfig => _remoteConfig;
  AdEligibilitySource get verification => _eligibility;
  AdRemoteConfig get config => _remoteConfig.config;
  bool get isSdkReady => _sdkReady;
  String? get currentRoute => _currentRoute;

  set currentRoute(String? value) {
    if (_currentRoute == value) return;
    _currentRoute = value;
    notifyListeners();
  }

  // ─── Bootstrap ────────────────────────────────────────────────────────────

  /// Idempotent. Safe to call from `main()` and again after hot restart.
  Future<void> initialize() async {
    if (_sdkReady || _initializing) return;
    _initializing = true;
    try {
      await _frequency.beginSession();
      unawaited(_remoteConfig.start());
      await _eligibility.refresh();

      if (kIsWeb) {
        // AdMob web is intentionally not wired: the previous implementation
        // left a fake "Sponsored" placeholder on screen forever because the load
        // path was skipped but the placeholder was not.
        _sdkReady = false;
        return;
      }

      _sdkReady = await _sdk.initialize();
      if (_sdkReady) {
        // Prime the fullscreen formats so the first eligible transition does
        // not have to wait for a network round-trip.
        unawaited(preloadInterstitial());
        unawaited(preloadRewarded());
      }
    } catch (e) {
      debugPrint('AdManager: initialize failed — $e');
      _sdkReady = false;
    } finally {
      _initializing = false;
      notifyListeners();
    }
  }

  void _onFrequencyChanged() => notifyListeners();
  void _onRemoteConfigChanged() => notifyListeners();
  void _onVerificationChanged() {
    // A Blue Tick grant or revocation changes what may render, so every mounted
    // AdSlot has to re-evaluate.
    notifyListeners();
  }

  // ─── Eligibility ──────────────────────────────────────────────────────────

  /// Central eligibility gate. Every format consults this before doing anything.
  bool get adsEnabledForUser {
    if (kIsWeb) return false;
    if (!config.adsEnabled) return false;
    if (_isCriticalFlow) return false;
    if (_eligibility.isSelfAdExempt && config.adsExemptBlueTickEnabled) {
      return false;
    }
    return true;
  }

  bool get _isCriticalFlow => isAdCriticalRoute(_currentRoute);

  /// Reason ads are currently suppressed, for diagnostics and the admin screen.
  AdSuppressionReason? get suppressionReason {
    if (kIsWeb) return AdSuppressionReason.adsDisabled;
    if (!config.adsEnabled) return AdSuppressionReason.adsDisabled;
    if (_isCriticalFlow) return AdSuppressionReason.criticalFlow;
    if (_eligibility.isSelfAdExempt && config.adsExemptBlueTickEnabled) {
      return AdSuppressionReason.ineligibleUser;
    }
    return null;
  }

/// True when the Blue Tick exemption applies to the signed-in account.
///
/// Kept separate from [adsEnabledForUser] so diagnostics can tell "the app
/// switched ads off" apart from "this seller is exempt".
bool get _isExemptByBlueTick =>
      _eligibility.isSelfAdExempt && config.adsExemptBlueTickEnabled;

AdDecision decideFullscreen({
    required AdPlacement placement,
    bool adLoaded = false,
    DateTime? now,
  }) {
    final allowed = config.isPlacementEnabled(placement);
    if (!allowed) {
      return AdDecision.deny(
        placement.isInFeed
            ? AdSuppressionReason.adsDisabled
            : AdSuppressionReason.placementDisabled,
      );
    }
    if (_fullscreenInFlight) {
      return const AdDecision.deny(AdSuppressionReason.alreadyShowing);
    }
    return _frequency.canShowFullscreen(
      placement: placement,
      // The combined gate minus the critical-route reason, which the controller
      // now checks first so it stays the clearest explanation.
      adsEnabled: config.adsEnabled && !_isExemptByBlueTick,
      userEligible: true,
      sdkReady: _sdkReady,
      adLoaded: adLoaded,
      currentRoute: _currentRoute,
      now: now,
    );
  }

AdDecision decideInline({
    required AdPlacement placement,
    DateTime? now,
  }) {
    if (!config.isPlacementEnabled(placement)) {
      return const AdDecision.deny(AdSuppressionReason.placementDisabled);
    }
    return _frequency.canShowInline(
      placement: placement,
      adsEnabled: config.adsEnabled && !_isExemptByBlueTick,
      userEligible: true,
      currentRoute: _currentRoute,
      now: now,
    );
  }

  // ─── Banner ───────────────────────────────────────────────────────────────

  /// Returns the cached banner for [slotKey], creating it on first request.
  ///
  /// Inline ads never render immediately: a reserve height is returned so the
  /// layout does not jump when the creative arrives, and nothing renders at all
  /// when the placement is ineligible.
  AdWidget? bannerWidgetFor(AdPlacement placement, {required String slotKey}) {
    if (!config.isPlacementEnabled(placement)) return null;
    if (!adsEnabledForUser) return null;
    if (kIsWeb) return null;
    if (_bannerLoaded[slotKey] != true) {
      // Fire-and-forget: the widget rebuilds when the listener fires.
      unawaited(_ensureBanner(slotKey));
      return null;
    }
    final ad = _banners[slotKey];
    if (ad == null) return null;
    return AdWidget(ad: ad);
  }

  /// Reserve height for the banner slot so surrounding content does not shift
  /// when the creative loads. Returns 0 when no ad may render.
  double bannerReserveHeight(AdPlacement placement) {
    if (!config.isPlacementEnabled(placement)) return 0;
    if (!adsEnabledForUser) return 0;
    if (kIsWeb) return 0;
    return _kBannerHeight;
  }

  static const double _kBannerHeight = 50;

  Future<void> _ensureBanner(String slotKey) async {
    if (_banners.containsKey(slotKey)) return;
    if (!adsEnabledForUser) return;
    if (kIsWeb) return;
    // Respect the failure backoff here, not just in preload*. The cache entry is
    // dropped on failure, so without this check every rebuild after a no-fill
    // would immediately request a new creative and hammer the SDK.
    final nextAttempt = _frequency.nextAttemptAt('banner.$slotKey');
    if (nextAttempt != null && nextAttempt.isAfter(DateTime.now())) return;

    final ad = _sdk.createBanner(
      adUnitId: AdUnitIds.banner(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          _bannerLoaded[slotKey] = true;
          notifyListeners();
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint(
              'AdManager: banner[$slotKey] load failed — ${error.message}');
          _frequency.recordLoadFailure('banner.$slotKey');
          _banners.remove(slotKey);
          _bannerLoaded.remove(slotKey);
          notifyListeners();
        },
      ),
    );
    _banners[slotKey] = ad;
    await _sdk.loadBanner(ad);
  }

  /// Releases a banner no longer on screen. Call from `AdSlot.dispose`.
void releaseBanner(String slotKey) {
    final ad = _banners.remove(slotKey);
    _bannerLoaded.remove(slotKey);
    if (ad == null) return;
    unawaited(ad.dispose());
  }

  // ─── Interstitial ────────────────────────────────────────────────────────

  bool get isInterstitialLoaded => _interstitial != null;

  Future<void> preloadInterstitial() async {
    if (kIsWeb || !_sdkReady) return;
    if (_interstitial != null || _interstitialLoading) return;
    if (!config.interstitialEnabled) return;
    // Do not fetch inventory at all for an ad-exempt seller: an exempt account
    // must never have AdMob bid for its session.
    if (_eligibility.isSelfAdExempt && config.adsExemptBlueTickEnabled) return;
    final next = _frequency.nextAttemptAt('interstitial');
    if (next != null && next.isAfter(DateTime.now())) return;

    _interstitialLoading = true;
    try {
      await _sdk.loadInterstitial(
        adUnitId: AdUnitIds.interstitial(),
        onLoaded: (ad) {
          _interstitialLoading = false;
          _interstitial = ad;
          _frequency.recordLoadSuccess('interstitial');
          notifyListeners();
        },
        onFailed: (error) {
          _interstitialLoading = false;
          _interstitial = null;
          _frequency.recordLoadFailure('interstitial');
          debugPrint('AdManager: interstitial load failed — $error');
          notifyListeners();
        },
      );
    } catch (e) {
      _interstitialLoading = false;
      debugPrint('AdManager: interstitial load threw — $e');
    }
  }

  /// Attempts an interstitial at a deliberate transition point.
  ///
  /// Returns true only when an ad was actually presented. The frequency
  /// controller is updated on *presentation*, not on request — the previous
  /// implementation burned its 20-minute cooldown even when nothing was cached.
  Future<bool> showInterstitial(
    AdPlacement placement, {
    DateTime? now,
  }) async {
    final decision = decideFullscreen(
      placement: placement,
      adLoaded: _interstitial != null,
      now: now,
    );
    if (!decision.allowed) {
      _debugLogSuppressed(placement, decision.reason);
      if (decision.reason == AdSuppressionReason.notLoaded) {
        unawaited(preloadInterstitial());
      }
      return false;
    }

    final ad = _interstitial!;
    _interstitial = null;
    _fullscreenInFlight = true;

    final completer = Completer<bool>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        unawaited(ad.dispose());
        _fullscreenInFlight = false;
        notifyListeners();
        unawaited(preloadInterstitial());
        if (!completer.isCompleted) completer.complete(true);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('AdManager: interstitial show failed — ${error.message}');
        unawaited(ad.dispose());
        _fullscreenInFlight = false;
        notifyListeners();
        // A show failure is a load-class failure: back off rather than retrying
        // on the next tick. The old code left the cache empty with no backoff.
        _frequency.recordLoadFailure('interstitial');
        if (!completer.isCompleted) completer.complete(false);
      },
    );

    try {
      await ad.show();
      _frequency.recordShown(placement, now: now);
    } catch (e) {
      debugPrint('AdManager: interstitial show threw — $e');
      _fullscreenInFlight = false;
      if (!completer.isCompleted) completer.complete(false);
      return false;
    }
    return completer.future;
  }

  // ─── Rewarded ─────────────────────────────────────────────────────────────

  bool get isRewardedLoaded => _rewarded != null;

  Future<bool> preloadRewarded() async {
    if (kIsWeb || !_sdkReady) return false;
    if (_rewarded != null) return true;
    if (_rewardedLoading) return false;
    if (!config.rewardedEnabled) return false;
    if (_eligibility.isSelfAdExempt && config.adsExemptBlueTickEnabled) {
      return false;
    }
    final next = _frequency.nextAttemptAt('rewarded');
    if (next != null && next.isAfter(DateTime.now())) return false;

    _rewardedLoading = true;
    await _sdk.loadRewarded(
      adUnitId: AdUnitIds.rewarded(),
      onLoaded: (ad) {
        _rewardedLoading = false;
        _rewarded = ad;
        _frequency.recordLoadSuccess('rewarded');
        notifyListeners();
      },
      onFailed: (error) {
        _rewardedLoading = false;
        _rewarded = null;
        _frequency.recordLoadFailure('rewarded');
        debugPrint('AdManager: rewarded load failed — $error');
        notifyListeners();
      },
    );
    return _rewarded != null;
  }

  /// Presents a rewarded ad for [placement].
  ///
  /// Blue Tick sellers are skipped entirely and resolve to `true`, which means
  /// "reward granted" — they are never asked to watch an ad in the first place.
  Future<bool> showRewarded(
    AdPlacement placement, {
    required VoidCallback onUserEarned,
  }) async {
    if (!config.isPlacementEnabled(placement)) return false;
    if (_eligibility.isSelfAdExempt && config.adsExemptBlueTickEnabled) {
      onUserEarned();
      return true;
    }
    if (!_sdkReady) return false;
    if (_fullscreenInFlight) return false;

    if (_rewarded == null && !await preloadRewarded()) return false;
    final ad = _rewarded;
    if (ad == null) return false;
    _rewarded = null;
    _fullscreenInFlight = true;

    final completer = Completer<bool>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        unawaited(ad.dispose());
        _fullscreenInFlight = false;
        notifyListeners();
        unawaited(preloadRewarded());
        if (!completer.isCompleted) completer.complete(false);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('AdManager: rewarded show failed — ${error.message}');
        unawaited(ad.dispose());
        _fullscreenInFlight = false;
        _frequency.recordLoadFailure('rewarded');
        if (!completer.isCompleted) completer.complete(false);
      },
    );

    try {
      await ad.show(
        onUserEarnedReward: (ad, reward) {
          onUserEarned();
          if (!completer.isCompleted) completer.complete(true);
        },
      );
      _frequency.recordShown(placement);
      return completer.future;
    } catch (e) {
      debugPrint('AdManager: rewarded show threw — $e');
      _fullscreenInFlight = false;
      if (!completer.isCompleted) completer.complete(false);
      return false;
    }
  }

  // ─── Rewarded gate persistence ────────────────────────────────────────────

  Future<bool> hasPassedGate(String action) => _frequency.hasPassedGate(action);

  Future<void> markGatePassed(String action) => _frequency.markGatePassed(action);

  Future<void> resetGate(String action) => _frequency.resetGate(action);

  // ─── Account switching ────────────────────────────────────────────────────

  /// Called on every auth transition. Clears persisted counters for the previous
  /// account and re-reads trusted verification for the new one, so a second
  /// account on the same device never inherits an ad exemption.
  Future<void> onAccountChanged(String? uid) async {
    await _frequency.adoptAccount(uid);
    await _eligibility.refresh();
    // Drop cached creatives: an ad unit that filled for the previous session can
    // carry targeting state we do not want to inherit.
    _disposeFullscreenCache();
    notifyListeners();
  }

  // ─── Lifecycle ────────────────────────────────────────────────────────────

  /// Called when the app resumes. Warms the caches only; it never shows an ad.
  ///
  /// The old implementation fired `tryShow()` on every resume from a timer
  /// mounted in the shell, which meant an interstitial could land on top of
  /// checkout or a payment sheet.
  void onAppResumed() {
    if (!config.interstitialEnabled) return;
    unawaited(preloadInterstitial());
  }

  void onAppPaused() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  void _disposeFullscreenCache() {
    unawaited(_interstitial?.dispose());
    _interstitial = null;
    _interstitialLoading = false;
    unawaited(_rewarded?.dispose());
    _rewarded = null;
    _rewardedLoading = false;
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _frequency.removeListener(_onFrequencyChanged);
    _remoteConfig.removeListener(_onRemoteConfigChanged);
    _eligibility.removeListener(_onVerificationChanged);
    for (final ad in _banners.values) {
      unawaited(ad.dispose());
    }
    _banners.clear();
    _bannerLoaded.clear();
    _disposeFullscreenCache();
    super.dispose();
  }

  void _debugLogSuppressed(AdPlacement placement, AdSuppressionReason? reason) {
    if (!kDebugMode) return;
    debugPrint(
        'AdManager: ${placement.id} suppressed (${reason?.name ?? 'unknown'})');
  }
}

/// Thin seam over the AdMob SDK so the manager is unit-testable without a
/// platform channel, and so tests can inject fake ads.
abstract class AdSdkGateway {
  const AdSdkGateway();

  Future<bool> initialize();

  BannerAd createBanner({
    required String adUnitId,
    required BannerAdListener listener,
  });

  Future<void> loadBanner(BannerAd ad);

  Future<void> loadInterstitial({
    required String adUnitId,
    required void Function(InterstitialAd ad) onLoaded,
    required void Function(String error) onFailed,
  });

  Future<void> loadRewarded({
    required String adUnitId,
    required void Function(RewardedAd ad) onLoaded,
    required void Function(String error) onFailed,
  });
}

class PlatformAdSdk implements AdSdkGateway {
  const PlatformAdSdk();

  @override
  Future<bool> initialize() async {
    if (kIsWeb) return false;
    try {
      await MobileAds.instance.initialize().timeout(const Duration(seconds: 12));
      // Belt-and-braces: even with swapped ad-unit IDs, ask the SDK for test
      // inventory whenever the app is configured for it.
      if (AdUnitIds.testMode) {
        await MobileAds.instance.updateRequestConfiguration(
          RequestConfiguration(
            tagForChildDirectedTreatment:
                TagForChildDirectedTreatment.unspecified,
          ),
        );
      }
      return true;
    } catch (e) {
      debugPrint('AdMob: initialize failed — $e');
      return false;
    }
  }

  @override
  BannerAd createBanner({
    required String adUnitId,
    required BannerAdListener listener,
  }) =>
      BannerAd(
        adUnitId: adUnitId,
        size: AdSize.banner,
        request: const AdRequest(),
        listener: listener,
      );

  @override
  Future<void> loadBanner(BannerAd ad) => ad.load();

  @override
  Future<void> loadInterstitial({
    required String adUnitId,
    required void Function(InterstitialAd ad) onLoaded,
    required void Function(String error) onFailed,
  }) async {
    await InterstitialAd.load(
      adUnitId: adUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: onLoaded,
        onAdFailedToLoad: (error) => onFailed(error.message),
      ),
    );
  }

  @override
  Future<void> loadRewarded({
    required String adUnitId,
    required void Function(RewardedAd ad) onLoaded,
    required void Function(String error) onFailed,
  }) async {
    await RewardedAd.load(
      adUnitId: adUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: onLoaded,
        onAdFailedToLoad: (error) => onFailed(error.message),
      ),
    );
  }
}

/// Process-wide instance, registered in `main.dart`'s `MultiProvider` so the
/// widget tree resolves it with `context.watch<AdManager>()`.
final AdManager adManager =
    AdManager(verification: sellerVerificationService);

/// Reads the nearest [AdManager] without subscribing. Use from callbacks that
/// need a one-shot decision and should not rebuild their subtree.
AdManager adManagerOf(BuildContext context) =>
    Provider.of<AdManager>(context, listen: false);
