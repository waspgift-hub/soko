import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class RewardedAdService {
  RewardedAdService._();

  /// Rewarded ad unit provided for "open feature" placements (create flash sale,
  /// unlock content). Test ads may take time to serve for new units; in debug
  /// builds Google's sample unit is used to allow verification.
  static const String openFeatureAdUnitId =
      'ca-app-pub-9510685366263226/6018252937';

  static const String _testRewardedAdUnitId =
      'ca-app-pub-3940256099942544/5224354917';

  static String get effectiveOpenFeatureAdUnitId =>
      kDebugMode ? _testRewardedAdUnitId : openFeatureAdUnitId;

  static Future<void> initialize() async {
    if (kIsWeb) return;
    try {
      await MobileAds.instance.initialize();
    } catch (e) {
      debugPrint('MobileAds init failed: $e');
    }
  }

  /// Loads and shows a rewarded ad. Resolves `true` only when the user earns a
  /// reward. Resolves `false` on load/show failure, dismissal without reward, or
  /// timeout.
  static Future<bool> showRewarded({String? adUnitId}) {
    if (kIsWeb) return Future.value(false);
    final unitId = adUnitId ?? effectiveOpenFeatureAdUnitId;
    final completer = Completer<bool>();
    var rewarded = false;
    var settled = false;

    void finish(bool value) {
      if (settled) return;
      settled = true;
      if (!completer.isCompleted) completer.complete(value);
    }

    RewardedAd.load(
      adUnitId: unitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              finish(rewarded);
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              debugPrint('Rewarded ad failed to show: $error');
              ad.dispose();
              finish(false);
            },
          );
          try {
            ad.show(onUserEarnedReward: (_, _) {
              rewarded = true;
            });
          } catch (e) {
            debugPrint('Rewarded ad show error: $e');
            ad.dispose();
            finish(false);
          }
        },
        onAdFailedToLoad: (error) {
          debugPrint('Rewarded ad failed to load: $error');
          finish(false);
        },
      ),
    );

    return completer.future.timeout(
      const Duration(seconds: 45),
      onTimeout: () => false,
    );
  }
}
