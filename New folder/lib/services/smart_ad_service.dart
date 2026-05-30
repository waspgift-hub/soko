import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class SmartAdService {
  static final SmartAdService _instance = SmartAdService._internal();
  factory SmartAdService() => _instance;
  SmartAdService._internal();

  InterstitialAd? _interstitialAd;
  RewardedAd? _rewardedAd;
  bool _isLoadingInterstitial = false;
  bool _isLoadingRewarded = false;

  int _productViewCount = 0;
  int _orderCompleteCount = 0;
  DateTime? _lastInterstitialTime;

  static const int adAfterProductViews = 8;
  static const int minSecondsBetweenInterstitials = 180;

  Future<void> initialize() async {
    _preloadInterstitial();
    _preloadRewarded();
  }

  Future<void> _preloadInterstitial() async {
    if (_isLoadingInterstitial) return;
    _isLoadingInterstitial = true;

    await InterstitialAd.load(
      adUnitId: 'ca-app-pub-3940256099942544/1033173712',
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _isLoadingInterstitial = false;
        },
        onAdFailedToLoad: (error) {
          debugPrint('SmartAd: interstitial failed - ${error.message}');
          _interstitialAd = null;
          _isLoadingInterstitial = false;
        },
      ),
    );
  }

  Future<void> _preloadRewarded() async {
    if (_isLoadingRewarded) return;
    _isLoadingRewarded = true;

    await RewardedAd.load(
      adUnitId: 'ca-app-pub-3940256099942544/5224354917',
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          _isLoadingRewarded = false;
        },
        onAdFailedToLoad: (error) {
          debugPrint('SmartAd: rewarded failed - ${error.message}');
          _rewardedAd = null;
          _isLoadingRewarded = false;
        },
      ),
    );
  }

  void recordProductView() {
    _productViewCount++;
    if (_productViewCount >= adAfterProductViews) {
      _productViewCount = 0;
      showSmartInterstitial();
    }
  }

  void recordOrderComplete() {
    _orderCompleteCount++;
    if (_orderCompleteCount >= 2) {
      _orderCompleteCount = 0;
      showSmartInterstitial();
    }
  }

  Future<void> showSmartInterstitial() async {
    final now = DateTime.now();
    if (_lastInterstitialTime != null) {
      final diff = now.difference(_lastInterstitialTime!).inSeconds;
      if (diff < minSecondsBetweenInterstitials) return;
    }

    if (_interstitialAd == null) {
      _preloadInterstitial();
      return;
    }

    _lastInterstitialTime = now;
    _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _interstitialAd = null;
        _preloadInterstitial();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _interstitialAd = null;
        _preloadInterstitial();
      },
    );

    await _interstitialAd!.show();
  }

  Future<bool> showRewardedAd({required Function() onUserEarned}) async {
    if (_rewardedAd == null) {
      await _preloadRewarded();
      return false;
    }

    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _rewardedAd = null;
        _preloadRewarded();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _rewardedAd = null;
        _preloadRewarded();
      },
    );

    await _rewardedAd!.show(
      onUserEarnedReward: (ad, reward) {
        onUserEarned();
      },
    );
    return true;
  }

  bool hasRewardedAdReady() => _rewardedAd != null;

  void dispose() {
    _interstitialAd?.dispose();
    _rewardedAd?.dispose();
    _interstitialAd = null;
    _rewardedAd = null;
  }
}
