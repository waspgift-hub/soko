import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../extensions/context_tr.dart';
import '../models/flash_sale_model.dart';
import '../models/product_model.dart';
import '../services/flash_sale_service.dart';
import '../services/recently_viewed_service.dart';
import '../app/routes.dart';
import 'premium_widgets.dart';
import 'product_card.dart';

/// Horizontal "recently viewed" carousel that follows the user's browsing
/// history in real time; hidden entirely when there is no history.
class RecentlyViewedRow extends StatelessWidget {
  const RecentlyViewedRow({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, FlashSale>>(
      stream: FlashSaleService().getActiveFlashSalesMapAtNow(DateTime.now()),
      builder: (context, flashSnap) {
        final flashSales = flashSnap.data ?? const <String, FlashSale>{};
        return StreamBuilder<List<String>>(
          stream: RecentlyViewedService.instance.watchIds(),
          builder: (context, snap) {
            final ids = snap.data ?? const <String>[];
            if (ids.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(title: context.tr('recently_viewed')),
                SizedBox(
                  height: 250,
                  child: FutureBuilder<List<Product>>(
                    future: RecentlyViewedService.instance.loadProducts(ids),
                    builder: (context, psnap) {
                      final products = psnap.data ?? const <Product>[];
                      if (products.isEmpty) return const SizedBox.shrink();
                      return ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: AppInsets.lg),
                        itemCount: products.length,
                        itemBuilder: (context, index) {
                          final product = products[index];
                          return Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: SizedBox(
                              width: 150,
                              child: ProductCard(
                                product: product,
                                flashSale: flashSales[product.id],
                                onTap: () => context.push(
                                  '${AppRoutes.productDetail}/${product.id}',
                                  extra: product,
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: AppInsets.md),
              ],
            );
          },
        );
      },
    );
  }
}