import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../main.dart';
import '../extensions/context_tr.dart';

class AdBanner extends StatefulWidget {
  final bool showAlways;
  final bool nativeStyle;

  const AdBanner({super.key, this.showAlways = false, this.nativeStyle = true});

  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;
  Timer? _retryTimer;

  bool get _shouldShow => widget.showAlways || themeManager.currentTier == 'free';

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
          if (mounted) setState(() => _isLoaded = true);
        },
        onAdFailedToLoad: (ad, error) {
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
    if (!_shouldShow) return const SizedBox.shrink();

    final isDark = themeManager.isDark;

    if (_isLoaded && _bannerAd != null) {
      return Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1A1A) : Colors.grey[50],
          border: Border(
            top: BorderSide(
              color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey[200]!,
              width: 0.5,
            ),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withOpacity(0.1) : Colors.grey[300],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      context.tr('ad'),
                      style: TextStyle(
                        color: isDark ? Colors.white.withOpacity(0.4) : Colors.grey[500],
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: _bannerAd!.size.width.toDouble(),
              height: _bannerAd!.size.height.toDouble(),
              child: AdWidget(ad: _bannerAd!),
            ),
          ],
        ),
      );
    }

    if (widget.nativeStyle) {
      return Container(
        height: 58,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1A1A) : Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? Colors.white.withOpacity(0.06) : Colors.grey[200]!,
            width: 0.5,
          ),
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withOpacity(0.08) : Colors.grey[200],
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  Icons.storefront_outlined,
                  size: 16,
                  color: isDark ? Colors.white.withOpacity(0.3) : Colors.grey[400],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                context.tr('ad'),
                style: TextStyle(
                  color: isDark ? Colors.white.withOpacity(0.3) : Colors.grey[400],
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return const SizedBox(height: 1);
  }
}

