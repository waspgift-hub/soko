import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'product_cached_image.dart';
import '../models/flash_sale_model.dart';
import '../extensions/context_tr.dart';
import '../app/routes.dart';

class FlashSaleBanner extends StatefulWidget {
  final List<FlashSale> sales;
  const FlashSaleBanner({super.key, required this.sales});

  @override
  State<FlashSaleBanner> createState() => _FlashSaleBannerState();
}

class _FlashSaleBannerState extends State<FlashSaleBanner>
    with WidgetsBindingObserver {
  late PageController _pageController;
  int _currentPage = 0;
  Timer? _timer;
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
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() {});
    }
  }

  void _startAutoSlide(int itemCount) {
    _timer?.cancel();
    if (itemCount <= 1) return;
    // 30s per slide so every active flash-sale deal gets a full read before
    // the next one advances; 8s felt rushed with many sales on screen.
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
    final sales = widget.sales;

    if (sales.isEmpty) {
      return _buildPlaceholder(cs);
    }

    _startAutoSlide(sales.length);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      height: 180,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(AppRoutes.flashSale),
        child: Row(
          children: [
            // Product image dominates 75% of the banner (guideline 1.2);
            // sale info is the remaining 25%.
            Expanded(flex: 3, child: _buildImagePanel(sales, cs)),
            Expanded(flex: 1, child: _buildInfoPanel(sales, cs)),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder(ColorScheme cs) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      height: 180,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [cs.primary.withValues(alpha: 0.05), cs.surfaceContainerLow],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_fire_department,
                color: cs.primary.withValues(alpha: 0.5), size: 32),
            const SizedBox(height: 8),
            Text(
              context.tr('flash_deals'),
              style: TextStyle(
                color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              context.tr('no_active_deals'),
              style: TextStyle(
                color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePanel(List<FlashSale> sales, ColorScheme cs) {
    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          controller: _pageController,
          onPageChanged: (page) => setState(() => _currentPage = page),
          itemCount: sales.length,
          itemBuilder: (context, index) {
            final sale = sales[index];
            return sale.productImage.isNotEmpty
                ? ProductCachedImage(
                    url: sale.productImage,
                    fit: BoxFit.cover,
                  )
                : const _ImagePlaceholder();
          },
        ),
        // Soft edge gradient so the discount/text stays readable on photos.
        Positioned.fill(
          child: IgnorePointer(
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
        ),
        if (sales.length > 1)
          Positioned(
            bottom: 8,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: () {
                // Render at most 10 dots even when there are thousands of
                // sales; active dot reflects the current page relative window.
                final total = sales.length;
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

  Widget _buildInfoPanel(List<FlashSale> sales, ColorScheme cs) {
    final sale = sales[_currentPage.clamp(0, sales.length - 1).toInt()];
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.deepOrange, Colors.orange],
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
                child: const Icon(Icons.local_fire_department,
                    color: Colors.white, size: 12),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  context.tr('flash'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            '-${sale.discountPercent.toStringAsFixed(0)}%',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            sale.productName,
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
          Text(
            context.formatPrice(sale.salePrice),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 9),
              const SizedBox(width: 2),
              Flexible(
                child: Text('${sales.length} ${context.tr('deals')}',
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
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.orange.shade100,
      child: Center(
        child: Icon(Icons.image, color: Colors.black.withValues(alpha: 0.2), size: 36),
      ),
    );
  }
}
