import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../main.dart';
import '../../services/localization_service.dart';
import '../../services/category_service.dart';
import '../../models/category_model.dart';
import '../../models/product_model.dart';
import '../../providers/product_feed_provider.dart';
import '../../widgets/product_card.dart';
import '../../widgets/ad_banner.dart';
import '../../widgets/banner_rotator.dart';
import '../../widgets/premium_widgets.dart';
import '../../widgets/animated_gradient_line.dart';

import '../../extensions/context_tr.dart';
import '../../utils/responsive.dart';
import '../../utils/network_error.dart';
import '../../app/routes.dart';
import '../../services/flash_sale_service.dart';
import '../../models/flash_sale_model.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  @override
  bool get wantKeepAlive => true;
  final FlashSaleService _flashSaleService = FlashSaleService();
  final CategoryService _categoryService = CategoryService();
  String? _selectedBrand;
  final _searchCtrl = TextEditingController();
  Map<String, FlashSale> _flashSales = {};
  StreamSubscription? _flashSub;

  // Filter state
  String _sortBy = 'newest';
  double? _minPrice;
  double? _maxPrice;
  String _condition = 'all';
  String _locationFilter = '';

  List<String> _brands = [
    'Nike', 'Adidas', 'Samsung', 'Apple', 'Sony', 'LG', 'Toyota', 'Hp', 'Dell', 'Other',
  ];

  void _showCurrencyPicker(BuildContext context) {
    final config = AppConfig.of(context);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40, height: 4, margin: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(
              color: Theme.of(ctx).colorScheme.onSurfaceVariant.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppInsets.lg),
            child: Text(context.tr('select_currency'),
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(ctx).colorScheme.onSurface),
            ),
          ),
          ...LocalizationService.supportedCurrencies.entries.map(
            (e) => ListTile(
              title: Text("${e.value['name']} (${e.value['symbol']})"),
              trailing: config.currencyCode == e.key
                  ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
                  : null,
              onTap: () {
                LocalizationService().setCurrency(e.key);
                config.onSetCurrency(e.key);
                Navigator.pop(ctx);
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscribeFlashSales();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<ProductFeedProvider>();
      if (provider.products.isEmpty && !provider.isLoading) {
        provider.refresh();
      }
    });
  }

  void _subscribeFlashSales() {
    _flashSub?.cancel();
    final now = DateTime.now();
    _flashSub = _flashSaleService.getActiveFlashSalesMapAtNow(now).listen(
      (map) { if (mounted) setState(() => _flashSales = map); },
      onError: (e) { debugPrint('Flash sales stream error: $e'); },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchCtrl.dispose();
    _flashSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _subscribeFlashSales();
    }
  }

  void _onBrandTap(String? brand) {
    setState(() => _selectedBrand = brand);
    final provider = context.read<ProductFeedProvider>();
    if (brand == null) { provider.refresh(); }
    else { provider.loadByBrand(brand); }
  }

  List<Product> _getFilteredProducts(List<Product> products) {
    var result = products.toList();
    if (_minPrice != null) result = result.where((p) => p.price >= _minPrice!).toList();
    if (_maxPrice != null) result = result.where((p) => p.price <= _maxPrice!).toList();
    if (_condition != 'all') result = result.where((p) => p.condition == _condition).toList();
    if (_locationFilter.isNotEmpty) result = result.where((p) => p.location.toLowerCase().contains(_locationFilter.toLowerCase())).toList();
    switch (_sortBy) {
      case 'price_asc':
        result.sort((a, b) => a.price.compareTo(b.price));
      case 'price_desc':
        result.sort((a, b) => b.price.compareTo(a.price));
      case 'popular':
        result.sort((a, b) => b.soldCount.compareTo(a.soldCount));
      default:
        result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    return result;
  }

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _FilterSheet(
        initialSort: _sortBy,
        initialMinPrice: _minPrice,
        initialMaxPrice: _maxPrice,
        initialCondition: _condition,
        initialLocation: _locationFilter,
        onApply: (sort, minP, maxP, cond, loc) {
          setState(() {
            _sortBy = sort;
            _minPrice = minP;
            _maxPrice = maxP;
            _condition = cond;
            _locationFilter = loc;
          });
        },
      ),
    );
  }

  Widget _brandChip(String label, String? brand) {
    final isSelected = _selectedBrand == brand;
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => _onBrandTap(brand),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? cs.primary : cs.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? cs.primary : cs.outlineVariant),
        ),
        child: Text(label,
          style: TextStyle(
            color: isSelected ? cs.onPrimary : cs.onSurfaceVariant,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Soko', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: cs.primary, letterSpacing: -0.5)),
            Text('Vibe', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant, letterSpacing: 2)),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.monetization_on_outlined, color: cs.primary),
            onPressed: () => _showCurrencyPicker(context),
          ),
          Stack(
            children: [
              IconButton(
                icon: Icon(Icons.notifications_outlined, color: cs.primary),
                onPressed: () => context.push(AppRoutes.notifications),
              ),
              Positioned(right: 8, top: 8, child: Container(
                width: 8, height: 8,
                decoration: BoxDecoration(color: cs.error, shape: BoxShape.circle),
              )),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 80),
          child: Column(
            children: [
              // Animated gradient line at top
              const AnimatedGradientLine(height: 3),
              const SizedBox(height: AppInsets.md),
              // Premium search bar
              Padding(
                padding: const EdgeInsets.fromLTRB(AppInsets.lg, 0, AppInsets.lg, AppInsets.md),
                child: Container(
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: cs.outlineVariant),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))],
                  ),
                  child: TextField(
                    controller: _searchCtrl,
                    readOnly: true,
                    onTap: () => context.push(AppRoutes.search),
                    decoration: InputDecoration(
                      hintText: context.tr('search_products'),
                      hintStyle: TextStyle(color: cs.onSurfaceVariant.withValues(alpha: 0.6), fontSize: 14),
                      prefixIcon: Icon(Icons.search_rounded, color: cs.primary, size: 22),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      suffixIcon: GestureDetector(
                        onTap: _showFilterSheet,
                        child: Container(
                          margin: const EdgeInsets.all(6),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: cs.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.tune_rounded, color: cs.primary, size: 16),
                              const SizedBox(width: 4),
                              Text('Filter', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.primary)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Brand chips
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: AppInsets.lg),
                  children: [
                    _brandChip('All', null),
                    ..._brands.map((b) => _brandChip(b, b)),
                  ],
                ),
              ),
              const SizedBox(height: AppInsets.sm),
              // Banners
              BannerRotator(flashSales: _flashSales.values.toList()),
              const SizedBox(height: AppInsets.sm),
              // Categories
              SectionHeader(
                title: context.tr('categories'),
                actionLabel: context.tr('see_all'),
                onAction: () => context.push(AppRoutes.category),
              ),
              const SizedBox(height: AppInsets.xs),
              SizedBox(
                height: 130,
                child: StreamBuilder<List<Category>>(
                  stream: _categoryService.getCategories(),
                  builder: (context, snapshot) {
                    final cats = snapshot.data ?? [];
                    if (cats.isEmpty) {
                      return Center(
                        child: Text(context.tr('no_categories'),
                          style: TextStyle(color: cs.onSurfaceVariant.withValues(alpha: 0.6), fontSize: 13),
                        ),
                      );
                    }
                    return ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: AppInsets.lg),
                      itemCount: cats.length,
                      itemBuilder: (context, index) {
                        final cat = cats[index];
                        final config = AppConfig.of(context);
                        return GestureDetector(
                          onTap: () => context.push('${AppRoutes.categoryProducts}/${cat.name}', extra: cat),
                          child: Container(
                            width: 80,
                            margin: const EdgeInsets.only(right: 14),
                            child: Column(
                              children: [
                                Container(
                                  width: 64, height: 64,
                                  decoration: BoxDecoration(
                                    color: cs.surface,
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(color: cs.outlineVariant),
                                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 3))],
                                  ),
                                  child: Center(child: Text(cat.icon, style: const TextStyle(fontSize: 28))),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  config.langCode == 'en' ? cat.name : cat.nameSw,
                                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, fontWeight: FontWeight.w500),
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: AppInsets.sm),
              // Products
              _buildProductsArea(),
              const SizedBox(height: AppInsets.lg),
              const AdBanner(),
              const SizedBox(height: AppInsets.xl),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProductsArea() {
    final cs = Theme.of(context).colorScheme;
    final provider = context.watch<ProductFeedProvider>();
    return Column(
      children: [
        SectionHeader(
          title: context.tr('latest_products'),
          actionLabel: context.tr('see_all'),
          onAction: () => context.push(AppRoutes.search),
        ),
        const SizedBox(height: AppInsets.sm),
        Builder(builder: (context) {
          if (provider.error != null && provider.products.isEmpty) {
            final kind = provider.errorKind;
            final (icon, title, subtitle) = switch (kind) {
              FirestoreErrorKind.permission => (
                Icons.lock_outline,
                context.tr('permission_denied'),
                context.tr('firestore_permission_hint'),
              ),
              FirestoreErrorKind.missingIndex => (
                Icons.hourglass_empty,
                context.tr('something_wrong'),
                context.tr('firestore_index_building'),
              ),
              FirestoreErrorKind.network => (
                Icons.cloud_off,
                context.tr('something_wrong'),
                context.tr('no_network'),
              ),
              _ => (Icons.error_outline, context.tr('something_wrong'), context.tr('please_try_again')),
            };
            return EmptyStateWidget(
              icon: icon, title: title, subtitle: subtitle,
              actionLabel: context.tr('try_again'),
              onAction: () => provider.refresh(),
            );
          }
          if (provider.products.isEmpty) {
            return EmptyStateWidget(icon: Icons.inventory_2_outlined, title: context.tr('no_products'));
          }
          final filtered = _getFilteredProducts(provider.products);
          if (filtered.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.filter_alt_off, size: 48, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
                    const SizedBox(height: 8),
                    Text('Hakuna bidhaa zinazolingana na vigezo',
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                    ),
                  ],
                ),
              ),
            );
          }
          return NotificationListener<ScrollNotification>(
            onNotification: (scrollInfo) {
              if (scrollInfo.metrics.pixels >= scrollInfo.metrics.maxScrollExtent - 200) {
                provider.loadNextPage();
              }
              return false;
            },
            child: GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: AppInsets.lg),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: Responsive.gridColumns(context),
                crossAxisSpacing: AppInsets.md,
                mainAxisSpacing: AppInsets.md,
                childAspectRatio: Responsive.cardAspectRatio(context),
              ),
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                return RepaintBoundary(
                  child: ProductCard(
                    product: filtered[index],
                    flashSale: _flashSales[filtered[index].id],
                    onTap: () => context.push('${AppRoutes.productDetail}/${filtered[index].id}', extra: filtered[index]),
                  ),
                );
              },
            ),
          );
        }),
      ],
    );
  }
}

class _FilterSheet extends StatefulWidget {
  final String initialSort;
  final double? initialMinPrice;
  final double? initialMaxPrice;
  final String initialCondition;
  final String initialLocation;
  final void Function(String sort, double? minP, double? maxP, String cond, String loc) onApply;

  const _FilterSheet({
    required this.initialSort,
    this.initialMinPrice,
    this.initialMaxPrice,
    required this.initialCondition,
    required this.initialLocation,
    required this.onApply,
  });

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late String _sort;
  late TextEditingController _minCtrl;
  late TextEditingController _maxCtrl;
  late String _condition;
  late TextEditingController _locCtrl;

  @override
  void initState() {
    super.initState();
    _sort = widget.initialSort;
    _minCtrl = TextEditingController(text: widget.initialMinPrice?.toStringAsFixed(0) ?? '');
    _maxCtrl = TextEditingController(text: widget.initialMaxPrice?.toStringAsFixed(0) ?? '');
    _condition = widget.initialCondition;
    _locCtrl = TextEditingController(text: widget.initialLocation);
  }

  @override
  void dispose() {
    _minCtrl.dispose();
    _maxCtrl.dispose();
    _locCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Container(
            width: 40, height: 4, margin: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(
              color: cs.onSurfaceVariant.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Chuja', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: cs.onSurface)),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _sort = 'newest';
                      _minCtrl.clear();
                      _maxCtrl.clear();
                      _condition = 'all';
                      _locCtrl.clear();
                    });
                  },
                  child: Text('Weka upya', style: TextStyle(color: cs.primary)),
                ),
              ],
            ),
          ),
          Divider(color: cs.outlineVariant),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              children: [
                Text('Panga kwa', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: cs.onSurface)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _sortChip(cs, 'newest', 'Mpya'),
                    _sortChip(cs, 'price_asc', 'Bei: Chini → Juu'),
                    _sortChip(cs, 'price_desc', 'Bei: Juu → Chini'),
                    _sortChip(cs, 'popular', 'Maarufu'),
                  ],
                ),
                const SizedBox(height: 20),
                Text('Bei', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: cs.onSurface)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _minCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          hintText: 'Kuanzia',
                          hintStyle: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: cs.outlineVariant)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: cs.outlineVariant)),
                        ),
                        style: TextStyle(fontSize: 14, color: cs.onSurface),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text('—', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 16)),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _maxCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          hintText: 'Hadi',
                          hintStyle: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: cs.outlineVariant)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: cs.outlineVariant)),
                        ),
                        style: TextStyle(fontSize: 14, color: cs.onSurface),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text('Hali', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: cs.onSurface)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    _condChip(cs, 'all', 'Zote'),
                    _condChip(cs, 'new', 'Mpya'),
                    _condChip(cs, 'used', 'Iliyotumika'),
                  ],
                ),
                const SizedBox(height: 20),
                Text('Eneo', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: cs.onSurface)),
                const SizedBox(height: 8),
                TextField(
                  controller: _locCtrl,
                  decoration: InputDecoration(
                    hintText: 'Mf. Dar es Salaam, Arusha...',
                    hintStyle: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                    prefixIcon: Icon(Icons.location_on_outlined, size: 18, color: cs.onSurfaceVariant),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: cs.outlineVariant)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: cs.outlineVariant)),
                  ),
                  style: TextStyle(fontSize: 14, color: cs.onSurface),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: () {
                  widget.onApply(
                    _sort,
                    double.tryParse(_minCtrl.text),
                    double.tryParse(_maxCtrl.text),
                    _condition,
                    _locCtrl.text.trim(),
                  );
                  Navigator.pop(context);
                },
                child: Text('Tuma Kichujio', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sortChip(ColorScheme cs, String value, String label) {
    final selected = _sort == value;
    return GestureDetector(
      onTap: () => setState(() => _sort = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? cs.primary : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label, style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: selected ? cs.onPrimary : cs.onSurfaceVariant,
        )),
      ),
    );
  }

  Widget _condChip(ColorScheme cs, String value, String label) {
    final selected = _condition == value;
    return GestureDetector(
      onTap: () => setState(() => _condition = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? cs.primary : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label, style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: selected ? cs.onPrimary : cs.onSurfaceVariant,
        )),
      ),
    );
  }
}
