import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../models/flash_sale_model.dart';
import '../../services/flash_sale_service.dart';

import '../../extensions/context_tr.dart';
import '../../widgets/google_loading.dart';
import '../../widgets/ad_banner.dart';
import '../../app/routes.dart';
import '../../theme/app_colors.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../services/product_service.dart';

class FlashSaleScreen extends StatefulWidget {
  const FlashSaleScreen({super.key});

  @override
  State<FlashSaleScreen> createState() => _FlashSaleScreenState();
}

class _FlashSaleScreenState extends State<FlashSaleScreen>
    with WidgetsBindingObserver {
  final FlashSaleService _service = FlashSaleService();
  Timer? _timer;
  int _refreshKey = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() => _refreshKey++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      body: StreamBuilder<List<FlashSale>>(
        key: ValueKey('flash_sale_$_refreshKey'),
        stream: _service.getActiveFlashSalesAtNow(DateTime.now()),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: GoogleLoading(size: 32));
          }
          final sales = snapshot.data!;
          if (sales.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.local_fire_department,
                    size: 64,
                    color: cs.outline,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Hakuna Flash Sale kwa sasa',
                    style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Subiri flash sale inayofuata!',
                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            );
          }
          return CustomScrollView(
            slivers: [
              _buildHeroBanner(sales.length),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.local_fire_department,
                        color: cs.tertiary.withValues(alpha: 0.8),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${sales.length} Flash Deals',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: cs.primary.withValues(alpha: 0.85),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'Inaisha muda wowote',
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _buildSaleCard(sales[index]),
                  childCount: sales.length,
                ),
              ),
              const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
            ],
          );
        },
      ),
      bottomNavigationBar: const AdBanner(),
    );
  }

  Widget _buildHeroBanner(int saleCount) {
    final cs = Theme.of(context).colorScheme;
    return SliverToBoxAdapter(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [cs.primary.withValues(alpha: 0.85), cs.primary],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
        ),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.only(top: 12, bottom: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back, color: cs.surface),
                      onPressed: () => context.pop(),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: cs.tertiary.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$saleCount Deals',
                        style: TextStyle(
                          color: cs.surface,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: cs.tertiary.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'SOKO LANGU',
                                style: TextStyle(
                                  color: cs.tertiary,
                                  fontSize: 9,
                                  letterSpacing: 1,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'FLASH SALE',
                              style: TextStyle(
                                color: cs.surface,
                                fontSize: 26,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'BIG DISCOUNTS · LIMITED OFFERS',
                              style: TextStyle(
                                color: cs.surface.withValues(alpha: 0.7),
                                fontSize: 10,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(
                                  Icons.local_fire_department,
                                  color: cs.surface,
                                  size: 12,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '$saleCount deals live',
                                  style: TextStyle(
                                    color: cs.surface.withValues(alpha: 0.8),
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Column(
                          children: [
                            Container(
                              width: 70,
                              height: 70,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: cs.surface.withValues(alpha: 0.3),
                                  width: 2,
                                ),
                              ),
                              child: Center(
                                child: Icon(
                                  Icons.local_fire_department,
                                  color: cs.surface,
                                  size: 36,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$saleCount Active',
                              style: TextStyle(
                                color: cs.surface.withValues(alpha: 0.8),
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSaleCard(FlashSale sale) {
    final cs = Theme.of(context).colorScheme;
    final remaining = sale.endTime.difference(DateTime.now());
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes.remainder(60);
    final secs = remaining.inSeconds.remainder(60);
    final saved = sale.originalPrice - sale.salePrice;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cs.tertiary.withValues(alpha: 0.5).withValues(alpha: 0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: cs.primary.withValues(alpha: 0.85).withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [cs.primary, cs.tertiary.withValues(alpha: 0.8)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
            ),
            child: Row(
              children: [
                Icon(Icons.timer, color: cs.surface, size: 16),
                const SizedBox(width: 6),
                Text(
                  '${hours}h ${minutes}m ${secs}s',
                  style: TextStyle(
                    color: cs.surface,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: cs.surface.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '-${sale.discountPercent.toStringAsFixed(0)}%',
                    style: TextStyle(
                      color: cs.surface,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: CachedNetworkImage(
                    imageUrl: sale.productImage,
                    width: 90,
                    height: 90,
                    fit: BoxFit.cover,
                    placeholder: (_, _) => Container(
                      width: 90,
                      height: 90,
                      color: cs.outlineVariant,
                      child: const Center(
                        child: GoogleLoading(size: 20, strokeWidth: 2),
                      ),
                    ),
                    errorWidget: (_, _, _) => Container(
                      width: 90,
                      height: 90,
                      color: cs.outlineVariant,
                      child: Icon(Icons.image, color: cs.onSurfaceVariant),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sale.productName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Text(
                            context.formatPrice(sale.originalPrice),
                            style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontSize: 13,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            context.formatPrice(sale.salePrice),
                            style: TextStyle(
                              color: cs.tertiary.withValues(alpha: 0.8),
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${context.tr('you_save')} ${context.formatPrice(saved)}',
                        style: TextStyle(
                          color: cs.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (sale.location.isNotEmpty)
                        Row(
                          children: [
                            Icon(
                              Icons.location_on,
                              size: 14,
                              color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              sale.location,
                              style: TextStyle(
                                color: cs.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final product = await ProductService().getProductById(sale.productId);
                      if (product != null && context.mounted) {
                        context.push(
                          '${AppRoutes.productDetail}/${sale.productId}',
                          extra: product,
                        );
                      }
                    },
                    icon: const Icon(Icons.visibility, size: 18),
                    label: const Text('Angalia'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: cs.primary,
                      side: BorderSide(color: cs.primary),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => context.push(
                      '${AppRoutes.chat}/${sale.sellerId}',
                      extra: {'name': sale.sellerName},
                    ),
                    icon: const Icon(Icons.chat_outlined, size: 18),
                    label: Text(context.tr('whatsapp')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cs.whatsappGreen,
                      foregroundColor: cs.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
