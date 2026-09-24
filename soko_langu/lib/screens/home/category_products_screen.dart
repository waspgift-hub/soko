import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../main.dart';
import '../../extensions/context_tr.dart';
import '../../data/marketplace_taxonomy.dart';
import '../../models/category_model.dart';
import '../../models/discovery_filters.dart';
import '../../models/product_model.dart';
import '../../services/product_service.dart';
import '../../services/flash_sale_service.dart';
import '../../models/flash_sale_model.dart';
import '../../utils/category_icons.dart';
import '../../widgets/marketplace/category_image.dart';
import '../../widgets/marketplace/discovery_filter_sheet.dart';
import '../../widgets/product_card.dart';
import '../../app/routes.dart';
import '../../theme/app_dimens.dart';
import '../../utils/responsive.dart';
import '../../widgets/google_loading.dart';
import '../../widgets/ad_banner.dart';

class CategoryProductsScreen extends StatefulWidget {
  final Category category;
  final String? initialSubcategory;
  final Set<String>? initialBrands;
  final Map<String, Set<String>>? initialAttributes;
  final Set<String>? initialFlags;
  const CategoryProductsScreen({
    super.key,
    required this.category,
    this.initialSubcategory,
    this.initialBrands,
    this.initialAttributes,
    this.initialFlags,
  });

  @override
  State<CategoryProductsScreen> createState() => _CategoryProductsScreenState();
}

class _CategoryProductsScreenState extends State<CategoryProductsScreen>
    with WidgetsBindingObserver {
  final _productService = ProductService();
  final _flashSaleService = FlashSaleService();
  String? _selectedSubcategory;
  late ProductFilter _filter;
  Map<String, FlashSale> _flashSales = {};
  StreamSubscription? _flashSub;
  int _flashRefreshKey = 0;

  TaxonomyCategory? get _tax => taxonomyById(widget.category.id);

  Set<String> get _catAliases =>
      _tax == null ? const {} : _tax!.aliases.toSet();

  @override
  void initState() {
    super.initState();
    _selectedSubcategory = _matchSub(widget.initialSubcategory);
    _filter = ProductFilter(
      brands: widget.initialBrands ?? const {},
      attributes: widget.initialAttributes ?? const {},
      flags: widget.initialFlags ?? const {},
    );
    WidgetsBinding.instance.addObserver(this);
    _subscribeFlashSales();
  }

  void _subscribeFlashSales() {
    _flashSub?.cancel();
    final now = DateTime.now();
    _flashSub = _flashSaleService.getActiveFlashSalesMapAtNow(now).listen(
      (map) {
        if (mounted) setState(() => _flashSales = map);
      },
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
      setState(() => _flashRefreshKey++);
      _subscribeFlashSales();
    }
  }

  /// Matches a raw subcategory name (or legacy alias) to the canonical
  /// model name used by the product queries.
  String? _matchSub(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    for (final s in widget.category.subcategories) {
      if (s.name == raw || s.nameSw == raw) return s.name;
    }
    final tax = _tax;
    if (tax != null) {
      final key = raw.toLowerCase();
      for (final ts in tax.subs) {
        final hit = ts.name.toLowerCase() == key ||
            ts.nameSw.toLowerCase() == key ||
            ts.aliases.any((a) => a.toLowerCase() == key);
        if (!hit) continue;
        for (final s in widget.category.subcategories) {
          if (s.id == ts.id) return s.name;
        }
      }
    }
    return null;
  }

  /// Legacy subcategory names stored on old products.
  Set<String> _currentSubAliases() {
    if (_selectedSubcategory == null) return const {};
    final tax = _tax;
    if (tax == null) return const {};
    final key = _selectedSubcategory!.toLowerCase();
    for (final ms in widget.category.subcategories) {
      if (ms.name.toLowerCase() != key) continue;
      for (final ts in tax.subs) {
        if (ts.id == ms.id ||
            ts.name.toLowerCase() == key ||
            ts.nameSw.toLowerCase() == key) {
          return ts.aliases.toSet();
        }
      }
    }
    return const {};
  }

  Stream<List<Product>> _stream() {
    if (_selectedSubcategory == null) {
      return _productService.getProductsByCategory(
        widget.category.name,
        aliases: _catAliases,
      );
    }
    return _productService.getProductsByCategoryAndSubcategory(
      widget.category.name,
      _selectedSubcategory!,
      categoryAliases: _catAliases,
      subcategoryAliases: _currentSubAliases(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final desktop = Responsive.isDesktop;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.category.nameSw, style: const TextStyle(fontSize: 16)),
            Text(
              widget.category.name,
              style: TextStyle(
                fontSize: 11,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          if (!desktop)
            Stack(
              alignment: Alignment.center,
              children: [
                IconButton(
                  tooltip: context.tr('filters'),
                  icon: const Icon(Icons.filter_list_rounded),
                  onPressed: () => _openFilterSheet(_baseCache),
                ),
                if (_filter.activeCount > 0)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: cs.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${_filter.activeCount}',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: cs.onPrimary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
      bottomNavigationBar: const AdBanner(),
      body: SafeArea(
        child: StreamBuilder<List<Product>>(
          stream: _stream(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const GoogleLoadingPage();
            }
            final base = snapshot.data ?? [];
            _baseCache = base;
            final shown = _filter.apply(base);
            if (desktop) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sidebar(base),
                  Expanded(child: _contentColumn(base, shown)),
                ],
              );
            }
            return _contentColumn(base, shown);
          },
        ),
      ),
    );
  }

  List<Product> _baseCache = const [];

  Future<void> _openFilterSheet(List<Product> base) async {
    final next = await showDiscoveryFilterSheet(
      context,
      taxonomy: _tax,
      initial: _filter,
      countResults: (f) => f.apply(base).length,
    );
    if (next != null && mounted) setState(() => _filter = next);
  }

  Widget _sidebar(List<Product> base) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 300,
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: cs.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    context.tr('filters'),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(
                    () => _filter = const ProductFilter(),
                  ),
                  child: Text(
                    context.tr('clear_all'),
                    style: TextStyle(color: cs.primary),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: DiscoveryFilterBody(
              taxonomy: _tax,
              value: _filter,
              onChanged: (f) => setState(() => _filter = f),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              '${_filter.apply(base).length} ${context.tr('results')}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _contentColumn(List<Product> base, List<Product> shown) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _headerBanner(base, shown),
        if (widget.category.subcategories.isNotEmpty)
          _buildSubcategoryRail(),
        if (_tax != null && _tax!.brands.isNotEmpty) _brandsRow(),
        if (!_filter.isEmpty) _activeChips(),
        Expanded(child: _productsGrid(shown)),
      ],
    );
  }

  Widget _headerBanner(List<Product> base, List<Product> shown) {
    final cs = Theme.of(context).colorScheme;
    final art = widget.category.displayImage;
    final narrowed = shown.length != base.length;
    return Semantics(
      header: true,
      label: widget.category.name,
      child: Stack(
        children: [
          SizedBox(
            height: 148,
            width: double.infinity,
            child: art != null
                ? CategoryImage(
                    imageUrl: art,
                    fallback: categoryIconFor(
                      icon: widget.category.icon,
                      slug: widget.category.id,
                      name: widget.category.name,
                    ),
                    memCacheSize: 600,
                  )
                : Container(color: cs.surfaceContainerHighest),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.05),
                    Colors.black.withValues(alpha: 0.55),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.category.nameSw.isNotEmpty
                      ? widget.category.nameSw
                      : widget.category.name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  narrowed
                      ? '${shown.length} / ${base.length} ${context.tr('listings')}'
                      : '${base.length} ${context.tr('listings')}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubcategoryRail() {
    final config = AppConfig.of(context);
    final subs = widget.category.subcategories;
    return SizedBox(
      height: 100,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: subs.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return _SubTile(
              label: context.tr('all'),
              fallback: Icons.layers_rounded,
              selected: _selectedSubcategory == null,
              onTap: () => setState(() => _selectedSubcategory = null),
            );
          }
          final sub = subs[index - 1];
          return _SubTile(
            label: config.langCode == 'en' ? sub.name : sub.nameSw,
            imageUrl: sub.image,
            fallback: categoryIconFor(slug: sub.id, name: sub.name),
            selected: _selectedSubcategory == sub.name,
            onTap: () => setState(() => _selectedSubcategory = sub.name),
          );
        },
      ),
    );
  }

  Widget _brandsRow() {
    final brands = _tax!.brands;
    return SizedBox(
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: brands.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(
                  context.tr('all'),
                  style: const TextStyle(fontSize: 12),
                ),
                selected: _filter.brands.isEmpty,
                onSelected: (_) => setState(
                  () => _filter = _filter.copyWith(brands: {}),
                ),
              ),
            );
          }
          final b = brands[index - 1];
          final on = _filter.brands.contains(b.name);
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(b.name, style: const TextStyle(fontSize: 12)),
              selected: on,
              onSelected: (_) {
                final next = Set<String>.of(_filter.brands);
                on ? next.remove(b.name) : next.add(b.name);
                setState(() => _filter = _filter.copyWith(brands: next));
              },
            ),
          );
        },
      ),
    );
  }

  Widget _activeChips() {
    final cs = Theme.of(context).colorScheme;
    final chips = _filter.chips();
    return SizedBox(
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: chips.length +
            ((_filter.minPrice != null || _filter.maxPrice != null) ? 1 : 0),
        itemBuilder: (context, index) {
          if (index < chips.length) {
            final c = chips[index];
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InputChip(
                label: Text(
                  _chipLabel(c),
                  style: const TextStyle(fontSize: 12),
                ),
                deleteIcon: const Icon(Icons.close_rounded, size: 16),
                onDeleted: () => _removeChip(c),
                backgroundColor: cs.primaryContainer,
                labelStyle: TextStyle(color: cs.onPrimaryContainer),
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InputChip(
              label: Text(
                _priceLabel(),
                style: const TextStyle(fontSize: 12),
              ),
              deleteIcon: const Icon(Icons.close_rounded, size: 16),
              onDeleted: () => setState(
                () => _filter =
                    _filter.copyWith(clearPriceBounds: true),
              ),
              backgroundColor: cs.primaryContainer,
              labelStyle: TextStyle(color: cs.onPrimaryContainer),
            ),
          );
        },
      ),
    );
  }

  String _chipLabel(FilterChipData c) {
    switch (c.kind) {
      case 'brand':
      case 'location':
        return c.value;
      case 'condition':
        return context.tr(c.value);
      default:
        if (c.kind.startsWith('attr:')) return c.value;
        if (c.kind == 'flag') {
          if (c.label != null) return c.label!;
          if (c.labelKey != null) return context.tr(c.labelKey!);
        }
        return c.value;
    }
  }

  String _priceLabel() {
    final min = _filter.minPrice;
    final max = _filter.maxPrice;
    if (min != null && max != null) {
      return '${min.toStringAsFixed(0)} - ${max.toStringAsFixed(0)}';
    }
    if (min != null) return '≥ ${min.toStringAsFixed(0)}';
    return '≤ ${(max ?? 0).toStringAsFixed(0)}';
  }

  void _removeChip(FilterChipData c) {
    switch (c.kind) {
      case 'brand':
        final next = Set<String>.of(_filter.brands)..remove(c.value);
        setState(() => _filter = _filter.copyWith(brands: next));
      case 'condition':
        setState(() => _filter = _filter.copyWith(condition: 'all'));
      case 'location':
        setState(() => _filter = _filter.copyWith(location: ''));
      case 'flag':
        final next = Set<String>.of(_filter.flags)..remove(c.value);
        setState(() => _filter = _filter.copyWith(flags: next));
      default:
        if (c.kind.startsWith('attr:')) {
          final key = c.kind.substring(5);
          final next = Map<String, Set<String>>.of(_filter.attributes);
          final set = Set<String>.of(next[key] ?? {})..remove(c.value);
          next[key] = set;
          setState(() => _filter = _filter.copyWith(attributes: next));
        }
    }
  }

  Widget _productsGrid(List<Product> products) {
    if (products.isEmpty) {
      final cs = Theme.of(context).colorScheme;
      return Center(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).padding.bottom + 20,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.shopping_bag_outlined,
                size: 64,
                color: cs.onSurface.withValues(alpha: 0.6),
              ),
              const SizedBox(height: 16),
              Text(
                context.tr('no_products_category'),
                style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.6),
                ),
              ),
              if (!_filter.isEmpty) ...[
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => setState(
                    () => _filter = const ProductFilter(),
                  ),
                  child: Text(context.tr('clear_all')),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(AppInsets.md),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: Responsive.gridColumns(context),
        crossAxisSpacing: AppInsets.md,
        mainAxisSpacing: AppInsets.md,
        childAspectRatio: Responsive.cardAspectRatio(context),
      ),
      itemCount: products.length,
      itemBuilder: (context, index) {
        return ProductCard(
          product: products[index],
          flashSale: _flashSales[products[index].id],
          onTap: () => context.push(
            '${AppRoutes.productDetail}/${products[index].id}',
            extra: products[index],
          ),
        );
      },
    );
  }
}

/// Photo tile for one subcategory in the filter rail. Falls back to an
/// icon when the subcategory has no uploaded artwork.
class _SubTile extends StatelessWidget {
  final String label;
  final String? imageUrl;
  final IconData fallback;
  final bool selected;
  final VoidCallback onTap;

  const _SubTile({
    required this.label,
    this.imageUrl,
    required this.fallback,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 72,
        margin: const EdgeInsets.only(right: 10),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: selected
                    ? cs.primary.withValues(alpha: 0.12)
                    : cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: selected ? cs.primary : cs.outlineVariant,
                  width: selected ? 2 : 1,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: CategoryImage(
                imageUrl: imageUrl,
                fallback: fallback,
                iconSize: 24,
                memCacheSize: 112,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? cs.primary : cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
