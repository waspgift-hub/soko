import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../main.dart';
import '../extensions/context_tr.dart';

class AdBanner extends StatefulWidget {
  final bool showAlways;

  const AdBanner({super.key, this.showAlways = false});

  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;
  Timer? _retryTimer;

  bool get _shouldShow =>
      widget.showAlways || themeManager.currentTier == 'free';

  @override
  void initState() {
    super.initState();
    if (_shouldShow) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadAd());
    }
  }

  void _loadAd() {
    _bannerAd = BannerAd(
      adUnitId: 'ca-app-pub-3940256099942544/6300978111',
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
        color: Colors.grey[100],
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
        color: const Color(0xFFD8F3DC).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFF2D6A4F).withValues(alpha: 0.3),
        ),
      ),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.ad_units,
              size: 16,
              color: const Color(0xFF2D6A4F).withValues(alpha: 0.5),
            ),
            const SizedBox(width: 6),
            Text(
              context.tr('ad'),
              style: TextStyle(
                color: const Color(0xFF2D6A4F).withValues(alpha: 0.5),
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
