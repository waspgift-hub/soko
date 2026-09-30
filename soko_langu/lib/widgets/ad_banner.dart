import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../extensions/context_tr.dart';
import '../services/api_config.dart';
import '../theme/app_colors.dart';

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
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 72,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [cs.brandPrimary.withValues(alpha: 0.14), cs.brandPrimary.withValues(alpha: 0.04)],
        ),
        border: Border.all(color: cs.brandPrimary.withValues(alpha: 0.18)),
        boxShadow: [BoxShadow(color: cs.brandPrimary.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: cs.brandPrimary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
            child: Icon(Icons.campaign_rounded, size: 20, color: cs.brandPrimary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(context.tr('sponsored'), style: TextStyle(color: cs.brandPrimary, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.1)),
              const SizedBox(height: 2),
              Text(context.tr('ad_label'), style: TextStyle(color: cs.onSurface, fontSize: 13, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(color: cs.brandPrimary, borderRadius: BorderRadius.circular(20)),
            child: Text(context.tr('view'), style: TextStyle(color: cs.surface, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 14),
        ],
      ),
    );
  }
}

