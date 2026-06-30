import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/price_drop_service.dart';
import '../extensions/context_tr.dart';

class PriceDropBanner extends StatefulWidget {
  const PriceDropBanner({super.key});

  @override
  State<PriceDropBanner> createState() => _PriceDropBannerState();
}

class _PriceDropBannerState extends State<PriceDropBanner> {
  final PriceDropService _service = PriceDropService();
  late PageController _pageController;
  int _currentPage = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
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
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
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
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _service.getActivePriceDrops(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }
        final drops = snapshot.data!;
        _startAutoSlide(drops.length);

        final cs = Theme.of(context).colorScheme;

        return Container(
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          height: 160,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: cs.error.withValues(alpha: 0.15),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Row(
              children: [
                Expanded(flex: 2, child: _buildLeftPanel(drops.length, cs)),
                Expanded(flex: 3, child: _buildRightPanel(drops, cs)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLeftPanel(int dropCount, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cs.error.withValues(alpha: 0.9), cs.error.withValues(alpha: 0.7)],
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
                  color: cs.surface.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(Icons.trending_down, color: cs.surface, size: 14),
              ),
              const SizedBox(width: 6),
              Text(context.tr('price_drop').toUpperCase(), style: TextStyle(color: cs.surface, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
            ],
          ),
          const Spacer(),
          Text(
            context.tr('prices_down'),
            style: TextStyle(
              color: cs.surface.withValues(alpha: 0.9),
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$dropCount ${context.tr('deals')}',
            style: TextStyle(color: cs.surface.withValues(alpha: 0.7), fontSize: 11, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          Icon(Icons.arrow_forward_ios, color: cs.surface.withValues(alpha: 0.5), size: 12),
        ],
      ),
    );
  }

  Widget _buildRightPanel(List<Map<String, dynamic>> drops, ColorScheme cs) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cs.error.withValues(alpha: 0.08), cs.surface],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: (page) => setState(() => _currentPage = page),
              itemCount: drops.length,
              itemBuilder: (context, index) {
                final drop = drops[index];
                final productName = drop['productName'] as String? ?? '';
                final productImage = drop['productImage'] as String? ?? '';
                final newPrice = (drop['newPrice'] ?? 0).toDouble();
                final originalPrice = (drop['originalPrice'] ?? 0).toDouble();
                final discount = drop['discountPercent'] as String? ?? '0';
                return Padding(
                  padding: const EdgeInsets.fromLTRB(10, 12, 10, 4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 60, height: 60,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: cs.error.withValues(alpha: 0.25), blurRadius: 8, offset: const Offset(0, 2)),
                          ],
                        ),
                        child: ClipOval(
                          child: productImage.isNotEmpty
                              ? CachedNetworkImage(imageUrl: productImage, fit: BoxFit.cover, errorWidget: (_, _, _) => Icon(Icons.image, color: cs.onSurface.withValues(alpha: 0.5), size: 24))
                              : Container(color: cs.error.withValues(alpha: 0.1), child: Icon(Icons.image, color: cs.onSurface.withValues(alpha: 0.5), size: 24)),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        productName.length > 16 ? '${productName.substring(0, 14)}..' : productName,
                        style: TextStyle(color: cs.onSurface, fontSize: 10, fontWeight: FontWeight.w600),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: cs.error.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '-$discount%',
                          style: TextStyle(color: cs.error, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            context.formatPrice(originalPrice),
                            style: TextStyle(color: cs.onSurface.withValues(alpha: 0.4), fontSize: 10, decoration: TextDecoration.lineThrough),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            context.formatPrice(newPrice),
                            style: TextStyle(color: cs.error, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          if (drops.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(drops.length, (i) {
                  final isActive = i == _currentPage;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    width: isActive ? 16 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: isActive ? cs.error.withValues(alpha: 0.7) : cs.onSurface.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(3),
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
