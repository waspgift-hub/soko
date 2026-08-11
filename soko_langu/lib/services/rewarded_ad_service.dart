import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_config.dart';

class RewardedAdService {
  static final RewardedAdService _instance = RewardedAdService._();
  factory RewardedAdService() => _instance;
  RewardedAdService._();

  RewardedAd? _rewardedAd;
  bool _isLoading = false;
  Completer<bool>? _loadCompleter;

  static const String _testAdUnitId = 'ca-app-pub-3940256099942544/5224354917';
  static const String _prodAdUnitId = 'ca-app-pub-3796499857968162/5224354917';

  String get _adUnitId => ApiConfig.kAdsTestMode ? _testAdUnitId : _prodAdUnitId;

  /// Loads a rewarded ad and resolves only when loading truly finishes.
  Future<bool> preload() async {
    if (kIsWeb) return false;
    if (_rewardedAd != null) return true;
    if (_isLoading) return _loadCompleter?.future ?? false;

    _isLoading = true;
    final completer = Completer<bool>();
    _loadCompleter = completer;
    // RewardedAd.load resolves via callback, not via its returned future.
    await RewardedAd.load(
      adUnitId: _adUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          _isLoading = false;
          if (!completer.isCompleted) completer.complete(true);
          debugPrint('RewardedAd: loaded');
        },
        onAdFailedToLoad: (error) {
          debugPrint('RewardedAd: failed - ${error.message}');
          _rewardedAd = null;
          _isLoading = false;
          if (!completer.isCompleted) completer.complete(false);
        },
      ),
    );
    return completer.future;
  }

  Future<bool> show({required VoidCallback onUserEarned}) async {
    if (_rewardedAd == null) {
      final loaded = await preload();
      if (!loaded || _rewardedAd == null) return false;
    }

    final completer = Completer<bool>();
    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _rewardedAd = null;
        preload();
        if (!completer.isCompleted) completer.complete(false);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _rewardedAd = null;
        preload();
        if (!completer.isCompleted) completer.complete(false);
      },
    );

    await _rewardedAd!.show(
      onUserEarnedReward: (ad, reward) {
        onUserEarned();
        if (!completer.isCompleted) completer.complete(true);
      },
    );
    return completer.future;
  }

  bool get isReady => _rewardedAd != null;

  void dispose() {
    _rewardedAd?.dispose();
    _rewardedAd = null;
  }
}

class AdGateService {
  static const String _prefix = 'ad_gate_';

  static Future<bool> hasPassedGate(String action) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_prefix$action') ?? false;
  }

  static Future<void> markGatePassed(String action) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_prefix$action', true);
  }

  static Future<void> resetGate(String action) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$action');
  }
}
