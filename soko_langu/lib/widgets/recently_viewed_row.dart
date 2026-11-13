import 'dart:async';

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
class RecentlyViewedRow extends StatefulWidget {
  const RecentlyViewedRow({super.key});

  @override
  State<RecentlyViewedRow> createState() => _RecentlyViewedRowState();
}

class _RecentlyViewedRowState extends State<RecentlyViewedRow> {
  // Both subscriptions and the product future are created ONCE.
  //
  // Previously every stream was constructed inline in build(), and the product
  // future was rebuilt on each one. Each emission triggered setState → rebuild →
  // re-listen + re-fetch, so the row generated its own traffic continuously
  // while the home screen was open.
  late final Stream<Map<String, FlashSale>> _flashStream;
  StreamSubscription<List<String>>? _idsSub;
  List<String> _ids = const [];
  Future<List<Product>>? _productsFuture;

  @override
  void initState() {
    super.initState();
    _flashStream = FlashSaleService().getActiveFlashSalesMapAtNow(DateTime.now());
    _idsSub = RecentlyViewedService.instance.watchIds().listen((ids) {
      if (!mounted) return;
      setState(() {
        _ids = ids;
        _productsFuture = ids.isEmpty
            ? null
            : RecentlyViewedService.instance.loadProducts(ids);
      });
    });
  }

  @override
  void dispose() {
    _idsSub?.cancel();
    _idsSub = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, FlashSale>>(
      stream: _flashStream,
      builder: (context, flashSnap) {
        final flashSales = flashSnap.data ?? const <String, FlashSale>{};
        if (_ids.isEmpty) return const SizedBox.shrink();
        final future = _productsFuture;
        if (future == null) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(title: context.tr('recently_viewed')),
            SizedBox(
              height: 250,
              child: FutureBuilder<List<Product>>(
                future: future,
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
  }
}