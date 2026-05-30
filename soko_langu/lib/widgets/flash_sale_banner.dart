import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/flash_sale_model.dart';
import '../services/flash_sale_service.dart';
import '../extensions/context_tr.dart';
import '../app/routes.dart';

const Color _darkGreen = Color(0xFF1B4332);
const Color _midGreen = Color(0xFF2D6A4F);
const Color _accentGreen = Color(0xFF52B788);
const Color _lightGreen = Color(0xFF95D5B2);

class FlashSaleBanner extends StatefulWidget {
  const FlashSaleBanner({super.key});

  @override
  State<FlashSaleBanner> createState() => _FlashSaleBannerState();
}

class _FlashSaleBannerState extends State<FlashSaleBanner> {
  final FlashSaleService _service = FlashSaleService();
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
    return StreamBuilder<List<FlashSale>>(
      stream: _service.getActiveFlashSales(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }
        final sales = snapshot.data!;
        _startAutoSlide(sales.length);

        return Container(
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          height: 180,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: _darkGreen.withValues(alpha: 0.2),
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
                  Expanded(flex: 3, child: _buildLeftPanel(sales.length)),
                  Expanded(flex: 2, child: _buildRightPanel(sales)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLeftPanel(int saleCount) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_darkGreen, _midGreen],
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
                  color: _accentGreen,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.local_fire_department, color: Colors.white, size: 14),
              ),
              const SizedBox(width: 6),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('SOKO LANGU', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  Text('FLASH SALE', style: TextStyle(color: Color(0xFF95D5B2), fontSize: 7, letterSpacing: 0.5)),
                ],
              ),
            ],
          ),
          const Spacer(),
          Text(
            'FLASH DEALS',
            style: TextStyle(
              color: _lightGreen,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
              shadows: [Shadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 4, offset: const Offset(1, 2))],
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'BIG DISCOUNTS\nFLASH SALES\nLIMITED OFFERS',
            style: TextStyle(color: Color(0xFFB7E4C7), fontSize: 10, height: 1.5, letterSpacing: 0.5),
          ),
          const Spacer(),
          Row(
            children: [
              Icon(Icons.phone, color: _accentGreen, size: 11),
              const SizedBox(width: 4),
              Text('$saleCount deals', style: const TextStyle(color: Color(0xFF95D5B2), fontSize: 9)),
              const Spacer(),
              Icon(Icons.arrow_forward_ios, color: _lightGreen.withValues(alpha: 0.6), size: 12),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRightPanel(List<FlashSale> sales) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_midGreen, _accentGreen.withValues(alpha: 0.2)],
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
              itemCount: sales.length,
              itemBuilder: (context, index) {
                final sale = sales[index];
                return Padding(
                  padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          width: 56, height: 56,
                          color: Colors.white.withValues(alpha: 0.15),
                          child: sale.productImage.isNotEmpty
                              ? CachedNetworkImage(imageUrl: sale.productImage, fit: BoxFit.cover, errorWidget: (_, _, _) => const Icon(Icons.image, color: Colors.white54, size: 28))
                              : const Icon(Icons.image, color: Colors.white54, size: 28),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        sale.productName.length > 14 ? '${sale.productName.substring(0, 12)}..' : sale.productName,
                        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w600),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _accentGreen,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '-${sale.discountPercent.toStringAsFixed(0)}%',
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        context.formatPrice(sale.salePrice),
                        style: const TextStyle(color: Color(0xFFB7E4C7), fontSize: 10, fontWeight: FontWeight.w500),
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
                children: List.generate(sales.length, (i) {
                  final isActive = i == _currentPage;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    width: isActive ? 16 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: isActive ? _accentGreen : Colors.white.withValues(alpha: 0.35),
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
