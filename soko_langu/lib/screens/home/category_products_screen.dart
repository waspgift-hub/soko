
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../extensions/context_tr.dart';
import '../../main.dart';
import '../../models/category_model.dart';
import '../../models/flash_sale_model.dart';
import '../../models/product_model.dart';
import '../../services/flash_sale_service.dart';
import '../../services/product_service.dart';
import '../../theme/app_dimens.dart';
import '../../utils/responsive.dart';
import '../../widgets/ad_banner.dart';
import '../../widgets/google_loading.dart';
import '../../widgets/product_card.dart';

class CategoryProductsScreen extends StatefulWidget {
  final Category category;

  const CategoryProductsScreen({
    super.key,
    required this.category,
  });

  @override
  State<CategoryProductsScreen> createState() =>
      _CategoryProductsScreenState();
}

class _CategoryProductsScreenState extends State<CategoryProductsScreen>
    with WidgetsBindingObserver {
  final _productService = ProductService();
  final _flashSaleService = FlashSaleService();

  String? _selectedSubcategory;
  Map<String, FlashSale> _flashSales = {};
  StreamSubscription? _flashSub;
  int _refreshKey = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscribeFlashSales();
  }

  void _subscribeFlashSales() {
    _flashSub?.cancel();
    _flashSub = _flashSaleService
        .getActiveFlashSalesMapAtNow(DateTime.now())
        .listen(
          (map) {
            if (mounted) setState(() => _flashSales = map);
          },
          onError: (_) {},
        );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flashSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() => _refreshKey++);
      _subscribeFlashSales();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final config = AppConfig.of(context);
    final title =
        config.langCode == 'en' ? widget.category.name : widget.category.nameSw;
    final subtitle =
        config.langCode == 'en' ? widget.category.nameSw : widget.category.name;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                categoryIconFor(widget.category.icon),
                color: cs.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const AdBanner(),
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.category.subcategories.isNotEmpty)
              _SubcategoryBar(
                category: widget.category,
                selected: _selectedSubcategory,
                onSelected: (value) =>
                    setState(() => _selectedSubcategory = value),
              ),
            Expanded(
              child: KeyedSubtree(
                key: ValueKey(
                  '${_selectedSubcategory ?? 'all'}-$_refreshKey',
                ),
                child: _buildProductsGrid(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductsGrid() {
    final stream = _selectedSubcategory == null
        ? _productService.getProductsByCategory(widget.category.name)
        : _productService.getProductsByCategoryAndSubcategory(
            widget.category.name,
            _selectedSubcategory!,
          );

    return StreamBuilder<List<Product>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const GoogleLoadingPage();
        }

        final products = snapshot.data ?? [];
        if (products.isEmpty) {
          return _EmptyCategoryProducts(category: widget.category);
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 1200
                ? 5
                : constraints.maxWidth >= 900
                    ? 4
                    : Responsive.gridColumns(context);

            return GridView.builder(
              padding: const EdgeInsets.fromLTRB(
                AppInsets.lg,
                AppInsets.md,
                AppInsets.lg,
                AppInsets.xxl,
              ),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: AppInsets.md,
                mainAxisSpacing: AppInsets.md,
                childAspectRatio: 0.70,
              ),
              itemCount: products.length,
              itemBuilder: (context, index) {
                final product = products[index];
                return ProductCard(
                  product: product,
                  flashSale: _flashSales[product.id],
                  onTap: () => context.push(
                    '${AppRoutes.productDetail}/${product.id}',
                    extra: product,
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _SubcategoryBar extends StatelessWidget {
  final Category category;
  final String? selected;
  final ValueChanged<String?> onSelected;

  const _SubcategoryBar({
    required this.category,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final config = AppConfig.of(context);

    return Container(
      height: 70,
      padding: const EdgeInsets.only(top: 9, bottom: 9),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: AppInsets.lg),
        scrollDirection: Axis.horizontal,
        itemCount: category.subcategories.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final isAll = index == 0;
          final sub = isAll ? null : category.subcategories[index - 1];
          final value = sub?.name;
          final selectedNow = selected == value;
          final label = isAll
              ? context.tr('all')
              : config.langCode == 'en'
                  ? sub!.name
                  : sub!.nameSw;

          return ChoiceChip(
            selected: selectedNow,
            onSelected: (_) => onSelected(value),
            avatar: Icon(
              isAll
                  ? Icons.grid_view_rounded
                  : Icons.arrow_forward_rounded,
              size: 15,
              color: selectedNow ? cs.onPrimary : cs.onSurfaceVariant,
            ),
            label: Text(label),
            padding: const EdgeInsets.symmetric(horizontal: 8),
          );
        },
      ),
    );
  }
}

class _EmptyCategoryProducts extends StatelessWidget {
  final Category category;

  const _EmptyCategoryProducts({
    required this.category,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final config = AppConfig.of(context);
    final name =
        config.langCode == 'en' ? category.name : category.nameSw;

    return Center(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppInsets.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                categoryIconFor(category.icon),
                size: 36,
                color: cs.primary,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              context.tr('no_products_category'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 5),
            Text(
              name,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
