import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
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
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      final nextPage = (_currentPage + 1) % itemCount;
      _pageController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 400),
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
      child: InkWell(
        onTap: () => context.push(AppRoutes.flashSale),
        borderRadius: BorderRadius.circular(20),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Row(
            children: [
              Expanded(flex: 3, child: _buildLeftPanel(sales.length, cs)),
              Expanded(flex: 2, child: _buildRightPanel(sales, cs)),
            ],
          ),
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

  Widget _buildLeftPanel(int saleCount, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orange.shade50, Colors.orange.shade100],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.local_fire_department,
                    color: Colors.black87, size: 14),
              ),
              const SizedBox(width: 6),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.tr('app_name').toUpperCase(),
                      style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1)),
                  Text(context.tr('flash_sale_label'),
                      style: TextStyle(
                          color: Colors.black54,
                          fontSize: 7,
                          letterSpacing: 0.5)),
                ],
              ),
            ],
          ),
          const Spacer(),
          Text(
            context.tr('flash_deals'),
            style: const TextStyle(
              color: Colors.black,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            context.tr('banner_subtitle'),
            style: TextStyle(
                color: Colors.black54,
                fontSize: 10,
                height: 1.5,
                letterSpacing: 0.5),
          ),
          const Spacer(),
          Row(
            children: [
              const Icon(Icons.phone,
                  color: Colors.black54, size: 11),
              const SizedBox(width: 4),
              Text('$saleCount ${context.tr('deals')}',
                  style: const TextStyle(
                      color: Colors.black54, fontSize: 9)),
              const Spacer(),
              const Icon(Icons.arrow_forward_ios,
                  color: Colors.black38, size: 12),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRightPanel(List<FlashSale> sales, ColorScheme cs) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orange.shade100, Colors.orange.shade50],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: (page) =>
                  setState(() => _currentPage = page),
              itemCount: sales.length,
              itemBuilder: (context, index) {
                final sale = sales[index];
                return Padding(
                  padding:
                      const EdgeInsets.fromLTRB(8, 12, 8, 4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                                color: cs.tertiary
                                    .withValues(alpha: 0.3),
                                blurRadius: 10,
                                offset: const Offset(0, 3)),
                          ],
                        ),
                        child: ClipOval(
                          child: sale.productImage.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: sale.productImage,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, _, _) => const Icon(
                                      Icons.image,
                                      color: Colors.black38,
                                      size: 28))
                              : Container(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  child: const Icon(Icons.image,
                                      color: Colors.black38,
                                      size: 28)),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        sale.productName.length > 14
                            ? '${sale.productName.substring(0, 12)}..'
                            : sale.productName,
                        style: const TextStyle(
                            color: Colors.black87,
                            fontSize: 9,
                            fontWeight: FontWeight.w600),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color:
                              Colors.black.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '-${sale.discountPercent.toStringAsFixed(0)}%',
                          style: const TextStyle(
                              color: Colors.black87,
                              fontSize: 11,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        context.formatPrice(sale.salePrice),
                        style: const TextStyle(
                            color: Colors.black54,
                            fontSize: 10,
                            fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          if (sales.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children:
                    List.generate(sales.length, (i) {
                  final isActive = i == _currentPage;
                  return AnimatedContainer(
                    duration:
                        const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(
                        horizontal: 2),
                    width: isActive ? 16 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: isActive
                          ? Colors.black87
                          : Colors.black26,
                      borderRadius:
                          BorderRadius.circular(3),
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
