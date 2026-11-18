import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/responsive_typography.dart';
import 'banners/soko_banner_theme.dart';

class PromoImageBanner extends StatefulWidget {
  const PromoImageBanner({super.key});

  @override
  State<PromoImageBanner> createState() => _PromoImageBannerState();
}

class _PromoImageBannerState extends State<PromoImageBanner> {
  static const List<String> _images = [
    'assets/banner/1794338739055.jpg',
    'assets/banner/1794339003692.jpg',
  ];

  final PageController _controller = PageController();
  int _current = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      final next = (_current + 1) % _images.length;
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ResponsiveBanner(
      minHeight: SokoBannerTheme.minHeight,
      margin: EdgeInsets.zero,
      borderRadius: SokoBannerTheme.borderRadius,
      decoration: SokoBannerTheme.surfaceDecoration(context),
      child: ClipRRect(
        borderRadius: SokoBannerTheme.borderRadius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            PageView.builder(
              controller: _controller,
              itemCount: _images.length,
              onPageChanged: (i) => setState(() => _current = i),
              itemBuilder: (context, i) => Image.asset(
                _images[i],
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
                  child: Icon(Icons.image_outlined, color: cs.onSurfaceVariant, size: 34),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 40,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black.withValues(alpha: 0.35), Colors.transparent],
                  ),
                ),
              ),
            ),
            if (_images.length > 1)
              Positioned(
                bottom: 10,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_images.length, (i) {
                    final active = i == _current;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 2.5),
                      width: active ? 16 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: active ? Colors.white : Colors.white.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    );
                  }),
                ),
              ),
          ],
        ),
      ),
    );
  }
}