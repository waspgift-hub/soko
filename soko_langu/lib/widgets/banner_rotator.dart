import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/flash_sale_model.dart';
import 'banners/soko_banner_theme.dart';
import 'flash_sale_banner.dart';
import 'dynamic_banner.dart';
import 'ads_promo_banner.dart';

/// Rotates in-app promotional sections on the home feed (NOT AdMob).
/// Preserves existing flash-sale dwell behavior and signed-in boost promo targeting.
class BannerRotator extends StatefulWidget {
  final List<FlashSale> flashSales;
  const BannerRotator({super.key, required this.flashSales});

  @override
  State<BannerRotator> createState() => _BannerRotatorState();
}

class _BannerRotatorState extends State<BannerRotator> {
  int _current = 0;
  Timer? _timer;
  bool _userInteracting = false;
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void didUpdateWidget(BannerRotator old) {
    super.didUpdateWidget(old);
    final changed =
        old.flashSales.length != widget.flashSales.length ||
        (widget.flashSales.isNotEmpty &&
            old.flashSales.isNotEmpty &&
            old.flashSales.first.id != widget.flashSales.first.id);
    if (changed) {
      _timer?.cancel();
      _timer = null;
      if (mounted) {
        setState(() => _current = 0);
        if (_pageController.hasClients) {
          _pageController.jumpToPage(0);
        }
        _startTimer();
      }
    }
  }

  void _startTimer() {
    if (_timer != null || _userInteracting) return;
    _scheduleNext();
  }

  void _scheduleNext() {
    _timer?.cancel();
    if (_userInteracting) return;
    final banners = _banners();
    if (banners.length <= 1) {
      _timer = null;
      return;
    }
    final isFlashSection = _current == 0 && widget.flashSales.isNotEmpty;
    final seconds = isFlashSection ? 30 * widget.flashSales.length : 30;
    _timer = Timer(Duration(seconds: seconds), () {
      if (!mounted || _userInteracting) return;
      final count = _banners().length;
      if (count <= 1) return;
      final next = (_current + 1) % count;
      final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      setState(() => _current = next);
      if (_pageController.hasClients) {
        if (reduceMotion) {
          _pageController.jumpToPage(next);
        } else {
          _pageController.animateToPage(
            next,
            duration: const Duration(milliseconds: 360),
            curve: Curves.easeOutCubic,
          );
        }
      }
      _scheduleNext();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  List<Widget> _banners() {
    final list = <Widget>[];
    if (widget.flashSales.isNotEmpty) {
      list.add(FlashSaleBanner(key: const ValueKey('flash_banner'), sales: widget.flashSales));
    }
    // Ads promo targets signed-in sellers/users; guests get the plain dynamic banner only.
    if (FirebaseAuth.instance.currentUser != null) {
      list.add(const AdsPromoBanner(key: ValueKey('ads_promo')));
    }
    list.add(const DynamicBanner(key: ValueKey('dynamic_banner')));
    return list;
  }

  void _onPageChanged(int index) {
    setState(() => _current = index);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final banners = _banners();
    final count = banners.length;

    if (count == 0) return const SizedBox.shrink();
    if (count == 1) {
      _timer?.cancel();
      _timer = null;
      return banners.first;
    }

    final idx = _current.clamp(0, count - 1);
    _startTimer();

    return SokoBannerFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            label: 'Promotional banners, ${idx + 1} of $count',
            child: NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n is ScrollStartNotification && n.dragDetails != null) {
                  _userInteracting = true;
                  _timer?.cancel();
                  _timer = null;
                } else if (n is ScrollEndNotification) {
                  _userInteracting = false;
                  _startTimer();
                }
                return false;
              },
              child: SizedBox(
                height: SokoBannerTheme.minHeight,
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: count,
                  onPageChanged: _onPageChanged,
                  physics: const BouncingScrollPhysics(),
                  itemBuilder: (context, i) => banners[i],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          ExcludeSemantics(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(count, (i) {
                final active = i == idx;
                return AnimatedContainer(
                  duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: active ? 20 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: active ? cs.primary : cs.outlineVariant.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(99),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}
