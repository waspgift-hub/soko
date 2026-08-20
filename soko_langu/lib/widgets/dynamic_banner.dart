import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'product_cached_image.dart';
import '../services/product_service.dart';
import '../models/product_model.dart';
import '../extensions/context_tr.dart';
import '../app/routes.dart';
import '../theme/app_colors.dart';

class DynamicBanner extends StatelessWidget {
  const DynamicBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Product>>(
      stream: ProductService().getFeaturedProducts(),
      builder: (context, snap) {
        final products = snap.data ?? [];
        if (products.isEmpty) return const EarnMoneyBanner();
        return _BoostedCarousel(products: products);
      },
    );
  }
}

// Single banner that cycles every boosted product inside it, mirroring the
// flash-sale banner so boosts never stack as one banner per product.
class _BoostedCarousel extends StatefulWidget {
  final List<Product> products;
  const _BoostedCarousel({required this.products});

  @override
  State<_BoostedCarousel> createState() => _BoostedCarouselState();
}

class _BoostedCarouselState extends State<_BoostedCarousel> {
  late PageController _pageController;
  int _currentPage = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _startAutoSlide(widget.products.length);
  }

  @override
  void didUpdateWidget(_BoostedCarousel old) {
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
    if (itemCount <= 1) return;
    // 30s per slide so every boost gets a full read, same as flash sales.
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      final nextPage = (_currentPage + 1) % itemCount;
      _pageController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final products = widget.products;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      height: 180,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(
          '${AppRoutes.productDetail}/${products[_currentPage].id}',
          extra: products[_currentPage],
        ),
        child: Row(
          children: [
            Expanded(flex: 3, child: _buildImagePanel(cs)),
            Expanded(flex: 1, child: _buildInfoPanel(cs)),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePanel(ColorScheme cs) {
    final products = widget.products;
    return Stack(
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
                : _imagePlaceholder(cs);
          },
        ),
        if (products.length > 1)
          Positioned(
            bottom: 8,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: () {
                final total = products.length;
                final win = total > 10 ? 10 : total;
                final active = total > 10
                    ? (_currentPage % win)
                    : _currentPage;
                return [
                  for (var i = 0; i < win; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      width: active == i ? 14 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: active == i
                            ? Colors.white
                            : Colors.white54,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                ];
              }(),
            ),
          ),
      ],
    );
  }

  Widget _buildInfoPanel(ColorScheme cs) {
    final p = widget.products[_currentPage.clamp(0, widget.products.length - 1)];
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.boostGold.withValues(alpha: 0.95),
            cs.boostBronze.withValues(alpha: 0.9),
          ],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.bolt, color: Colors.white, size: 12),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  context.tr('boosted'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            context.formatPrice(p.price),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            p.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.star, color: Colors.white, size: 10),
              const SizedBox(width: 2),
              Text(
                p.rating.toStringAsFixed(1),
                style: const TextStyle(color: Colors.white, fontSize: 10),
              ),
              const SizedBox(width: 2),
              Flexible(
                child: Text(' · ${p.soldCount} ${context.tr('sold')}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 9)),
              ),
            ],
          ),
          const Spacer(),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 9),
              const SizedBox(width: 2),
              Flexible(
                child: Text('${widget.products.length} ${context.tr('featured_products')}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 8)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _imagePlaceholder(ColorScheme cs) {
    return Container(
      color: cs.surfaceContainerLow,
      child: Icon(Icons.image, color: cs.onSurfaceVariant, size: 32),
    );
  }
}

class EarnMoneyBanner extends StatelessWidget {
  const EarnMoneyBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => context.push(AppRoutes.addProduct),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        height: 180,
        decoration: BoxDecoration(
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
        ),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 8, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        context.tr('earn_money_title'),
                        style: TextStyle(
                          color: cs.primary,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                      Text(
                        context.tr('earn_money_subtitle'),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: cs.onSurface,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 6),
                      Text(
                        context.tr('earn_money_desc'),
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 11.5,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: cs.primary,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        context.tr('start_selling'),
                        style: TextStyle(
                          color: cs.surface,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Container(
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.monetization_on_rounded,
                        size: 48,
                        color: cs.primary,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '+${context.currencySymbol()}',
                        style: TextStyle(
                          color: cs.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
