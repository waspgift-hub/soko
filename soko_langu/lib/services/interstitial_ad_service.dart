import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'api_config.dart';

class InterstitialAdService {
  InterstitialAd? _interstitialAd;
  bool _isLoading = false;
  bool _showQueued = false;
  DateTime? _lastShownAt;

  static const String _prodAdUnitId = 'ca-app-pub-3796499857968162/1033173712';
  static const String _testAdUnitId = 'ca-app-pub-3940256099942544/1033173712';

  static const int _cooldownMinutes = 20;

  bool get _isCooldownPassed {
    if (_lastShownAt == null) return true;
    return DateTime.now().difference(_lastShownAt!).inMinutes >= _cooldownMinutes;
  }

  Future<bool> tryShow() async {
    if (kIsWeb) return false;
    if (!_isCooldownPassed) return false;
    _lastShownAt = DateTime.now();
    await show();
    return true;
  }

  Future<void> load() async {
    if (kIsWeb) return;
    if (_isLoading) return;
    _isLoading = true;

    await InterstitialAd.load(
      adUnitId: ApiConfig.kAdsTestMode ? _testAdUnitId : _prodAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          debugPrint('InterstitialAd: loaded');
          _interstitialAd = ad;
          _isLoading = false;
          if (_showQueued) {
            _showQueued = false;
            show();
          }
        },
        onAdFailedToLoad: (error) {
          debugPrint('InterstitialAd: failed — ${error.message}');
          _interstitialAd = null;
          _isLoading = false;
        },
      ),
    );
  }

  Future<void> show() async {
    if (_interstitialAd == null) {
      _showQueued = true;
      if (!_isLoading) load();
      return;
    }

    _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _interstitialAd = null;
        load();
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
