import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'product_cached_image.dart';
import '../services/product_service.dart';
import '../models/product_model.dart';
import '../extensions/context_tr.dart';
import '../app/routes.dart';
import '../theme/design_tokens.dart';
import '../theme/responsive_typography.dart';
import 'banners/soko_banner_theme.dart';

class DynamicBanner extends StatefulWidget {
  const DynamicBanner({super.key});

  @override
  State<DynamicBanner> createState() => _DynamicBannerState();
}

class _DynamicBannerState extends State<DynamicBanner> {
  late final Stream<List<Product>> _featured;

  @override
  void initState() {
    super.initState();
    _featured = ProductService().getFeaturedProducts();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Product>>(
      stream: _featured,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const _BannerSkeleton();
        }
        final products = snap.data ?? const <Product>[];
        if (products.isEmpty) return const EarnMoneyBanner();
        return _AdsCarousel(products: products);
      },
    );
  }
}

class _BannerSkeleton extends StatelessWidget {
  const _BannerSkeleton();
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ResponsiveBanner(
      minHeight: SokoBannerTheme.minHeight,
      margin: EdgeInsets.zero,
      borderRadius: SokoBannerTheme.borderRadius,
      decoration: SokoBannerTheme.surfaceDecoration(context),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: SokoBannerTheme.borderRadius,
          gradient: LinearGradient(
            colors: [cs.surfaceContainerHighest.withValues(alpha: 0.35), cs.surfaceContainerLow],
          ),
        ),
      ),
    );
  }
}

class _AdsCarousel extends StatefulWidget {
  final List<Product> products;
  const _AdsCarousel({required this.products});

  @override
  State<_AdsCarousel> createState() => _AdsCarouselState();
}

class _AdsCarouselState extends State<_AdsCarousel> {
  late PageController _pageController;
  int _currentPage = 0;
  Timer? _timer;
  bool _interacting = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _startAutoSlide(widget.products.length);
  }

  @override
  void didUpdateWidget(_AdsCarousel old) {
    super.didUpdateWidget(old);
    final newLength = widget.products.length;
    if (newLength != old.products.length) {
      _pageController.dispose();
      _pageController = PageController();
      _currentPage = 0;
      _startAutoSlide(newLength);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _startAutoSlide(int itemCount) {
    _timer?.cancel();
    if (_interacting || itemCount <= 1) return;
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted || _interacting) return;
      final nextPage = (_currentPage + 1) % itemCount;
      final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      if (reduceMotion) {
        _pageController.jumpToPage(nextPage);
      } else {
        _pageController.animateToPage(
          nextPage,
          duration: const Duration(milliseconds: 360),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final products = widget.products;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final current = products[_currentPage.clamp(0, products.length - 1)];

    return ResponsiveBanner(
      minHeight: SokoBannerTheme.minHeight,
      margin: EdgeInsets.zero,
      borderRadius: SokoBannerTheme.borderRadius,
      onTap: () => context.push('${AppRoutes.productDetail}/${current.id}', extra: current),
      decoration: SokoBannerTheme.surfaceDecoration(context),
      child: ClipRRect(
        borderRadius: SokoBannerTheme.borderRadius,
        child: Row(
          children: [
            Expanded(flex: 11, child: _buildImagePanel(cs, products, reduceMotion)),
            Expanded(flex: 9, child: _buildInfoPanel(context, cs, current, products.length)),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePanel(ColorScheme cs, List<Product> products, bool reduceMotion) {
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n is ScrollStartNotification && n.dragDetails != null) {
          _interacting = true;
          _timer?.cancel();
        } else if (n is ScrollEndNotification) {
          _interacting = false;
          _startAutoSlide(products.length);
        }
        return false;
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: _pageController,
            onPageChanged: (page) => setState(() => _currentPage = page),
            itemCount: products.length,
            itemBuilder: (context, index) {
              final p = products[index];
              return p.images.isNotEmpty
                  ? ProductCachedImage(url: p.images.first, fit: BoxFit.cover)
                  : Container(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
                      child: Icon(Icons.image_outlined, color: cs.onSurfaceVariant, size: 34),
                    );
            },
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 56,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black.withValues(alpha: 0.28), Colors.transparent],
                ),
              ),
            ),
          ),
          if (products.length > 1)
            Positioned(
              bottom: 10,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(products.length > 8 ? 8 : products.length, (i) {
                  final active = (products.length > 8 ? _currentPage % 8 : _currentPage) == i;
                  return AnimatedContainer(
                    duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 200),
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
    );
  }

  Widget _buildInfoPanel(BuildContext context, ColorScheme cs, Product p, int count) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(left: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.35))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SokoBannerTheme.badge(
            context,
            context.tr('featured_products'),
            icon: Icons.auto_awesome_outlined,
          ),
          const SizedBox(height: 10),
          BannerText(
            p.name,
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
              height: 1.2,
              color: cs.onSurface,
              letterSpacing: -0.2,
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 6),
          Text(
            context.formatPrice(p.price),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Ds.priceLarge(cs.primary).copyWith(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.star_rounded, size: 15, color: cs.tertiary),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  '${p.rating.toStringAsFixed(1)} · ${p.soldCount} ${context.tr('sold')}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: Text(
                  '$count ${context.tr('featured_products')}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
                ),
              ),
              Icon(Icons.arrow_forward_rounded, size: 16, color: cs.primary),
            ],
          ),
        ],
      ),
    );
  }
}

class EarnMoneyBanner extends StatelessWidget {
  const EarnMoneyBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;
    return ResponsiveBanner(
      minHeight: SokoBannerTheme.minHeight,
      margin: EdgeInsets.zero,
      borderRadius: SokoBannerTheme.borderRadius,
      onTap: () => context.push(AppRoutes.addProduct),
      decoration: SokoBannerTheme.surfaceDecoration(
        context,
        gradient: LinearGradient(
          colors: [
            cs.primary.withValues(alpha: isDark ? 0.16 : 0.09),
            cs.surfaceContainerLow,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Expanded(
              flex: 6,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SokoBannerTheme.badge(
                    context,
                    context.tr('earn_money_title'),
                    icon: Icons.storefront_outlined,
                  ),
                  const SizedBox(height: 12),
                  BannerText(
                    context.tr('earn_money_subtitle'),
                    style: TextStyle(
                      fontSize: 20,
                      height: 1.15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.45,
                      color: cs.onSurface,
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 8),
                  BannerText(
                    context.tr('earn_money_desc'),
                    style: TextStyle(fontSize: 13.5, height: 1.4, color: cs.onSurfaceVariant),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 14),
                  SokoBannerTheme.ctaPill(context, context.tr('start_selling')),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 4,
              child: Container(
                constraints: const BoxConstraints(minHeight: 120),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: isDark ? 0.14 : 0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: cs.primary.withValues(alpha: 0.10)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.sell_outlined, size: 38, color: cs.primary),
                    const SizedBox(height: 8),
                    Text(
                      '+${context.currencySymbol()}',
                      style: Ds.labelLg(
                        cs.primary,
                      ).copyWith(fontWeight: FontWeight.w800, fontSize: 18),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
