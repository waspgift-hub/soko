import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../extensions/context_tr.dart';
import '../services/api_config.dart';

class AdBanner extends StatefulWidget {
  const AdBanner({super.key});

  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;
  Timer? _retryTimer;

  bool get _shouldShow => true;

  @override
  void initState() {
    super.initState();
    if (_shouldShow && !kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadAd());
    }
  }

  static const String _prodAdUnitId = 'ca-app-pub-3796499857968162/6300978111';
  static const String _testAdUnitId = 'ca-app-pub-3940256099942544/6300978111';

  void _loadAd() {
    _bannerAd = BannerAd(
      adUnitId: ApiConfig.kAdsTestMode ? _testAdUnitId : _prodAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          debugPrint('AdBanner: loaded');
          if (mounted) setState(() => _isLoaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('AdBanner: failed — ${error.message}');
          debugPrint(
            'AdBanner: response info — ${error.responseInfo?.responseId ?? "none"}',
          );
          ad.dispose();
          _retryTimer = Timer(const Duration(seconds: 15), () {
            if (mounted) _loadAd();
          });
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    _retryTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoaded && _bannerAd != null) {
      return Container(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        child: SizedBox(
          width: _bannerAd!.size.width.toDouble(),
          height: _bannerAd!.size.height.toDouble(),
          child: AdWidget(ad: _bannerAd!),
        ),
      );
    }
    if (!_shouldShow) {
      return const SizedBox(height: 1);
    }
    return Container(
      height: 50,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.tertiaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.ad_units,
              size: 16,
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(width: 6),
            Text(
              context.tr('ad'),
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

