import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'product_cached_image.dart';
import '../models/flash_sale_model.dart';
import '../extensions/context_tr.dart';
import '../app/routes.dart';
import '../theme/design_tokens.dart';
import '../theme/responsive_typography.dart';
import 'banners/soko_banner_theme.dart';

class FlashSaleBanner extends StatefulWidget {
  final List<FlashSale> sales;
  const FlashSaleBanner({super.key, required this.sales});

  @override
  State<FlashSaleBanner> createState() => _FlashSaleBannerState();
}

class _FlashSaleBannerState extends State<FlashSaleBanner> with WidgetsBindingObserver {
  late PageController _pageController;
  int _currentPage = 0;
  Timer? _timer;
  bool _interacting = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(FlashSaleBanner old) {
    super.didUpdateWidget(old);
    final newLength = widget.sales.length;
    if (newLength < old.sales.length && _currentPage >= newLength && newLength > 0) {
      _currentPage = 0;
      if (_pageController.hasClients) _pageController.jumpToPage(0);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) setState(() {});
  }

  void _startAutoSlide(int itemCount) {
    _timer?.cancel();
    if (_interacting || itemCount <= 1) return;
    // 30s per slide — preserves existing flash-sale readability/timing behavior.
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
    final sales = widget.sales;
    if (sales.isEmpty) return _buildPlaceholder(context, cs);
    _startAutoSlide(sales.length);
    final sale = sales[_currentPage.clamp(0, sales.length - 1)];
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return ResponsiveBanner(
      minHeight: SokoBannerTheme.minHeight,
      margin: EdgeInsets.zero,
      borderRadius: SokoBannerTheme.borderRadius,
      onTap: () => context.push(AppRoutes.flashSale),
      decoration: SokoBannerTheme.surfaceDecoration(context),
      child: ClipRRect(
        borderRadius: SokoBannerTheme.borderRadius,
        child: Row(
          children: [
            Expanded(flex: 11, child: _buildImagePanel(sales, cs, reduceMotion)),
            Expanded(flex: 9, child: _buildInfoPanel(context, cs, sale, sales.length)),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder(BuildContext context, ColorScheme cs) {
    return ResponsiveBanner(
      minHeight: SokoBannerTheme.minHeight,
      margin: EdgeInsets.zero,
      borderRadius: SokoBannerTheme.borderRadius,
      decoration: SokoBannerTheme.surfaceDecoration(context),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.local_offer_outlined, color: cs.primary.withValues(alpha: 0.7), size: 30),
              const SizedBox(height: 8),
              Text(
                context.tr('flash_deals'),
                style: Ds.bodyMd(cs.onSurfaceVariant).copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(context.tr('no_active_deals'), style: Ds.caption(cs.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImagePanel(List<FlashSale> sales, ColorScheme cs, bool reduceMotion) {
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n is ScrollStartNotification && n.dragDetails != null) {
          _interacting = true;
          _timer?.cancel();
        } else if (n is ScrollEndNotification) {
          _interacting = false;
          _startAutoSlide(sales.length);
        }
        return false;
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: _pageController,
            onPageChanged: (page) => setState(() => _currentPage = page),
            itemCount: sales.length,
            itemBuilder: (context, index) {
              final sale = sales[index];
              return sale.productImage.isNotEmpty
                  ? ProductCachedImage(url: sale.productImage, fit: BoxFit.cover)
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
          if (sales.length > 1)
            Positioned(
              bottom: 10,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(sales.length > 8 ? 8 : sales.length, (i) {
                  final active = (sales.length > 8 ? _currentPage % 8 : _currentPage) == i;
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

  Widget _buildInfoPanel(BuildContext context, ColorScheme cs, FlashSale sale, int count) {
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
          SokoBannerTheme.badge(context, context.tr('flash_deals'), icon: Icons.bolt_rounded),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: cs.errorContainer.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '-${sale.discountPercent.toStringAsFixed(0)}%',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: cs.onErrorContainer,
              ),
            ),
          ),
          const SizedBox(height: 8),
          BannerText(
            sale.productName,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              height: 1.2,
              color: cs.onSurface,
              letterSpacing: -0.2,
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 4),
          Text(
            context.formatPrice(sale.salePrice),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Ds.priceLarge(cs.primary).copyWith(fontSize: 16.5, fontWeight: FontWeight.w800),
          ),
          if (sale.originalPrice > sale.salePrice)
            Text(
              context.formatPrice(sale.originalPrice),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurfaceVariant,
                decoration: TextDecoration.lineThrough,
              ),
            ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: Text(
                  '$count ${context.tr('deals')}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
                ),
              ),
              SokoBannerTheme.ctaPill(context, context.tr('shop_now')),
            ],
          ),
        ],
      ),
    );
  }
}
