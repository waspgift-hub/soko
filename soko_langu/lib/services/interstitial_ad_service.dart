import 'dart:async';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../main.dart';

class InterstitialAdService {
  InterstitialAd? _interstitialAd;
  bool _isLoading = false;

  bool get _isFree => themeManager.currentTier == 'free';

  Future<void> load() async {
    if (!_isFree) return;
    if (_isLoading) return;
    _isLoading = true;

    await InterstitialAd.load(
      adUnitId: 'ca-app-pub-3796499857968162/2220136124',
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _isLoading = false;
        },
        onAdFailedToLoad: (error) {
          _interstitialAd = null;
          _isLoading = false;
        },
      ),
    );
  }

  Future<void> show() async {
    if (!_isFree) {
      _interstitialAd?.dispose();
      _interstitialAd = null;
      return;
    }

    if (_interstitialAd == null) return;

    _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _interstitialAd = null;
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _interstitialAd = null;
      },
    );

    await _interstitialAd!.show();
  }

  void dispose() {
    _interstitialAd?.dispose();
    _interstitialAd = null;
  }
}
