import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/banner_model.dart';
import '../services/banner_service.dart';
import '../theme/design_tokens.dart';
import '../theme/responsive_typography.dart';
import 'product_cached_image.dart';

/// A widget that displays banners from the centralized banner service
/// for a specific placement.
class SokoBannerWidget extends StatefulWidget {
  const SokoBannerWidget({
    super.key,
    required this.placement,
    this.maxBanners = 1,
    this.autoRotate = true,
    this.rotationInterval = const Duration(seconds: 30),
    this.onBannerTap,
    this.onImpression,
    this.onClick,
  });

  final BannerPlacement placement;
  final int maxBanners;
  final bool autoRotate;
  final Duration rotationInterval;
  final void Function(BannerCampaign)? onBannerTap;
  final void Function(BannerCampaign)? onImpression;
  final void Function(BannerCampaign)? onClick;

  @override
  State<SokoBannerWidget> createState() => _SokoBannerWidgetState();
}

class _SokoBannerWidgetState extends State<SokoBannerWidget>
    with WidgetsBindingObserver {
  late BannerService _bannerService;
  StreamSubscription<Map<BannerPlacement, List<BannerCampaign>>>?
      _bannerSubscription;
  List<BannerCampaign> _banners = [];
  int _currentIndex = 0;
  Timer? _rotationTimer;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bannerService = context.read<BannerService>();
    _subscribeToBanners();
  }

  @override
  void dispose() {
    _disposed = true;
    _rotationTimer?.cancel();
    _bannerSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      // Restart rotation timer on resume
      _startRotation();
    } else if (state == AppLifecycleState.paused) {
      _rotationTimer?.cancel();
    }
  }

  void _subscribeToBanners() {
    _bannerSubscription?.cancel();
    _bannerSubscription = _bannerService.bannersStream.listen((banners) {
      if (_disposed) return;
      final newBanners = banners[widget.placement] ?? [];
      if (mounted) {
        setState(() {
          _banners = newBanners.take(widget.maxBanners).toList();
          _currentIndex = 0;
        });
        _startRotation();
        // Record impressions for visible banners
        for (final banner in _banners) {
          widget.onImpression?.call(banner);
          unawaited(_bannerService.recordImpression(
            bannerId: banner.id,
            placement: widget.placement,
          ));
        }
      }
    });
  }

  void _startRotation() {
    _rotationTimer?.cancel();
    if (!widget.autoRotate || _banners.length <= 1) return;

    _rotationTimer = Timer.periodic(widget.rotationInterval, (_) {
      if (!mounted || _disposed) return;
      setState(() {
        _currentIndex = (_currentIndex + 1) % _banners.length;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_banners.isEmpty) return const SizedBox.shrink();

    final banner = _banners[_currentIndex];
    return _buildBanner(banner);
  }

  Widget _buildBanner(BannerCampaign banner) {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () {
        widget.onClick?.call(banner);
        unawaited(_bannerService.recordClick(
          bannerId: banner.id,
          placement: widget.placement,
        ));
        _handleNavigation(banner);
      },
      child: ResponsiveBanner(
        minHeight: 180,
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        borderRadius: BorderRadius.circular(20),
        decoration: _getBannerDecoration(banner, cs),
        child: _buildBannerContent(banner, cs),
      ),
    );
  }

  Decoration? _getBannerDecoration(BannerCampaign banner, ColorScheme cs) {
    switch (banner.type) {
      case BannerType.sponsoredAd:
        return BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [
              cs.primary.withValues(alpha: 0.15),
              cs.primary.withValues(alpha: 0.03),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: cs.primary.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        );
      case BannerType.promotion:
        return BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [
              cs.primary.withValues(alpha: 0.18),
              cs.primary.withValues(alpha: 0.04),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: cs.primary.withValues(alpha: 0.1),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        );
      case BannerType.newFeature:
        return BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [
              cs.primary.withValues(alpha: 0.12),
              cs.primary.withValues(alpha: 0.03),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: cs.primary.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        );
      case BannerType.platformAnnouncement:
        return BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [
              Colors.blue.withValues(alpha: 0.12),
              Colors.blue.withValues(alpha: 0.03),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.blue.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        );
      case BannerType.adminConfigured:
        return BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: cs.surfaceContainerLow,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        );
    }
  }

  Widget _buildBannerContent(BannerCampaign banner, ColorScheme cs) {
    // Use localized content if available for current locale
    final locale = Localizations.localeOf(context).languageCode;
    final localization = banner.localization?[locale];

    final title = localization?.title ?? banner.title;
    final mainText = localization?.mainText ?? banner.mainText;
    final subtitle = localization?.subtitle ?? banner.subtitle;
    final ctaLabel = localization?.ctaLabel ?? banner.ctaLabel;

    if (banner.imageUrl != null && banner.imageUrl!.isNotEmpty) {
      // Image-based banner layout
      return Row(
        children: [
          Expanded(
            flex: 3,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ProductCachedImage(
                  url: banner.imageUrl!,
                  fit: BoxFit.cover,
                ),
                // Gradient overlay for text readability
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          Colors.black.withValues(alpha: 0.3),
                          Colors.transparent,
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (banner.type == BannerType.sponsoredAd) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: BannerText(
                        'SPONSORED',
                        style: Ds.badge(Colors.white).copyWith(fontSize: 9),
                        maxLines: 1,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  BannerText(
                    title,
                    style: Ds.bannerTitle(cs.onSurface).copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 2,
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 6),
                    BannerText(
                      subtitle,
                      style: Ds.bannerSubtitle(cs.onSurfaceVariant),
                      maxLines: 2,
                    ),
                  ],
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: cs.primary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: BannerText(
                      ctaLabel,
                      style: Ds.bannerCta(cs.onPrimary).copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    } else {
      // Text-only banner layout
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (banner.type == BannerType.sponsoredAd) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: BannerText(
                  'SPONSORED',
                  style: Ds.bannerCta(cs.primary).copyWith(fontSize: 9),
                  maxLines: 1,
                ),
              ),
              const SizedBox(height: 8),
            ],
            BannerText(
              title,
              style: Ds.bannerTitle(cs.onSurface).copyWith(
                fontWeight: FontWeight.w700,
              ),
              maxLines: 2,
            ),
            if (mainText.isNotEmpty) ...[
              const SizedBox(height: 6),
              BannerText(
                mainText,
                style: Ds.bannerSubtitle(cs.onSurface),
                maxLines: 3,
              ),
            ],
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              BannerText(
                subtitle,
                style: Ds.bannerSubtitle(cs.onSurfaceVariant),
                maxLines: 2,
              ),
            ],
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: cs.primary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: BannerText(
                ctaLabel,
                style: Ds.bannerCta(cs.onPrimary).copyWith(
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    }
  }

  void _handleNavigation(BannerCampaign banner) {
    widget.onBannerTap?.call(banner);

    switch (banner.destinationType) {
      case BannerDestinationType.productDetail:
        context.push('/product/${banner.destinationValue}');
        break;
      case BannerDestinationType.categoryPage:
        context.push('/category/${banner.destinationValue}');
        break;
      case BannerDestinationType.sellerProfile:
        context.push('/seller/${banner.destinationValue}');
        break;
      case BannerDestinationType.externalUrl:
        // Would need url_launcher
        break;
      case BannerDestinationType.deepLink:
        context.push(banner.destinationValue);
        break;
      case BannerDestinationType.flashSalePage:
        context.push('/flash-sale');
        break;
      case BannerDestinationType.addProduct:
        context.push('/add-product');
        break;
      case BannerDestinationType.boostProduct:
        context.push('/boost-product');
        break;
      case BannerDestinationType.kycPage:
        context.push('/kyc');
        break;
      case BannerDestinationType.notificationsPage:
        context.push('/notifications');
        break;
    }
  }
}

/// A banner rotator that cycles through multiple banners for a placement.
class SokoBannerRotator extends StatefulWidget {
  const SokoBannerRotator({
    super.key,
    required this.placement,
    this.maxBanners = 3,
    this.rotationInterval = const Duration(seconds: 30),
    this.showIndicators = true,
  });

  final BannerPlacement placement;
  final int maxBanners;
  final Duration rotationInterval;
  final bool showIndicators;

  @override
  State<SokoBannerRotator> createState() => _SokoBannerRotatorState();
}

class _SokoBannerRotatorState extends State<SokoBannerRotator> {
  late BannerService _bannerService;
  StreamSubscription<Map<BannerPlacement, List<BannerCampaign>>>?
      _bannerSubscription;
  List<BannerCampaign> _banners = [];
  int _currentIndex = 0;
  Timer? _rotationTimer;
  bool _disposed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bannerService = context.read<BannerService>();
    _subscribeToBanners();
  }

  @override
  void dispose() {
    _disposed = true;
    _rotationTimer?.cancel();
    _bannerSubscription?.cancel();
    super.dispose();
  }

  void _subscribeToBanners() {
    _bannerSubscription = _bannerService.bannersStream.listen((banners) {
      if (_disposed) return;
      final newBanners = banners[widget.placement] ?? [];
      if (mounted) {
        setState(() {
          _banners = newBanners.take(widget.maxBanners).toList();
          _currentIndex = 0;
        });
        _startRotation();
      }
    });
  }

  void _startRotation() {
    _rotationTimer?.cancel();
    if (_banners.length <= 1) return;

    _rotationTimer = Timer.periodic(widget.rotationInterval, (_) {
      if (!mounted || _disposed) return;
      setState(() {
        _currentIndex = (_currentIndex + 1) % _banners.length;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_banners.isEmpty) return const SizedBox.shrink();
    if (_banners.length == 1) {
      return SokoBannerWidget(
        key: ValueKey(_banners.first.id),
        placement: widget.placement,
        maxBanners: 1,
        autoRotate: false,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          switchInCurve: Curves.easeInOut,
          switchOutCurve: Curves.easeInOut,
          child: SokoBannerWidget(
            key: ValueKey(_banners[_currentIndex].id),
            placement: widget.placement,
            maxBanners: 1,
            autoRotate: false,
          ),
        ),
        if (widget.showIndicators) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_banners.length, (i) {
              final active = i == _currentIndex;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: active ? 22 : 8,
                height: 6,
                decoration: BoxDecoration(
                  color: active
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outline
                          .withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }),
          ),
        ],
      ],
    );
  }
}